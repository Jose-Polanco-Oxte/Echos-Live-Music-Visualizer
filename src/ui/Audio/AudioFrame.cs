namespace EchoVisualizer.Audio;

/// Managed representation of the native `AudioFrameData` contract.
public sealed record AudioFrame(
    float Rms,
    float SpectralCentroidHz,
    bool OnsetDetected,
    float[] BandEnergies,
    ulong TimestampMs);

/// <summary>
/// Ephemeral projection of the native <c>AudioFrameData</c> buffer.
/// RF-FFI: <see cref="BandEnergies"/> must be consumed before the next native
/// frame read or engine destruction; callers must never store this ref struct.
/// </summary>
public readonly ref struct AudioFrameView(
    float rms,
    float spectralCentroidHz,
    bool onsetDetected,
    ReadOnlySpan<float> bandEnergies,
    ulong timestampMs)
{
    public float Rms { get; } = rms;
    public float SpectralCentroidHz { get; } = spectralCentroidHz;
    public bool OnsetDetected { get; } = onsetDetected;
    public ReadOnlySpan<float> BandEnergies { get; } = bandEnergies;
    public ulong TimestampMs { get; } = timestampMs;

    public AudioFrame Snapshot() => new(Rms, SpectralCentroidHz, OnsetDetected, BandEnergies.ToArray(), TimestampMs);
}

/// <summary>
/// ABI v2 ownership lease. This ref struct deliberately cannot be stored in a
/// field, boxed, or crossed an await. Its spans are valid only until Dispose.
/// </summary>
public readonly unsafe ref struct AudioFrameLease
{
    private readonly AudioCoreService? _owner;
    private readonly NativeAnalysisFrameDataV2 _native;
    private readonly bool _isV2;

    internal AudioFrameLease(AudioCoreService owner, NativeAnalysisFrameDataV2 native, bool isV2)
    {
        _owner = owner;
        _native = native;
        _isV2 = isV2;
    }

    public bool IsValid => _native.LeaseId != 0 && _native.BandCount is > 0 and <= 128;
    public uint AbiVersion => _native.AbiVersion;
    public uint Flags => _native.Flags;
    public float Rms => _native.Rms;
    public float RmsDbfs => _native.RmsDbfs;
    public float SpectralCentroidHz => _native.SpectralCentroidHz;
    public bool OnsetDetected => _native.OnsetDetected != 0;
    public float OnsetScore => _native.OnsetScore;
    public int BandCount => checked((int)_native.BandCount);
    public ulong Sequence => _native.Sequence;
    public ulong CaptureTimestampUs => _native.CaptureTimestampUs;
    public uint AnalysisSampleRateHz => _native.AnalysisSampleRateHz;
    public uint HopFrames => _native.HopFrames;
    public ulong ComputeLatencyUs => _native.ComputeLatencyUs;
    public ulong ProfileGeneration => _native.ProfileGeneration;
    public ReadOnlySpan<float> RawBandEnergies => new(_native.RawBandEnergies, BandCount);
    public ReadOnlySpan<float> ConditionedBandEnergies => new(_native.ConditionedBandEnergies, BandCount);
    public ReadOnlySpan<float> BandPeakEnergies => new(_native.BandPeakEnergies, BandCount);
    public ReadOnlySpan<float> BandCentersHz => new(_native.BandCentersHz, BandCount);

    /// Projects to the legacy ephemeral view without copying. The returned
    /// view has the same lifetime as this lease and must not outlive it.
    public AudioFrameView AsView() => new(
        Rms,
        SpectralCentroidHz,
        OnsetDetected,
        ConditionedBandEnergies,
        CaptureTimestampUs / 1_000);

    public void Dispose()
    {
        if (_isV2 && _owner is not null && _native.LeaseId != 0)
        {
            _owner.ReleaseLease(_native.LeaseId);
        }
    }
}

public interface IAudioFrameSource
{
    AudioFrame Current { get; }
    void Advance();
    bool TryReadFrame(out AudioFrameView frame);
}
