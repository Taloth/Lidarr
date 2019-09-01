using System;

namespace NzbDrone.Common.EnvironmentInfo
{

    public enum PlatformType
    {
        DotNet = 0,
        Mono = 1,
        NetCore = 2
    }

    public interface IPlatformInfo
    {
        Version Version { get; }
    }

    public abstract class PlatformInfo : IPlatformInfo
    {
        static PlatformInfo()
        {
#if !NETCOREAPP3_0
            if (Type.GetType("Mono.Runtime") != null)
            {
                Platform = PlatformType.Mono;
            }
            else
            {
                Platform = PlatformType.DotNet;
            }
#else
            Platform = PlatformType.NetCore;
#endif
        }

        public static PlatformType Platform { get; }
        public static bool IsMono => Platform == PlatformType.Mono;
        public static bool IsDotNet => Platform == PlatformType.DotNet;
        public static bool IsNetCore => Platform == PlatformType.NetCore;

        public static string PlatformName
        {
            get
            {
                if (IsDotNet)
                {
                    return ".NET";
                }
                else if (IsMono)
                {
                    return "Mono";
                }
                else
                {
                    return ".NET Core";
                }
            }
        }

        public abstract Version Version { get; }
    }
}
