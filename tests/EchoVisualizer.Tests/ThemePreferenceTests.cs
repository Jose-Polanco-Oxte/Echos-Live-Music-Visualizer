using System.Text.Json;
using EchoVisualizer.Services;

namespace EchoVisualizer.Tests;

public sealed class ThemePreferenceTests
{
    [Theory]
    [InlineData(-1, ThemePreference.System)]
    [InlineData(0, ThemePreference.System)]
    [InlineData(1, ThemePreference.Light)]
    [InlineData(2, ThemePreference.Dark)]
    [InlineData(3, ThemePreference.System)]
    public void FromLegacyIndex_MapsKnownValuesAndNormalizesUnknownValues(
        int index,
        ThemePreference expected)
    {
        Assert.Equal(expected, ThemePreferenceMapper.FromLegacyIndex(index));
    }

    [Theory]
    [InlineData(ThemePreference.System, 0)]
    [InlineData(ThemePreference.Light, 1)]
    [InlineData(ThemePreference.Dark, 2)]
    [InlineData((ThemePreference)99, 0)]
    public void ToLegacyIndex_PreservesThePersistedContract(ThemePreference preference, int expected)
    {
        Assert.Equal(expected, ThemePreferenceMapper.ToLegacyIndex(preference));
    }

    [Fact]
    public void UserSettingsData_DeserializesExistingIntegerThemeIndex()
    {
        var data = JsonSerializer.Deserialize<UserSettingsData>("""{"ThemeIndex":2}""");

        Assert.NotNull(data);
        Assert.Equal(ThemePreference.Dark, data.ThemePreference);
    }

    [Fact]
    public void UserSettingsData_NormalizesUnknownPersistedThemeIndex()
    {
        var data = JsonSerializer.Deserialize<UserSettingsData>("""{"ThemeIndex":99}""");

        Assert.NotNull(data);
        Assert.Equal(ThemePreference.System, data.ThemePreference);
    }

    [Fact]
    public void UserSettingsData_KeepsLegacyJsonPropertyName()
    {
        var json = JsonSerializer.Serialize(new UserSettingsData
        {
            ThemePreference = ThemePreference.Light
        });

        Assert.Contains("\"ThemeIndex\":1", json);
        Assert.DoesNotContain("ThemePreference", json);
    }
}
