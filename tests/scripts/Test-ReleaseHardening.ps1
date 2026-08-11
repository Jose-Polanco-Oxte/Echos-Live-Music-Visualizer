# Test-ReleaseHardening.ps1
#
# Regression coverage for the Microsoft Store release CD hardening plan
# (PLAN-20260811-RELEASE-CD-HARDENING). Each case maps to an audited defect:
#   R2  gh api JSON parsing (single-document, not per-element)
#   R3  lightweight + annotated tag resolution to a real commit SHA
#   R4  idempotent stable release recovery; fail-closed conflicts
#   R5  exact filename -> hash validation in SHA256SUMS.txt
#   R9  Store state separation (NoSubmission / PendingCommit / active / terminal)
#   R10 pending-submission correlation with target version/package/hash
#   R11 retry classification (429/5xx transient vs auth/validation permanent)
#   R14 strict Product.props schema parsing
#
# No network and no credentials: gh/msstore are simulated through module seams.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixturesGitHub = Join-Path $repoRoot 'tests\fixtures\github'
$fixturesStore = Join-Path $repoRoot 'tests\fixtures\store'
$modulePath = Join-Path $repoRoot 'scripts\modules\Echo.ReleaseMetadata.psm1'
$githubModulePath = Join-Path $repoRoot 'scripts\modules\Echo.GitHubRelease.psm1'
$storeModulePath = Join-Path $repoRoot 'scripts\modules\Echo.StoreSubmission.psm1'
Import-Module $modulePath -Force -DisableNameChecking
Import-Module $githubModulePath -Force -DisableNameChecking
Import-Module $storeModulePath -Force -DisableNameChecking

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

# ---------------------------------------------------------------------------
# R2 — gh api JSON parsing: a single document is parsed as one JSON document.
# ---------------------------------------------------------------------------
Write-Host '== R2 GitHub JSON parsing ==' -ForegroundColor Cyan

# An object response parses into a single object.
$objectDoc = '{"tag_name":"v0.2.0.19","draft":false}'
$parsed = ConvertTo-EchoJsonDocument -Raw $objectDoc -Command 'test'
Assert-Equal 'v0.2.0.19' $parsed.tag_name 'single object parses'

# An array response parses into an array.
$arrayDoc = '[{"name":"a"},{"name":"b"}]'
$parsedArray = @(ConvertTo-EchoJsonDocument -Raw $arrayDoc -Command 'test')
Assert-Equal 2 $parsedArray.Count 'array collects all elements'

# Multi-element stdout from `.items[] | {...}` style output must be rejected as
# malformed instead of parsed as a single object, because it is NDJSON and a
# single ConvertFrom-Json over the whole stream fails or loses elements.
$ndjson = (@(
    '{"name":"Lint GitHub Actions Workflows","status":"completed","conclusion":"success"}'
    '{"name":"Test, Publish and Validate Distributions","status":"completed","conclusion":"success"}'
) -join "`n")
Assert-Throws { ConvertTo-EchoJsonDocument -Raw $ndjson -Command 'items' } 'malformed JSON' 'per-element NDJSON must not parse as a single document'

# --- R2/R4: release lookup through the seam -------------------------------
$runnerScript = $null
$runnerMap = @{
    'repos/example/repo/releases/tags/v0.2.0.19' = (Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-compatible.json') -Raw)
    'repos/example/repo/git/ref/tags/v0.2.0.19' = (Get-Content -LiteralPath (Join-Path $fixturesGitHub 'tag-lightweight.json') -Raw)
}
Set-EchoGitHubCommandRunner -Runner ([scriptblock]{ param($Arguments)
    $apiIndex = [Array]::IndexOf([string[]]$Arguments, 'api')
    $path = if ($apiIndex -ge 0 -and $apiIndex + 1 -lt $Arguments.Count) { $Arguments[$apiIndex + 1] } else { '' }
    if ($runnerMap.ContainsKey($path)) { return $runnerMap[$path] }
    return [pscustomobject]@{ ExitCode = 1; Stdout = @('{"message":"Not Found"}') }
})

$release = Get-EchoGitHubReleaseByTag -Repository 'example/repo' -Tag 'v0.2.0.19'
Assert-Equal 100 $release.id 'release by tag resolves through the seam'

# --- R3: lightweight tag resolution ---------------------------------------
Write-Host '== R3 Tag resolution ==' -ForegroundColor Cyan
$lightSha = Resolve-EchoTagCommitSha -Repository 'example/repo' -Tag 'v0.2.0.19'
Assert-Equal '1111111111111111111111111111111111111111' $lightSha 'lightweight tag resolves to the commit directly'

# Annotated tag follows tag object -> commit through a separate API call.
Set-EchoGitHubCommandRunner -Runner ([scriptblock]{ param($Arguments)
    $command = ($Arguments | Select-Object -Skip 1) -join ' '
    if ($command -match 'git/ref/tags/v0.2.0.19') { return (Get-Content -LiteralPath (Join-Path $fixturesGitHub 'tag-annotated-ref.json') -Raw) }
    if ($command -match 'git/tags/2222222222222222222222222222222222222222') { return (Get-Content -LiteralPath (Join-Path $fixturesGitHub 'tag-annotated-object.json') -Raw) }
    return '{"object":{"type":"unknown"}}'
})
$annotatedSha = Resolve-EchoTagCommitSha -Repository 'example/repo' -Tag 'v0.2.0.19'
Assert-Equal '3333333333333333333333333333333333333333' $annotatedSha 'annotated tag dereferences to the commit'

# --- R4: release identity and idempotency ----------------------------------
Write-Host '== R4 Release idempotency ==' -ForegroundColor Cyan
$expectedAssets = @(
    [pscustomobject]@{ name = 'EchoVisualizer-0.2.0.19-win-x64.zip'; size = 1000 }
    [pscustomobject]@{ name = 'EchoVisualizer-0.2.0.19-win-arm64.zip'; size = 1100 }
    [pscustomobject]@{ name = 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle'; size = 33790000 }
    [pscustomobject]@{ name = 'EchoVisualizer-0.2.0.19-release-manifest.json'; size = 2000 }
    [pscustomobject]@{ name = 'SHA256SUMS.txt'; size = 500 }
)

$compatibleAssets = Get-EchoReleaseAssetSet -ReleaseInfo $release
$verdict = Test-EchoGitHubReleaseCompatibility `
    -ReleaseInfo $release `
    -ExpectedCommitSha '3333333333333333333333333333333333333333' `
    -ExpectedAssets $expectedAssets `
    -ActualAssets $compatibleAssets
Assert-True $verdict.Safe 'exact compatible release is a no-op'
Assert-Equal 'no-op' $verdict.Action 'compatible release never republishes'

# Conflicted commit (different SHA with same assets) must fail closed.
$conflicted = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-conflicted-commit.json') -Raw | ConvertFrom-Json
$verdict2 = Test-EchoGitHubReleaseCompatibility `
    -ReleaseInfo $conflicted `
    -ExpectedCommitSha '3333333333333333333333333333333333333333' `
    -ExpectedAssets $expectedAssets `
    -ActualAssets $conflicted.assets
Assert-True (-not $verdict2.Safe) 'conflicted commit release fails closed'

# Draft / prerelease fail closed.
$draft = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-draft.json') -Raw | ConvertFrom-Json
$verdictDraft = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $draft -ExpectedCommitSha $annotatedSha -ExpectedAssets @() -ActualAssets @()
Assert-Equal 'fail-closed' $verdictDraft.Action 'draft release must not be auto-published'

$prerelease = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-prerelease.json') -Raw | ConvertFrom-Json
$verdictPre = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $prerelease -ExpectedCommitSha $annotatedSha -ExpectedAssets @() -ActualAssets @()
Assert-Equal 'fail-closed' $verdictPre.Action 'prerelease must fail closed'

# Missing release -> create-draft.
$verdictMissing = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $null -ExpectedCommitSha $annotatedSha -ExpectedAssets @() -ActualAssets @()
Assert-Equal 'create-draft' $verdictMissing.Action 'missing release allows a single draft creation'

# --- R5: exact filename -> hash validation ---------------------------------
Write-Host '== R5 SHA256SUMS exact pairs ==' -ForegroundColor Cyan
$sumsContent = @'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  EchoVisualizer-0.2.0.19-win-x64.zip
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  SHA256SUMS.txt
'@
Assert-True (Test-EchoChecksumPair -ChecksumsContent $sumsContent -FileName 'EchoVisualizer-0.2.0.19-win-x64.zip' -ActualSha256 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') 'exact name/hash pair accepted'
# A hash that exists on ANY line but under a different file name must fail.
Assert-Throws { Test-EchoChecksumPair -ChecksumsContent $sumsContent -FileName 'EchoVisualizer-0.2.0.19-win-arm64.zip' -ActualSha256 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' } 'does not contain' 'hash matching another file name must not be accepted for a different name'
# Wrong hash for the right name must fail.
Assert-Throws { Test-EchoChecksumPair -ChecksumsContent $sumsContent -FileName 'EchoVisualizer-0.2.0.19-win-x64.zip' -ActualSha256 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' } 'declares' 'wrong hash for the exact name fails'

# ---------------------------------------------------------------------------
# R9/R10 — Store state separation and correlation
# ---------------------------------------------------------------------------
Write-Host '== R9/R10 Store state + correlation ==' -ForegroundColor Cyan

# NoSubmission: upload allowed only when target is monotonic higher.
$verdictNosub = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'NoSubmission' `
    -TargetVersion '0.2.19.0' `
    -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'upload' $verdictNosub.Action 'NoSubmission uploads a newer target'
$verdictNosubEqual = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'NoSubmission' `
    -TargetVersion '0.2.0.0' `
    -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'fail-monotonic' $verdictNosubEqual.Action 'NoSubmission equal target fails monotonicity'

# PendingCommit that exactly matches the target resumes.
$verdictResume = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetVersion '0.2.19.0' `
    -PendingTargetVersion '0.2.19.0' `
    -PendingPackageName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
    -PendingPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76' `
    -PendingPackageSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
    -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
    -TargetBundleSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
    -TargetPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76'
Assert-Equal 'commit-resume' $verdictResume.Action 'exact pending commit resumes'

# PendingCommit with a different version fails closed.
$verdictConflictVersion = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetVersion '0.2.19.0' `
    -PendingTargetVersion '0.2.18.0'
Assert-Equal 'fail-closed' $verdictConflictVersion.Action 'pending version mismatch fails closed'

# PendingCommit with a different bundle name fails closed.
$verdictConflictBundle = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetVersion '0.2.19.0' `
    -PendingTargetVersion '0.2.19.0' `
    -PendingPackageName 'EchoVisualizer-0.2.0.18-msixbundle.msixbundle' `
    -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle'
Assert-Equal 'fail-closed' $verdictConflictBundle.Action 'pending bundle-name mismatch fails closed'

# Active states are monitor-only.
$verdictActive = Test-EchoStoreStateSafeToProceed -CurrentState 'Certification' -TargetVersion '0.2.19.0'
Assert-Equal 'monitor-only' $verdictActive.Action 'active states are monitor-only'

# Terminal failures fail closed.
$verdictFailed = Test-EchoStoreStateSafeToProceed -CurrentState 'CertificationFailed' -TargetVersion '0.2.19.0'
Assert-Equal 'fail-closed' $verdictFailed.Action 'terminal failure fails closed'
$verdictUnknown = Test-EchoStoreStateSafeToProceed -CurrentState 'Unknown' -TargetVersion '0.2.19.0'
Assert-Equal 'fail-closed' $verdictUnknown.Action 'unknown state fails closed'

# --- Get-EchoStoreSubmissionState reads the fixture contract ----------------
# A pending matching submission surfaces separated latest/pending/hash fields.
$stateJson = Get-Content -LiteralPath (Join-Path $fixturesStore 'state-pendingcommit-matching.json') -Raw
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    if ($Arguments -contains 'get') {
        return [pscustomobject]@{ ExitCode = 0; Stdout = @($stateJson); Stderr = @() }
    }
    return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() }
})
$state = Get-EchoStoreSubmissionState -CliPath 'fake\msstore.exe' -ProductId '9NJMJFH8J616'
Assert-Equal 'PendingCommit' $state.State 'pending state normalized'
Assert-Equal '0.2.0.0' $state.LatestPublishedVersion 'latest published version separated'
Assert-Equal '0.2.19.0' $state.PendingTargetVersion 'pending target version separated'
Assert-Equal '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' $state.PendingPackageSha256 'pending hash separated'

# NoSubmission fixture surfaces as absent submission.
$nosubJson = Get-Content -LiteralPath (Join-Path $fixturesStore 'state-nosubmission.json') -Raw
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    return [pscustomobject]@{ ExitCode = 0; Stdout = @($nosubJson); Stderr = @() }
})
$nosub = Get-EchoStoreSubmissionState -CliPath 'fake\msstore.exe' -ProductId '9NJMJFH8J616'
Assert-Equal 'NoSubmission' $nosub.State 'no-submission fixture normalizes'
Assert-True (-not $nosub.SubmissionExists) 'no-submission flags no pending submission'

# A pending submission referencing a different version must fail the preflight.
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    return [pscustomobject]@{ ExitCode = 0; Stdout = @((Get-Content -LiteralPath (Join-Path $fixturesStore 'state-pendingcommit-conflicting.json') -Raw)); Stderr = @() }
})
Assert-Throws {
    Invoke-EchoStorePreflight `
        -CliPath 'fake\msstore.exe' `
        -ProductId '9NJMJFH8J616' `
        -TargetVersion '0.2.19.0' `
        -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
        -TargetBundleSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
        -TargetPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76'
} 'failed closed' 'conflicting pending submission stops the preflight'
Set-EchoStoreCliProcessInvoker -Invoker $null

# --- R11 — retry classification --------------------------------------------
Write-Host '== R11 Retry classification ==' -ForegroundColor Cyan
Assert-True (Test-EchoMsStoreTransientFailure -ExitCode 429 -Stdout @() -Stderr @('HTTP/1.1 429 Too Many Requests')) '429 classified transient'
Assert-True (Test-EchoMsStoreTransientFailure -ExitCode 503 -Stdout @() -Stderr @('service unavailable')) '5xx classified transient'
Assert-True (-not (Test-EchoMsStoreTransientFailure -ExitCode 401 -Stdout @() -Stderr @('Authentication failed'))) '401 auth is not transient'
Assert-True (-not (Test-EchoMsStoreTransientFailure -ExitCode 400 -Stdout @() -Stderr @('validation'))) 'validation is not transient'

# Retry is consumed (2 transient => 3 attempts) and permanent errors fail fast.
$attempts = 0
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    $script:attempts++
    if ($script:attempts -le 2) {
        return [pscustomobject]@{ ExitCode = 429; Stdout = @(); Stderr = @('HTTP/1.1 429 Too Many Requests') }
    }
    return [pscustomobject]@{ ExitCode = 0; Stdout = @('{"ok":true}'); Stderr = @() }
})
$result = Invoke-EchoMsStoreCli -CliPath 'fake\msstore.exe' -Arguments @('submission','get') -RetryCount 2
Assert-Equal 3 $script:attempts 'two transient failures are retried exactly twice'
Assert-Equal 0 $result.ExitCode 'retry recovers to success'

$script:attempts = 0
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    $script:attempts++
    if ($script:attempts -eq 1) {
        return [pscustomobject]@{ ExitCode = 429; Stdout = @(); Stderr = @('HTTP/1.1 429 Too Many Requests') }
    }
    return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() }
})
$exhausted = $script:attempts
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    $script:attempts++
    return [pscustomobject]@{ ExitCode = 503; Stdout = @(); Stderr = @('HTTP/1.1 503') }
})
Assert-Throws { Invoke-EchoMsStoreCli -CliPath 'fake\msstore.exe' -Arguments @('submission','get') -RetryCount 1 } 'after 1 retries' 'retry cap is enforced'
Set-EchoStoreCliProcessInvoker -Invoker $null

# Secret redaction keeps credential values out of error text.
$redacted = Get-EchoRedactedText -Text 'client: super-secret-value and more' -SecretValues @('super-secret-value')
Assert-True ($redacted -notmatch 'super-secret-value') 'secret value redacted'

# ---------------------------------------------------------------------------
# R14 — strict Product.props schema parsing
# ---------------------------------------------------------------------------
Write-Host '== R14 Strict Product.props parsing ==' -ForegroundColor Cyan

# Unknown item group fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.UnknownItemGroup.props') } 'not part of the distribution schema|unknown Echo item type' 'unknown item group rejected'

# Required item group missing entirely fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.MissingGroup.props') } 'missing from the distribution configuration|EchoBrandTargetSizeAsset' 'missing required item group rejected'

# Unknown metadata on a schema item fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.UnknownMetadata.props') } 'not part of the schema' 'unknown metadata rejected'

# Duplicate architecture fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.DuplicateArchitecture.props') } 'duplicate architecture|duplicated' 'duplicate architecture rejected'

# Invalid capability name fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.InvalidCapabilityName.props') } 'not a valid capability name' 'invalid capability name rejected'

# Invalid ManifestElement enum fails closed.
Assert-Throws { Get-EchoDistributionConfiguration -Path (Join-Path $fixturesStore 'Product.InvalidCapabilityElement.props') } 'unsupported ManifestElement' 'invalid capability element rejected'

Write-Host 'Release hardening regression fixtures: PASS' -ForegroundColor Green