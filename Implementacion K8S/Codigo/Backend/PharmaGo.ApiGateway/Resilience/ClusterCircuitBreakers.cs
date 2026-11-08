using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using InstrumentationInterface;
using Microsoft.Extensions.Options;
using Polly;
using Polly.CircuitBreaker;

namespace PharmaGo.ApiGateway.Resilience
{
    // Un circuit breaker por cluster de YARP (users-cluster, pharmacy-cluster): si un microservicio
    // falla, el gateway deja de mandarle tráfico sin afectar al otro.
    // El estado vive en memoria, así que cada réplica del gateway tiene sus propios circuitos.
    public class ClusterCircuitBreakers : IDisposable
    {
        private readonly ConcurrentDictionary<string, AsyncCircuitBreakerPolicy<bool>> _breakers = new();
        private readonly CircuitBreakerOptions _options;
        private readonly IStructuredLogger _logger;
        private readonly Meter _meter;
        private readonly Counter<long> _rejected;
        private readonly Counter<long> _transitions;

        public ClusterCircuitBreakers(IOptions<CircuitBreakerOptions> options, IStructuredLogger logger)
        {
            _options = options.Value;
            _logger = logger;

            // Mismo nombre de Meter que CustomMetrics para que lo tome el AddMeter existente
            _meter = new Meter("PharmaGo.CustomMetrics");
            _meter.CreateObservableGauge(
                "pharmago_circuit_breaker_state",
                () => _breakers.Select(kvp => new Measurement<int>(ToValue(kvp.Value.CircuitState), new KeyValuePair<string, object?>("cluster", kvp.Key))),
                description: "Estado del circuit breaker por cluster (0 cerrado, 1 half-open, 2 abierto)"
            );
            _rejected = _meter.CreateCounter<long>(
                "pharmago_circuit_breaker_rejected_total",
                description: "Requests rechazados por el gateway con el circuito abierto"
            );
            _transitions = _meter.CreateCounter<long>(
                "pharmago_circuit_breaker_transitions_total",
                description: "Cambios de estado del circuit breaker por cluster y estado nuevo"
            );
        }

        public TimeSpan BreakDuration => TimeSpan.FromSeconds(_options.BreakDurationSeconds);

        public AsyncCircuitBreakerPolicy<bool> For(string cluster) => _breakers.GetOrAdd(cluster, Create);

        public void RecordRejected(string cluster) =>
            _rejected.Add(1, new KeyValuePair<string, object?>("cluster", cluster));

        // El resultado de cada ejecución es "¿falló?"; solo cuentan como falla los true
        private AsyncCircuitBreakerPolicy<bool> Create(string cluster) =>
            Policy<bool>
                .HandleResult(failed => failed)
                .AdvancedCircuitBreakerAsync(
                    failureThreshold: _options.FailureRatio,
                    samplingDuration: TimeSpan.FromSeconds(_options.SamplingDurationSeconds),
                    minimumThroughput: _options.MinimumThroughput,
                    durationOfBreak: BreakDuration,
                    onBreak: (_, breakDuration) => OnStateChange(cluster, CircuitState.Open,
                        $"Circuito abierto para {cluster}: demasiadas fallas, se rechaza el tráfico por {breakDuration.TotalSeconds} s"),
                    onReset: () => OnStateChange(cluster, CircuitState.Closed,
                        $"Circuito cerrado para {cluster}: el servicio volvió a responder"),
                    onHalfOpen: () => OnStateChange(cluster, CircuitState.HalfOpen,
                        $"Circuito half-open para {cluster}: se deja pasar un request de prueba"));

        private void OnStateChange(string cluster, CircuitState state, string message)
        {
            _transitions.Add(1,
                new KeyValuePair<string, object?>("cluster", cluster),
                new KeyValuePair<string, object?>("state", state.ToString()));

            var metadata = new Dictionary<string, object>
            {
                ["event"] = "circuit_breaker",
                ["cluster"] = cluster,
                ["state"] = state.ToString()
            };
            if (state == CircuitState.Open)
                _logger.LogError(message, null, metadata);
            else if (state == CircuitState.HalfOpen)
                _logger.LogWarning(message, null, metadata);
            else
                _logger.LogInformation(message, metadata);
        }

        private static int ToValue(CircuitState state) => state switch
        {
            CircuitState.Closed => 0,
            CircuitState.HalfOpen => 1,
            _ => 2
        };

        public void Dispose() => _meter.Dispose();
    }
}
