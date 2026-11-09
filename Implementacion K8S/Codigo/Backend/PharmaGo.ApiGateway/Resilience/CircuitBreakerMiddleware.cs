using Polly.CircuitBreaker;
using Yarp.ReverseProxy.Forwarder;
using Yarp.ReverseProxy.Model;

namespace PharmaGo.ApiGateway.Resilience
{
    // Paso del pipeline de YARP: corre después de elegir la ruta y antes de reenviar el request.
    // Cuenta como falla los 5xx y los timeouts del microservicio. Los 4xx no cuentan, porque son
    // errores del cliente: si contaran, cualquiera podría abrir el circuito mandando requests inválidos.
    public class CircuitBreakerMiddleware
    {
        public const string StateHeader = "X-Circuit-Breaker";

        private readonly RequestDelegate _next;
        private readonly ClusterCircuitBreakers _breakers;

        public CircuitBreakerMiddleware(RequestDelegate next, ClusterCircuitBreakers breakers)
        {
            _next = next;
            _breakers = breakers;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var cluster = context.GetReverseProxyFeature().Cluster.Config.ClusterId;
            var breaker = _breakers.For(cluster);

            try
            {
                await breaker.ExecuteAsync(async () =>
                {
                    await _next(context);
                    return IsFailure(context);
                });
            }
            catch (BrokenCircuitException)
            {
                // Circuito abierto (o half-open con el request de prueba en curso): se responde
                // al instante sin tocar el microservicio
                _breakers.RecordRejected(cluster);
                var retryAfter = (int)_breakers.BreakDuration.TotalSeconds;
                context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                context.Response.Headers["Retry-After"] = retryAfter.ToString();
                context.Response.Headers[StateHeader] = "open";
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "Service unavailable",
                    message = $"El servicio de {cluster} está fallando, se cortó el tráfico temporalmente",
                    retryAfterSeconds = retryAfter
                });
            }
        }

        private static bool IsFailure(HttpContext context)
        {
            // Si el cliente cortó la conexión no es culpa del microservicio
            if (context.RequestAborted.IsCancellationRequested)
                return false;

            var error = context.Features.Get<IForwarderErrorFeature>()?.Error ?? ForwarderError.None;
            if (IsClientError(error))
                return false;

            // Incluye los 502/504 que pone YARP cuando no puede conectarse o el servicio no responde
            // a tiempo (HttpRequest.ActivityTimeout del cluster) y los 503 sin destinos sanos
            return error != ForwarderError.None || context.Response.StatusCode >= 500;
        }

        private static bool IsClientError(ForwarderError error) => error is
            ForwarderError.RequestCanceled or
            ForwarderError.RequestBodyCanceled or
            ForwarderError.RequestBodyClient or
            ForwarderError.ResponseBodyCanceled or
            ForwarderError.ResponseBodyClient or
            ForwarderError.UpgradeRequestCanceled or
            ForwarderError.UpgradeRequestClient or
            ForwarderError.UpgradeResponseCanceled or
            ForwarderError.UpgradeResponseClient;
    }

    public static class CircuitBreakerExtensions
    {
        public static IServiceCollection AddClusterCircuitBreakers(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<CircuitBreakerOptions>(configuration.GetSection("CircuitBreaker"));
            services.AddSingleton<ClusterCircuitBreakers>();
            return services;
        }

        public static IReverseProxyApplicationBuilder UseClusterCircuitBreaker(this IReverseProxyApplicationBuilder proxyPipeline)
        {
            proxyPipeline.UseMiddleware<CircuitBreakerMiddleware>();
            return proxyPipeline;
        }
    }
}
