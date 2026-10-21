using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using InstrumentationInterface;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Instrumentation
{
    // Publica el estado de cada chequeo como métrica y loguea en JSON cuando cambia
    public class HealthMetricsPublisher : IHealthCheckPublisher, IDisposable
    {
        private readonly IStructuredLogger _logger;
        private readonly Meter _meter;
        private readonly ConcurrentDictionary<string, HealthStatus> _lastStatus = new();

        public HealthMetricsPublisher(IStructuredLogger logger)
        {
            _logger = logger;
            // Mismo nombre de Meter que CustomMetrics para que lo tome el AddMeter existente
            _meter = new Meter("PharmaGo.CustomMetrics");
            _meter.CreateObservableGauge(
                "pharmago_health_status",
                () => _lastStatus.Select(kvp => new Measurement<double>(ToValue(kvp.Value), new KeyValuePair<string, object?>("check", kvp.Key))),
                description: "Health check status by check (1 healthy, 0.5 degraded, 0 unhealthy)"
            );
        }

        public Task PublishAsync(HealthReport report, CancellationToken cancellationToken)
        {
            foreach (var (name, entry) in report.Entries)
            {
                var previous = _lastStatus.TryGetValue(name, out var last) ? last : (HealthStatus?)null;
                _lastStatus[name] = entry.Status;
                if (previous == entry.Status)
                    continue;

                var metadata = new Dictionary<string, object>
                {
                    ["event"] = "health_check",
                    ["check"] = name,
                    ["status"] = entry.Status.ToString(),
                    ["previous_status"] = previous?.ToString() ?? "none"
                };
                var message = $"Health check {name} pasó a {entry.Status}: {entry.Description}";

                if (entry.Status == HealthStatus.Healthy)
                    _logger.LogInformation(message, metadata);
                else if (entry.Status == HealthStatus.Degraded)
                    _logger.LogWarning(message, entry.Exception, metadata);
                else
                    _logger.LogError(message, entry.Exception, metadata);
            }

            return Task.CompletedTask;
        }

        private static double ToValue(HealthStatus status) => status switch
        {
            HealthStatus.Healthy => 1,
            HealthStatus.Degraded => 0.5,
            _ => 0
        };

        public void Dispose() => _meter.Dispose();
    }
}
