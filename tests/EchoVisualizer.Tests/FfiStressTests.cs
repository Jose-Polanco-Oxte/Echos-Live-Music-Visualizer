using System.Diagnostics;
using System.Runtime.InteropServices;
using EchoVisualizer.Audio;

namespace EchoVisualizer.Tests;

/// <summary>
/// V2: invokes the deployed C# source-generated ABI entry point one million
/// times. The core owns all native state; the managed heap delta is checked to
/// detect accidental wrapper allocations on the hot call path.
/// </summary>
public sealed class FfiStressTests
{
    private const int OneMillion = 1_000_000;

    [Fact]
    public void AnalysisFrameV2_LayoutMatchesRustReprCContract()
    {
        Assert.Equal(112, Marshal.SizeOf<NativeAnalysisFrameDataV2>());
        Assert.Equal((nuint)0, (nuint)Marshal.OffsetOf<NativeAnalysisFrameDataV2>(nameof(NativeAnalysisFrameDataV2.AbiVersion)));
        Assert.Equal((nuint)24, (nuint)Marshal.OffsetOf<NativeAnalysisFrameDataV2>(nameof(NativeAnalysisFrameDataV2.OnsetScore)));
        Assert.Equal((nuint)32, (nuint)Marshal.OffsetOf<NativeAnalysisFrameDataV2>(nameof(NativeAnalysisFrameDataV2.RawBandEnergies)));
        Assert.Equal((nuint)64, (nuint)Marshal.OffsetOf<NativeAnalysisFrameDataV2>(nameof(NativeAnalysisFrameDataV2.Sequence)));
        Assert.Equal((nuint)104, (nuint)Marshal.OffsetOf<NativeAnalysisFrameDataV2>(nameof(NativeAnalysisFrameDataV2.LeaseId)));
    }

    [Fact]
    public void AudioDeviceV2_LayoutMatchesRustReprCContract()
    {
        Assert.Equal(32, Marshal.SizeOf<NativeAudioDevicePropertiesV2>());
        Assert.Equal((nuint)0, (nuint)Marshal.OffsetOf<NativeAudioDevicePropertiesV2>(nameof(NativeAudioDevicePropertiesV2.StructSize)));
        Assert.Equal((nuint)8, (nuint)Marshal.OffsetOf<NativeAudioDevicePropertiesV2>(nameof(NativeAudioDevicePropertiesV2.DeviceId)));
        Assert.Equal((nuint)24, (nuint)Marshal.OffsetOf<NativeAudioDevicePropertiesV2>(nameof(NativeAudioDevicePropertiesV2.IsDefault)));
        Assert.Equal((nuint)25, (nuint)Marshal.OffsetOf<NativeAudioDevicePropertiesV2>(nameof(NativeAudioDevicePropertiesV2.Kind)));
    }

    [Fact]
    public void AudioFrameLease_DefaultHasNoBorrowedSpan()
    {
        var lease = default(AudioFrameLease);
        Assert.False(lease.IsValid);
        Assert.Empty(lease.ConditionedBandEnergies.ToArray());
        lease.Dispose();
    }

    [Fact]
    public void EchoCoreVersion_OneMillionAbiQueries_DoNotGrowManagedHeap()
    {
        Assert.Equal(1u, EchoCoreNative.GetVersion());

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        var heapBefore = GC.GetTotalMemory(forceFullCollection: true);
        var stopwatch = Stopwatch.StartNew();

        for (var call = 0; call < OneMillion; call++)
        {
            Assert.Equal(1u, EchoCoreNative.GetVersion());
        }

        stopwatch.Stop();
        var heapAfter = GC.GetTotalMemory(forceFullCollection: true);
        var deltaBytes = heapAfter - heapBefore;
        Assert.True(deltaBytes < 1_048_576, $"ABI query path retained {deltaBytes:N0} bytes.");
        Assert.True(stopwatch.Elapsed > TimeSpan.Zero);
    }

    [Fact]
    public void AudioCoreService_GetLatestFrame_ValidHandle_FillsStruct()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable, "EchoCore.dll must load for the ABI contract test.");

        Assert.True(service.TryReadFrame(out var frame));

        Assert.Equal(3, frame.BandEnergies.Length);
        Assert.All(frame.BandEnergies.ToArray(), energy => Assert.InRange(energy, 0f, 1f));
    }

    [Fact]
    public void AudioCoreService_OneMillionFrameReads_DoNotAllocateManagedMemory()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable, "EchoCore.dll must load for the ABI contract test.");
        Assert.True(service.TryReadFrame(out _)); // warm the native and source-generated paths

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        var allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
        var checksum = 0f;
        for (var call = 0; call < OneMillion; call++)
        {
            Assert.True(service.TryReadFrame(out var frame));
            checksum += frame.BandEnergies[0];
        }

        var allocated = GC.GetAllocatedBytesForCurrentThread() - allocatedBefore;
        Assert.True(float.IsFinite(checksum));
        Assert.Equal(0, allocated);
    }

    [Fact]
    public void AudioCoreService_V2OneMillionAcquireRelease_DoNotAllocateManagedMemory()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable, "EchoCore.dll must load for the ABI contract test.");

        AudioFrameLease first = default;
        var deadline = Stopwatch.GetTimestamp() + (long)(Stopwatch.Frequency * 3.0);
        var acquired = false;
        while (!(acquired = service.TryAcquireFrame(out first)) && Stopwatch.GetTimestamp() < deadline)
        {
            Thread.Yield();
        }
        Assert.True(acquired, "The worker must publish at least one ABI v2 frame.");
        using (first)
        {
            Assert.True(first.IsValid);
            Assert.Equal(2u, first.AbiVersion);
            Assert.InRange(first.BandCount, 1, 128);
            Assert.Equal(first.BandCount, first.ConditionedBandEnergies.Length);
        }

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        var allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
        var checksum = 0f;
        var reads = 0;
        for (var call = 0; call < OneMillion; call++)
        {
            if (!service.TryAcquireFrame(out var lease))
            {
                continue;
            }

            using (lease)
            {
                checksum += lease.ConditionedBandEnergies[0];
                reads++;
            }
        }

        var allocated = GC.GetAllocatedBytesForCurrentThread() - allocatedBefore;
        Assert.True(reads > 0);
        Assert.True(float.IsFinite(checksum));
        Assert.Equal(0, allocated);
    }

    [Fact]
    public void AudioCoreService_GetAudioDevices_FreesMemory()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable, "EchoCore.dll must load for the ABI contract test.");

        var workingSetBefore = Process.GetCurrentProcess().PrivateMemorySize64;
        for (var query = 0; query < 100; query++)
        {
            _ = service.GetLoopbackDevices();
        }

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        var workingSetAfter = Process.GetCurrentProcess().PrivateMemorySize64;
        Assert.True(
            workingSetAfter - workingSetBefore < 64L * 1024 * 1024,
            $"Device-list ABI queries increased private memory by {(workingSetAfter - workingSetBefore):N0} bytes.");
    }

    [Fact]
    public void AudioCoreService_DeviceV2ExposesOnlyDefinedKinds()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);

        var devices = service.GetAudioDevices();
        Assert.All(devices, device => Assert.True(
            device.Kind is AudioDeviceKind.RenderLoopback or AudioDeviceKind.DirectCapture));
    }

    [Fact]
    public void AudioCoreService_FailedSelectionReturnsNativeErrorAndKeepsDefaultSelectable()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);

        var devices = service.GetAudioDevices();
        if (devices.Count > 0)
        {
            Assert.True(service.SelectAudioDevice("default").Succeeded);
        }

        var failed = service.SelectAudioDevice("echo-device-that-does-not-exist");

        Assert.False(failed.Succeeded);
        Assert.Equal(AudioDeviceSelectionFailure.NativeFailure, failed.Failure);
        Assert.False(string.IsNullOrWhiteSpace(failed.ErrorMessage));

        if (devices.Count > 0)
        {
            Assert.True(service.SelectAudioDevice("default").Succeeded);
        }
    }

    [Fact]
    public async Task AudioCoreService_ActivityConfirmationIsBoundedToThreeSeconds()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);
        var stopwatch = Stopwatch.StartNew();

        var result = await service.ConfirmCaptureActivityAsync(TimeSpan.FromMilliseconds(150));

        Assert.True(result is AudioCaptureActivityResult.Advancing
            or AudioCaptureActivityResult.NoAdvancingFrames);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(3));
    }

    [Fact]
    public void AudioCoreService_ExposesNativeLufsModes()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);
        Assert.True(service.TrySetLufsMode(LufsConfiguration.Automatic));
        Assert.True(service.TrySetLufsMode(new LufsConfiguration(LufsMode.Manual, 1.5f, 2f)));
        Assert.False(service.TrySetLufsMode(new LufsConfiguration(LufsMode.Manual, -1f, 1f)));
    }

    [Fact]
    public void AudioCoreService_SwitchesRf4_3_2AndRf4_3_3ConditioningModes()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);
        Assert.True(service.TrySetConditioningMode(ConditioningMode.StabilizedPivot));
        Assert.True(service.TrySetConditioningMode(ConditioningMode.MasterPeak));
        Assert.True(service.TrySetConditioningMode(ConditioningMode.HybridMacroMaster));
        Assert.True(service.TryReadFrame(out _));
        Assert.True(service.TryReadLufsDiagnostics(out var diagnostics));
        // A machine without an active WASAPI frame legitimately reports no
        // master peak yet. Once a frame exists, RF4.3 requires the floor.
        Assert.True(
            diagnostics.MasterPeak == 0f
                || (float.IsFinite(diagnostics.MasterPeak) && diagnostics.MasterPeak >= 0.05f),
            $"unexpected master peak {diagnostics.MasterPeak}");
    }

    [Fact]
    public void AudioCoreService_ReportsLufsDiagnosticsWithoutReadingAnotherFrame()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);
        Assert.True(service.TryReadFrame(out _));

        Assert.True(service.TryReadLufsDiagnostics(out var diagnostics));
        Assert.True(float.IsFinite(diagnostics.ShortTermLufs));
        Assert.InRange(diagnostics.Gain, 0f, 8f);
        Assert.InRange(diagnostics.Gamma, 1f, 2.2f);
        Assert.InRange(diagnostics.PreEnergyMean, 0f, 1f);
        Assert.InRange(diagnostics.PostEnergyMean, 0f, 1f);
        Assert.InRange(diagnostics.MasterPeak, 0.05f, 1f);
    }

    [Fact]
    public void AudioCoreService_ConfiguresTheNormativeSpectralBarsProfile()
    {
        using var service = new AudioCoreService();
        Assert.True(service.IsAvailable);
        Assert.False(service.TryConfigureSpectralBands(3, 1));
        Assert.False(service.TryConfigureSpectralBands(48, 3));
        Assert.True(service.TryConfigureSpectralBands(48, 1));
        Assert.True(service.TryReadFrame(out var frame));
        Assert.Equal(48, frame.BandEnergies.Length);
    }
}
