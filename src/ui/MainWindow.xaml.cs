using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using EchoVisualizer.Views;
using EchoVisualizer.Services;

namespace EchoVisualizer
{
    public sealed partial class MainWindow : Window
    {
        public static MainWindow? Instance { get; private set; }

        public bool IsCursorHidden { get; private set; }

        private const uint WM_SETCURSOR = 0x0020;
        private const uint WM_MOUSEMOVE = 0x0200;
        private const int IDC_ARROW = 32512;

        private SUBCLASSPROC? _subclassProc;
        private static IntPtr _blankHCursor = IntPtr.Zero;

        [DllImport("comctl32.dll", CharSet = CharSet.Auto)]
        private static extern bool SetWindowSubclass(IntPtr hWnd, SUBCLASSPROC pfnSubclass, uint uIdSubclass, IntPtr dwRefData);

        [DllImport("comctl32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr DefSubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern IntPtr CreateCursor(IntPtr hInstance, int xHotSpot, int yHotSpot, int nWidth, int nHeight, byte[] pvANDPlane, byte[] pvXORPlane);

        [DllImport("user32.dll")]
        private static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);

        [DllImport("user32.dll")]
        private static extern IntPtr SetCursor(IntPtr hCursor);

        private delegate IntPtr SUBCLASSPROC(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, uint uIdSubclass, IntPtr dwRefData);

        public MainWindow()
        {
            Instance = this;
            AppVisualizerState.InitializeAndLoadSettings();

            InitializeComponent();

            var themeIndex = AppVisualizerState.SettingsViewModel.ThemeIndex;
            var targetTheme = themeIndex switch
            {
                1 => ElementTheme.Light,
                2 => ElementTheme.Dark,
                _ => ElementTheme.Default
            };

            SetTheme(targetTheme);
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);

            var iconPath = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
            if (System.IO.File.Exists(iconPath))
            {
                AppWindow.SetIcon(iconPath);
            }

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            _subclassProc = new SUBCLASSPROC(WindowSubclassProc);
            SetWindowSubclass(hwnd, _subclassProc, 101, IntPtr.Zero);

            AppWindow.Changed += AppWindow_Changed;

            RootFrame.Navigate(typeof(VisualizerPage));
        }

        private static IntPtr GetBlankCursor()
        {
            if (_blankHCursor == IntPtr.Zero)
            {
                byte[] andMask = new byte[32];
                byte[] xorMask = new byte[32];
                for (int i = 0; i < 32; i++)
                {
                    andMask[i] = 0xFF; // Transparent mask
                    xorMask[i] = 0x00;
                }
                _blankHCursor = CreateCursor(IntPtr.Zero, 0, 0, 16, 16, andMask, xorMask);
            }
            return _blankHCursor;
        }

        private IntPtr WindowSubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, uint uIdSubclass, IntPtr dwRefData)
        {
            if (uMsg == WM_SETCURSOR && IsCursorHidden)
            {
                SetCursor(GetBlankCursor());
                return (IntPtr)1; // Intercept WM_SETCURSOR so WinUI 3 cannot restore Arrow cursor!
            }
            return DefSubclassProc(hWnd, uMsg, wParam, lParam);
        }

        public void SetCursorHidden(bool hidden)
        {
            IsCursorHidden = hidden;

            if (hidden)
            {
                SetCursor(GetBlankCursor());
            }
            else
            {
                SetCursor(LoadCursor(IntPtr.Zero, IDC_ARROW));
            }
        }

        private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
        {
            if (args.DidPresenterChange)
            {
                UpdateTitleBarVisibility();
                if (AppWindow.Presenter.Kind != AppWindowPresenterKind.FullScreen)
                {
                    SetCursorHidden(false);
                }
            }
        }

        public void ToggleFullScreen()
        {
            if (AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen)
            {
                AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
                SetCursorHidden(false);
            }
            else
            {
                AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
            }

            UpdateTitleBarVisibility();
        }

        private void UpdateTitleBarVisibility()
        {
            var isFullScreen = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;
            AppTitleBar.Visibility = isFullScreen ? Visibility.Collapsed : Visibility.Visible;
        }

        private void Grid_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.F11)
            {
                e.Handled = true;
                ToggleFullScreen();
            }
            else if (e.Key == Windows.System.VirtualKey.Escape && AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen)
            {
                e.Handled = true;
                ToggleFullScreen();
            }
        }

        private void RootFrame_NavigationFailed(object sender, NavigationFailedEventArgs e)
        {
            throw new Exception("Failed to load Page " + e.SourcePageType.FullName);
        }

        public void SetTheme(ElementTheme theme)
        {
            if (Content is FrameworkElement rootContent)
            {
                rootContent.RequestedTheme = theme;
            }
            UpdateTitleBarTheme(theme);
        }

        public void UpdateTitleBarTheme(ElementTheme theme)
        {
            if (!AppWindowTitleBar.IsCustomizationSupported()) return;

            var titleBar = AppWindow.TitleBar;
            titleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
            titleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;

            bool isDark = theme == ElementTheme.Dark ||
                         (theme == ElementTheme.Default && Application.Current.RequestedTheme == ApplicationTheme.Dark);

            if (isDark)
            {
                titleBar.ButtonForegroundColor = Windows.UI.Color.FromArgb(255, 242, 244, 248);
                titleBar.ButtonHoverForegroundColor = Windows.UI.Color.FromArgb(255, 255, 255, 255);
                titleBar.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(32, 255, 255, 255);
                titleBar.ButtonInactiveForegroundColor = Windows.UI.Color.FromArgb(255, 154, 163, 181);
            }
            else
            {
                titleBar.ButtonForegroundColor = Windows.UI.Color.FromArgb(255, 17, 24, 39);
                titleBar.ButtonHoverForegroundColor = Windows.UI.Color.FromArgb(255, 0, 0, 0);
                titleBar.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(32, 0, 0, 0);
                titleBar.ButtonInactiveForegroundColor = Windows.UI.Color.FromArgb(255, 107, 114, 128);
            }
        }
    }
}
