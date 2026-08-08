using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace EchoVisualizer.Services
{
    public class UserSettingsData
    {
        // Global Settings
        public string SelectedAudioDeviceId { get; set; } = "default";
        public int ThemeIndex { get; set; } = 0; // 0: System, 1: Light, 2: Dark/Night

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
            try
            {
                var filePath = GetSettingsFilePath();
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
            try
            {
                var filePath = GetSettingsFilePath();
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
