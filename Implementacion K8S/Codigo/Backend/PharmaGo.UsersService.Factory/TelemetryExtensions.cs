using Microsoft.Extensions.DependencyInjection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Exporter;
using System.Diagnostics;
using OpenTelemetry.Trace;

namespace PharmaGo.UsersService.Factory
{
    public static class OpenTelemetryExtensions
    {
        public static IServiceCollection AddPharmaGoOpenTelemetryMetrics(this IServiceCollection services, string serviceName = "PharmaGo.UsersService")
        {
            services.AddOpenTelemetry()
                    .WithMetrics(metricsBuilder => metricsBuilder
                        .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService(serviceName))
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddMeter("PharmaGo.CustomMetrics")
                    .AddPrometheusExporter()
                    .AddOtlpExporter(o =>
                    {
                        o.Endpoint = new Uri("http://otlp-collector:4317");
                        o.Protocol = OtlpExportProtocol.Grpc;
                    }))
                .WithTracing(tracing => tracing
                    .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService(serviceName))
                    .AddAspNetCoreInstrumentation(o =>
                    {
                        // No trazar las probes ni el scrape de Prometheus
                        o.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health")
                                       && !ctx.Request.Path.StartsWithSegments("/metrics");
                        o.RecordException = true;
                    })
                    .AddHttpClientInstrumentation(o =>
                    {
                        o.FilterHttpRequestMessage = req => req.RequestUri?.AbsolutePath.StartsWith("/health") != true;
                        o.RecordException = true;
                    })
                    .AddSqlClientInstrumentation(o =>
                    {
                        o.SetDbStatementForText = true;   // muestra el SQL en el span
                        o.RecordException = true;
                    })
                    .AddOtlpExporter(o =>
                    {
                        o.Endpoint = new Uri("http://otlp-collector:4317");
                        o.Protocol = OtlpExportProtocol.Grpc;
                    }));

            return services;
        }
    }
}

