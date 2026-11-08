using AspNetCoreRateLimit;
using Microsoft.Extensions.Options;

namespace PharmaGo.ApiGateway.Resilience
{
    // La configuración por defecto de AspNetCoreRateLimit toma la IP del header X-Real-IP si viene
    // (aunque no esté en appsettings, es su valor por defecto). Como delante del gateway no hay un
    // proxy que pise ese header, un cliente podía mandar un X-Real-IP distinto en cada request y
    // esquivar el límite. Acá solo se usa la IP real de la conexión TCP.
    public class ConnectionIpRateLimitConfiguration : RateLimitConfiguration
    {
        public ConnectionIpRateLimitConfiguration(
            IOptions<IpRateLimitOptions> ipOptions,
            IOptions<ClientRateLimitOptions> clientOptions)
            : base(ipOptions, clientOptions)
        {
        }

        public override void RegisterResolvers()
        {
            // Sin llamar a base: base agrega IpHeaderResolveContributor(X-Real-IP)
            IpResolvers.Add(new IpConnectionResolveContributor());
        }
    }
}
