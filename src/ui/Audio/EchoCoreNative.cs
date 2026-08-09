using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EchoVisualizer.Audio;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeAudioFrameData
{
    public float Rms;
    public float SpectralCentroidHz;
    public byte OnsetDetected;
    public uint BandCount;
    public float* BandEnergies;
    public ulong TimestampMs;
}

/// ABI v2 leased frame. Rust guarantees that the pointed-to arrays remain
/// valid until the matching release call for LeaseId.
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeAnalysisFrameDataV2
{
    public uint AbiVersion;
    public uint Flags;
    public float Rms;
    public float RmsDbfs;
    public float SpectralCentroidHz;
    public byte OnsetDetected;
    public byte Reserved0;
    public byte Reserved1;
    public byte Reserved2;
    public float OnsetScore;
    public uint BandCount;
    public float* RawBandEnergies;
    public float* ConditionedBandEnergies;
    public float* BandPeakEnergies;
    public float* BandCentersHz;
    public ulong Sequence;
    public ulong CaptureTimestampUs;
    public uint AnalysisSampleRateHz;
    public uint HopFrames;
    public ulong ComputeLatencyUs;
    public ulong ProfileGeneration;
    public ulong LeaseId;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLoudnessDiagnosticsData
{
    public float ShortTermLufs;
    public float Gain;
    public float Gamma;
    public float PreEnergyMean;
    public float PreEnergyMax;
    public float PostEnergyMean;
    public float PostEnergyMax;
    public float MasterPeak;
    public byte CaptureBlockIsNew;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeAudioDeviceProperties
{
    public sbyte* DeviceId;
    public sbyte* Name;
    public byte IsDefault;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeAudioDevicePropertiesV2
{
    public uint StructSize;
    public uint AbiVersion;
    public sbyte* DeviceId;
    public sbyte* Name;
    public byte IsDefault;
    public byte Kind;
    public ushort Reserved;
}

/// Native ABI import. The UI does not call it until the Rust DLL is deployed;
/// this keeps presentation work independently executable.
internal static unsafe partial class EchoCoreNative
{
    private const string DllName = "EchoCore.dll";

    [LibraryImport(DllName, EntryPoint = "echo_core_version")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint GetVersion();

    [LibraryImport(DllName, EntryPoint = "init_audio_engine")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial IntPtr Initialize(uint sampleRate, uint frameSize);

    [LibraryImport(DllName, EntryPoint = "get_latest_frame")]
    [SuppressGCTransition]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte GetLatestFrame(IntPtr handle, NativeAudioFrameData* outFrame);

    [LibraryImport(DllName, EntryPoint = "acquire_latest_analysis_frame_v2")]
    [SuppressGCTransition]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte AcquireLatestAnalysisFrameV2(IntPtr handle, NativeAnalysisFrameDataV2* outFrame);

    [LibraryImport(DllName, EntryPoint = "release_analysis_frame_v2")]
    [SuppressGCTransition]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte ReleaseAnalysisFrameV2(IntPtr handle, ulong leaseId);

    [LibraryImport(DllName, EntryPoint = "get_loudness_diagnostics")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte GetLoudnessDiagnostics(IntPtr handle, NativeLoudnessDiagnosticsData* outDiagnostics);

    [LibraryImport(DllName, EntryPoint = "set_band_configuration")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetBandConfiguration(IntPtr handle, uint bandCount, byte scaleType);

    [LibraryImport(DllName, EntryPoint = "set_smoothing_parameters")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetSmoothingParameters(IntPtr handle, float attack, float decay);

    [LibraryImport(DllName, EntryPoint = "set_lufs_mode")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetLufsMode(IntPtr handle, byte mode, float gain, float gamma);

    [LibraryImport(DllName, EntryPoint = "set_conditioning_mode")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetConditioningMode(IntPtr handle, byte mode);

    [LibraryImport(DllName, EntryPoint = "echo_core_set_spectral_scaling_mode")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetSpectralScalingMode(IntPtr handle, uint mode);

    [LibraryImport(DllName, EntryPoint = "set_audio_device", StringMarshalling = StringMarshalling.Utf8)]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte SetAudioDevice(IntPtr handle, string deviceId);

    [LibraryImport(DllName, EntryPoint = "get_audio_devices")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte GetAudioDevices(
        IntPtr handle,
        NativeAudioDeviceProperties** outDevices,
        uint* outCount);

    [LibraryImport(DllName, EntryPoint = "free_device_list")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial void FreeDeviceList(NativeAudioDeviceProperties* devices, uint count);

    [LibraryImport(DllName, EntryPoint = "get_audio_devices_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial byte GetAudioDevicesV2(
        IntPtr handle,
        NativeAudioDevicePropertiesV2** outDevices,
        uint* outCount);

    [LibraryImport(DllName, EntryPoint = "free_device_list_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial void FreeDeviceListV2(NativeAudioDevicePropertiesV2* devices, uint count);

    [LibraryImport(DllName, EntryPoint = "get_last_error")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint GetLastError(IntPtr handle, sbyte* buffer, uint bufferLength);

    [LibraryImport(DllName, EntryPoint = "destroy_audio_engine")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial void Destroy(IntPtr handle);
}

public enum SpectralScalingMode : uint
{
    Linear = 0,
    Decibels = 1,
    PerceptualPinkNoise = 2,
}
