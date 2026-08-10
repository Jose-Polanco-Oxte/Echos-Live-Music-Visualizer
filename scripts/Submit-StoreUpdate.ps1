[CmdletBinding()]
param(
    [string]$AppId,

    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$StoreVersion,

    [string[]]$BundlePaths,

    [string]$Release,

    [ValidateSet('Default', 'Manual', 'Immediate', 'SpecificDate')]
    [string]$TargetPublishMode = 'Default',

    [string]$TargetPublishDate,

    [ValidateRange(0, 100)]
    [int]$RolloutPercentage = -1,

    [string]$NotesForCertification,

    [ValidateSet('ReplacePackages', 'AddPackages')]
    [string]$PackageUpdateAction = 'ReplacePackages',

    [string]$ConfigPath,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:RepoRoot 'docs/store/StoreBrokerConfiguration.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "StoreBroker configuration was not found at $ConfigPath. Run scripts/Initialize-StoreBroker.ps1 after the first Store submission is published."
}
[string]$script:StoreBrokerModule = (Get-Module -ListAvailable -Name StoreBroker | Sort-Object Version -Descending | Select-Object -First 1).Name
if (-not $script:StoreBrokerModule) {
    throw 'StoreBroker PowerShell module is not installed. Run: Install-Module -Name StoreBroker -Force -Scope CurrentUser'
}
Import-Module -Name StoreBroker -Force

function Resolve-StoreBundle {
    param([Parameter(Mandatory)][string]$RuntimeIdentifier)

    $searchRoot = Join-Path $script:RepoRoot "artifacts/store-test/$RuntimeIdentifier"
    if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
        throw "Store bundle directory was not found: $searchRoot"
    }
    return Get-ChildItem -LiteralPath $searchRoot -Filter '*.msix' -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $BundlePaths -or $BundlePaths.Count -eq 0) {
    $BundlePaths = @(
        (Resolve-StoreBundle 'win-x64')
        (Resolve-StoreBundle 'win-arm64')
    )
}
$BundlePaths = @($BundlePaths | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
foreach ($bundle in $BundlePaths) {
    if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
        throw "Store bundle was not found: $bundle"
    }
}
Write-Host 'Store bundles for submission:' -ForegroundColor Cyan
$BundlePaths | ForEach-Object { Write-Host "  $_" }

# StoreBrokerConfiguration.json is checked in without credentials. All
# authentication material comes from the environment (GitHub Actions Secrets)
# and is injected into a temporary copy of the configuration.
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $AppId) { $AppId = $config.applicationId }
if (-not $AppId) {
    throw 'Application (Store) ID was not provided and is not set in the StoreBroker configuration.'
}
if (-not $StoreVersion) {
    $StoreVersion = $config.applicationVersion
    if (-not $StoreVersion) {
        throw "Store package version (A.B.C.0) was not provided and is not recorded in the StoreBroker configuration."
    }
}

$envClientId = $env:STORE_CLIENT_ID
$envClientSecret = $env:STORE_CLIENT_SECRET
$envTenantId = $env:STORE_TENANT_ID

if (-not $DryRun) {
    if (-not $envClientId -or -not $envClientSecret -or -not $envTenantId) {
        throw 'STORE_CLIENT_ID, STORE_CLIENT_SECRET and STORE_TENANT_ID environment variables are required. See docs/public/publishing/microsoft-store.md.'
    }
}

$clientId = $config.clientId
if (-not $clientId) { $clientId = $envClientId }
$tenantId = $config.tenantId
if (-not $tenantId) { $tenantId = $envTenantId }
$serviceEndpoint = $config.serviceEndpoint

if (-not $Release) { $Release = $config.release }
if (-not $Release) { $Release = $StoreVersion }
if (-not $serviceEndpoint) { $serviceEndpoint = 200 }

$pdpRootPath = $config.pdpRootPath
if (-not $pdpRootPath) { $pdpRootPath = Join-Path $script:RepoRoot 'docs/store/pdp' }
$imagesRootPath = $config.imagesRootPath
$pdpInclude = $config.pdpInclude
if (-not $pdpInclude) { $pdpInclude = 'PDP.xml' }

$payloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "echo-store-submission-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
$payloadOutName = "submission-$StoreVersion"

Write-Host "`nGenerating submission payload ($StoreVersion)..." -ForegroundColor Cyan
try {
    $newPackageParams = @{
        ConfigPath = $ConfigPath
        PdpRootPath = $pdpRootPath
        PdpInclude = $pdpInclude
        AppxPath = $BundlePaths
        OutPath = $payloadDir
        OutName = $payloadOutName
    }
    if ($imagesRootPath) {
        $newPackageParams.ImagesRootPath = $imagesRootPath
    }
    if (-not [string]::IsNullOrWhiteSpace($config.release)) {
        $newPackageParams.Release = $config.release
    }
    elseif ($Release) {
        $newPackageParams.Release = $Release
    }

    New-SubmissionPackage @newPackageParams -ErrorAction Stop

    $submissionJson = Join-Path $payloadDir "$payloadOutName.json"
    $submissionZip = Join-Path $payloadDir "$payloadOutName.zip"
    if (-not (Test-Path -LiteralPath $submissionJson -PathType Leaf) -or
        -not (Test-Path -LiteralPath $submissionZip -PathType Leaf)) {
        throw 'StoreBroker did not produce the submission.json/submission.zip payload.'
    }
}
catch {
    Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

$updateParams = @{
    AppId = $AppId
    SubmissionDataPath = $submissionJson
    PackagePath = $submissionZip
    AutoCommit = $true
    Force = $true
}
switch ($PackageUpdateAction) {
    'ReplacePackages' { $updateParams.ReplacePackages = $true }
    'AddPackages' { $updateParams.AddPackages = $true }
}
if ($TargetPublishMode -ne 'Default') {
    $updateParams.TargetPublishMode = $TargetPublishMode
}
if ($TargetPublishMode -eq 'SpecificDate') {
    if (-not $TargetPublishDate) {
        throw 'TargetPublishDate is required when TargetPublishMode is SpecificDate.'
    }
    $updateParams.TargetPublishDate = $TargetPublishDate
}
if ($RolloutPercentage -ge 0) {
    $updateParams.PackageRolloutPercentage = $RolloutPercentage
}
if (-not [string]::IsNullOrWhiteSpace($NotesForCertification)) {
    $updateParams.UpdateNotesForCertification = $true
}

if ($DryRun) {
    Write-Host '`nDry run: submission would use the following plan (no API call):' -ForegroundColor Yellow
    Write-Host "  AppId:                  $AppId"
    Write-Host "  ServiceEndpoint:        $serviceEndpoint"
    Write-Host "  Store package version:  $StoreVersion"
    Write-Host "  Package update action:  $PackageUpdateAction"
    Write-Host "  Target publish mode:    $TargetPublishMode"
    if ($TargetPublishMode -eq 'SpecificDate') { Write-Host "  Target publish date:    $TargetPublishDate" }
    if ($RolloutPercentage -ge 0) { Write-Host "  Rollout percentage:     $RolloutPercentage" }
    if (-not [string]::IsNullOrWhiteSpace($NotesForCertification)) { Write-Host '  Notes for certification (from config template)' }
    Write-Host "  Payload:                $submissionJson"
    Write-Host "  Package zip:            $submissionZip"
    Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

Write-Host "`nAuthenticating StoreBroker (tenant $tenantId)..." -ForegroundColor Cyan
$secureSecret = ConvertTo-SecureString -String $envClientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($envClientId, $secureSecret)
Set-StoreBrokerAuthentication -TenantId $envTenantId -Credential $credential

Write-Host "`nSubmitting Store update (publish mode $TargetPublishMode)..." -ForegroundColor Cyan
try {
    $result = Update-ApplicationSubmission @updateParams -Verbose -ErrorAction Stop
    Write-Host "`nSubmission committed." -ForegroundColor Green
    Write-Host "Submission ID: $($result.Id)"
    Write-Host "Submission status: $($result.Status)"
}
finally {
    Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue
}