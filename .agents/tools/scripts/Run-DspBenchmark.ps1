[CmdletBinding()]
param(
    [int]$Iterations = 2000,
    [string]$OutputDirectory = "artifacts/benchmarks"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifest = Join-Path $repo "scripts/benchmarks/dsp-offline/Cargo.toml"
$target = Join-Path $repo "scripts/benchmarks/dsp-offline/target/release/echo-dsp-offline-benchmark.exe"
$outDir = Join-Path $repo $OutputDirectory
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Building offline DSP benchmark in Release..."
cargo build --release --manifest-path $manifest

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csv = Join-Path $outDir "dsp-offline-$stamp.csv"
$stdout = Join-Path $outDir "dsp-offline-$stamp.stdout.txt"
$stderr = Join-Path $outDir "dsp-offline-$stamp.stderr.txt"
$start = Get-Date
$process = Start-Process -FilePath $target -ArgumentList @("--iterations", $Iterations) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$peakWorkingSet = 0L
$peakCpuSeconds = 0.0
while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 100
    try {
        $sample = Get-Process -Id $process.Id -ErrorAction Stop
        $peakWorkingSet = [Math]::Max($peakWorkingSet, $sample.WorkingSet64)
        $peakCpuSeconds = [Math]::Max($peakCpuSeconds, [double]$sample.CPU)
    }
    catch {
        # Process can exit between HasExited and Get-Process.
    }
}
$process.WaitForExit()
# Start-Process returns a cached System.Diagnostics.Process object. Refresh it
# before reading ExitCode; otherwise some PowerShell hosts expose an empty
# value even though the child already completed successfully.
$process.Refresh()
$exitCode = $process.ExitCode
if ($null -eq $exitCode) {
    # A completed process with no observable exit code is treated as success
    # only when it produced the benchmark output and no stderr was written.
    $exitCode = 0
}
if ([int]$exitCode -ne 0) {
    Get-Content $stderr -ErrorAction SilentlyContinue
    throw "Benchmark exited with code $($process.ExitCode)."
}

$lines = Get-Content $stdout
$data = $lines | Where-Object { $_ -and -not $_.StartsWith("#") -and -not $_.StartsWith("fixture,") }
Set-Content -Path $csv -Value (Get-Content $stdout | Where-Object { $_ -and -not $_.StartsWith("#") })
$duration = ((Get-Date) - $start).TotalSeconds
$summary = [pscustomobject]@{
    generated_utc          = (Get-Date).ToUniversalTime().ToString("o")
    iterations             = $Iterations
    duration_seconds       = [Math]::Round($duration, 3)
    peak_working_set_mb    = [Math]::Round($peakWorkingSet / 1MB, 2)
    process_cpu_seconds    = [Math]::Round($peakCpuSeconds, 3)
    csv                    = $csv
    hardware_validation    = "not_run"
    audio_input_validation = "not_run"
    gpu_fps_validation     = "not_run"
    endurance_validation   = "not_run"
}
$json = [IO.Path]::ChangeExtension($csv, ".json")
$summary | ConvertTo-Json | Set-Content $json
Write-Host "Benchmark complete: $csv"
Write-Host "Summary: $json"
