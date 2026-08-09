using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace EchoVisualizer.Services
{
    public class UserSettingsData
    {
        // Global Settings
        public string SelectedAudioDeviceId { get; set; } = "default";
        private ThemePreference _themePreference = ThemePreference.System;

        // Keep the persisted ThemeIndex key so existing settings migrate without
        // a second settings store or a one-time file rewrite.
        [JsonPropertyName("ThemeIndex")]
        public ThemePreference ThemePreference
        {
            get => _themePreference;
            set => _themePreference = ThemePreferenceMapper.Normalize(value);
        }

        // Visualizer Customization Settings
        public int BandCount { get; set; } = 48;
        public int ScalingModeIndex { get; set; } = 2; // PerceptualPinkNoise
        public int LayoutIndex { get; set; } = 0; // BottomUp
        public int ColorModeIndex { get; set; } = 0; // AudioMapped
        public byte PrimaryR { get; set; } = 38;
        public byte PrimaryG { get; set; } = 222;
        public byte PrimaryB { get; set; } = 255;
        public byte SecondaryR { get; set; } = 255;
        public byte SecondaryG { get; set; } = 62;
        public byte SecondaryB { get; set; } = 154;

        // Catalog Preferences
        public string SelectedPresetId { get; set; } = "bars-spectral";
        public List<string> FavoritePresetIds { get; set; } = new();
    }

    public static class UserSettingsService
    {
        private static readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = true };

        public static string GetSettingsFilePath()
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EchoVisualizer");
            Directory.CreateDirectory(folder);
            return Path.Combine(folder, "user_settings.json");
        }

        public static UserSettingsData Load()
        {
            return LoadFromPath(GetSettingsFilePath());
        }

        internal static UserSettingsData LoadFromPath(string filePath)
        {
            try
            {
                if (File.Exists(filePath))
                {
                    var json = File.ReadAllText(filePath);
                    var data = JsonSerializer.Deserialize<UserSettingsData>(json, _jsonOptions);
                    if (data != null)
                    {
                        return data;
                    }
                }
            }
            catch
            {
                // Fallback to default on read/deserialize error
            }

            return new UserSettingsData();
        }

        public static bool Save(UserSettingsData data)
        {
            return SaveToPath(data, GetSettingsFilePath());
        }

        internal static bool SaveToPath(UserSettingsData data, string filePath)
        {
            try
            {
                var directory = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }
                var json = JsonSerializer.Serialize(data, _jsonOptions);
                File.WriteAllText(filePath, json);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
