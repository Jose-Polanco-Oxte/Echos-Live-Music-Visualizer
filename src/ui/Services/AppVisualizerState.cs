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
            SettingsViewModel.ThemePreference = data.ThemePreference;

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

            if (RestoreAudioSelection(data.SelectedAudioDeviceId))
            {
                // RF6.2.3: stale or rejected endpoints are synchronized only
                // after every other persisted field has been restored.
                SaveSettings();
            }
        }

        private static bool RestoreAudioSelection(string? persistedDeviceId)
        {
            var defaultItem = new AudioDeviceItem
            {
                Id = "default",
                Name = "Salida predeterminada del sistema (loopback)",
                Kind = AudioDeviceKind.RenderLoopback,
            };
            var requestedId = string.IsNullOrWhiteSpace(persistedDeviceId)
                ? "default"
                : persistedDeviceId;

            if (requestedId == "default")
            {
                SettingsViewModel.SelectedAudioDevice = defaultItem;
                var defaultResult = AudioCoreService.SelectAudioDevice("default");
                if (!defaultResult.Succeeded)
                {
                    SettingsViewModel.AudioStatusMessage =
                        $"No se pudo iniciar la salida predeterminada del sistema. {defaultResult.ErrorMessage}";
                    SettingsViewModel.AudioStatusKind = AudioStatusKind.Error;
                    SettingsViewModel.AudioRecoveryAction = AudioRecoveryAction.None;
                }
                return false;
            }

            var device = AudioCoreService.GetAudioDevices()
                .FirstOrDefault(candidate => candidate.Id == requestedId);
            if (device is null)
            {
                FallBackToDefault(
                    defaultItem,
                    "El dispositivo guardado ya no está disponible. Se restauró la salida predeterminada del sistema.",
                    AudioStatusKind.Warning,
                    AudioRecoveryAction.None);
                return true;
            }

            if (device.Kind == AudioDeviceKind.DirectCapture
                && MicrophonePrivacyService.CheckForStartup() is MicrophoneAccessState.Denied
                    or MicrophoneAccessState.PromptRequired)
            {
                FallBackToDefault(
                    defaultItem,
                    "Windows todavía no permite usar el micrófono guardado. Se restauró el loopback predeterminado; vuelve a seleccionarlo para revisar el acceso.",
                    AudioStatusKind.Warning,
                    AudioRecoveryAction.OpenMicrophonePrivacy);
                return true;
            }

            var result = AudioCoreService.SelectAudioDevice(device.Id);
            if (!result.Succeeded)
            {
                FallBackToDefault(
                    defaultItem,
                    $"No se pudo restaurar {device.Name}. {result.ErrorMessage}",
                    AudioStatusKind.Error,
                    device.Kind == AudioDeviceKind.DirectCapture
                        ? AudioRecoveryAction.OpenMicrophonePrivacy
                        : AudioRecoveryAction.None);
                return true;
            }

            SettingsViewModel.SelectedAudioDevice = new AudioDeviceItem
            {
                Id = device.Id,
                Name = device.Name,
                Kind = device.Kind,
            };
            return false;
        }

        private static void FallBackToDefault(
            AudioDeviceItem defaultItem,
            string message,
            AudioStatusKind statusKind,
            AudioRecoveryAction recoveryAction)
        {
            var fallback = AudioCoreService.SelectAudioDevice("default");
            if (!fallback.Succeeded)
            {
                message = $"{message} Tampoco se pudo iniciar el loopback predeterminado: {fallback.ErrorMessage}";
                statusKind = AudioStatusKind.Error;
            }
            SettingsViewModel.SelectedAudioDevice = defaultItem;
            SettingsViewModel.AudioStatusMessage = message;
            SettingsViewModel.AudioStatusKind = statusKind;
            SettingsViewModel.AudioRecoveryAction = recoveryAction;
        }

        public static void SaveSettings()
        {
            var data = new UserSettingsData
            {
                SelectedAudioDeviceId = SettingsViewModel.SelectedAudioDevice?.Id ?? "default",
                ThemePreference = SettingsViewModel.ThemePreference,
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
