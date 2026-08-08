using System.Linq;
using EchoVisualizer.Audio;
using EchoVisualizer.ViewModels;

namespace EchoVisualizer.Services
{
    public static class AppVisualizerState
    {
        public static AudioCoreService AudioCoreService { get; } = new();
        public static VisualizerViewModel VisualizerViewModel { get; } = new();
        public static SettingsViewModel SettingsViewModel { get; } = new();
        public static CatalogViewModel CatalogViewModel { get; } = new();

        public static void InitializeAndLoadSettings()
        {
            var data = UserSettingsService.Load();

            // Load Global Settings
            SettingsViewModel.ThemeIndex = data.ThemeIndex;
            if (!string.IsNullOrEmpty(data.SelectedAudioDeviceId))
            {
                SettingsViewModel.SelectedAudioDevice = new AudioDeviceItem { Id = data.SelectedAudioDeviceId, Name = data.SelectedAudioDeviceId };
                if (data.SelectedAudioDeviceId != "default")
                {
                    AudioCoreService.TrySelectAudioDevice(data.SelectedAudioDeviceId);
                }
            }

            // Load Visualizer Customization Settings
            VisualizerViewModel.BandCount = data.BandCount;
            VisualizerViewModel.ScalingModeIndex = data.ScalingModeIndex;
            VisualizerViewModel.LayoutIndex = data.LayoutIndex;
            VisualizerViewModel.ColorModeIndex = data.ColorModeIndex;
            VisualizerViewModel.PrimaryR = data.PrimaryR;
            VisualizerViewModel.PrimaryG = data.PrimaryG;
            VisualizerViewModel.PrimaryB = data.PrimaryB;
            VisualizerViewModel.SecondaryR = data.SecondaryR;
            VisualizerViewModel.SecondaryG = data.SecondaryG;
            VisualizerViewModel.SecondaryB = data.SecondaryB;

            // Load Catalog Preferences
            if (data.FavoritePresetIds != null && data.FavoritePresetIds.Count > 0)
            {
                foreach (var item in CatalogViewModel.Items)
                {
                    item.IsFavorite = data.FavoritePresetIds.Contains(item.Id);
                }
            }

            if (!string.IsNullOrEmpty(data.SelectedPresetId))
            {
                var selected = CatalogViewModel.Items.FirstOrDefault(p => p.Id == data.SelectedPresetId);
                if (selected != null)
                {
                    foreach (var item in CatalogViewModel.Items) item.IsSelected = false;
                    selected.IsSelected = true;
                }
            }
        }

        public static void SaveSettings()
        {
            var data = new UserSettingsData
            {
                SelectedAudioDeviceId = SettingsViewModel.SelectedAudioDevice?.Id ?? "default",
                ThemeIndex = SettingsViewModel.ThemeIndex,
                BandCount = VisualizerViewModel.BandCount,
                ScalingModeIndex = VisualizerViewModel.ScalingModeIndex,
                LayoutIndex = VisualizerViewModel.LayoutIndex,
                ColorModeIndex = VisualizerViewModel.ColorModeIndex,
                PrimaryR = VisualizerViewModel.PrimaryR,
                PrimaryG = VisualizerViewModel.PrimaryG,
                PrimaryB = VisualizerViewModel.PrimaryB,
                SecondaryR = VisualizerViewModel.SecondaryR,
                SecondaryG = VisualizerViewModel.SecondaryG,
                SecondaryB = VisualizerViewModel.SecondaryB,
                SelectedPresetId = CatalogViewModel.Items.FirstOrDefault(p => p.IsSelected)?.Id ?? "bars"
            };

            foreach (var preset in CatalogViewModel.Items)
            {
                if (preset.IsFavorite)
                {
                    data.FavoritePresetIds.Add(preset.Id);
                }
            }

            UserSettingsService.Save(data);
        }
    }
}
