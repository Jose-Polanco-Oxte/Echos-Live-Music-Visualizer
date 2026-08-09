using System;
using System.Diagnostics;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace EchoVisualizer.Services;

public sealed class ResolvedThemeChangedEventArgs : EventArgs
{
    public ResolvedThemeChangedEventArgs(ElementTheme resolvedTheme, Color surfaceBackgroundColor, bool isHighContrast)
    {
        ResolvedTheme = resolvedTheme;
        SurfaceBackgroundColor = surfaceBackgroundColor;
        IsHighContrast = isHighContrast;
    }

    public ElementTheme ResolvedTheme { get; }
    public Color SurfaceBackgroundColor { get; }
    public bool IsHighContrast { get; }
}

/// <summary>
/// RF6.6.3: resolves the persisted theme preference and keeps XAML, title-bar,
/// Win2D, and high-contrast surfaces synchronized at runtime.
/// </summary>
public sealed class ThemeService : IDisposable
{
    private readonly Panel _root;
    private readonly AppWindow _appWindow;
    private readonly AccessibilitySettings _accessibilitySettings = new();
    private readonly UISettings _uiSettings = new();
    private bool _isAccessibilitySettingsSubscribed;
    private bool _isUiSettingsSubscribed;
    private bool _isDisposed;

    public ThemeService(Panel root, AppWindow appWindow)
    {
        _root = root ?? throw new ArgumentNullException(nameof(root));
        _appWindow = appWindow ?? throw new ArgumentNullException(nameof(appWindow));

        _root.Loaded += Root_Loaded;
        _root.ActualThemeChanged += Root_ActualThemeChanged;
        TrySubscribeToSystemThemeChanges();
    }

    public event EventHandler<ResolvedThemeChangedEventArgs>? ResolvedThemeChanged;

    public ThemePreference Preference { get; private set; } = ThemePreference.System;

    public ElementTheme ResolvedTheme { get; private set; } = ElementTheme.Default;

    public Color SurfaceBackgroundColor { get; private set; }

    public bool IsHighContrast => _accessibilitySettings.HighContrast;

    public void ApplyPreference(ThemePreference preference)
    {
        ObjectDisposedException.ThrowIf(_isDisposed, this);

        Preference = ThemePreferenceMapper.Normalize(preference);
        _root.RequestedTheme = Preference switch
        {
            ThemePreference.Light => ElementTheme.Light,
            ThemePreference.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default
        };

        PublishResolvedTheme();
    }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        _root.Loaded -= Root_Loaded;
        _root.ActualThemeChanged -= Root_ActualThemeChanged;
        if (_isAccessibilitySettingsSubscribed)
        {
            _accessibilitySettings.HighContrastChanged -= AccessibilitySettings_HighContrastChanged;
        }
        if (_isUiSettingsSubscribed)
        {
            _uiSettings.ColorValuesChanged -= UiSettings_ColorValuesChanged;
        }
        ResolvedThemeChanged = null;
    }

    private void TrySubscribeToSystemThemeChanges()
    {
        // Some Windows builds expose AccessibilitySettings.HighContrast to an
        // unpackaged process but return ERROR_NOT_FOUND when registering its
        // WinRT event. UISettings.ColorValuesChanged remains the cross-profile
        // notification and PublishResolvedTheme re-reads HighContrast there.
        try
        {
            _accessibilitySettings.HighContrastChanged += AccessibilitySettings_HighContrastChanged;
            _isAccessibilitySettingsSubscribed = true;
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"High-contrast event is unavailable; using color-change notifications: {exception}");
        }

        try
        {
            _uiSettings.ColorValuesChanged += UiSettings_ColorValuesChanged;
            _isUiSettingsSubscribed = true;
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"System color-change notifications are unavailable: {exception}");
        }
    }

    private void Root_Loaded(object sender, RoutedEventArgs e) => PublishResolvedTheme();

    private void Root_ActualThemeChanged(FrameworkElement sender, object args) => PublishResolvedTheme();

    private void AccessibilitySettings_HighContrastChanged(AccessibilitySettings sender, object args) =>
        PublishResolvedThemeOnUiThread();

    private void UiSettings_ColorValuesChanged(UISettings sender, object args) =>
        PublishResolvedThemeOnUiThread();

    private void PublishResolvedThemeOnUiThread()
    {
        if (_isDisposed)
        {
            return;
        }

        if (_root.DispatcherQueue.HasThreadAccess)
        {
            PublishResolvedTheme();
        }
        else
        {
            _root.DispatcherQueue.TryEnqueue(PublishResolvedTheme);
        }
    }

    private void PublishResolvedTheme()
    {
        if (_isDisposed)
        {
            return;
        }

        ResolvedTheme = ResolveActualTheme();
        SurfaceBackgroundColor = ResolveSurfaceBackgroundColor();

        UpdateTitleBarColors();
        ResolvedThemeChanged?.Invoke(
            this,
            new ResolvedThemeChangedEventArgs(ResolvedTheme, SurfaceBackgroundColor, IsHighContrast));
    }

    private Color ResolveSurfaceBackgroundColor()
    {
        if (IsHighContrast)
        {
            return _uiSettings.GetColorValue(UIColorType.Background);
        }

        return _root.Background is SolidColorBrush backgroundBrush
            ? backgroundBrush.Color
            : _uiSettings.GetColorValue(UIColorType.Background);
    }

    private ElementTheme ResolveActualTheme() => _root.ActualTheme switch
    {
        ElementTheme.Light => ElementTheme.Light,
        ElementTheme.Dark => ElementTheme.Dark,
        _ when Preference == ThemePreference.Light => ElementTheme.Light,
        _ when Preference == ThemePreference.Dark => ElementTheme.Dark,
        _ when Application.Current.RequestedTheme == ApplicationTheme.Light => ElementTheme.Light,
        _ => ElementTheme.Dark
    };

    private void UpdateTitleBarColors()
    {
        if (!AppWindowTitleBar.IsCustomizationSupported())
        {
            return;
        }

        var titleBar = _appWindow.TitleBar;
        if (IsHighContrast)
        {
            titleBar.ButtonForegroundColor = null;
            titleBar.ButtonBackgroundColor = null;
            titleBar.ButtonHoverForegroundColor = null;
            titleBar.ButtonHoverBackgroundColor = null;
            titleBar.ButtonPressedForegroundColor = null;
            titleBar.ButtonPressedBackgroundColor = null;
            titleBar.ButtonInactiveForegroundColor = null;
            titleBar.ButtonInactiveBackgroundColor = null;
            return;
        }

        titleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;

        if (ResolvedTheme == ElementTheme.Dark)
        {
            titleBar.ButtonForegroundColor = Color.FromArgb(255, 242, 244, 248);
            titleBar.ButtonHoverForegroundColor = Color.FromArgb(255, 255, 255, 255);
            titleBar.ButtonHoverBackgroundColor = Color.FromArgb(32, 255, 255, 255);
            titleBar.ButtonPressedForegroundColor = Color.FromArgb(255, 255, 255, 255);
            titleBar.ButtonPressedBackgroundColor = Color.FromArgb(48, 255, 255, 255);
            titleBar.ButtonInactiveForegroundColor = Color.FromArgb(255, 154, 163, 181);
        }
        else
        {
            titleBar.ButtonForegroundColor = Color.FromArgb(255, 17, 24, 39);
            titleBar.ButtonHoverForegroundColor = Color.FromArgb(255, 0, 0, 0);
            titleBar.ButtonHoverBackgroundColor = Color.FromArgb(32, 0, 0, 0);
            titleBar.ButtonPressedForegroundColor = Color.FromArgb(255, 0, 0, 0);
            titleBar.ButtonPressedBackgroundColor = Color.FromArgb(48, 0, 0, 0);
            titleBar.ButtonInactiveForegroundColor = Color.FromArgb(255, 107, 114, 128);
        }
    }
}
