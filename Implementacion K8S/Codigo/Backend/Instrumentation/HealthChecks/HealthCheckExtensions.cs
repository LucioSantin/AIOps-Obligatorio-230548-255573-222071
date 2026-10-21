using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Instrumentation
{
    public static class HealthCheckExtensions
    {
        // Publisher de métricas y logs del estado de los chequeos, común a los 3 servicios
        public static IHealthChecksBuilder AddPharmaGoHealthChecks(this IServiceCollection services)
        {
            services.Configure<HealthCheckPublisherOptions>(options =>
            {
                options.Delay = TimeSpan.FromSeconds(5);
                options.Period = TimeSpan.FromSeconds(10);
            });
            services.AddSingleton<IHealthCheckPublisher, HealthMetricsPublisher>();

            return services.AddHealthChecks();
        }

        // /health con todos los chequeos para readiness y /health/live sin chequeos para liveness y startup
        public static void MapPharmaGoHealthChecks(this IEndpointRouteBuilder app)
        {
            app.MapHealthChecks("/health", new HealthCheckOptions { ResponseWriter = HealthResponseWriter.WriteAsync });
            app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
        }
    }
}
