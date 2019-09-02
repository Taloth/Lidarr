using System.Collections.Generic;
using Nancy.Bootstrapper;
using Lidarr.Http;
using NzbDrone.Common.Composition;
using NzbDrone.Common.EnvironmentInfo;

#if NETCOREAPP3_0
using NzbDrone.SignalR.NetCoreApp;
#else
using NzbDrone.SignalR.NetFramework;
#endif

namespace NzbDrone.Host
{
    public class MainAppContainerBuilder : ContainerBuilderBase
    {
        public static IContainer BuildContainer(StartupContext args)
        {
            var assemblies = new List<string>
                             {
                                 "Lidarr.Host",
                                 "Lidarr.Core",
                                 "Lidarr.SignalR",
                                 "Lidarr.Api.V1",
                                 "Lidarr.Http"
                             };

            return new MainAppContainerBuilder(args, assemblies).Container;
        }

        private MainAppContainerBuilder(StartupContext args, List<string> assemblies)
            : base(args, assemblies)
        {
#if NETCOREAPP3_0
            AutoRegisterImplementations<MessageHub>();
#else
            AutoRegisterImplementations<NzbDronePersistentConnection>();
#endif

            Container.Register<INancyBootstrapper, LidarrBootstrapper>();

            if (OsInfo.IsWindows)
            {
                Container.Register<INzbDroneServiceFactory, NzbDroneServiceFactory>();
            }
            else
            {
                Container.Register<INzbDroneServiceFactory, DummyNzbDroneServiceFactory>();
            }
        }
    }
}
