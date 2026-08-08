using EchoVisualizer.Visualizers;

namespace EchoVisualizer.Tests;

public sealed class SpectralBarMathTests
{
    [Fact]
    public void NextEnvelope_UsesInstantAttackAndNormativeDecayEquation()
    {
        Assert.Equal(0.8f, SpectralBarMath.NextEnvelope(0.3f, 0.8f), 5);
        // RF-EQ.2: 0.90 * 1.0 + 0.10 * 0.0.
        Assert.Equal(0.9f, SpectralBarMath.NextEnvelope(1f, 0f), 5);
    }

    [Fact]
    public void GeometryParameters_AcceptZeroGapAndClampBandFrequencyRange()
    {
        Assert.Equal(0f, SpectralBarMath.ClampGap(-10f));
        Assert.Equal(0f, SpectralBarMath.ClampGap(0f));
        Assert.Equal(12f, SpectralBarMath.ClampGap(99f));
        Assert.Equal(20f, SpectralBarMath.CentralFrequencyHz(0, 12), 3);
        Assert.Equal(20_000f, SpectralBarMath.CentralFrequencyHz(11, 12), 1);
    }

    [Fact]
    public void AudioMappedColor_ChangesWithFrequencyAndCentroidPhase()
    {
        var bass = SpectralBarMath.AudioMappedColor(0, 48, 1_000f);
        var treble = SpectralBarMath.AudioMappedColor(47, 48, 1_000f);
        var brightCentroid = SpectralBarMath.AudioMappedColor(0, 48, 16_000f);

        Assert.NotEqual(bass, treble);
        Assert.NotEqual(bass, brightCentroid);
    }

    [Fact]
    public void LogarithmicSampling_EmphasizesLowFrequencySourcePositions()
    {
        var source = Enumerable.Range(0, 128).Select(i => (float)i / 127f).ToArray();
        var low = SpectralBarMath.SampleLogarithmic(source, 1, 48);
        var middle = SpectralBarMath.SampleLogarithmic(source, 24, 48);

        Assert.True(low < 0.01f);
        Assert.True(middle < 0.25f);
    }

    [Fact]
    public void LogarithmicSampling_PreservesEveryNativeBandWhenCountsMatch()
    {
        var source = new[] { 0.02f, 0.85f, 0.11f, 0.73f, 0.36f };

        for (var index = 0; index < source.Length; index++)
        {
            Assert.Equal(source[index], SpectralBarMath.SampleLogarithmic(source, index, source.Length), 5);
        }
    }

    [Fact]
    public void PeakHold_UsesIndependentRateAndImmediateNewPeak()
    {
        Assert.Equal(0.75f, SpectralBarMath.NextPeak(1f, 0.2f, 0.5f, 0.5f), 4);
        Assert.Equal(0.9f, SpectralBarMath.NextPeak(0.2f, 0.9f, 0.5f, 0.5f), 4);
    }
}
