using System;
using System.Runtime.Versioning;
using System.Threading.Tasks;
using Windows.ApplicationModel;
using Windows.Foundation.Metadata;
using Windows.Security.Authorization.AppCapabilityAccess;
using Windows.System;

namespace EchoVisualizer.Services;

internal enum MicrophoneAccessState
{
    NotApplicable,
    Allowed,
    PromptRequired,
    Denied,
}

/// Identity-aware microphone privacy adapter. It never reads the registry:
/// packaged apps use AppCapabilityAccess, while unpackaged Win32 relies on the
/// Windows desktop-app privacy control and only offers its Settings URI.
internal static class MicrophonePrivacyService
{
    public static bool HasPackageIdentity
    {
        get
        {
            try
            {
                _ = Package.Current.Id.Name;
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    public static MicrophoneAccessState CheckForStartup()
    {
        if (!HasPackageIdentity)
        {
            return MicrophoneAccessState.NotApplicable;
        }

        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 18362)
            || !ApiInformation.IsTypePresent(
            "Windows.Security.Authorization.AppCapabilityAccess.AppCapability"))
        {
            return MicrophoneAccessState.PromptRequired;
        }

        try
        {
            return Map(AppCapability.Create("microphone").CheckAccess());
        }
        catch (Exception)
        {
            return MicrophoneAccessState.Denied;
        }
    }

    public static async Task<MicrophoneAccessState> EnsureAccessAsync()
    {
        if (!HasPackageIdentity)
        {
            return MicrophoneAccessState.NotApplicable;
        }

        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 18362)
            || !ApiInformation.IsTypePresent(
            "Windows.Security.Authorization.AppCapabilityAccess.AppCapability"))
        {
            return MicrophoneAccessState.PromptRequired;
        }

        try
        {
            var capability = AppCapability.Create("microphone");
            var status = capability.CheckAccess();
            if (status == AppCapabilityAccessStatus.UserPromptRequired)
            {
                status = await capability.RequestAccessAsync();
            }
            return Map(status);
        }
        catch (Exception)
        {
            return MicrophoneAccessState.Denied;
        }
    }

    public static async Task OpenPrivacySettingsAsync() =>
        _ = await Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-microphone"));

    [SupportedOSPlatform("windows10.0.18362")]
    private static MicrophoneAccessState Map(AppCapabilityAccessStatus status) => status switch
    {
        AppCapabilityAccessStatus.Allowed => MicrophoneAccessState.Allowed,
        AppCapabilityAccessStatus.UserPromptRequired => MicrophoneAccessState.PromptRequired,
        _ => MicrophoneAccessState.Denied,
    };
}
