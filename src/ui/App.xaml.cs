using Microsoft.UI.Xaml;
using System;
using System.Runtime.InteropServices;

namespace EchoVisualizer;

public partial class App : Application
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiAwarenessContext);

    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    private Window? _window;

    public App()
    {
        // Fix DPI scaling on high-DPI monitors
        try
        {
            SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        }
        catch
        {
            // Ignore if not supported on this system
        }

        InitializeComponent();
        UnhandledException += (_, eventArgs) =>
        {
            // Preserve the managed detail behind WinUI's generic stowed-exception
            // crash report. Do not mark it handled: a broken UI must not continue.
            WriteStartupDiagnostic(eventArgs.Exception.ToString());
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    private static void WriteStartupDiagnostic(string message)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "EchoVisualizer");
            Directory.CreateDirectory(directory);
            File.AppendAllText(
                Path.Combine(directory, "startup-errors.log"),
                $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostic output must never affect application startup.
        }
    }
}
