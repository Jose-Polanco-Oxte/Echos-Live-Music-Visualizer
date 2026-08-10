[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppId,

    [string]$Release,

    [switch]$InstallModule
)

# One-time bootstrap for the Microsoft Store continuous delivery pipeline.
# Generates and checks in the StoreBroker configuration and PDP snapshot that
# the submission workflow (store-publish.yml) consumes. Run this once AFTER the
# first Store submission has been accepted and published in Partner Center.
#
#   STORE_TENANT_ID must be set (or provided interactively); ClientId and
#   ClientSecret may be supplied via STORE_CLIENT_ID / STORE_CLIENT_SECRET or
#   prompted interactively.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:StoreDir = Join-Path $script:RepoRoot 'docs/store'
$script:PdpRoot = Join-Path $script:StoreDir 'pdp'
$script:ImagesRoot = Join-Path $script:StoreDir 'images'
$script:ConfigPath = Join-Path $script:StoreDir 'StoreBrokerConfiguration.json'

if (-not (Get-Module -ListAvailable -Name StoreBroker)) {
    if (-not $InstallModule) {
        throw 'StoreBroker is not installed. Re-run with -InstallModule or run: Install-Module -Name StoreBroker -Force -Scope CurrentUser'
    }
    Install-Module -Name StoreBroker -Force -Scope CurrentUser
}
Import-Module -Name StoreBroker -Force

$moduleBase = (Get-Module -Name StoreBroker).ModuleBase
$convertScript = Join-Path $moduleBase 'Extensions\ConvertFrom-ExistingSubmission.ps1'
if (-not (Test-Path -LiteralPath $convertScript -PathType Leaf)) {
    throw "StoreBroker Extensions helper was not found: $convertScript"
}

Write-Host 'Authenticating StoreBroker against your Partner Center account...' -ForegroundColor Cyan
if ($env:STORE_CLIENT_ID -and $env:STORE_CLIENT_SECRET -and $env:STORE_TENANT_ID) {
    $secureSecret = ConvertTo-SecureString -String $env:STORE_CLIENT_SECRET -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($env:STORE_CLIENT_ID, $secureSecret)
    Set-StoreBrokerAuthentication -TenantId $env:STORE_TENANT_ID -Credential $credential
}
else {
    Set-StoreBrokerAuthentication
}

New-Item -ItemType Directory -Path $script:PdpRoot -Force | Out-Null
New-Item -ItemType Directory -Path $script:ImagesRoot -Force | Out-Null

Write-Host "Generating StoreBroker configuration at $script:ConfigPath..." -ForegroundColor Cyan
New-StoreBrokerConfigFile -Path $script:ConfigPath -AppId $AppId

if (-not $Release) {
    $release = Read-Host 'Release name for this snapshot (unused Release snaps the current PDP)'
}
else {
    $release = $Release
}

Write-Host "Generating PDP snapshot under $script:PdpRoot..." -ForegroundColor Cyan
& $convertScript -AppId $AppId -Release $release -PdpFileName 'PDP.xml' -OutPath $script:PdpRoot

Write-Host "`nBootstrap completed." -ForegroundColor Green
Write-Host @"

Review docs/store/StoreBrokerConfiguration.json and fill in:
  - pdpRootPath:    $script:PdpRoot (normally already correct)
  - imagesRootPath: $script:ImagesRoot (drop your Store screenshots here)
  - release:        used for PDP/Images release sub-folders
Leave clientId/tenantId/clientSecret empty; credentials are injected at
submission time from the STORE_CLIENT_ID / STORE_CLIENT_SECRET /
STORE_TENANT_ID environment variables (GitHub Actions Secrets).

Serve the screenshots layout StoreBroker expects (release sub-folder + locale):
  $script:ImagesRoot/<release>/<lang-code>/*.png

Commit docs/store/ and then dispatch the Microsoft Store Continuous Delivery
workflow from GitHub Actions.
"@