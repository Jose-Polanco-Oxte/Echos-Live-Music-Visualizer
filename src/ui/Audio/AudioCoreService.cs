using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;

namespace EchoVisualizer.Audio;

/// Owns the native DSP engine. The real-time presentation path borrows the
/// worker-published ABI v2 frame through AudioFrameLease; the managed snapshot
/// remains only as a legacy/demo compatibility surface.
public sealed unsafe class AudioCoreService : IAudioFrameSource, IDisposable
{
    private readonly AudioEngineHandle? _handle;
    private bool _v2Available = true;

    public AudioCoreService(uint sampleRate = 48_000, uint frameSize = 1_024)
    {
        try
        {
            var handle = EchoCoreNative.Initialize(sampleRate, frameSize);
            if (handle != IntPtr.Zero)
            {
                _handle = new AudioEngineHandle(handle);
            }
            else
            {
                InitializationError = "EchoCore no pudo crear el motor de audio.";
            }
        }
        catch (DllNotFoundException exception)
        {
            InitializationError = $"EchoCore.dll no está disponible: {exception.Message}";
        }
        catch (EntryPointNotFoundException exception)
        {
            InitializationError = $"EchoCore.dll no expone la ABI requerida: {exception.Message}";
        }
        catch (BadImageFormatException exception)
        {
            InitializationError = $"EchoCore.dll no coincide con la arquitectura x64: {exception.Message}";
        }

        Current = new AudioFrame(0, 0, false, Array.Empty<float>(), 0);
    }

    public bool IsAvailable => _handle is { IsInvalid: false, IsClosed: false };

    /// <summary>Reason shown by the UI when the native capture engine cannot start.</summary>
    public string? InitializationError { get; }

    public AudioFrame Current { get; private set; }

    /// <summary>
    /// FFI §2.1: returns a zero-allocation view over the Rust-owned frame.
    /// The view expires at the next native read or when this service is disposed.
    /// </summary>
    public bool TryReadFrame(out AudioFrameView view)
    {
        view = default;
        if (!IsAvailable)
        {
            return false;
        }

        NativeAudioFrameData frame = default;
        if (EchoCoreNative.GetLatestFrame(_handle!.DangerousGetHandle(), &frame) == 0
            || frame.BandEnergies == null
            || frame.BandCount is 0 or > 128)
        {
            return false;
        }

        view = new AudioFrameView(
            frame.Rms,
            frame.SpectralCentroidHz,
            frame.OnsetDetected != 0,
            new ReadOnlySpan<float>(frame.BandEnergies, checked((int)frame.BandCount)),
            frame.TimestampMs);
        return true;
    }

    /// <summary>
    /// RF5.1/RNF-PERF.3: acquire the worker-published v2 frame. This operation
    /// only borrows a retained native slot; it never schedules DSP. The caller
    /// must dispose the returned lease in the same synchronous tick.
    /// </summary>
    public bool TryAcquireFrame(out AudioFrameLease lease)
    {
        lease = default;
        if (!IsAvailable)
        {
            return false;
        }

        if (_v2Available)
        {
            NativeAnalysisFrameDataV2 native = default;
            try
            {
                if (EchoCoreNative.AcquireLatestAnalysisFrameV2(_handle!.DangerousGetHandle(), &native) != 0
                    && native.AbiVersion == 2
                    && native.LeaseId != 0
                    && native.BandCount is > 0 and <= 128
                    && native.ConditionedBandEnergies is not null)
                {
                    lease = new AudioFrameLease(this, native, isV2: true);
                    return true;
                }

                return false;
            }
            catch (EntryPointNotFoundException)
            {
                // Compatibility with a pre-v2 DLL. This path is intentionally
                // isolated and is not used by the current packaged runtime.
                _v2Available = false;
            }
        }

        // ABI v1 fallback: keep old deployments usable. v1 owns no explicit
        // lease, so the returned view remains valid only until the next poll.
        NativeAudioFrameData legacy = default;
        if (EchoCoreNative.GetLatestFrame(_handle!.DangerousGetHandle(), &legacy) == 0
            || legacy.BandEnergies is null
            || legacy.BandCount is 0 or > 128)
        {
            return false;
        }

        var nativeV2 = new NativeAnalysisFrameDataV2
        {
            AbiVersion = 1,
            Rms = legacy.Rms,
            SpectralCentroidHz = legacy.SpectralCentroidHz,
            OnsetDetected = legacy.OnsetDetected,
            BandCount = legacy.BandCount,
            ConditionedBandEnergies = legacy.BandEnergies,
            CaptureTimestampUs = legacy.TimestampMs * 1_000,
            LeaseId = 0,
        };
        lease = new AudioFrameLease(this, nativeV2, isV2: false);
        return true;
    }

    internal void ReleaseLease(ulong leaseId)
    {
        if (!IsAvailable || leaseId == 0 || !_v2Available)
        {
            return;
        }

        try
        {
            _ = EchoCoreNative.ReleaseAnalysisFrameV2(_handle!.DangerousGetHandle(), leaseId);
        }
        catch (EntryPointNotFoundException)
        {
            _v2Available = false;
        }
    }

    /// <summary>
    /// RF1.3/RF-EQ.1: configures the native FFT grouping requested by the
    /// spectral-bars profile. The UI only accepts its normative 12–128 range.
    /// </summary>
    public bool TryConfigureSpectralBands(int bandCount, int scaleType) =>
        IsAvailable
        && bandCount is >= 12 and <= 128
        && scaleType is >= 0 and <= 2
        && EchoCoreNative.SetBandConfiguration(
            _handle!.DangerousGetHandle(),
            checked((uint)bandCount),
            checked((byte)scaleType)) != 0;

    /// <summary>RF6.2.2: active render endpoints that support system loopback.</summary>
    public IReadOnlyList<AudioDevice> GetAudioDevices()
    {
        if (!IsAvailable)
        {
            return [];
        }

        NativeAudioDeviceProperties* nativeDevices = null;
        uint count = 0;
        if (EchoCoreNative.GetAudioDevices(_handle!.DangerousGetHandle(), &nativeDevices, &count) == 0
            || nativeDevices is null)
        {
            return [];
        }

        try
        {
            var devices = new List<AudioDevice>(checked((int)count));
            for (var index = 0; index < count; index++)
            {
                var device = nativeDevices[index];
                if (device.DeviceId is null || device.Name is null)
                {
                    continue;
                }

                devices.Add(new AudioDevice(
                    Marshal.PtrToStringUTF8((IntPtr)device.DeviceId) ?? string.Empty,
                    Marshal.PtrToStringUTF8((IntPtr)device.Name) ?? string.Empty,
                    device.IsDefault != 0));
            }
            return devices;
        }
        finally
        {
            EchoCoreNative.FreeDeviceList(nativeDevices, count);
        }
    }

    /// <summary>Compatibility alias for callers not yet migrated to the source selector.</summary>
    public IReadOnlyList<AudioDevice> GetLoopbackDevices() => GetAudioDevices();

    /// <summary>RF6.2.3: swaps only the native capture worker; UI polling continues.</summary>
    public bool TrySelectLoopbackDevice(string deviceId) =>
        IsAvailable
        && !string.IsNullOrWhiteSpace(deviceId)
        && EchoCoreNative.SetAudioDevice(_handle!.DangerousGetHandle(), deviceId) != 0;

    public bool TrySelectAudioDevice(string deviceId) => TrySelectLoopbackDevice(deviceId);

    /// <summary>RF4.3: selects normative automatic (0) or explicit manual (1) conditioning.</summary>
    public bool TrySetLufsMode(LufsConfiguration configuration)
    {
        if (!IsAvailable)
        {
            return false;
        }

        return configuration.Mode switch
        {
            LufsMode.Automatic => EchoCoreNative.SetLufsMode(_handle!.DangerousGetHandle(), 0, 0f, 0f) != 0,
            LufsMode.Manual when float.IsFinite(configuration.Gain)
                && float.IsFinite(configuration.Gamma)
                && configuration.Gain >= 0f
                && configuration.Gamma > 0f => EchoCoreNative.SetLufsMode(
                    _handle!.DangerousGetHandle(), 1, configuration.Gain, configuration.Gamma) != 0,
            _ => false,
        };
    }

    /// <summary>RF4.3.2: selects a pre-FFI conditioning route without replacing the ABI frame.</summary>
    public bool TrySetConditioningMode(ConditioningMode mode) =>
        IsAvailable && EchoCoreNative.SetConditioningMode(_handle!.DangerousGetHandle(), (byte)mode) != 0;

    /// <summary>Configures the visual spectral magnitude scaling (Linear, Decibels, PerceptualPinkNoise).</summary>
    public bool TrySetSpectralScalingMode(SpectralScalingMode mode) =>
        IsAvailable && EchoCoreNative.SetSpectralScalingMode(_handle!.DangerousGetHandle(), (uint)mode) != 0;

    /// <summary>RF4.3.1: reads scalar calibration data without reading a new frame.</summary>
    public bool TryReadLufsDiagnostics(out LufsDiagnosticSample sample)
    {
        sample = default;
        if (!IsAvailable)
        {
            return false;
        }

        NativeLoudnessDiagnosticsData diagnostics = default;
        if (EchoCoreNative.GetLoudnessDiagnostics(_handle!.DangerousGetHandle(), &diagnostics) == 0)
        {
            return false;
        }

        sample = new LufsDiagnosticSample(
            diagnostics.ShortTermLufs,
            diagnostics.Gain,
            diagnostics.Gamma,
            diagnostics.PreEnergyMean,
            diagnostics.PreEnergyMax,
            diagnostics.PostEnergyMean,
            diagnostics.PostEnergyMax,
            diagnostics.MasterPeak,
            diagnostics.CaptureBlockIsNew != 0);
        return true;
    }

    public void Advance()
    {
        if (!TryReadFrame(out var frame))
        {
            return;
        }

        // Legacy compatibility only. The real-time path calls TryReadFrame.
        Current = new AudioFrame(
            frame.Rms,
            frame.SpectralCentroidHz,
            frame.OnsetDetected,
            frame.BandEnergies.ToArray(),
            frame.TimestampMs);
    }

    public void Dispose() => _handle?.Dispose();

    private sealed class AudioEngineHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public AudioEngineHandle(IntPtr handle) : base(true)
        {
            SetHandle(handle);
        }

        protected override bool ReleaseHandle()
        {
            EchoCoreNative.Destroy(handle);
            return true;
        }
    }
}

public sealed record AudioDevice(string Id, string Name, bool IsDefault);

public enum LufsMode
{
    Automatic,
    Manual,
}

public enum ConditioningMode : byte
{
    NormativeLufs = 0,
    StabilizedPivot = 1,
    MasterPeak = 2,
    HybridMacroMaster = 3,
}

public readonly record struct LufsConfiguration(LufsMode Mode, float Gain, float Gamma)
{
    public static LufsConfiguration Automatic => new(LufsMode.Automatic, 0f, 0f);
}

public readonly record struct LufsDiagnosticSample(
    float ShortTermLufs,
    float Gain,
    float Gamma,
    float PreEnergyMean,
    float PreEnergyMax,
    float PostEnergyMean,
    float PostEnergyMax,
    float MasterPeak,
    bool CaptureBlockIsNew);
