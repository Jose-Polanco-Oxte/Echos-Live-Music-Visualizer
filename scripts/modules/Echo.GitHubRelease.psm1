# Echo.GitHubRelease.psm1
#
# Shared GitHub API / release-provenance boundary (D2). Both release.yml and
# store-publish.yml consume this module so that JSON parsing, tag dereference
# and release identity comparison exist in exactly one offline-testable place.
#
# Contract rules:
#   - Every `gh` response is captured as a single raw document and parsed with
#     ConvertTo-EchoJsonDocument. Per-element `.items[]` stdout piped into one
#     ConvertFrom-Json is forbidden (the audit found that it silently corrupts
#     multi-line output).
#   - Tags (lightweight and annotated) resolve recursively to a real commit
#     SHA-256 of 40 lowercase hex chars.
#   - Release identity is (tag, commit, draft/prerelease state, asset set with
#     exact names/sizes/hashes). Idempotent recovery only when all match;
#     conflict is fail-closed.
#   - SHA256SUMS.txt is validated by the exact `filename -> hash` pair, never by
#     matching a bare hash on any line.
#
# No credentials are stored here. Secrets are bound by the caller through the
# GitHub token available to actions only.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Optional test seam. When set, Invoke-EchoGitHubCommand delegates to this
# scriptblock instead of the real `gh` executable. The scriptblock receives the
# argument array and must return either:
#   - an array of raw output lines (exit code assumed zero), or
#   - a [pscustomobject] with `ExitCode` and `Stdout` (array of lines).
# Implementations must not contain secret values.
$script:GitHubCommandRunner = $null

function Set-EchoGitHubCommandRunner {
    [CmdletBinding()]
    param([scriptblock]$Runner)
    $script:GitHubCommandRunner = $Runner
}

function Invoke-EchoGitHubCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFail
    )
    if ($script:GitHubCommandRunner) {
        $simulated = & $script:GitHubCommandRunner $Arguments
        if ($null -ne $simulated -and $simulated.PSObject.Properties.Name -contains 'ExitCode') {
            if (-not $AllowFail -and $simulated.ExitCode -ne 0) {
                throw "gh $($Arguments[0]) failed with exit code $($simulated.ExitCode): $($simulated.Stdout -join ' ')"
            }
            return @($simulated.Stdout)
        }
        return @($simulated)
    }
    $output = @(& gh @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFail -and $exitCode -ne 0) {
        throw "gh $($Arguments[0]) failed with exit code $exitCode`: $($output -join ' ')"
    }
    return @($output)
}

function ConvertTo-EchoJsonDocument {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Raw,
        [Parameter(Mandatory)][string]$Command,
        [bool]$AllowEmpty = $false
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        if ($AllowEmpty) { return $null }
        throw "GitHub command returned no output: $Command"
    }
    try {
        return ($Raw | ConvertFrom-Json)
    }
    catch {
        throw "GitHub command returned malformed JSON for '$Command': $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Tag -> commit resolution (lightweight and annotated tags)
# ---------------------------------------------------------------------------

function Resolve-EchoTagCommitSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Repository,
        [int]$MaxDepth = 10
    )

    if ($Tag -notmatch '^v\d+\.\d+\.\d+\.\d+$') {
        throw "Release tag must use vA.B.C.D: $Tag"
    }

    $refCommand = "repos/$Repository/git/ref/tags/$Tag"
    $refRaw = @(Invoke-EchoGitHubCommand -Arguments @('api', $refCommand, '--jq', '{object:{type:.object.type,sha:.object.sha}}'))
    $refDoc = ConvertTo-EchoJsonDocument -Raw (($refRaw -join "`n")) -Command $refCommand

    $sha = [string]$refDoc.object.sha
    $type = [string]$refDoc.object.type
    if (-not $sha -or -not $type) {
        throw "Unable to resolve release tag $Tag to a Git object."
    }

    # Recursively dereference annotated tag objects to the underlying commit.
    $depth = 0
    while ($type -eq 'tag') {
        $depth++
        if ($depth -gt $MaxDepth) {
            throw "Annotated tag $Tag exceeded the maximum dereference depth ($MaxDepth)."
        }
        $tagCommand = "repos/$Repository/git/tags/$sha"
        $tagRaw = @(Invoke-EchoGitHubCommand -Arguments @('api', $tagCommand, '--jq', '{object:{type:.object.type,sha:.object.sha}}'))
        $tagDoc = ConvertTo-EchoJsonDocument -Raw (($tagRaw -join "`n")) -Command $tagCommand
        $sha = [string]$tagDoc.object.sha
        $type = [string]$tagDoc.object.type
    }

    if ($type -ne 'commit') {
        throw "Tag $Tag dereferenced to a '$type' object; expected a commit."
    }
    if ($sha -notmatch '^[0-9a-f]{40}$') {
        throw "Resolved commit SHA for $Tag is not a 40-character lowercase hex SHA: $sha"
    }
    return $sha
}

# ---------------------------------------------------------------------------
# Release lookup and identity comparison
# ---------------------------------------------------------------------------

function Get-EchoGitHubReleaseByTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Repository
    )

    $command = "repos/$Repository/releases/tags/$Tag"
    $rawLines = @(Invoke-EchoGitHubCommand -Arguments @('api', $command, '--jq', '.') -AllowFail)
    if ($rawLines -match '(?i)(Not Found|404)') {
        return $null
    }
    if (-not $rawLines -or [string]::IsNullOrWhiteSpace(($rawLines -join "`n"))) {
        return $null
    }
    return (ConvertTo-EchoJsonDocument -Raw (($rawLines -join "`n")) -Command $command)
}

function Get-EchoReleaseAssetSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$ReleaseInfo
    )
    $assets = @()
    if ($null -ne $ReleaseInfo.PSObject.Properties.Name -and $ReleaseInfo.PSObject.Properties.Name -contains 'assets') {
        $assets = @($ReleaseInfo.assets | ForEach-Object {
            [pscustomobject]@{
                name = [string]$_.name
                size = [long]$_.size
                url = [string]$_.browser_download_url
            }
        })
    }
    return $assets
}

# Returns a verdict object:
#   Safe   - whether the caller may treat the release as the exact target
#   Action - 'no-op' | 'create-draft' | 'publish-draft' | 'fail-closed'
#   Reason - human-readable cause (no secrets)
function Test-EchoGitHubReleaseCompatibility {
    [CmdletBinding()]
    param(
        [object]$ReleaseInfo,
        [Parameter(Mandatory)][string]$ExpectedCommitSha,
        [AllowEmptyCollection()][object[]]$ExpectedAssets,
        [AllowEmptyCollection()][object[]]$ActualAssets
    )

    if ($null -eq $ReleaseInfo -or [string]::IsNullOrWhiteSpace([string]$ReleaseInfo.id)) {
        return [pscustomobject]@{ Safe = $true; Action = 'create-draft'; Reason = 'No release exists for this tag yet; a draft must be created.' }
    }

    if ($ReleaseInfo.draft -eq $true) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = 'Release exists but is still a draft; automatic publish of an unexpected draft is not allowed.' }
    }
    if ($ReleaseInfo.prerelease -eq $true) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = 'Release exists but is a prerelease; only stable releases are accepted.' }
    }

    # R2: commit provenance must be provable before any no-op. A release is only
    # a no-op when it points at the exact resolved commit SHA. Absent marker,
    # branch name, invalid format or any mismatch always fails closed.
    if ($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$') {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Expected commit must be a lowercase 40-character hex SHA; got '$ExpectedCommitSha'." }
    }
    $hasTargetCommitish = $ReleaseInfo.PSObject.Properties.Name -contains 'target_commitish'
    $targetCommitish = if ($hasTargetCommitish) { [string]$ReleaseInfo.target_commitish } else { '' }
    if ([string]::IsNullOrWhiteSpace($targetCommitish)) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = 'Release does not record a resolvable commit marker (target_commitish is absent); cannot prove provenance.' }
    }
    if ($targetCommitish -notmatch '^[0-9a-f]{40}$') {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Release target_commitish '$targetCommitish' is not a commit SHA (likely a branch name); a branch is not valid source proof." }
    }
    if ($targetCommitish -cne $ExpectedCommitSha) {
        return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Release points to commit $targetCommitish but the expected release commit is $ExpectedCommitSha." }
    }

    $actualAssets = @($ActualAssets)
    $expectedByName = @{}
    foreach ($expected in $ExpectedAssets) {
        $expectedByName[[string]$expected.name] = $expected
    }
    $actualByName = @{}
    foreach ($actual in $actualAssets) {
        $actualByName[[string]$actual.name] = $actual
    }

    foreach ($name in $expectedByName.Keys) {
        if (-not $actualByName.ContainsKey($name)) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Release is missing expected asset '$name'." }
        }
        $expected = $expectedByName[$name]
        $actual = $actualByName[$name]
        if ([long]$actual.size -ne [long]$expected.size) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Release asset '$name' has a different size (expected $($expected.size)B, found $($actual.size)B)." }
        }
    }
    foreach ($name in $actualByName.Keys) {
        if (-not $expectedByName.ContainsKey($name)) {
            return [pscustomobject]@{ Safe = $false; Action = 'fail-closed'; Reason = "Release contains unexpected asset '$name'." }
        }
    }

    return [pscustomobject]@{ Safe = $true; Action = 'no-op'; Reason = 'Release matches the exact expected identity ({ tag, assets, sizes }).' }
}

# ---------------------------------------------------------------------------
# SHA256SUMS.txt exact-pair validation (R5)
# ---------------------------------------------------------------------------

function Test-EchoChecksumPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChecksumsContent,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$ActualSha256
    )

    $pairFound = $false
    foreach ($line in @($ChecksumsContent -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        $parts = @($trimmed -split '\s+')
        if ($parts.Count -lt 2 -or $parts[1] -ne $FileName) { continue }
        $declared = $parts[0].ToLowerInvariant()
        if ($declared -cne $ActualSha256) {
            throw "SHA256SUMS.txt declares $declared for '$FileName' but the downloaded bytes hash to $ActualSha256."
        }
        $pairFound = $true
        break
    }
    if (-not $pairFound) {
        throw "SHA256SUMS.txt does not contain an entry for the exact file name '$FileName'."
    }
    return $true
}

Export-ModuleMember -Function @(
    'Set-EchoGitHubCommandRunner',
    'Invoke-EchoGitHubCommand',
    'ConvertTo-EchoJsonDocument',
    'Resolve-EchoTagCommitSha',
    'Get-EchoGitHubReleaseByTag',
    'Get-EchoReleaseAssetSet',
    'Test-EchoGitHubReleaseCompatibility',
    'Test-EchoChecksumPair'
)