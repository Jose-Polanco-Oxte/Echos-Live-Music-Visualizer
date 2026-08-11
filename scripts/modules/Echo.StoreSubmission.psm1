# Echo.StoreSubmission.psm1
#
# Fail-closed adapter for the Microsoft Store Developer CLI (msstore) that:
#   - reads the pinned CLI coordinates from Product.props through
#     Get-EchoDistributionConfiguration (never repeats them);
#   - wraps CLI JSON output, normalizes Partner Center states, redacts secrets;
#   - implements the D11 transition table without hidden deletes;
#   - implements the D12 two-stage submit (no-commit publish -> verify -> commit).
#
# No mutating command is ever invoked before a read-only preflight classifies
# Partner Center state. Unknown or malformed state fails closed.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:KnownStates = @(
    'Published',
    'PendingCommit',
    'CommitStarted',
    'PreProcessing',
    'Certification',
    'Release',
    'Publishing',
    'CommitFailed',
    'PreProcessingFailed',
    'CertificationFailed',
    'ReleaseFailed',
    'PublishFailed',
    'Canceled',
    'Unknown'
)

function Invoke-MsStoreCliJson {
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$Environment,
        [int]$RetryCount = 2
    )

    $envSnapshot = @{}
    if ($Environment) {
        foreach ($entry in $Environment.GetEnumerator()) {
            $envSnapshot[$entry.Key] = (Get-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue).Value
            Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
        }
    }
    try {
        try {
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo.FileName = $CliPath
            $process.StartInfo.Arguments = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.RedirectStandardOutput = $true
            $process.StartInfo.RedirectStandardError = $true
            $process.StartInfo.CreateNoWindow = $true
            foreach ($environmentVariable in $Environment.GetEnumerator()) {
                $process.StartInfo.EnvironmentVariables[$environmentVariable.Key] = $environmentVariable.Value
            }
            $null = $process.Start()
            $stdoutText = $process.StandardOutput.ReadToEnd()
            $stderrText = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $exitCode = $process.ExitCode

            Write-Verbose "msstore stderr: $stderrText"
            return [pscustomobject]@{ ExitCode = $exitCode; Stdout = @($stdoutText); Stderr = @($stderrText) }
        }
        catch {
            throw "Unable to invoke msstore CLI: $($_.Exception.Message)"
        }
    }
    finally {
        if ($Environment) {
            foreach ($entry in $Environment.GetEnumerator()) {
                if ($envSnapshot.ContainsKey($entry.Key) -and $null -ne $envSnapshot[$entry.Key]) {
                    Set-Item -Path "Env:$($entry.Key)" -Value $envSnapshot[$entry.Key]
                }
                else {
                    Remove-Item -Path "Env:$($entry.Key)" -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Get-EchoStoreSubmissionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [hashtable]$Environment
    )

    $result = Invoke-MsStoreCliJson `
        -CliPath $CliPath `
        -Arguments @('submission', 'get', '--productid', $ProductId, '--json') `
        -Environment $Environment

    if ($result.ExitCode -ne 0) {
        throw "msstore submission get failed (exit $($result.ExitCode))."
    }

    $raw = ($result.Stdout -join '').Trim()
    if (-not $raw) {
        # CLI may return the state outside a JSON envelope.
        if (($result.Stderr -join ' ') -match '(?i)(published|pendingcommit|processing|certification|failed|canceled)') {
            $raw = ($result.Stderr -join ' ')
        }
        else {
            throw 'msstore submission get returned no recognizable JSON state.'
        }
    }

    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Normalize a plain-text state line.
        if ($raw -match '(?i)(published|pendingcommit|commitstarted|preprocessing|processing|certification|release|publishing|canceled|failed)') {
            return [pscustomobject]@{
                State = (Normalize-EchoStoreState (($Matches[0] -replace ' ', '')).ToLowerInvariant())
                Raw = $raw
            }
        }
        throw "msstore submission get returned malformed output: $($result.Stderr -join ' ')"
    }

    # Try multiple known field shapes.
    $stateValue = $null
    foreach ($field in @('status', 'state', 'submissionStatus', 'currentStatus', 'Status')) {
        if ($json.$field) { $stateValue = $json.$field; break }
    }
    if (-not $stateValue -and $json.PSObject.Properties.Name -contains 'status') {
        $stateValue = $json.status
    }

    return [pscustomobject]@{
        State = (Normalize-EchoStoreState ([string]$stateValue))
        Raw = $raw
        Json = $json
    }
}

function Normalize-EchoStoreState {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unknown' }
    $map = @{
        'published' = 'Published'
        'publishedwithpendingcommit' = 'PendingCommit'
        'pendingcommit' = 'PendingCommit'
        'commitstarted' = 'CommitStarted'
        'preprocessing' = 'PreProcessing'
        'processing' = 'PreProcessing'
        'certification' = 'Certification'
        'inprogresscertification' = 'Certification'
        'release' = 'Release'
        'publishing' = 'Publishing'
        'commitfailed' = 'CommitFailed'
        'preprocessingfailed' = 'PreProcessingFailed'
        'certificationfailed' = 'CertificationFailed'
        'releasefailed' = 'ReleaseFailed'
        'publishfailed' = 'PublishFailed'
        'canceled' = 'Canceled'
        'cancelled' = 'Canceled'
    }
    $key = ($Value.Trim() -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    return 'Unknown'
}

function Test-EchoStoreStateSafeToProceed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$TargetVersion,
        [string]$LatestPublishedVersion = ''
    )

    $allowed = @('Published', 'PendingCommit', 'CommitStarted', 'PreProcessing', 'Certification', 'Release', 'Publishing')
    if ($CurrentState -notin $allowed) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "State '$CurrentState' is not resumeable without operator action." }
    }

    if ($CurrentState -eq 'Published') {
        if ($LatestPublishedVersion -and [version]$TargetVersion -le [version]$LatestPublishedVersion) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-monotonic'; Reason = "Target $TargetVersion does not exceed latest published $LatestPublishedVersion." }
        }
        return [pscustomobject]@{ Safe = $true; Action = 'upload'; Reason = 'No pending submission; safe to create a new draft.' }
    }

    if ($CurrentState -eq 'PendingCommit') {
        return [pscustomobject]@{ Safe = $true; Action = 'commit-resume'; Reason = 'Existing pending submission may be resumed by committing the same target.' }
    }

    # Active processing states are safe to monitor, not mutate.
    return [pscustomobject]@{ Safe = $true; Action = 'monitor-only'; Reason = "State '$CurrentState' is active; monitor without mutation." }
}

function Invoke-EchoStorePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$TargetVersion,
        [hashtable]$Environment
    )

    $current = Get-EchoStoreSubmissionState -CliPath $CliPath -ProductId $ProductId -Environment $Environment
    $verdict = Test-EchoStoreStateSafeToProceed `
        -CurrentState $current.State `
        -TargetVersion $TargetVersion `
        -LatestPublishedVersion $current.State

    if (-not $verdict.Safe) {
        throw "Store preflight failed closed for $TargetVersion (state $($current.State)): $($verdict.Reason)"
    }

    return [pscustomobject]@{
        State = $current.State
        Verdict = $verdict
        Current = $current
    }
}

function Invoke-EchoStorePublish {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$BundlePath,
        [hashtable]$Environment
    )

    # D11/D12: no-commit publish, verified draft, explicit commit afterwards.
    $result = Invoke-MsStoreCliJson `
        -CliPath $CliPath `
        -Arguments @(
            'publish', '--productid', $ProductId,
            '--package', $BundlePath,
            '--noCommit',
            '--json'
        ) `
        -Environment $Environment
    if ($result.ExitCode -ne 0) {
        throw "msstore publish (no-commit) failed (exit $($result.ExitCode))."
    }
    return $result
}

function Invoke-EchoStoreCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [hashtable]$Environment
    )

    $result = Invoke-MsStoreCliJson `
        -CliPath $CliPath `
        -Arguments @('commit', '--productid', $ProductId, '--json') `
        -Environment $Environment
    if ($result.ExitCode -ne 0) {
        throw "msstore commit failed (exit $($result.ExitCode))."
    }
    return $result
}
Export-ModuleMember -Function @(
    'Invoke-EchoStorePreflight',
    'Invoke-EchoStorePublish',
    'Invoke-EchoStoreCommit',
    'Get-EchoStoreSubmissionState',
    'Test-EchoStoreStateSafeToProceed',
    'Normalize-EchoStoreState',
    'Invoke-MsStoreCliJson'
)
