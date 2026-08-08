using CommunityToolkit.Mvvm.ComponentModel;

namespace EchoVisualizer.ViewModels
{
    public sealed partial class VisualizerViewModel : ObservableObject
    {
        [ObservableProperty]
        private bool isSidebarOpen;

        [ObservableProperty]
        private int bandCount = 48;

        [ObservableProperty]
        private int scalingModeIndex = 0; // 0: Hybrid LUFS, 1: dB, 2: Linear

        [ObservableProperty]
        private int layoutIndex = 0; // 0: Bottom-Up, 1: Top-Down, 2: Center-Out

        [ObservableProperty]
        private int colorModeIndex = 0; // 0: AudioMapped, 1: Custom Palette

        [ObservableProperty]
        private byte primaryR = 38;

        [ObservableProperty]
        private byte primaryG = 222;

        [ObservableProperty]
        private byte primaryB = 255;

        [ObservableProperty]
        private byte secondaryR = 255;

        [ObservableProperty]
        private byte secondaryG = 62;

        [ObservableProperty]
        private byte secondaryB = 154;

        [ObservableProperty]
        private string customPrimaryHex = "#26DEFF";

        [ObservableProperty]
        private string customSecondaryHex = "#FF3E9A";
    }
}
