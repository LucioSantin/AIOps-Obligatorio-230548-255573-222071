namespace PharmaGo.ApiGateway.Resilience
{
    // Sección "CircuitBreaker" de appsettings.json
    public class CircuitBreakerOptions
    {
        // Proporción de fallas (5xx o timeouts) en la ventana que abre el circuito
        public double FailureRatio { get; set; } = 0.5;

        // Ventana en la que se cuentan las fallas
        public int SamplingDurationSeconds { get; set; } = 10;

        // Mínimo de requests en la ventana para poder abrir, así un par de errores sueltos no lo abren
        public int MinimumThroughput { get; set; } = 10;

        // Tiempo que el circuito queda abierto antes de dejar pasar un request de prueba (half-open)
        public int BreakDurationSeconds { get; set; } = 15;
    }
}
