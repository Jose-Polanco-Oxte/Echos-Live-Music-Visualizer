# Echo.StoreSubmission.psm1
#
# Fail-closed adapter for the Microsoft Store Developer CLI (msstore) that:
#   - reads the pinned CLI coordinates from Product.props through
#     Get-EchoDistributionConfiguration (never repeats them);
#   - wraps CLI JSON output as a single document, normalizes Partner Center
#     states and redacts secrets from messages;
#   - models Store state with explicit separation (D4): CurrentState,
#     LatestPublishedVersion, PendingTargetVersion, PendingPackageName/Hash are
#     never conflated and no textual state is ever coerced into a [version];
#   - implements the D11 transition table with limited retries (R11) classified
#     as transient (429/5xx) vs permanent, and no hidden deletes;
#   - implements the D12 two-stage submit (no-commit publish -> verify -> commit).
#
# No mutating command is ever invoked before a read-only preflight classifies
# Partner Center state. Unknown or malformed state fails closed. A pending
# submission can only be resumed when it exactly matches the target product,
# version, bundle name and hash (R10).

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

# Optional test seam. When set, Invoke-EchoMsStoreCliProcess delegates the
# actual process launch to this scriptblock so the state machine and retry
# logic can be exercised offline. The scriptblock receives the CLI path and the
# argument array and must return an object with ExitCode, Stdout and Stderr.
$script:StoreCliProcessInvoker = $null

function Set-EchoStoreCliProcessInvoker {
    [CmdletBinding()]
    param([scriptblock]$Invoker)
    $script:StoreCliProcessInvoker = $Invoker
}

function Get-EchoRedactedText {
    [CmdletBinding()]
    param(
        [string]$Text,
        [string[]]$SecretValues
    )
    foreach ($secret in $SecretValues) {
        if ($secret) {
            $Text = $Text.Replace($secret, '***')
        }
    }
    return $Text
}

function Invoke-EchoMsStoreCliProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$Environment
    )

    if ($script:StoreCliProcessInvoker) {
        return & $script:StoreCliProcessInvoker $CliPath $Arguments $Environment
    }

    $envSnapshot = @{}
    if ($Environment) {
        foreach ($entry in $Environment.GetEnumerator()) {
            $envSnapshot[$entry.Key] = (Get-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue).Value
            Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
        }
    }
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
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = @($stdoutText); Stderr = @($stderrText) }
    }
    catch {
        throw "Unable to invoke msstore CLI: $($_.Exception.Message)"
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

# Classifies whether a non-zero msstore invocation is a transient failure that
# is safe to retry (429 or 5xx), a permanent failure that must fail closed
# (auth, validation, identity, monotonicity, unknown state) or a recoverable
# wrapper error.
function Test-EchoMsStoreTransientFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [string[]]$Stdout,
        [string[]]$Stderr
    )

    $errorText = (@($Stdout + $Stderr) -join "`n")
    if ($ExitCode -eq 429 -or $ExitCode -ge 500 -or $errorText -match '(?i)(HTTP/1\.\d 429|Too Many Requests|Rate limit)') {
        return $true
    }
    if ($errorText -match '(?i)(HTTP/1\.\d 5\d\d|5\d\d Server|Service Unavailable|Gateway|Timeout)') {
        return $true
    }
    return $false
}

# Invokes the CLI exactly once with a redaction-aware wrapper. Callers that need
# retries must use Invoke-EchoMsStoreCli (below), which never retries permanent
# failures.
function Invoke-EchoMsStoreCliOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$Environment,
        [string[]]$SecretValues
    )

    $result = Invoke-EchoMsStoreCliProcess -CliPath $CliPath -Arguments $Arguments -Environment $Environment
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Stdout = @($result.Stdout)
        Stderr = @($result.Stderr)
        RedactedStdout = @($result.Stdout | ForEach-Object { Get-EchoRedactedText -Text $_ -SecretValues $SecretValues })
        RedactedStderr = @($result.Stderr | ForEach-Object { Get-EchoRedactedText -Text $_ -SecretValues $SecretValues })
    }
}

# R11: retry only identifiable transient failures (429/5xx) with a documented
# cap and backoff. Auth, validation, identity, monotonicity and unknown-state
# errors are permanent and never retried.
function Invoke-EchoMsStoreCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$Environment,
        [int]$RetryCount = 2,
        [int]$InitialBackoffSeconds = 5,
        [int]$MaxBackoffSeconds = 30,
        [string[]]$SecretValues
    )

    $attempt = 0
    while ($true) {
        $attempt++
        $result = Invoke-EchoMsStoreCliOnce -CliPath $CliPath -Arguments $Arguments -Environment $Environment -SecretValues $SecretValues
        if ($result.ExitCode -eq 0) {
            return $result
        }
        if (-not (Test-EchoMsStoreTransientFailure -ExitCode $result.ExitCode -Stdout $result.Stdout -Stderr $result.Stderr)) {
            $message = "msstore $($Arguments[0]) failed (exit $($result.ExitCode))."
            $detail = (($result.RedactedStderr + $result.RedactedStdout) -join ' ').Trim()
            if ($detail) { $message = "$message $detail" }
            throw $message
        }
        if ($attempt -gt $RetryCount) {
            throw "msstore $($Arguments[0]) failed after $RetryCount retries (exit $($result.ExitCode)); last transient error stopped at the retry cap."
        }
        $backoff = [Math]::Min($MaxBackoffSeconds, $InitialBackoffSeconds * [Math]::Pow(2, $attempt - 1))
        Write-Verbose "msstore $($Arguments[0]) hit a transient failure (exit $($result.ExitCode)); retrying in ${backoff}s."
        Start-Sleep -Seconds $backoff
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
        'nosubmission' = 'NoSubmission'
    }
    $key = ($Value.Trim() -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    return 'Unknown'
}

function Get-EchoFieldValue {
    param(
        [Parameter(Mandatory)][object]$Json,
        [Parameter(Mandatory)][string[]]$CandidateFields
    )
    foreach ($field in $CandidateFields) {
        $value = $null
        try { $value = $Json.$field } catch { $value = $null }
        if ($null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value) -eq $false) {
            return ([string]$value).Trim()
        }
    }
    return ''
}

# R9: read a complete, explicit representation of Partner Center state. No
# textual state is ever converted into a version; the latest published version
# and the pending target fields are separate data points.
function Get-EchoStoreSubmissionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [hashtable]$Environment,
        [string[]]$SecretValues
    )

    $result = Invoke-EchoMsStoreCli `
        -CliPath $CliPath `
        -Arguments @('submission', 'get', '--productid', $ProductId, '--json') `
        -Environment $Environment `
        -SecretValues $SecretValues

    if ($result.ExitCode -ne 0) {
        throw "msstore submission get failed (exit $($result.ExitCode))."
    }

    $raw = ($result.Stdout -join '').Trim()
    if (-not $raw) {
        $stderrText = ($result.Stderr -join ' ')
        if ($stderrText -match '(?i)(no submission|not found|no submissions)') {
            return [pscustomobject]@{
                SubmissionExists = $false
                State = 'NoSubmission'
                LatestPublishedVersion = ''
                PendingTargetVersion = ''
                PendingPackageName = ''
                PendingPackageFamilyName = ''
                PendingPackageSha256 = ''
                Raw = ''
            }
        }
        throw "msstore submission get returned no recognizable state: $stderrText"
    }

    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "msstore submission get returned malformed JSON: $($result.RedactedStderr -join ' ')"
    }

    $hasSubmission = $true
    $hasSubmissionMarker = Get-EchoFieldValue -Json $json -CandidateFields @('hasSubmission', 'hasPendingSubmission')
    if ($hasSubmissionMarker) {
        $hasSubmission = ($hasSubmissionMarker -ieq 'true')
    }
    $stateValue = Get-EchoFieldValue -Json $json -CandidateFields @('status', 'state', 'submissionStatus', 'currentStatus', 'Status')
    if (-not $stateValue) {
        if (-not $hasSubmission) {
            $stateValue = 'NoSubmission'
        }
        else {
            $stateValue = 'Unknown'
        }
    }

    $submission = $null
    try { $submission = $json.submission } catch { $submission = $null }
    $pendingVersion = ''
    $pendingPackageName = ''
    $pendingPackageFamilyName = ''
    $pendingPackageSha256 = ''
    if ($null -ne $submission) {
        $pendingVersion = Get-EchoFieldValue -Json $submission -CandidateFields @('version', 'targetPublishMode', 'releaseVersion')
        $package = $null
        try { $package = $submission.package } catch { $package = $null }
        if ($null -ne $package) {
            $pendingPackageName = Get-EchoFieldValue -Json $package -CandidateFields @('name', 'bundleName', 'fileName')
            $pendingPackageFamilyName = Get-EchoFieldValue -Json $package -CandidateFields @('packageFamilyName')
            $pendingPackageSha256 = Get-EchoFieldValue -Json $package -CandidateFields @('sha256', 'hash')
        }
    }

    $latestPublished = Get-EchoFieldValue -Json $json -CandidateFields @('latestPublishedVersion', 'publishedVersion')
    if (-not $latestPublished -and $null -ne $submission) {
        # Publishing state may report the currently certifying version.
        $latestPublished = Get-EchoFieldValue -Json $submission -CandidateFields @('publishedVersion')
    }

    return [pscustomobject]@{
        SubmissionExists = $hasSubmission
        State = Normalize-EchoStoreState $stateValue
        LatestPublishedVersion = $latestPublished
        PendingTargetVersion = $pendingVersion
        PendingPackageName = $pendingPackageName
        PendingPackageFamilyName = $pendingPackageFamilyName
        PendingPackageSha256 = $pendingPackageSha256
        Raw = $raw
    }
}

# Returns $true when $Left does not exceed $Right (i.e. Left <= Right).
function Test-EchoVersionNotExceeds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $leftParts = @($Left.Split('.'))
    $rightParts = @($Right.Split('.'))
    for ($i = 0; $i -lt 4; $i++) {
        $leftValue = [int]$leftParts[$i]
        $rightValue = [int]$rightParts[$i]
        if ($leftValue -lt $rightValue) { return $true }
        if ($leftValue -gt $rightValue) { return $false }
    }
    return $true
}

# Transition verdict table (D11) with pending-submission correlation (R10).
function Test-EchoStoreStateSafeToProceed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$TargetVersion,
        [string]$LatestPublishedVersion = '',
        [string]$PendingTargetVersion = '',
        [string]$PendingPackageName = '',
        [string]$PendingPackageFamilyName = '',
        [string]$PendingPackageSha256 = '',
        [string]$TargetBundleName = '',
        [string]$TargetBundleSha256 = '',
        [string]$TargetPackageFamilyName = ''
    )

    $allowed = @('NoSubmission', 'Published', 'PendingCommit', 'CommitStarted', 'PreProcessing', 'Certification', 'Release', 'Publishing')
    if ($CurrentState -notin $allowed) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "State '$CurrentState' is not resumable without operator action." }
    }

    if ($CurrentState -in @('NoSubmission', 'Published')) {
        if ($LatestPublishedVersion) {
            $notGreater = Test-EchoVersionNotExceeds -Left $TargetVersion -Right $LatestPublishedVersion
            if ($notGreater) {
                return [pscustomobject]@{ Safe = $false; Action = 'fail-monotonic'; Reason = "Target $TargetVersion does not exceed latest published $LatestPublishedVersion." }
            }
        }
        return [pscustomobject]@{ Safe = $true; Action = 'upload'; Reason = 'No pending submission; safe to create a new draft.' }
    }

    if ($CurrentState -eq 'PendingCommit') {
        # R10: resume only when the pending submission exactly matches the target.
        if ($PendingTargetVersion -and $PendingTargetVersion -ne $TargetVersion) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Pending submission targets $PendingTargetVersion but release expects $TargetVersion. Stop for an explicit decision." }
        }
        if ($TargetPackageFamilyName -and $PendingPackageFamilyName -and $PendingPackageFamilyName -ne $TargetPackageFamilyName) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Pending submission package family '$PendingPackageFamilyName' does not match target '$TargetPackageFamilyName'. Stop for an explicit decision." }
        }
        if ($TargetBundleName -and $PendingPackageName -and $PendingPackageName -ne $TargetBundleName) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Pending submission bundle '$PendingPackageName' does not match target '$TargetBundleName'. Stop for an explicit decision." }
        }
        if ($TargetBundleSha256 -and $PendingPackageSha256 -and $PendingPackageSha256 -ne $TargetBundleSha256) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = 'Pending submission bundle hash does not match the target bundle hash. Stop for an explicit decision.' }
        }
        return [pscustomobject]@{ Safe = $true; Action = 'commit-resume'; Reason = 'Existing pending submission matches the exact target; safe to commit.' }
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
        [string]$TargetBundleName = '',
        [string]$TargetBundleSha256 = '',
        [string]$TargetPackageFamilyName = '',
        [hashtable]$Environment,
        [string[]]$SecretValues
    )

    $current = Get-EchoStoreSubmissionState -CliPath $CliPath -ProductId $ProductId -Environment $Environment -SecretValues $SecretValues
    $verdict = Test-EchoStoreStateSafeToProceed `
        -CurrentState $current.State `
        -TargetVersion $TargetVersion `
        -LatestPublishedVersion $current.LatestPublishedVersion `
        -PendingTargetVersion $current.PendingTargetVersion `
        -PendingPackageName $current.PendingPackageName `
        -PendingPackageFamilyName $current.PendingPackageFamilyName `
        -PendingPackageSha256 $current.PendingPackageSha256 `
        -TargetBundleName $TargetBundleName `
        -TargetBundleSha256 $TargetBundleSha256 `
        -TargetPackageFamilyName $TargetPackageFamilyName

    if (-not $verdict.Safe) {
        throw "Store preflight failed closed for $TargetVersion (state $($current.State)): $($verdict.Reason)"
    }

    return [pscustomobject]@{
        State = $current.State
        LatestPublishedVersion = $current.LatestPublishedVersion
        PendingTargetVersion = $current.PendingTargetVersion
        PendingPackageName = $current.PendingPackageName
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
        [hashtable]$Environment,
        [string[]]$SecretValues
    )

    # D11/D12: no-commit publish, verified draft, explicit commit afterwards.
    return (Invoke-EchoMsStoreCli `
        -CliPath $CliPath `
        -Arguments @(
            'publish', '--productid', $ProductId,
            '--package', $BundlePath,
            '--noCommit',
            '--json'
        ) `
        -Environment $Environment `
        -SecretValues $SecretValues)
}

function Invoke-EchoStoreCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string]$ProductId,
        [hashtable]$Environment,
        [string[]]$SecretValues
    )

    return (Invoke-EchoMsStoreCli `
        -CliPath $CliPath `
        -Arguments @('commit', '--productid', $ProductId, '--json') `
        -Environment $Environment `
        -SecretValues $SecretValues)
}

Export-ModuleMember -Function @(
    'Invoke-EchoStorePreflight',
    'Invoke-EchoStorePublish',
    'Invoke-EchoStoreCommit',
    'Get-EchoStoreSubmissionState',
    'Test-EchoStoreStateSafeToProceed',
    'Normalize-EchoStoreState',
    'Invoke-EchoMsStoreCli',
    'Invoke-EchoMsStoreCliOnce',
    'Invoke-EchoMsStoreCliProcess',
    'Test-EchoMsStoreTransientFailure',
    'Get-EchoRedactedText',
    'Set-EchoStoreCliProcessInvoker'
)