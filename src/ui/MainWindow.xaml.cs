using System;
using System.ComponentModel;
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

        public ThemeService ThemeService { get; }

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
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);

            ThemeService = new ThemeService(RootLayout, AppWindow);
            AppVisualizerState.SettingsViewModel.PropertyChanged += SettingsViewModel_PropertyChanged;
            ThemeService.ApplyPreference(AppVisualizerState.SettingsViewModel.ThemePreference);
            Closed += MainWindow_Closed;

            BrandingService.ApplyWindowIcon(AppWindow);

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            _subclassProc = new SUBCLASSPROC(WindowSubclassProc);
            SetWindowSubclass(hwnd, _subclassProc, 101, IntPtr.Zero);

            AppWindow.Changed += AppWindow_Changed;

            RootFrame.Navigate(typeof(VisualizerPage), ThemeService);
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

        private void SettingsViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(AppVisualizerState.SettingsViewModel.ThemePreference))
            {
                ThemeService.ApplyPreference(AppVisualizerState.SettingsViewModel.ThemePreference);
            }
        }

        private void MainWindow_Closed(object sender, WindowEventArgs args)
        {
            Closed -= MainWindow_Closed;
            AppWindow.Changed -= AppWindow_Changed;
            AppVisualizerState.SettingsViewModel.PropertyChanged -= SettingsViewModel_PropertyChanged;
            ThemeService.Dispose();
            if (ReferenceEquals(Instance, this))
            {
                Instance = null;
            }
        }
    }
}
