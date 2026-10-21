using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Instrumentation
{
    // Respuesta JSON de /health con el detalle de cada chequeo, sin mensajes de excepción
    public static class HealthResponseWriter
    {
        public static Task WriteAsync(HttpContext context, HealthReport report)
        {
            var response = new
            {
                status = report.Status.ToString(),
                total_ms = Math.Round(report.TotalDuration.TotalMilliseconds, 1),
                checks = report.Entries.Select(entry => new
                {
                    name = entry.Key,
                    status = entry.Value.Status.ToString(),
                    duration_ms = Math.Round(entry.Value.Duration.TotalMilliseconds, 1),
                    description = entry.Value.Description,
                    data = entry.Value.Data
                })
            };

            context.Response.ContentType = "application/json";
            return context.Response.WriteAsync(JsonSerializer.Serialize(response));
        }
    }
}
