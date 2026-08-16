# Get-MicrosoftStoreReleaseStatus.ps1
#
# Read-only Microsoft Store submission status reporter. Only status/get commands
# are permitted; publish, submission update, submission delete and commit are
# never invoked. Product ID and credentials come from centralized configuration
# and their declared environment bindings.

[CmdletBinding()]
param(
    [string]$CliPath,
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$metadataModulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
$submissionModulePath = Join-Path $PSScriptRoot 'modules\Echo.StoreSubmission.psm1'
Import-Module $metadataModulePath -Force -DisableNameChecking
Import-Module $submissionModulePath -Force -DisableNameChecking

$config = Get-EchoDistributionConfiguration
$productId = $config.Store.ProductId

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
$secretValues = @(
    $cliEnvironment.Values |
        Where-Object { $_ } |
        ForEach-Object { [string]$_ }
)

$configureResult = Invoke-EchoMsStoreCli `
    -CliPath $CliPath `
    -Arguments @(
        'reconfigure',
        '--tenantId', [Environment]::GetEnvironmentVariable('PARTNER_CENTER_TENANT_ID'),
        '--sellerId', [Environment]::GetEnvironmentVariable('PARTNER_CENTER_SELLER_ID'),
        '--clientId', [Environment]::GetEnvironmentVariable('PARTNER_CENTER_CLIENT_ID'),
        '--clientSecret', [Environment]::GetEnvironmentVariable('PARTNER_CENTER_CLIENT_SECRET')
    ) `
    -Environment $cliEnvironment `
    -SecretValues $secretValues
if ($configureResult.ExitCode -ne 0) {
    throw "msstore reconfigure failed (exit $($configureResult.ExitCode))."
}

# Read-only status only. Never a mutating verb.
$status = Get-EchoStoreSubmissionState -CliPath $CliPath -ProductId $productId -Environment $cliEnvironment -SecretValues $secretValues

$report = [ordered]@{
    productId = $productId
    packageFamilyName = $config.Store.PackageFamilyName
    targetStoreVersion = $config.Store.Versioning.StoreVersion
    state = $status.State
    latestPublishedVersion = $status.LatestPublishedVersion
    pendingTargetVersion = $status.PendingTargetVersion
    observedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$report.outcome = if ($status.State -eq 'Published') { 'PUBLISHED' } elseif ($status.State -eq 'NoSubmission') { 'NO_SUBMISSION' } elseif ($status.State -in @('PreProcessing', 'Certification', 'CommitStarted', 'Release', 'Publishing')) { 'IN_PROGRESS' } elseif ($status.State -eq 'PendingCommit') { 'PENDING_COMMIT' } else { 'TERMINAL_FAILURE' }
$report.conclusion = if ($report.outcome -in @('PUBLISHED', 'NO_SUBMISSION')) { 'success' } elseif ($report.outcome -eq 'IN_PROGRESS') { 'in_progress' } else { 'failure' }

$json = $report | ConvertTo-Json -Depth 4
if ($OutFile) {
    [System.IO.File]::WriteAllText(
        (Join-Path $repoRoot $OutFile),
        $json,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "Status report written: $OutFile" -ForegroundColor Green
}
else {
    $json
}