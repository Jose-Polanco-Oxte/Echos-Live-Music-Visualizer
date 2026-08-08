using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EchoVisualizer.ViewModels
{
    public sealed partial class AudioDeviceItem : ObservableObject
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
    }

    public sealed partial class SettingsViewModel : ObservableObject
    {
        [ObservableProperty]
        private AudioDeviceItem? selectedAudioDevice;

        [ObservableProperty]
        private int themeIndex = 0; // 0: System, 1: Light, 2: Dark (Noche)

        public ObservableCollection<AudioDeviceItem> AudioDevices { get; } = new()
        {
            new AudioDeviceItem { Id = "default", Name = "Dispositivo predeterminado del sistema" }
        };
    }
}
