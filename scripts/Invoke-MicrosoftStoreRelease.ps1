# Invoke-MicrosoftStoreRelease.ps1
#
# Entry point for Store submission through the pinned Microsoft Store Developer
# CLI. Product ID, Package Family Name and credentials bindings come exclusively
# from build/Product.props / environment secrets declared there. Version and
# package are read from a verified release manifest plus an exact downloaded
# asset; no caller version/package override is accepted.
#
# Operations:
#   submit-or-resume    query Partner Center, then no-op / resume-commit / upload
#                       per the D11 state machine.
#   delete-target-draft guarded destructive recovery for the exact target draft.

[CmdletBinding()]
param(
    [ValidateSet('submit-or-resume', 'delete-target-draft')]
    [string]$Operation = 'submit-or-resume',

    [Parameter(Mandatory)][string]$ReleaseManifestPath,
    [Parameter(Mandatory)][string]$BundlePath,
    [string]$CliPath,

    # Test-only seam. Production workflows leave this unset and invoke the
    # pinned CLI process normally.
    [scriptblock]$CliProcessInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$modulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
$submissionModulePath = Join-Path $PSScriptRoot 'modules\Echo.StoreSubmission.psm1'
Import-Module $modulePath -Force -DisableNameChecking
Import-Module $submissionModulePath -Force -DisableNameChecking
if ($CliProcessInvoker) {
    Set-EchoStoreCliProcessInvoker -Invoker $CliProcessInvoker
}

$config = Get-EchoDistributionConfiguration

if (-not $CliPath) {
    $cliPathKnown = Join-Path $env:RUNNER_TEMP 'msstore-cli\msstore.exe'
    if (Test-Path -LiteralPath $cliPathKnown -PathType Leaf) {
        $CliPath = $cliPathKnown
    }
    else {
        $found = Get-ChildItem -Path $env:RUNNER_TEMP -Recurse -Filter 'msstore.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $found) {
            throw 'msstore CLI was not found in RUNNER_TEMP. Run scripts/Install-MicrosoftStoreCli.ps1 first.'
        }
        $CliPath = $found.FullName
    }
}

if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
    throw "msstore CLI executable is missing: $CliPath"
}
$bundleFull = [System.IO.Path]::GetFullPath($BundlePath)
if (-not (Test-Path -LiteralPath $bundleFull -PathType Leaf)) {
    throw "Store bundle is missing: $bundleFull"
}

# Verify the release manifest (D6) against centralized configuration.
$manifest = Test-EchoReleaseManifestSchema -Path $ReleaseManifestPath -Configuration $config
$targetVersion = $config.Store.Versioning.StoreVersion
$productId = $config.Store.ProductId

# Require the four declared Partner Center secrets.
$requiredSecretNames = @($config.ExternalBindings.RequiredSecrets | ForEach-Object { $_.Name })
$missing = @(
    foreach ($name in $requiredSecretNames) {
        if (-not [Environment]::GetEnvironmentVariable($name)) { $name }
    }
)
if ($missing.Count -gt 0) {
    throw "Missing Partner Center credentials: $($missing -join ', ')"
}

$cliEnvironment = @{
    MSSTORE_CLIENT_ID = [Environment]::GetEnvironmentVariable('PARTNER_CENTER_CLIENT_ID')
    MSSTORE_CLIENT_SECRET = [Environment]::GetEnvironmentVariable('PARTNER_CENTER_CLIENT_SECRET')
    MSSTORE_TENANT_ID = [Environment]::GetEnvironmentVariable('PARTNER_CENTER_TENANT_ID')
    MSSTORE_SELLER_ID = [Environment]::GetEnvironmentVariable('PARTNER_CENTER_SELLER_ID')
}

# Redaction values: never surface credential values in errors or reports.
$secretValues = @(
    $cliEnvironment.Values |
        Where-Object { $_ } |
        ForEach-Object { [string]$_ }
)

# Authenticate once via `msstore configure`.
$configureResult = Invoke-EchoMsStoreCli `
    -CliPath $CliPath `
    -Arguments @('configure', '--json') `
    -Environment $cliEnvironment `
    -SecretValues $secretValues
if ($configureResult.ExitCode -ne 0) {
    throw "msstore configure failed (exit $($configureResult.ExitCode))."
}

# Target bundle identity from the verified release manifest and the exact
# downloaded asset, so a pending submission can be correlated (R7/R10).
$bundleName = Split-Path $bundleFull -Leaf
$bundleSha256 = (Get-FileHash -LiteralPath $bundleFull -Algorithm SHA256).Hash.ToLowerInvariant()
$targetPackageFamilyName = $config.Store.PackageFamilyName

if ($Operation -eq 'delete-target-draft') {
    # R12/R6: deletion requires the same strict correlation as commit, including
    # the bundle hash, before any destructive mutation. State-only checks are
    # never sufficient.
    Write-Host "Recovery: verifying target draft for $productId at $targetVersion" -ForegroundColor Yellow
    $current = Get-EchoStoreSubmissionState -CliPath $CliPath -ProductId $productId -Environment $cliEnvironment -SecretValues $secretValues
    $deleteVerdict = Test-EchoStoreStateSafeToProceed `
        -CurrentState $current.State `
        -TargetProductId $productId `
        -QueriedProductId $current.QueriedProductId `
        -TargetVersion $targetVersion `
        -LatestPublishedVersion $current.LatestPublishedVersion `
        -PendingTargetVersion $current.PendingTargetVersion `
        -PendingPackageName $current.PendingPackageName `
        -PendingPackageFamilyName $current.PendingPackageFamilyName `
        -PendingPackageSha256 $current.PendingPackageSha256 `
        -TargetBundleName $bundleName `
        -TargetBundleSha256 $bundleSha256 `
        -TargetPackageFamilyName $targetPackageFamilyName
    if (-not $deleteVerdict.Safe) {
        throw "Refusing to delete pending draft (state $($current.State)): $($deleteVerdict.Reason)"
    }
    $deleteResult = Invoke-EchoMsStoreCli `
        -CliPath $CliPath `
        -Arguments @('submission', 'delete', '--productid', $productId, '--json') `
        -Environment $cliEnvironment `
        -SecretValues $secretValues
    if ($deleteResult.ExitCode -ne 0) {
        throw "msstore submission delete failed (exit $($deleteResult.ExitCode))."
    }
    Write-Host 'Target draft deleted.' -ForegroundColor Green
    return
}

# submit-or-resume state machine (D11).
$preflight = Invoke-EchoStorePreflight `
    -CliPath $CliPath `
    -ProductId $productId `
    -TargetVersion $targetVersion `
    -TargetBundleName $bundleName `
    -TargetBundleSha256 $bundleSha256 `
    -TargetPackageFamilyName $targetPackageFamilyName `
    -Environment $cliEnvironment `
    -SecretValues $secretValues

switch ($preflight.Verdict.Action) {
    'monitor-only' {
        Write-Host "Store state '$($preflight.State)' is active; monitoring without mutation." -ForegroundColor Cyan
        exit 0
    }
    'commit-resume' {
        Write-Host "Resuming existing pending submission for $targetVersion." -ForegroundColor Cyan
        Invoke-EchoStoreCommit -CliPath $CliPath -ProductId $productId -Environment $cliEnvironment -SecretValues $secretValues | Out-Null
        Write-Host 'Existing draft committed.' -ForegroundColor Green
        return
    }
    'upload' {
        Write-Host "Creating a new draft submission for $targetVersion." -ForegroundColor Cyan
        $publish = Invoke-EchoStorePublish `
            -CliPath $CliPath `
            -ProductId $productId `
            -BundlePath $bundleFull `
            -Environment $cliEnvironment `
            -SecretValues $secretValues
        if ($publish.ExitCode -ne 0) {
            throw "msstore publish (no-commit) failed (exit $($publish.ExitCode))."
        }

        $verify = Get-EchoStoreSubmissionState -CliPath $CliPath -ProductId $productId -Environment $cliEnvironment -SecretValues $secretValues
        # R6: after a no-commit publish, commit is authorised only when the full
        # correlation verdict is exactly `commit-resume`; a State-only check is not
        # sufficient and could commit a different submission.
        $postVerdict = Test-EchoStoreStateSafeToProceed `
            -CurrentState $verify.State `
            -TargetProductId $productId `
            -QueriedProductId $verify.QueriedProductId `
            -TargetVersion $targetVersion `
            -LatestPublishedVersion $verify.LatestPublishedVersion `
            -PendingTargetVersion $verify.PendingTargetVersion `
            -PendingPackageName $verify.PendingPackageName `
            -PendingPackageFamilyName $verify.PendingPackageFamilyName `
            -PendingPackageSha256 $verify.PendingPackageSha256 `
            -TargetBundleName $bundleName `
            -TargetBundleSha256 $bundleSha256 `
            -TargetPackageFamilyName $targetPackageFamilyName
        if ($postVerdict.Action -ne 'commit-resume') {
            throw "Post-publish correlation failed closed in state $($verify.State): $($postVerdict.Reason)"
        }

        Invoke-EchoStoreCommit -CliPath $CliPath -ProductId $productId -Environment $cliEnvironment -SecretValues $secretValues | Out-Null
        Write-Host "Draft uploaded and committed for $targetVersion." -ForegroundColor Green
        return
    }
    default {
        throw "Store preflight reported an unhandled action '$($preflight.Verdict.Action)'."
    }
}
