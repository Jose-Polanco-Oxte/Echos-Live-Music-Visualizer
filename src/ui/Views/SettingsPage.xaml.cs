using System;
using System.Linq;
using System.Threading;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using EchoVisualizer.Audio;
using EchoVisualizer.Services;
using EchoVisualizer.ViewModels;

namespace EchoVisualizer.Views
{
    public partial class SettingsPage : Page
    {
        private readonly SettingsViewModel _viewModel = AppVisualizerState.SettingsViewModel;
        private bool _isInitializing = true;
        private CancellationTokenSource? _activityConfirmation;

        public SettingsPage()
        {
            _isInitializing = true;
            InitializeComponent();
            DataContext = _viewModel;
            AudioDeviceSelector.ItemsSource = _viewModel.AudioDevices;
            ThemeSelector.SelectedIndex = ThemePreferenceMapper.ToLegacyIndex(_viewModel.ThemePreference);
            LoadAudioDevices();
            RestoreAudioStatus();
            _isInitializing = false;
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            _isInitializing = true;
            ThemeSelector.SelectedIndex = ThemePreferenceMapper.ToLegacyIndex(_viewModel.ThemePreference);
            LoadAudioDevices();
            RestoreAudioStatus();
            _isInitializing = false;
        }

        protected override void OnNavigatedFrom(NavigationEventArgs e)
        {
            _activityConfirmation?.Cancel();
            _activityConfirmation?.Dispose();
            _activityConfirmation = null;
            base.OnNavigatedFrom(e);
        }

        private void LoadAudioDevices()
        {
            try
            {
                _isInitializing = true;
                _viewModel.AudioDevices.Clear();
                _viewModel.AudioDevices.Add(new AudioDeviceItem
                {
                    Id = "default",
                    Name = "Salida predeterminada del sistema (loopback)",
                    Kind = AudioDeviceKind.RenderLoopback,
                });

                var devices = AppVisualizerState.AudioCoreService.GetAudioDevices();
                foreach (var device in devices)
                {
                    var category = device.Kind == AudioDeviceKind.DirectCapture
                        ? "Entrada directa"
                        : "Salida (loopback)";
                    var defaultSuffix = device.IsDefault ? " (Predeterminado)" : string.Empty;
                    _viewModel.AudioDevices.Add(new AudioDeviceItem
                    {
                        Id = device.Id,
                        Name = $"{category}: {device.Name}{defaultSuffix}",
                        Kind = device.Kind,
                    });
                }

                SyncSelectedAudioDevice();
            }
            catch (Exception exception)
            {
                ShowAudioStatus(
                    $"No se pudieron enumerar los dispositivos. {exception.Message}",
                    AudioStatusKind.Error,
                    AudioRecoveryAction.None);
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

        private async void AudioDeviceSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isInitializing) return;

            if (AudioDeviceSelector.SelectedItem is AudioDeviceItem selectedDevice)
            {
                if (_viewModel.SelectedAudioDevice?.Id != selectedDevice.Id)
                {
                    var previousDevice = _viewModel.SelectedAudioDevice;
                    var selectionCommitted = false;
                    AudioDeviceSelector.IsEnabled = false;
                    try
                    {
                        if (selectedDevice.Kind == AudioDeviceKind.DirectCapture)
                        {
                            var access = await MicrophonePrivacyService.EnsureAccessAsync();
                            if (access is MicrophoneAccessState.Denied or MicrophoneAccessState.PromptRequired)
                            {
                                ShowAudioStatus(
                                    "Windows no permite el acceso al micrófono. Revisa la configuración de privacidad y vuelve a intentarlo.",
                                    AudioStatusKind.Error,
                                    AudioRecoveryAction.OpenMicrophonePrivacy);
                                RestoreSelection(previousDevice);
                                return;
                            }
                        }

                        var result = AppVisualizerState.AudioCoreService.SelectAudioDevice(selectedDevice.Id);
                        if (!result.Succeeded)
                        {
                            var unpackagedGuidance = selectedDevice.Kind == AudioDeviceKind.DirectCapture
                                && !MicrophonePrivacyService.HasPackageIdentity
                                ? " En la versión unpackaged, Windows controla el acceso mediante el ajuste global para aplicaciones de escritorio."
                                : string.Empty;
                            ShowAudioStatus(
                                $"No se pudo iniciar {selectedDevice.Name}. {result.ErrorMessage}{unpackagedGuidance}",
                                AudioStatusKind.Error,
                                selectedDevice.Kind == AudioDeviceKind.DirectCapture
                                    ? AudioRecoveryAction.OpenMicrophonePrivacy
                                    : AudioRecoveryAction.None);
                            RestoreSelection(previousDevice);
                            return;
                        }

                        _viewModel.SelectedAudioDevice = selectedDevice;
                        AppVisualizerState.SaveSettings();
                        selectionCommitted = true;
                        ShowAudioStatus(
                            $"{selectedDevice.Name} se inició. Comprobando actividad…",
                            AudioStatusKind.Informational,
                            AudioRecoveryAction.None);
                        await ConfirmActivityAsync(selectedDevice);
                    }
                    catch (OperationCanceledException)
                    {
                        // Navigation or a newer selection ended this diagnostic.
                    }
                    catch (Exception exception)
                    {
                        ShowAudioStatus(
                            $"No se pudo completar el cambio de dispositivo. {exception.Message}",
                            AudioStatusKind.Error,
                            selectedDevice.Kind == AudioDeviceKind.DirectCapture
                                ? AudioRecoveryAction.OpenMicrophonePrivacy
                                : AudioRecoveryAction.None);
                        if (!selectionCommitted)
                        {
                            RestoreSelection(previousDevice);
                        }
                    }
                    finally
                    {
                        AudioDeviceSelector.IsEnabled = true;
                    }
                }
            }
        }

        private void RestoreSelection(AudioDeviceItem? device)
        {
            _isInitializing = true;
            AudioDeviceSelector.SelectedItem = device is null
                ? null
                : _viewModel.AudioDevices.FirstOrDefault(candidate => candidate.Id == device.Id);
            _isInitializing = false;
        }

        private async System.Threading.Tasks.Task ConfirmActivityAsync(AudioDeviceItem selectedDevice)
        {
            _activityConfirmation?.Cancel();
            _activityConfirmation?.Dispose();
            _activityConfirmation = new CancellationTokenSource();
            var activity = await AppVisualizerState.AudioCoreService.ConfirmCaptureActivityAsync(
                TimeSpan.FromSeconds(3),
                _activityConfirmation.Token);
            if (activity == AudioCaptureActivityResult.Advancing)
            {
                ShowAudioStatus(
                    $"{selectedDevice.Name} está entregando audio.",
                    AudioStatusKind.Success,
                    AudioRecoveryAction.None);
            }
            else
            {
                ShowAudioStatus(
                    $"{selectedDevice.Name} se abrió, pero no llegaron datos de audio en 3 segundos.",
                    AudioStatusKind.Warning,
                    selectedDevice.Kind == AudioDeviceKind.DirectCapture
                        ? AudioRecoveryAction.OpenMicrophonePrivacy
                        : AudioRecoveryAction.RetryActivity);
            }
        }

        private void RestoreAudioStatus()
        {
            if (!string.IsNullOrWhiteSpace(_viewModel.AudioStatusMessage))
            {
                ShowAudioStatus(
                    _viewModel.AudioStatusMessage,
                    _viewModel.AudioStatusKind,
                    _viewModel.AudioRecoveryAction);
            }
        }

        private void ShowAudioStatus(
            string message,
            AudioStatusKind statusKind,
            AudioRecoveryAction recoveryAction)
        {
            _viewModel.AudioStatusMessage = message;
            _viewModel.AudioStatusKind = statusKind;
            _viewModel.AudioRecoveryAction = recoveryAction;
            AudioStatusBar.Message = message;
            AudioStatusBar.Severity = statusKind switch
            {
                AudioStatusKind.Success => InfoBarSeverity.Success,
                AudioStatusKind.Warning => InfoBarSeverity.Warning,
                AudioStatusKind.Error => InfoBarSeverity.Error,
                _ => InfoBarSeverity.Informational,
            };
            AudioRecoveryButton.Content = recoveryAction == AudioRecoveryAction.RetryActivity
                ? "Volver a comprobar"
                : "Abrir privacidad del micrófono";
            AudioRecoveryButton.Visibility = recoveryAction == AudioRecoveryAction.None
                ? Visibility.Collapsed
                : Visibility.Visible;
            AudioStatusBar.IsOpen = true;
        }

        private async void AudioRecoveryButton_Click(object sender, RoutedEventArgs e)
        {
            if (_viewModel.AudioRecoveryAction == AudioRecoveryAction.OpenMicrophonePrivacy)
            {
                await MicrophonePrivacyService.OpenPrivacySettingsAsync();
                return;
            }

            if (_viewModel.AudioRecoveryAction == AudioRecoveryAction.RetryActivity
                && _viewModel.SelectedAudioDevice is { } selectedDevice)
            {
                AudioDeviceSelector.IsEnabled = false;
                try
                {
                    ShowAudioStatus(
                        $"Comprobando de nuevo la actividad de {selectedDevice.Name}…",
                        AudioStatusKind.Informational,
                        AudioRecoveryAction.None);
                    await ConfirmActivityAsync(selectedDevice);
                }
                catch (OperationCanceledException)
                {
                }
                finally
                {
                    AudioDeviceSelector.IsEnabled = true;
                }
            }
        }

        private void ThemeSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isInitializing || ThemeSelector.SelectedIndex < 0) return;

            var preference = ThemePreferenceMapper.FromLegacyIndex(ThemeSelector.SelectedIndex);
            if (_viewModel.ThemePreference != preference)
            {
                _viewModel.ThemePreference = preference;
                AppVisualizerState.SaveSettings();
            }
        }
    }
}
