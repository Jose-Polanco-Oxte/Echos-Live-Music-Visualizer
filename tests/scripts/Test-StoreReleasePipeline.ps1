# Test-StoreReleasePipeline.ps1
#
# Self-contained PowerShell assertions (no external framework) for the Store
# release pipeline: centralized Product.props schema-1 parsing, D5 version
# mapping, version monotonicity and configuration fixtures.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failed = @()
function Assert-Equal {
    param(
        [Parameter(Mandatory)][object]$Expected,
        [Parameter(Mandatory)][object]$Actual,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Expected -ne $Actual) {
        throw "FAIL: $Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$ConditionValue,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $ConditionValue) {
        throw "FAIL: $Message"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Test,
        [Parameter(Mandatory)][string]$Contains,
        [Parameter(Mandatory)][string]$Message
    )
    $fired = $false
    $failureText = $null
    try {
        & $Test | Out-Null
    }
    catch {
        $fired = $true
        $failureText = $_.Exception.Message
    }
    if (-not $fired) {
        throw "FAIL: $Message (expected an exception containing '$Contains' but none was thrown)"
    }
    if ($failureText -notmatch $Contains) {
        throw "FAIL: $Message (exception did not match '$Contains': $failureText)"
    }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$modulePath = Join-Path $repoRoot 'scripts\modules\Echo.ReleaseMetadata.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$fixtures = Join-Path $repoRoot 'tests\fixtures\store'

Write-Host '== S2/S5 version and configuration fixtures ==' -ForegroundColor Cyan

# --- D5 mapping table ---
$d5Table = @(
    @{ Product = '0.2.0.19'; Store = '0.2.19.0' },
    @{ Product = '0.2.0.20'; Store = '0.2.20.0' },
    @{ Product = '0.2.1.0';  Store = '0.2.256.0' },
    @{ Product = '0.3.0.0';  Store = '0.3.0.0' }
)
foreach ($row in $d5Table) {
    $actual = Get-EchoStoreVersion -ProductVersion $row.Product
    Assert-Equal $row.Store $actual "D5 mapping for $($row.Product)"
}

# --- D5 boundary failures ---
foreach ($invalid in @('0.2.0.300', '0.70000.0.0', '0.2.256.0')) {
    Assert-Throws { Get-EchoStoreVersion -ProductVersion $invalid } 'bound|Version|Product|65535' "D5 must reject $invalid"
}

# --- monotonicity ---
Assert-True (Test-EchoStoreVersionMonotonic -Current '0.2.21.0' -LatestPublished '0.2.19.0') '0.2.21.0 must exceed 0.2.19.0'
Assert-True (-not (Test-EchoStoreVersionMonotonic -Current '0.2.19.0' -LatestPublished '0.2.19.0')) 'equal Store versions must not be monotonic'
Assert-True (-not (Test-EchoStoreVersionMonotonic -Current '0.2.18.0' -LatestPublished '0.2.19.0')) 'lower Store version must be rejected'
Assert-Equal 0 (Compare-EchoVersion '0.2.19.0' '0.2.19.0') 'equal comparison'
Assert-Equal -1 (Compare-EchoVersion '0.2.18.0' '0.2.19.0') 'less-than comparison'
Assert-Equal 1 (Compare-EchoVersion '0.3.0.0' '0.2.19.0') 'greater-than comparison'

# --- valid schema-1 fixture ---
$valid = Get-EchoDistributionConfiguration -Path (Join-Path $fixtures 'Product.Valid.props')
Assert-Equal 1 $valid.SchemaVersion 'schema version'
Assert-Equal '0.2.19.0' $valid.Store.Versioning.StoreVersion 'fixture derived Store version'
Assert-Equal 2 $valid.Store.Architectures.Count 'exactly two architectures'
Assert-Equal 2 $valid.Store.Capabilities.Count 'exactly two capabilities'
Assert-Equal 256 $valid.Store.Versioning.PackingBase 'packing base'

# --- invalid fixtures ---
foreach ($case in @(
    @{ File = 'Product.DuplicateProperty.props'; Contains = 'Duplicate' },
    @{ File = 'Product.MissingProperty.props'; Contains = 'missing' },
    @{ File = 'Product.VersionOutOfRange.props'; Contains = '0\.\.255' },
    @{ File = 'Product.PackingBaseMismatch.props'; Contains = 'PackingBase' }
)) {
    $casePath = Join-Path $fixtures $case.File
    Assert-Throws { Get-EchoDistributionConfiguration -Path $casePath } $case.Contains "configuration fixture $($case.File) must fail closed"
}

Write-Host '== S5 Store submission state machine ==' -ForegroundColor Cyan

Import-Module (Join-Path $repoRoot 'scripts\modules\Echo.StoreSubmission.psm1') -Force -DisableNameChecking

# Normalization table for recognized Partner Center states.
foreach ($case in @(
    @{ Raw = 'Published'; Expected = 'Published' },
    @{ Raw = 'PendingCommit'; Expected = 'PendingCommit' },
    @{ Raw = 'published'; Expected = 'Published' },
    @{ Raw = 'PENDINGCOMMIT'; Expected = 'PendingCommit' },
    @{ Raw = 'InProgressCertification'; Expected = 'Certification' },
    @{ Raw = 'PreProcessingFailed'; Expected = 'PreProcessingFailed' },
    @{ Raw = 'garbage'; Expected = 'Unknown' }
)) {
    $normalized = Normalize-EchoStoreState $case.Raw
    Assert-Equal $case.Expected $normalized "state normalization for '$($case.Raw)'"
}

# transition verdicts
$upload = Test-EchoStoreStateSafeToProceed -CurrentState 'Published' -TargetVersion '0.2.19.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'upload' $upload.Action 'published -> upload'
Assert-True $upload.Safe 'published is safe to upload'

# R5: commit-resume requires complete, matching pending identity.
$resume = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetVersion '0.2.19.0' `
    -LatestPublishedVersion '0.2.0.0' `
    -PendingTargetVersion '0.2.19.0' `
    -PendingPackageName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
    -PendingPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76' `
    -PendingPackageSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
    -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
    -TargetBundleSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
    -TargetPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76'
Assert-Equal 'commit-resume' $resume.Action 'pendingcommit -> resume'
Assert-True $resume.Safe 'pendingcommit is safe to resume'
$resumeIncomplete = Test-EchoStoreStateSafeToProceed -CurrentState 'PendingCommit' -TargetVersion '0.2.19.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'fail-closed' $resumeIncomplete.Action 'pendingcommit without identity fails closed'

$monitor = Test-EchoStoreStateSafeToProceed -CurrentState 'Certification' -TargetVersion '0.2.19.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'monitor-only' $monitor.Action 'certification -> monitor'
Assert-True $monitor.Safe 'certification is safe to monitor'

$monoFail = Test-EchoStoreStateSafeToProceed -CurrentState 'Published' -TargetVersion '0.2.0.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'fail-monotonic' $monoFail.Action 'equal published target must fail monotonicity'
Assert-True (-not $monoFail.Safe) 'equal published target is not safe'

$terminalFail = Test-EchoStoreStateSafeToProceed -CurrentState 'CertificationFailed' -TargetVersion '0.2.19.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'fail-closed' $terminalFail.Action 'terminal failure must fail closed'
Assert-True (-not $terminalFail.Safe) 'terminal failure is not safe'

Write-Host 'Store submission state machine fixtures: PASS' -ForegroundColor Green
Write-Host 'Store release pipeline version/configuration fixtures: PASS' -ForegroundColor Green