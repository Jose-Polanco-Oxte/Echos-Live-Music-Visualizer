using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using EchoVisualizer.Audio;
using EchoVisualizer.Services;

namespace EchoVisualizer.ViewModels
{
    public sealed partial class AudioDeviceItem : ObservableObject
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public AudioDeviceKind Kind { get; set; } = AudioDeviceKind.RenderLoopback;
    }

    public sealed partial class SettingsViewModel : ObservableObject
    {
        [ObservableProperty]
        private AudioDeviceItem? selectedAudioDevice;

        [ObservableProperty]
        private ThemePreference themePreference = ThemePreference.System;

        [ObservableProperty]
        private string? audioStatusMessage;

        [ObservableProperty]
        private AudioStatusKind audioStatusKind;

        [ObservableProperty]
        private AudioRecoveryAction audioRecoveryAction;

        public ObservableCollection<AudioDeviceItem> AudioDevices { get; } = new()
        {
            new AudioDeviceItem { Id = "default", Name = "Dispositivo predeterminado del sistema" }
        };
    }

    public enum AudioStatusKind
    {
        Informational,
        Success,
        Warning,
        Error,
    }

    public enum AudioRecoveryAction
    {
        None,
        OpenMicrophonePrivacy,
        RetryActivity,
    }
}
