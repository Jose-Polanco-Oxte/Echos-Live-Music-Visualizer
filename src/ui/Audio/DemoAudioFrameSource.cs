namespace EchoVisualizer.Audio;

/// Temporary visual test signal. It keeps rendering independent from capture
/// hardware while the native WASAPI engine is brought online.
public sealed class DemoAudioFrameSource : IAudioFrameSource
{
    private const int BandCount = 48;
    private float _time;
    private readonly float[] _bands = new float[BandCount];

    public AudioFrame Current { get; private set; } = CreateFrame(0f);

    public void Advance()
    {
        _time += 1f / 60f;
        Current = CreateFrame(_time);
    }

    public bool TryReadFrame(out AudioFrameView frame)
    {
        _time += 1f / 60f;
        FillBands(_time, _bands);
        var beatPhase = _time % 0.5f;
        var onset = beatPhase < 0.04f;
        frame = new AudioFrameView(
            0.48f + (onset ? 0.24f : 0f),
            2_400f,
            onset,
            _bands,
            (ulong)(_time * 1_000));
        return true;
    }

    private static AudioFrame CreateFrame(float time)
    {
        var bands = new float[BandCount];
        FillBands(time, bands);

        var beatPhase = time % 0.5f;
        var onset = beatPhase < 0.04f;
        return new AudioFrame(
            Rms: 0.48f + (onset ? 0.24f : 0f),
            SpectralCentroidHz: 2_400f,
            OnsetDetected: onset,
            BandEnergies: bands,
            TimestampMs: (ulong)(time * 1_000));
    }

    private static void FillBands(float time, Span<float> bands)
    {
        for (var index = 0; index < bands.Length; index++)
        {
            var position = index / (float)(bands.Length - 1);
            var wave = (MathF.Sin(time * (2.8f + position * 6f) + position * 13f) + 1f) * 0.5f;
            var envelope = 0.25f + 0.75f * MathF.Pow(1f - position, 0.35f);
            bands[index] = Math.Clamp(wave * envelope, 0.03f, 1f);
        }
    }
}
