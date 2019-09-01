using Microsoft.AspNetCore.Builder;

namespace NzbDrone.Host.NetCoreApp.Middleware
{
    public interface IAspNetCoreMiddleware
    {
        int Order { get; }
        void Attach(IApplicationBuilder appBuilder);
    }
}
