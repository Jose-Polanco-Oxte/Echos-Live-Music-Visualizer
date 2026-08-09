using EchoVisualizer.ViewModels;
using EchoVisualizer.Services;

namespace EchoVisualizer.Tests;

public sealed class ViewModelsTests
{
    [Fact]
    public void VisualizerViewModel_DefaultPropertiesAreValid()
    {
        var vm = new VisualizerViewModel();
        Assert.False(vm.IsSidebarOpen);
        Assert.Equal(48, vm.BandCount);
        Assert.Equal(0, vm.LayoutIndex);
        Assert.Equal(0, vm.ColorModeIndex);
        Assert.Equal("#26DEFF", vm.CustomPrimaryHex);
        Assert.Equal("#FF3E9A", vm.CustomSecondaryHex);
    }

    [Fact]
    public void CatalogViewModel_ContainsDefaultRS_EBPreset()
    {
        var vm = new CatalogViewModel();
        Assert.Single(vm.Items);
        Assert.Equal("bars", vm.Items[0].Id);
        Assert.True(vm.Items[0].IsFavorite);
        Assert.True(vm.Items[0].IsSelected);
    }

    [Fact]
    public void SettingsViewModel_DefaultThemeIsSystem()
    {
        var vm = new SettingsViewModel();
        Assert.Equal(ThemePreference.System, vm.ThemePreference);
        Assert.NotEmpty(vm.AudioDevices);
    }
}
