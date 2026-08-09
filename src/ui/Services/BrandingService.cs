using Microsoft.UI.Windowing;
using System;
using System.Diagnostics;
using System.IO;

namespace EchoVisualizer.Services
{
    /// <summary>RF6.1.6: applies the canonical loose icon to the runtime window surface.</summary>
    internal static class BrandingService
    {
        private static readonly string ApplicationIconPath = Path.Combine(
            AppContext.BaseDirectory,
            "Assets",
            "AppIcon.ico");

        public static void ApplyWindowIcon(AppWindow appWindow)
        {
            ArgumentNullException.ThrowIfNull(appWindow);

            if (!File.Exists(ApplicationIconPath))
            {
                Debug.WriteLine($"Echo branding asset is missing: {ApplicationIconPath}");
                return;
            }

            try
            {
                appWindow.SetIcon(ApplicationIconPath);
            }
            catch (Exception exception)
            {
                Debug.WriteLine($"Unable to apply the Echo window icon: {exception}");
            }
        }
    }
}
