using System.Numerics;

namespace EchoVisualizer.Visualizers;

public enum SpectralBarLayout
{
    BottomUp,
    TopDown,
    CenterOut
}

public enum SpectralBarVariant
{
    Bars
}

public enum SpectralColorMode
{
    AudioMapped,
    CustomPalette,
    Custom = CustomPalette
}

/// <summary>
/// Deterministic RS-EB mappings. Keeping these calculations separate lets the
/// renderer consume short-lived native spans without retaining them.
/// </summary>
public static class SpectralBarMath
{
    public const float MinimumFrequencyHz = 20f;
    public const float MaximumFrequencyHz = 20_000f;
    public const float DefaultDecay = 0.90f;

    /// <summary>
    /// RF-EQ.2: instant attack; otherwise alpha * previous + (1-alpha) * energy.
    /// </summary>
    public static float NextEnvelope(float previous, float energy, float decay = DefaultDecay)
    {
        var safePrevious = Sanitize(previous);
        var safeEnergy = Sanitize(energy);
        var safeDecay = Math.Clamp(decay, 0.85f, 0.95f);
        return safeEnergy >= safePrevious
            ? safeEnergy
            : (safeDecay * safePrevious) + ((1f - safeDecay) * safeEnergy);
    }

    public static float NextPeak(float previousPeak, float envelope, float fallPerSecond, float deltaSeconds) =>
        Math.Max(Sanitize(envelope), Math.Max(0f, Sanitize(previousPeak) - (Math.Max(0f, fallPerSecond) * Math.Max(0f, deltaSeconds))));

    public static float ClampGap(float gap) => Math.Clamp(float.IsFinite(gap) ? gap : 0f, 0f, 12f);

    public static float CentralFrequencyHz(int index, int count)
    {
        var progress = count <= 1 ? 0.5f : Math.Clamp(index / (float)(count - 1), 0f, 1f);
        return MinimumFrequencyHz * MathF.Pow(MaximumFrequencyHz / MinimumFrequencyHz, progress);
    }

    /// <summary>
    /// RF-EQ.3: log-frequency hue with a global phase driven by spectral centroid.
    /// Returns normalized RGB so it is portable to tests and Win2D.
    /// </summary>
    public static Vector3 AudioMappedColor(int index, int count, float spectralCentroidHz)
    {
        var relativeFrequency = count <= 1 ? 0.5f : Math.Clamp(index / (float)(count - 1), 0f, 1f);
        var centroid = Math.Clamp(SanitizeFrequencyHz(spectralCentroidHz) / MaximumFrequencyHz, 0f, 1f);
        // Blue-to-magenta identity palette plus a centroid phase of +/- 0.07 turns.
        var hue = Wrap01(0.54f + (relativeFrequency * 0.37f) + ((centroid - 0.5f) * 0.14f));
        return HsvToRgb(hue, 0.82f, 1f);
    }

    public static float LogSamplePosition(int sourceLength, int index, int targetLength)
    {
        if (sourceLength <= 1 || targetLength <= 1)
        {
            return 0f;
        }

        var normalized = index / (float)(targetLength - 1);
        // Preserve 20 Hz as the first band and sample the source on a logarithmic axis.
        var mapped = (MathF.Pow(sourceLength, normalized) - 1f) / (sourceLength - 1f);
        return Math.Clamp(mapped * (sourceLength - 1), 0f, sourceLength - 1);
    }

    public static float SampleLogarithmic(ReadOnlySpan<float> source, int index, int targetLength)
    {
        if (source.IsEmpty)
        {
            return 0f;
        }

        if (source.Length == 1 || targetLength <= 1)
        {
            return Sanitize(source[0]);
        }

        // RF-EQ.1/2: when Core already published the requested logarithmic or
        // Mel N-band vector, preserve E_i exactly. Interpolating it again
        // creates the artificial smooth arch visible with a three-band source.
        if (source.Length == targetLength)
        {
            return Sanitize(source[Math.Clamp(index, 0, source.Length - 1)]);
        }

        var position = LogSamplePosition(source.Length, index, targetLength);
        var lower = (int)position;
        var upper = Math.Min(source.Length - 1, lower + 1);
        var fraction = position - lower;
        return Sanitize(source[lower] + ((source[upper] - source[lower]) * fraction));
    }

    private static Vector3 HsvToRgb(float hue, float saturation, float value)
    {
        var sector = hue * 6f;
        var index = (int)MathF.Floor(sector) % 6;
        var fraction = sector - MathF.Floor(sector);
        var p = value * (1f - saturation);
        var q = value * (1f - (fraction * saturation));
        var t = value * (1f - ((1f - fraction) * saturation));
        return index switch
        {
            0 => new Vector3(value, t, p),
            1 => new Vector3(q, value, p),
            2 => new Vector3(p, value, t),
            3 => new Vector3(p, q, value),
            4 => new Vector3(t, p, value),
            _ => new Vector3(value, p, q),
        };
    }

    private static float Sanitize(float value) => float.IsFinite(value) ? Math.Clamp(value, 0f, 1f) : 0f;

    private static float SanitizeFrequencyHz(float value) => float.IsFinite(value) ? Math.Max(0f, value) : 0f;

    private static float Wrap01(float value) => value - MathF.Floor(value);
}
