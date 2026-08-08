using System;
using System.IO;
using Xunit;
using EchoVisualizer.Services;

namespace EchoVisualizer.Tests
{
    public sealed class UserSettingsTests
    {
        [Fact]
        public void UserSettingsService_SaveAndLoad_RoundtripsDataCorrectly()
        {
            var data = new UserSettingsData
            {
                SelectedAudioDeviceId = "test-device-id-123",
                ThemeIndex = 1, // Light
                BandCount = 64,
                ScalingModeIndex = 1,
                LayoutIndex = 2,
                ColorModeIndex = 1,
                PrimaryR = 100,
                PrimaryG = 150,
                PrimaryB = 200,
                SecondaryR = 210,
                SecondaryG = 220,
                SecondaryB = 230,
                SelectedPresetId = "custom-bars-preset"
            };
            data.FavoritePresetIds.Add("preset-1");
            data.FavoritePresetIds.Add("preset-2");

            bool saveResult = UserSettingsService.Save(data);
            Assert.True(saveResult);

            var loaded = UserSettingsService.Load();
            Assert.NotNull(loaded);
            Assert.Equal("test-device-id-123", loaded.SelectedAudioDeviceId);
            Assert.Equal(1, loaded.ThemeIndex);
            Assert.Equal(64, loaded.BandCount);
            Assert.Equal(1, loaded.ScalingModeIndex);
            Assert.Equal(2, loaded.LayoutIndex);
            Assert.Equal(1, loaded.ColorModeIndex);
            Assert.Equal(100, loaded.PrimaryR);
            Assert.Equal(150, loaded.PrimaryG);
            Assert.Equal(200, loaded.PrimaryB);
            Assert.Equal(210, loaded.SecondaryR);
            Assert.Equal(220, loaded.SecondaryG);
            Assert.Equal(230, loaded.SecondaryB);
            Assert.Equal("custom-bars-preset", loaded.SelectedPresetId);
            Assert.Contains("preset-1", loaded.FavoritePresetIds);
            Assert.Contains("preset-2", loaded.FavoritePresetIds);
        }
    }
}
