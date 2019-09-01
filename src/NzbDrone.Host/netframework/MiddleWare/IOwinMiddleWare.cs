using Owin;

namespace NzbDrone.Host.NetFramework.MiddleWare
{
    public interface IOwinMiddleWare
    {
        int Order { get; }
        void Attach(IAppBuilder appBuilder);
    }
}