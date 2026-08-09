namespace EchoVisualizer.Services;

public enum ThemePreference
{
    System = 0,
    Light = 1,
    Dark = 2
}

public static class ThemePreferenceMapper
{
    public static ThemePreference FromLegacyIndex(int index) => index switch
    {
        1 => ThemePreference.Light,
        2 => ThemePreference.Dark,
        _ => ThemePreference.System
    };

    public static int ToLegacyIndex(ThemePreference preference) =>
        (int)Normalize(preference);

    public static ThemePreference Normalize(ThemePreference preference) => preference switch
    {
        ThemePreference.Light => ThemePreference.Light,
        ThemePreference.Dark => ThemePreference.Dark,
        _ => ThemePreference.System
    };
}
