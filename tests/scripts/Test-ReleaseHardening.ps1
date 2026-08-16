# Test-ReleaseHardening.ps1
#
# Regression coverage for the Microsoft Store release CD hardening plan
# (PLAN-20260811-RELEASE-CD-HARDENING). Each case maps to an audited defect:
#   R2  gh api JSON parsing (single-document, not per-element)
#   R3  lightweight + annotated tag resolution to a real commit SHA
#   R4  idempotent stable release recovery; fail-closed conflicts
#   R5  exact filename -> hash validation in SHA256SUMS.txt
#   R9  Store state separation (NoSubmission / PendingCommit / active / terminal)
#   R10 pending-submission correlation with target Product ID/version/package/hash
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
$testProductId = '9NJMJFH8J616'
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

# --- R2: commit provenance is mandatory for any no-op -------------
Write-Host '== R2 Commit provenance (post-audit) ==' -ForegroundColor Cyan

# A release whose target_commitish is absent can never be a no-op.
$noSha = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-compatible.json') -Raw | ConvertFrom-Json
$noSha.PSObject.Properties.Remove('target_commitish')
$verdictNoSha = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $noSha -ExpectedCommitSha $annotatedSha -ExpectedAssets $expectedAssets -ActualAssets $compatibleAssets
Assert-Equal 'fail-closed' $verdictNoSha.Action 'release without a commit marker fails closed, never no-op'

# A release whose target_commitish is a branch name (not a SHA) fails closed.
$branch = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-compatible.json') -Raw | ConvertFrom-Json
$branch.target_commitish = 'main'
$verdictBranch = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $branch -ExpectedCommitSha $annotatedSha -ExpectedAssets $expectedAssets -ActualAssets $compatibleAssets
Assert-Equal 'fail-closed' $verdictBranch.Action 'a branch target_commitish is not valid source proof'

# A release with a malformed/non-SHA marker fails closed.
$malformed = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-compatible.json') -Raw | ConvertFrom-Json
$malformed.target_commitish = 'not-a-commit'
$verdictMalformed = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $malformed -ExpectedCommitSha $annotatedSha -ExpectedAssets $expectedAssets -ActualAssets $compatibleAssets
Assert-Equal 'fail-closed' $verdictMalformed.Action 'malformed target_commitish fails closed'

# An invalid ExpectedCommitSha (wrong length/format) fails closed even when the
# assets match exactly.
$badExpect = Test-EchoGitHubReleaseCompatibility -ReleaseInfo $release -ExpectedCommitSha 'abc' -ExpectedAssets $expectedAssets -ActualAssets $compatibleAssets
Assert-Equal 'fail-closed' $badExpect.Action 'invalid expected SHA fails closed'

# An expected SHA that does not match the resolved release commit fails closed
# with otherwise-identical assets (isolates commit conflict, R3).
$conflicted = Get-Content -LiteralPath (Join-Path $fixturesGitHub 'release-conflicted-commit.json') -Raw | ConvertFrom-Json
$verdict2 = Test-EchoGitHubReleaseCompatibility `
    -ReleaseInfo $conflicted `
    -ExpectedCommitSha '3333333333333333333333333333333333333333' `
    -ExpectedAssets $expectedAssets `
    -ActualAssets $conflicted.assets
Assert-Equal 'fail-closed' $verdict2.Action 'commit-conflicted release fails closed even with identical assets'

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
    -TargetProductId $testProductId `
    -QueriedProductId $testProductId `
    -TargetVersion '0.2.19.0' `
    -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'upload' $verdictNosub.Action 'NoSubmission uploads a newer target'
$verdictNosubEqual = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'NoSubmission' `
    -TargetProductId $testProductId `
    -QueriedProductId $testProductId `
    -TargetVersion '0.2.0.0' `
    -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'fail-monotonic' $verdictNosubEqual.Action 'NoSubmission equal target fails monotonicity'

# PendingCommit that exactly matches the target resumes.
$verdictResume = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetProductId $testProductId `
    -QueriedProductId $testProductId `
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
    -TargetProductId $testProductId `
    -QueriedProductId $testProductId `
    -TargetVersion '0.2.19.0' `
    -PendingTargetVersion '0.2.18.0'
Assert-Equal 'fail-closed' $verdictConflictVersion.Action 'pending version mismatch fails closed'

# PendingCommit with a different bundle name fails closed.
$verdictConflictBundle = Test-EchoStoreStateSafeToProceed `
    -CurrentState 'PendingCommit' `
    -TargetProductId $testProductId `
    -QueriedProductId $testProductId `
    -TargetVersion '0.2.19.0' `
    -PendingTargetVersion '0.2.19.0' `
    -PendingPackageName 'EchoVisualizer-0.2.0.18-msixbundle.msixbundle' `
    -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle'
Assert-Equal 'fail-closed' $verdictConflictBundle.Action 'pending bundle-name mismatch fails closed'

# Active states are monitor-only.
$verdictActive = Test-EchoStoreStateSafeToProceed -CurrentState 'Certification' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0'
Assert-Equal 'monitor-only' $verdictActive.Action 'active states are monitor-only'

# Terminal failures fail closed.
$verdictFailed = Test-EchoStoreStateSafeToProceed -CurrentState 'CertificationFailed' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0'
Assert-Equal 'fail-closed' $verdictFailed.Action 'terminal failure fails closed'
$verdictUnknown = Test-EchoStoreStateSafeToProceed -CurrentState 'Unknown' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0'
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
$state = Get-EchoStoreSubmissionState -CliPath 'fake\msstore.exe' -ProductId $testProductId
Assert-Equal $testProductId $state.QueriedProductId 'pending state retains queried Product ID'
Assert-Equal 'PendingCommit' $state.State 'pending state normalized'
Assert-Equal '0.2.0.0' $state.LatestPublishedVersion 'latest published version separated'
Assert-Equal '0.2.19.0' $state.PendingTargetVersion 'pending target version separated'
Assert-Equal '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' $state.PendingPackageSha256 'pending hash separated'

# NoSubmission fixture surfaces as absent submission.
$nosubJson = Get-Content -LiteralPath (Join-Path $fixturesStore 'state-nosubmission.json') -Raw
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    return [pscustomobject]@{ ExitCode = 0; Stdout = @($nosubJson); Stderr = @() }
})
$nosub = Get-EchoStoreSubmissionState -CliPath 'fake\msstore.exe' -ProductId $testProductId
Assert-Equal $testProductId $nosub.QueriedProductId 'no-submission state retains queried Product ID'
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

# --- R4: Published requires a valid canonical latest version ---------------
Write-Host '== R4 Published version requirement (post-audit) ==' -ForegroundColor Cyan

# Published with a valid canonical latest version and a newer target uploads.
$pubOk = Test-EchoStoreStateSafeToProceed -CurrentState 'Published' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0' -LatestPublishedVersion '0.2.0.0'
Assert-Equal 'upload' $pubOk.Action 'published with valid version uploads a newer target'

# Published with an empty latest version can never upload (fail closed).
$pubNoVersion = Test-EchoStoreStateSafeToProceed -CurrentState 'Published' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0' -LatestPublishedVersion ''
Assert-Equal 'fail-closed' $pubNoVersion.Action 'published without latest version fails closed, never upload'

# Published with a malformed latest version fails closed.
$pubMalformed = Test-EchoStoreStateSafeToProceed -CurrentState 'Published' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0' -LatestPublishedVersion 'not.a.version'
Assert-Equal 'fail-closed' $pubMalformed.Action 'published with malformed latest version fails closed'

# NoSubmission is the only state that may lack a previous version.
$nosubNoVersion = Test-EchoStoreStateSafeToProceed -CurrentState 'NoSubmission' -TargetProductId $testProductId -QueriedProductId $testProductId -TargetVersion '0.2.19.0' -LatestPublishedVersion ''
Assert-Equal 'upload' $nosubNoVersion.Action 'NoSubmission may upload without a prior version'

# --- R5: PendingCommit is all-or-nothing -----------------------------------
Write-Host '== R5 PendingCommit all-or-nothing (post-audit) ==' -ForegroundColor Cyan

function New-PendingSplat {
    param(
        [string]$PendingTargetVersion = '0.2.19.0',
        [string]$PendingPackageName = 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle',
        [string]$PendingPackageFamilyName = 'Tun4z.EchoVisualizer_ga3qxkah0cx76',
        [string]$PendingPackageSha256 = '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e'
    )
    return @{
        CurrentState = 'PendingCommit'
        TargetProductId = $testProductId
        QueriedProductId = $testProductId
        TargetVersion = '0.2.19.0'
        TargetBundleName = 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle'
        TargetBundleSha256 = '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e'
        TargetPackageFamilyName = 'Tun4z.EchoVisualizer_ga3qxkah0cx76'
        PendingTargetVersion = $PendingTargetVersion
        PendingPackageName = $PendingPackageName
        PendingPackageFamilyName = $PendingPackageFamilyName
        PendingPackageSha256 = $PendingPackageSha256
    }
}

# Complete, exact match resumes.
$splat = New-PendingSplat
$resumeExact = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'commit-resume' $resumeExact.Action 'complete exact pending resumes commit'

# Missing remote field -> fail closed, never wildcard.
$splat = New-PendingSplat -PendingPackageSha256 ''
$missingRemote = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'fail-closed' $missingRemote.Action 'missing remote hash fails closed'

# Missing remote bundle name -> fail closed.
$splat = New-PendingSplat -PendingPackageName ''
$missingName = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'fail-closed' $missingName.Action 'missing remote bundle name fails closed'
$splat = New-PendingSplat -PendingPackageFamilyName ''
$missingPfn = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'fail-closed' $missingPfn.Action 'missing remote package family name fails closed'
$splat = New-PendingSplat -PendingTargetVersion ''
$missingVersion = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'fail-closed' $missingVersion.Action 'missing remote version fails closed'

# Missing target field -> fail closed.
$missingTarget = New-PendingSplat
$missingTarget.TargetBundleSha256 = ''
$missingTargetVerdict = Test-EchoStoreStateSafeToProceed @missingTarget
Assert-Equal 'fail-closed' $missingTargetVerdict.Action 'missing target hash fails closed'

# Mismatched hash -> fail closed (the specific prior gap).
$splat = New-PendingSplat -PendingPackageSha256 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$mismatchHash = Test-EchoStoreStateSafeToProceed @splat
Assert-Equal 'fail-closed' $mismatchHash.Action 'mismatched pending hash fails closed'

# Product ID context is part of the correlation contract, not an implicit
# caller convention.
$productMismatch = New-PendingSplat
$productMismatch.QueriedProductId = '9NJMJFH8J616-other'
$productMismatchVerdict = Test-EchoStoreStateSafeToProceed @productMismatch
Assert-Equal 'fail-closed' $productMismatchVerdict.Action 'queried Product ID mismatch fails closed'
$productMissing = New-PendingSplat
$productMissing.QueriedProductId = ''
$productMissingVerdict = Test-EchoStoreStateSafeToProceed @productMissing
Assert-Equal 'fail-closed' $productMissingVerdict.Action 'missing queried Product ID fails closed'

# --- R6/R7: fail-closed cases invoke zero mutators -------------------------
Write-Host '== R6/R7 Mutation counters (post-audit) ==' -ForegroundColor Cyan

# Count mutating invocations when a conflicting pending state is preflighted:
# preflight must call only read-only `submission get`, never publish/commit/delete.
$mutatingCount = @{ publish = 0; commit = 0; del = 0; get = 0 }
Set-EchoStoreCliProcessInvoker -Invoker ([scriptblock]{ param($CliPath, $Arguments, $Environment)
    if ($Arguments -contains 'get') { $script:mutatingCount.get++; return [pscustomobject]@{ ExitCode = 0; Stdout = @((Get-Content -LiteralPath (Join-Path $fixturesStore 'state-pendingcommit-conflicting.json') -Raw)); Stderr = @() } }
    if ($Arguments -contains 'publish') { $script:mutatingCount.publish++; return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
    if ($Arguments -contains 'commit') { $script:mutatingCount.commit++; return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
    if ($Arguments -contains 'delete') { $script:mutatingCount.del++; return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
    return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() }
})
$preflightFired = $false
try {
    Invoke-EchoStorePreflight `
        -CliPath 'fake\msstore.exe' `
        -ProductId '9NJMJFH8J616' `
        -TargetVersion '0.2.19.0' `
        -TargetBundleName 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle' `
        -TargetBundleSha256 '070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e' `
        -TargetPackageFamilyName 'Tun4z.EchoVisualizer_ga3qxkah0cx76' | Out-Null
}
catch { $preflightFired = $true }
Assert-True $preflightFired 'conflicting preflight must throw'
Assert-Equal 0 $script:mutatingCount.publish 'fail-closed preflight never calls publish'
Assert-Equal 0 $script:mutatingCount.commit 'fail-closed preflight never calls commit'
Assert-Equal 0 $script:mutatingCount.del 'fail-closed preflight never calls submission delete'
Set-EchoStoreCliProcessInvoker -Invoker $null

# --- R6/R7: real caller flow through a fake CLI ----------------------------
Write-Host '== R6/R7 Caller flow with fake CLI (post-audit) ==' -ForegroundColor Cyan

$callerScript = Join-Path $repoRoot 'scripts\Invoke-MicrosoftStoreRelease.ps1'
$callerPwsh = (Get-Command pwsh -ErrorAction Stop).Source
$callerTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("echo-store-caller-" + [guid]::NewGuid().ToString('N'))
$callerBundleName = 'EchoVisualizer-0.2.0.19-msixbundle.msixbundle'
$callerBundlePath = Join-Path $callerTempRoot $callerBundleName
$callerManifestPath = Join-Path $callerTempRoot 'release-manifest.json'
$callerConfig = Get-EchoDistributionConfiguration
$callerSecretNames = @(
    'PARTNER_CENTER_TENANT_ID',
    'PARTNER_CENTER_SELLER_ID',
    'PARTNER_CENTER_CLIENT_ID',
    'PARTNER_CENTER_CLIENT_SECRET'
)
$callerPreviousEnvironment = @{}

function Get-CallerVerb {
    param([string[]]$Arguments)
    if ($Arguments -contains 'reconfigure') { return 'reconfigure' }
    if ($Arguments -contains 'submission' -and $Arguments -contains 'publish') { return 'commit' }
    if ($Arguments -contains 'publish') { return 'publish' }
    if ($Arguments -contains 'delete') { return 'delete' }
    if ($Arguments -contains 'get') { return 'get' }
    return 'unknown'
}

function Assert-CallerSequence {
    param(
        [Parameter(Mandatory)][pscustomobject]$LogHolder,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    $actual = @($LogHolder.Entries | ForEach-Object { Get-CallerVerb -Arguments $_.Arguments })
    Assert-True (($actual -join ',') -eq ($Expected -join ',')) "$Message (actual: $($actual -join ',') )"
}

function Assert-CallerProductId {
    param(
        [Parameter(Mandatory)][pscustomobject]$LogHolder,
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$Message
    )
    foreach ($entry in $LogHolder.Entries) {
        $verb = Get-CallerVerb -Arguments $entry.Arguments
        if ($verb -in @('get', 'publish', 'commit', 'delete')) {
            $hasProductId = ($entry.Arguments -contains $ProductId)
            if (-not $hasProductId) {
                $appIdIndex = [Array]::IndexOf([string[]]$entry.Arguments, '--appId')
                if ($appIdIndex -ge 0 -and $entry.Arguments[$appIdIndex + 1] -ceq $ProductId) {
                    $hasProductId = $true
                }
            }
            Assert-True $hasProductId "$Message ($verb)"
        }
    }
}

function New-CallerInvoker {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Queue[string]]$States,
        [Parameter(Mandatory)][pscustomobject]$LogHolder
    )
    $invoker = {
        param($CliPath, $Arguments, $Environment)
        $LogHolder.Entries.Add([pscustomobject]@{ Arguments = @($Arguments); Environment = $Environment })
        $verb = Get-CallerVerb -Arguments $Arguments
        switch ($verb) {
            'reconfigure' { return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
            'get' {
                if ($States.Count -eq 0) { throw 'fake CLI received an unexpected submission get' }
                return [pscustomobject]@{ ExitCode = 0; Stdout = @($States.Dequeue()); Stderr = @() }
            }
            'publish' { return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
            'commit' { return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
            'delete' { return [pscustomobject]@{ ExitCode = 0; Stdout = @('{}'); Stderr = @() } }
            default { throw "fake CLI received unexpected arguments: $($Arguments -join ' ')" }
        }
    }
    return $invoker.GetNewClosure()
}

function New-CallerPendingState {
    param(
        [Parameter(Mandatory)][string]$Sha256,
        [string]$PackageName = $callerBundleName
    )
    return ([ordered]@{
        hasSubmission = $true
        status = 'PendingCommit'
        latestPublishedVersion = '0.2.0.0'
        submission = [ordered]@{
            version = '0.2.19.0'
            package = [ordered]@{
                name = $PackageName
                packageFamilyName = $callerConfig.Store.PackageFamilyName
                sha256 = $Sha256
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress)
}

try {
    New-Item -ItemType Directory -Path $callerTempRoot -Force | Out-Null
    [System.IO.File]::WriteAllBytes($callerBundlePath, [byte[]](0..31))
    $callerBundleHash = (Get-FileHash -LiteralPath $callerBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $callerManifest = [ordered]@{
        schemaVersion = 1
        product = [ordered]@{
            version = $callerConfig.Product.Version
            coreVersion = $callerConfig.Product.CoreVersion
            name = $callerConfig.Product.Name
            publisherDisplayName = $callerConfig.Product.PublisherDisplayName
            packageIdentityName = $callerConfig.Product.PackageIdentityName
            packagePublisher = $callerConfig.Product.PackagePublisher
            applicationId = $callerConfig.Product.ApplicationId
        }
        store = [ordered]@{
            productId = $callerConfig.Store.ProductId
            packageFamilyName = $callerConfig.Store.PackageFamilyName
            artifactType = $callerConfig.Store.ArtifactType
            targetDeviceFamily = $callerConfig.Store.TargetDeviceFamily
            privacyPolicyUrl = $callerConfig.Store.PrivacyPolicyUrl
        }
        assets = @([ordered]@{
            filename = $callerBundleName
            mediaRole = 'store-bundle'
            sizeBytes = (Get-Item -LiteralPath $callerBundlePath).Length
            sha256 = $callerBundleHash
        })
    }
    [System.IO.File]::WriteAllText($callerManifestPath, ($callerManifest | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

    foreach ($name in $callerSecretNames) {
        $callerPreviousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, "test-$name", 'Process')
    }

    # Successful submit: configure -> preflight get -> publish --noCommit ->
    # post-publish get -> commit, with Product ID on every Store command.
    $submitLog = [pscustomobject]@{ Entries = [System.Collections.Generic.List[object]]::new() }
    $submitStates = [System.Collections.Generic.Queue[string]]::new()
    $submitStates.Enqueue((Get-Content -LiteralPath (Join-Path $fixturesStore 'state-published.json') -Raw))
    $submitStates.Enqueue((New-CallerPendingState -Sha256 $callerBundleHash))
    $submitInvoker = New-CallerInvoker -States $submitStates -LogHolder $submitLog
    & $callerScript `
        -Operation 'submit-or-resume' `
        -ReleaseManifestPath $callerManifestPath `
        -BundlePath $callerBundlePath `
        -CliPath $callerPwsh `
        -CliProcessInvoker $submitInvoker | Out-Null
    Assert-CallerSequence -LogHolder $submitLog -Expected @('reconfigure', 'get', 'publish', 'get', 'commit') -Message 'successful submit follows the guarded sequence'
    Assert-CallerProductId -LogHolder $submitLog -ProductId $testProductId -Message 'successful submit preserves Product ID context'
    $publishCall = @($submitLog.Entries | Where-Object { (Get-CallerVerb -Arguments $_.Arguments) -eq 'publish' })[0]
    Assert-True ($publishCall.Arguments -contains '--noCommit') 'successful submit uses publish --noCommit'

    # Post-publish mismatch: commit must not be reached after the second get.
    $postMismatchLog = [pscustomobject]@{ Entries = [System.Collections.Generic.List[object]]::new() }
    $postMismatchStates = [System.Collections.Generic.Queue[string]]::new()
    $postMismatchStates.Enqueue((Get-Content -LiteralPath (Join-Path $fixturesStore 'state-published.json') -Raw))
    $postMismatchStates.Enqueue((New-CallerPendingState -Sha256 ('a' * 64)))
    $postMismatchInvoker = New-CallerInvoker -States $postMismatchStates -LogHolder $postMismatchLog
    Assert-Throws {
        & $callerScript `
            -Operation 'submit-or-resume' `
            -ReleaseManifestPath $callerManifestPath `
            -BundlePath $callerBundlePath `
            -CliPath $callerPwsh `
            -CliProcessInvoker $postMismatchInvoker | Out-Null
    } 'Post-publish correlation failed closed' 'post-publish mismatch fails before commit'
    Assert-CallerSequence -LogHolder $postMismatchLog -Expected @('reconfigure', 'get', 'publish', 'get') -Message 'post-publish mismatch stops before commit'
    Assert-CallerProductId -LogHolder $postMismatchLog -ProductId $testProductId -Message 'post-publish mismatch preserves Product ID context'

    # Delete matching draft: delete is allowed only after full correlation.
    $deleteLog = [pscustomobject]@{ Entries = [System.Collections.Generic.List[object]]::new() }
    $deleteStates = [System.Collections.Generic.Queue[string]]::new()
    $deleteStates.Enqueue((New-CallerPendingState -Sha256 $callerBundleHash))
    $deleteInvoker = New-CallerInvoker -States $deleteStates -LogHolder $deleteLog
    & $callerScript `
        -Operation 'delete-target-draft' `
        -ReleaseManifestPath $callerManifestPath `
        -BundlePath $callerBundlePath `
        -CliPath $callerPwsh `
        -CliProcessInvoker $deleteInvoker | Out-Null
    Assert-CallerSequence -LogHolder $deleteLog -Expected @('reconfigure', 'get', 'delete') -Message 'matching delete follows the guarded sequence'
    Assert-CallerProductId -LogHolder $deleteLog -ProductId $testProductId -Message 'matching delete preserves Product ID context'

    # Delete mismatch: submission delete must never be reached.
    $deleteMismatchLog = [pscustomobject]@{ Entries = [System.Collections.Generic.List[object]]::new() }
    $deleteMismatchStates = [System.Collections.Generic.Queue[string]]::new()
    $deleteMismatchStates.Enqueue((New-CallerPendingState -Sha256 ('b' * 64)))
    $deleteMismatchInvoker = New-CallerInvoker -States $deleteMismatchStates -LogHolder $deleteMismatchLog
    Assert-Throws {
        & $callerScript `
            -Operation 'delete-target-draft' `
            -ReleaseManifestPath $callerManifestPath `
            -BundlePath $callerBundlePath `
            -CliPath $callerPwsh `
            -CliProcessInvoker $deleteMismatchInvoker | Out-Null
    } 'Refusing to delete pending draft' 'delete mismatch fails before submission delete'
    Assert-CallerSequence -LogHolder $deleteMismatchLog -Expected @('reconfigure', 'get') -Message 'delete mismatch stops before delete'
    Assert-CallerProductId -LogHolder $deleteMismatchLog -ProductId $testProductId -Message 'delete mismatch preserves Product ID context'
}
finally {
    Set-EchoStoreCliProcessInvoker -Invoker $null
    foreach ($name in $callerSecretNames) {
        [Environment]::SetEnvironmentVariable($name, $callerPreviousEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $callerTempRoot) {
        Remove-Item -LiteralPath $callerTempRoot -Recurse -Force
    }
}

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

# ---------------------------------------------------------------------------
# R6 — CLI installer parses and never uses the broken variable interpolation
# ---------------------------------------------------------------------------
Write-Host '== R6 CLI installer ==' -ForegroundColor Cyan
$installerPath = Join-Path $repoRoot 'scripts\Install-MicrosoftStoreCli.ps1'
$installerTokens = $null
$installerErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$installerTokens, [ref]$installerErrors) | Out-Null
Assert-Equal 0 $installerErrors.Count 'Install-MicrosoftStoreCli.ps1 parses with zero errors'
$installerText = Get-Content -Raw $installerPath
Assert-True ($installerText -notmatch '`$\x7B?expectedVersion:') 'no broken $expectedVersion: interpolation remains in the installer'
Assert-True ($installerText -match 'Copy-Item -Path.*extractRoot.*cliRoot.*-Recurse.*-Force') 'CLI installer preserves the complete extracted payload'
Assert-True ($installerText -notmatch 'Copy-Item -LiteralPath \$cliCandidate\.FullName') 'CLI installer does not copy only the apphost executable'

# ---------------------------------------------------------------------------
# R13 — config-derived projections (no active duplicate literals)
# ---------------------------------------------------------------------------
Write-Host '== R13 Config-derived projections ==' -ForegroundColor Cyan
$currentConfig = Get-EchoDistributionConfiguration

# Runtime -> rust target / platform must derive from the architecture items.
Assert-Equal 'x86_64-pc-windows-msvc' (($currentConfig.Store.Architectures | Where-Object { $_.RuntimeIdentifier -eq 'win-x64' }).RustTarget) 'win-x64 rust target from config'
Assert-Equal 'aarch64-pc-windows-msvc' (($currentConfig.Store.Architectures | Where-Object { $_.RuntimeIdentifier -eq 'win-arm64' }).RustTarget) 'win-arm64 rust target from config'
Assert-Equal 'x64' (($currentConfig.Store.Architectures | Where-Object { $_.RuntimeIdentifier -eq 'win-x64' }).ProcessorArchitecture) 'win-x64 platform from config'
Assert-Equal 'arm64' (($currentConfig.Store.Architectures | Where-Object { $_.RuntimeIdentifier -eq 'win-arm64' }).ProcessorArchitecture) 'win-arm64 platform from config'

# Icon sizes derive from Branding config.
Assert-True ($currentConfig.Branding.Icon.Sizes -contains 16 -and $currentConfig.Branding.Icon.Sizes -contains 256) 'icon sizes include the centralized min/max'

# Build-Distributions must not contain the banned fallback literal or the
# hardcoded capability list any more.
$buildScript = Get-Content -Raw (Join-Path $repoRoot 'scripts\Build-Distributions.ps1')
Assert-True ($buildScript -notmatch "(?m)if \(`\?not `\?artifactType\) \{ `\?artifactType = 'msixbundle'") 'no msixbundle fallback literal in Build-Distributions'
Assert-True ($buildScript -notmatch "@\('runFullTrust', 'microphone'\)") 'no hardcoded capability list in Build-Distributions'

Write-Host 'Release hardening regression fixtures: PASS' -ForegroundColor Green
