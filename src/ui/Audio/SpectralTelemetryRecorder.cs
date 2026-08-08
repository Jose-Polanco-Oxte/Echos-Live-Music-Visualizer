using System.Globalization;

namespace EchoVisualizer.Audio;

/// RF5.1/RF4.3.4: low-rate diagnostic telemetry for the real-time lease path.
/// It aggregates spans while the lease is alive and never stores band vectors.
public sealed class SpectralTelemetryRecorder : IDisposable
{
    private readonly StreamWriter _writer;
    private DateTimeOffset _nextSampleAt;

    public SpectralTelemetryRecorder()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "EchoVisualizer",
            "telemetry");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"spectral-{DateTime.UtcNow:yyyyMMdd-HHmmss}.csv");
        _writer = new StreamWriter(path, append: false);
        _writer.WriteLine("utc,sequence,rms,raw_power_mean,raw_power_max,amplitude_mean,amplitude_max,master_peak,conditioned_mean,conditioned_max");
        _nextSampleAt = DateTimeOffset.MinValue;
    }

    public void TryAppend(AudioCoreService core, in AudioFrameLease lease)
    {
        var now = DateTimeOffset.UtcNow;
        if (now < _nextSampleAt)
        {
            return;
        }

        _nextSampleAt = now.AddMilliseconds(250);
        if (!core.TryReadLufsDiagnostics(out var diagnostics))
        {
            return;
        }

        var raw = lease.RawBandEnergies;
        var conditioned = lease.ConditionedBandEnergies;
        if (raw.IsEmpty || conditioned.Length != raw.Length)
        {
            return;
        }

        var rawSum = 0d;
        var rawMax = 0f;
        var amplitudeSum = 0d;
        var amplitudeMax = 0f;
        var conditionedSum = 0d;
        var conditionedMax = 0f;
        for (var index = 0; index < raw.Length; index++)
        {
            var power = float.IsFinite(raw[index]) ? MathF.Max(0f, raw[index]) : 0f;
            var output = float.IsFinite(conditioned[index]) ? MathF.Max(0f, conditioned[index]) : 0f;
            var amplitude = MathF.Sqrt(power);
            rawSum += power;
            rawMax = MathF.Max(rawMax, power);
            amplitudeSum += amplitude;
            amplitudeMax = MathF.Max(amplitudeMax, amplitude);
            conditionedSum += output;
            conditionedMax = MathF.Max(conditionedMax, output);
        }

        var count = raw.Length;
        _writer.WriteLine(string.Join(",", new[]
        {
            now.ToString("O", CultureInfo.InvariantCulture),
            lease.Sequence.ToString(CultureInfo.InvariantCulture),
            lease.Rms.ToString("R", CultureInfo.InvariantCulture),
            (rawSum / count).ToString("R", CultureInfo.InvariantCulture),
            rawMax.ToString("R", CultureInfo.InvariantCulture),
            (amplitudeSum / count).ToString("R", CultureInfo.InvariantCulture),
            amplitudeMax.ToString("R", CultureInfo.InvariantCulture),
            diagnostics.MasterPeak.ToString("R", CultureInfo.InvariantCulture),
            (conditionedSum / count).ToString("R", CultureInfo.InvariantCulture),
            conditionedMax.ToString("R", CultureInfo.InvariantCulture),
        }));
        _writer.Flush();
    }

    public void Dispose() => _writer.Dispose();
}
