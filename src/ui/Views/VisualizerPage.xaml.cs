using System;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;
using EchoVisualizer.Audio;
using EchoVisualizer.Services;
using EchoVisualizer.ViewModels;
using EchoVisualizer.Visualizers;

namespace EchoVisualizer.Views
{
    public partial class VisualizerPage : Page
    {
        private static bool _hasDisclaimerBeenShown;

        private readonly VisualizerViewModel _viewModel = AppVisualizerState.VisualizerViewModel;
        private readonly OverlayVisibilityService _overlayService;
        private readonly Win2DGpuSpectralBarVisualizer _gpuVisualizer;
        private readonly AudioCoreService _audioCore = AppVisualizerState.AudioCoreService;
        private readonly DispatcherTimer _disclaimerTimer = new();
        private readonly DispatcherTimer _renderTimer = new();
        private ThemeService? _themeService;
        private bool _isThemeServiceSubscribed;
        private int _countdown = 5;

        public VisualizerPage()
        {
            InitializeComponent();
            DataContext = _viewModel;

            _overlayService = new OverlayVisibilityService(DispatcherQueue);
            _overlayService.StateChanged += OverlayService_StateChanged;

            _gpuVisualizer = new Win2DGpuSpectralBarVisualizer(Win2DCanvas);

            _renderTimer.Interval = TimeSpan.FromMilliseconds(16);
            _renderTimer.Tick += RenderTimer_Tick;

            Loaded += VisualizerPage_Loaded;
            Unloaded += VisualizerPage_Unloaded;

            SyncViewModelToUiAndGpu();

            if (_hasDisclaimerBeenShown)
            {
                DisclaimerOverlayGrid.Visibility = Visibility.Collapsed;
                _renderTimer.Start();
            }
            else
            {
                InitializeDisclaimerTimer();
            }
        }

        private void SyncViewModelToUiAndGpu()
        {
            var primaryColor = Color.FromArgb(255, _viewModel.PrimaryR, _viewModel.PrimaryG, _viewModel.PrimaryB);
            var secondaryColor = Color.FromArgb(255, _viewModel.SecondaryR, _viewModel.SecondaryG, _viewModel.SecondaryB);

            // Sync UI Controls
            BandCountSlider.Value = _viewModel.BandCount;
            BandCountValueText.Text = _viewModel.BandCount.ToString();
            LayoutSelector.SelectedIndex = _viewModel.LayoutIndex;
            ColorModeSelector.SelectedIndex = _viewModel.ColorModeIndex;
            PrimaryColorPicker.Color = primaryColor;
            SecondaryColorPicker.Color = secondaryColor;
            PrimaryColorPreview.Background = new SolidColorBrush(primaryColor);
            SecondaryColorPreview.Background = new SolidColorBrush(secondaryColor);
            CustomColorPanel.Visibility = _viewModel.ColorModeIndex == 1 ? Visibility.Visible : Visibility.Collapsed;

            // Sync GPU Visualizer
            _gpuVisualizer.BarCount = _viewModel.BandCount;
            _gpuVisualizer.Layout = (SpectralBarLayout)_viewModel.LayoutIndex;
            _gpuVisualizer.ColorMode = _viewModel.ColorModeIndex == 1 ? SpectralColorMode.Custom : SpectralColorMode.AudioMapped;
            _gpuVisualizer.CustomPrimary = primaryColor;
            _gpuVisualizer.CustomSecondary = secondaryColor;
            _audioCore.TryConfigureSpectralBands(_viewModel.BandCount, _viewModel.ScalingModeIndex);
            _audioCore.TrySetSpectralScalingMode((SpectralScalingMode)_viewModel.ScalingModeIndex);
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            if (e.Parameter is ThemeService themeService)
            {
                _themeService = themeService;
            }

            SyncViewModelToUiAndGpu();
            if (_hasDisclaimerBeenShown)
            {
                _renderTimer.Start();
            }
        }

        protected override void OnNavigatedFrom(NavigationEventArgs e)
        {
            base.OnNavigatedFrom(e);
            _renderTimer.Stop();
        }

        private void VisualizerPage_Loaded(object sender, RoutedEventArgs e)
        {
            if (_isThemeServiceSubscribed || _themeService == null)
            {
                return;
            }

            _themeService.ResolvedThemeChanged += ThemeService_ResolvedThemeChanged;
            _isThemeServiceSubscribed = true;
            Win2DCanvas.ClearColor = _themeService.SurfaceBackgroundColor;
        }

        private void VisualizerPage_Unloaded(object sender, RoutedEventArgs e)
        {
            if (!_isThemeServiceSubscribed || _themeService == null)
            {
                return;
            }

            _themeService.ResolvedThemeChanged -= ThemeService_ResolvedThemeChanged;
            _isThemeServiceSubscribed = false;
        }

        private void ThemeService_ResolvedThemeChanged(object? sender, ResolvedThemeChangedEventArgs e)
        {
            Win2DCanvas.ClearColor = e.SurfaceBackgroundColor;
        }

        private void InitializeDisclaimerTimer()
        {
            _disclaimerTimer.Interval = TimeSpan.FromSeconds(1);
            _disclaimerTimer.Tick += (_, _) =>
            {
                _countdown--;
                if (_countdown > 0)
                {
                    DisclaimerCountdownText.Text = $"Puedes continuar en {_countdown} ...";
                }
                else
                {
                    _disclaimerTimer.Stop();
                    _hasDisclaimerBeenShown = true;
                    DisclaimerOverlayGrid.Visibility = Visibility.Collapsed;
                    _renderTimer.Start();
                }
            };
            _disclaimerTimer.Start();
        }

        private void RenderTimer_Tick(object? sender, object e)
        {
            if (_audioCore is not null && _audioCore.TryReadFrame(out var frame))
            {
                _gpuVisualizer.UpdateFrame(frame.Rms, frame.SpectralCentroidHz, frame.OnsetDetected, frame.BandEnergies);
            }
        }

        private void RootViewportGrid_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            _overlayService.NotifyActivity();
        }



        private void OverlayService_StateChanged(object? sender, OverlayState state)
        {
            var isFullScreen = MainWindow.Instance?.AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;

            switch (state)
            {
                case OverlayState.Full:
                    MainWindow.Instance?.SetCursorHidden(false);
                    AnimateOpacity(TopBarOverlay, 1.0);
                    AnimateOpacity(BottomOverlay, 1.0);
                    AnimateOpacity(EyeButton, 1.0);
                    TopBarOverlay.IsHitTestVisible = true;
                    BottomOverlay.IsHitTestVisible = true;
                    EyeButton.IsHitTestVisible = true;
                    EyeIcon.Glyph = "\uE890"; // Eye open
                    break;

                case OverlayState.ManualCollapsed:
                    MainWindow.Instance?.SetCursorHidden(false);
                    AnimateOpacity(TopBarOverlay, 0.0);
                    AnimateOpacity(BottomOverlay, 0.0);
                    AnimateOpacity(EyeButton, 1.0);
                    TopBarOverlay.IsHitTestVisible = false;
                    BottomOverlay.IsHitTestVisible = false;
                    EyeButton.IsHitTestVisible = true;
                    EyeIcon.Glyph = "\uED1A"; // Eye closed
                    break;

                case OverlayState.IdleHidden:
                    // Cursor MUST ONLY hide when in FullScreen mode!
                    MainWindow.Instance?.SetCursorHidden(isFullScreen);
                    AnimateOpacity(TopBarOverlay, 0.0);
                    AnimateOpacity(BottomOverlay, 0.0);
                    AnimateOpacity(EyeButton, 0.0);
                    TopBarOverlay.IsHitTestVisible = false;
                    BottomOverlay.IsHitTestVisible = false;
                    EyeButton.IsHitTestVisible = false;
                    break;
            }
        }

        private void AnimateOpacity(UIElement element, double targetOpacity)
        {
            var animation = new DoubleAnimation
            {
                To = targetOpacity,
                Duration = new Duration(TimeSpan.FromMilliseconds(300)),
                EasingFunction = new CubicEase { EasingMode = targetOpacity > 0 ? EasingMode.EaseOut : EasingMode.EaseIn }
            };
            Storyboard.SetTarget(animation, element);
            Storyboard.SetTargetProperty(animation, "Opacity");
            var sb = new Storyboard();
            sb.Children.Add(animation);
            sb.Begin();
        }

        private void PencilButton_Click(object sender, RoutedEventArgs e)
        {
            _viewModel.IsSidebarOpen = PencilButton.IsChecked == true;
            SettingsSplitView.IsPaneOpen = _viewModel.IsSidebarOpen;
            UpdateSidebarState(_viewModel.IsSidebarOpen);
        }

        private void CloseSidebarButton_Click(object sender, RoutedEventArgs e)
        {
            _viewModel.IsSidebarOpen = false;
            PencilButton.IsChecked = false;
            SettingsSplitView.IsPaneOpen = false;
            UpdateSidebarState(false);
        }

        private void UpdateSidebarState(bool isOpen)
        {
            if (isOpen)
            {
                _overlayService.SuspendTimer();
                BottomOverlay.Visibility = Visibility.Collapsed;
                EyeButton.Visibility = Visibility.Collapsed;
            }
            else
            {
                BottomOverlay.Visibility = Visibility.Visible;
                EyeButton.Visibility = Visibility.Visible;
                _overlayService.ResumeTimer();
            }
        }

        private void CatalogButton_Click(object sender, RoutedEventArgs e)
        {
            Frame.Navigate(typeof(CatalogPage), null, new SlideNavigationTransitionInfo { Effect = SlideNavigationTransitionEffect.FromRight });
        }

        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            Frame.Navigate(typeof(SettingsPage), null, new SlideNavigationTransitionInfo { Effect = SlideNavigationTransitionEffect.FromRight });
        }

        private void FullScreenButton_Click(object sender, RoutedEventArgs e)
        {
            if (MainWindow.Instance is MainWindow window)
            {
                window.ToggleFullScreen();
            }
        }

        private void EyeButton_Click(object sender, RoutedEventArgs e)
        {
            _overlayService.ToggleEyeButton();
        }

        private void BandCountSlider_ValueChanged(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs e)
        {
            if (_gpuVisualizer is null || _viewModel is null) return;
            var val = (int)Math.Round(e.NewValue / 4d) * 4;
            _viewModel.BandCount = val;
            BandCountValueText.Text = val.ToString();
            _gpuVisualizer.BarCount = val;
            _audioCore?.TryConfigureSpectralBands(val, _viewModel.ScalingModeIndex);
            AppVisualizerState.SaveSettings();
        }

        private void LayoutSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_gpuVisualizer is null || _viewModel is null) return;
            _viewModel.LayoutIndex = LayoutSelector.SelectedIndex;
            _gpuVisualizer.Layout = (SpectralBarLayout)_viewModel.LayoutIndex;
            AppVisualizerState.SaveSettings();
        }

        private void ColorModeSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_gpuVisualizer is null || _viewModel is null) return;
            _viewModel.ColorModeIndex = ColorModeSelector.SelectedIndex;
            var isCustom = ColorModeSelector.SelectedIndex == 1;
            CustomColorPanel.Visibility = isCustom ? Visibility.Visible : Visibility.Collapsed;
            _gpuVisualizer.ColorMode = isCustom ? SpectralColorMode.Custom : SpectralColorMode.AudioMapped;
            AppVisualizerState.SaveSettings();
        }

        private void PrimaryColorPicker_ColorChanged(ColorPicker sender, ColorChangedEventArgs args)
        {
            if (_gpuVisualizer is null || _viewModel is null) return;
            _viewModel.PrimaryR = args.NewColor.R;
            _viewModel.PrimaryG = args.NewColor.G;
            _viewModel.PrimaryB = args.NewColor.B;
            PrimaryColorPreview.Background = new SolidColorBrush(args.NewColor);
            _gpuVisualizer.CustomPrimary = args.NewColor;
            AppVisualizerState.SaveSettings();
        }

        private void SecondaryColorPicker_ColorChanged(ColorPicker sender, ColorChangedEventArgs args)
        {
            if (_gpuVisualizer is null || _viewModel is null) return;
            _viewModel.SecondaryR = args.NewColor.R;
            _viewModel.SecondaryG = args.NewColor.G;
            _viewModel.SecondaryB = args.NewColor.B;
            SecondaryColorPreview.Background = new SolidColorBrush(args.NewColor);
            _gpuVisualizer.CustomSecondary = args.NewColor;
            AppVisualizerState.SaveSettings();
        }
    }
}
