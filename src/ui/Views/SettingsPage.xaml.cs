using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using EchoVisualizer.Services;
using EchoVisualizer.ViewModels;

namespace EchoVisualizer.Views
{
    public partial class SettingsPage : Page
    {
        private readonly SettingsViewModel _viewModel = AppVisualizerState.SettingsViewModel;
        private bool _isInitializing = true;

        public SettingsPage()
        {
            _isInitializing = true;
            InitializeComponent();
            DataContext = _viewModel;
            AudioDeviceSelector.ItemsSource = _viewModel.AudioDevices;
            ThemeSelector.SelectedIndex = _viewModel.ThemeIndex;
            LoadAudioDevices();
            _isInitializing = false;
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            _isInitializing = true;
            ThemeSelector.SelectedIndex = _viewModel.ThemeIndex;
            LoadAudioDevices();
            _isInitializing = false;
        }

        private void LoadAudioDevices()
        {
            try
            {
                _isInitializing = true;
                _viewModel.AudioDevices.Clear();

                var devices = AppVisualizerState.AudioCoreService.GetAudioDevices();
                if (devices.Count > 0)
                {
                    foreach (var device in devices)
                    {
                        var displayName = device.IsDefault ? $"{device.Name} (Predeterminado)" : device.Name;
                        _viewModel.AudioDevices.Add(new AudioDeviceItem { Id = device.Id, Name = displayName });
                    }
                }
                else
                {
                    _viewModel.AudioDevices.Add(new AudioDeviceItem { Id = "default", Name = "Dispositivo predeterminado del sistema" });
                }

                SyncSelectedAudioDevice();
            }
            catch
            {
                // Fallback to default
            }
            finally
            {
                _isInitializing = false;
            }
        }

        private void SyncSelectedAudioDevice()
        {
            if (_viewModel.SelectedAudioDevice != null)
            {
                var match = _viewModel.AudioDevices.FirstOrDefault(d => d.Id == _viewModel.SelectedAudioDevice.Id);
                if (match != null)
                {
                    AudioDeviceSelector.SelectedItem = match;
                    return;
                }
            }

            if (_viewModel.AudioDevices.Count > 0)
            {
                AudioDeviceSelector.SelectedIndex = 0;
            }
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
        }

        private void AudioDeviceSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isInitializing) return;

            if (AudioDeviceSelector.SelectedItem is AudioDeviceItem selectedDevice)
            {
                if (_viewModel.SelectedAudioDevice?.Id != selectedDevice.Id)
                {
                    _viewModel.SelectedAudioDevice = selectedDevice;
                    if (!string.IsNullOrEmpty(selectedDevice.Id) && selectedDevice.Id != "default")
                    {
                        try
                        {
                            AppVisualizerState.AudioCoreService.TrySelectAudioDevice(selectedDevice.Id);
                        }
                        catch
                        {
                            // Safe fallback
                        }
                    }
                    AppVisualizerState.SaveSettings();
                }
            }
        }

        private void ThemeSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isInitializing || ThemeSelector.SelectedIndex < 0) return;

            if (_viewModel.ThemeIndex != ThemeSelector.SelectedIndex)
            {
                _viewModel.ThemeIndex = ThemeSelector.SelectedIndex;

                var targetTheme = ThemeSelector.SelectedIndex switch
                {
                    1 => ElementTheme.Light,
                    2 => ElementTheme.Dark,
                    _ => ElementTheme.Default
                };

                if (MainWindow.Instance != null)
                {
                    MainWindow.Instance.SetTheme(targetTheme);
                }
                else
                {
                    RequestedTheme = targetTheme;
                }

                AppVisualizerState.SaveSettings();
            }
        }
    }
}
