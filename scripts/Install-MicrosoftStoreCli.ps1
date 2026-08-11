# Install-MicrosoftStoreCli.ps1
#
# Downloads and installs the pinned Microsoft Store Developer CLI (msstore)
# declared in build/Product.props (D7). The exact archive, version, .NET
# runtime requirement and SHA-256 are read exclusively from the centralized
# distribution configuration; no `latest` token is ever used.

[CmdletBinding()]
param(
    [switch]$InstallDotnetSdk
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$modulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$config = Get-EchoDistributionConfiguration
$cli = $config.Tooling.MsStore

$expectedVersion = $cli.Version
$assetName = $cli.AssetName
$expectedSha256 = $cli.Sha256
$runtimeMajor = $cli.RuntimeMajor

if (-not $env:RUNNER_TEMP) {
    $env:RUNNER_TEMP = Join-Path ([System.IO.Path]::GetTempPath()) 'echo-runner-temp'
}
New-Item -ItemType Directory -Path $env:RUNNER_TEMP -Force | Out-Null

$downloadRoot = Join-Path $env:RUNNER_TEMP 'msstore-cli'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

$archivePath = Join-Path $downloadRoot $assetName
$extractRoot = Join-Path $downloadRoot ('extract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

if ($InstallDotnetSdk) {
    Write-Host "Ensuring .NET SDK $($cli.DotNetSdkVersion) is available (runtime $runtimeMajor)..." -ForegroundColor Cyan
    $dotnetRoot = Join-Path $downloadRoot 'dotnet'
    New-Item -ItemType Directory -Path $dotnetRoot -Force | Out-Null
    dotnet --list-sdks | Out-Null
    $exists = & dotnet --list-sdks 2>$null | Select-String -SimpleMatch $cli.DotNetSdkVersion
    if (-not $exists) {
        $installer = Join-Path $downloadRoot 'dotnet-install.ps1'
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer -UseBasicParsing
        & $installer -Version $cli.DotNetSdkVersion -InstallDir $dotnetRoot -NoPath
        if ($LASTEXITCODE -ne 0) {
            throw ".NET SDK $($cli.DotNetSdkVersion) installation failed."
        }
        "$dotnetRoot" >> $env:GITHUB_PATH
    }
    else {
        Write-Host ".NET SDK $($cli.DotNetSdkVersion) is already available." -ForegroundColor DarkGray
    }
}

# The published CLI release URL is stable: the GitHub release named by the
# pinned version hosts exactly the declared asset.
$releaseUrl = "https://github.com/microsoft/msstore-cli/releases/download/v$expectedVersion/$assetName"
Write-Host "Downloading $releaseUrl" -ForegroundColor DarkGray
Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath -UseBasicParsing

$actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -cne $expectedSha256) {
    throw "msstore CLI archive digest mismatch. Expected $expectedSha256, found $actualSha256."
}

# Also validate the publisher checksum file when GitHub exposes it.
$checksumCandidate = $releaseUrl + '.sha256'
try {
    $checksumContent = (Invoke-WebRequest -Uri $checksumCandidate -UseBasicParsing -ErrorAction Stop).Content.Trim()
    $publishedHash = ($checksumContent -split '\s+')[0].ToLowerInvariant()
    if ($publishedHash -and $publishedHash -cne $expectedSha256) {
        throw "msstore CLI publisher checksum mismatch. Expected $publishedHash, found $expectedSha256."
    }
}
catch {
    Write-Host 'Publisher checksum file was not available; the pinned digest validation above remains authoritative.' -ForegroundColor DarkYellow
}

Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

$cliCandidate = Get-ChildItem -LiteralPath $extractRoot -Recurse -Filter 'msstore*.exe' -File |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $cliCandidate) {
    throw 'No msstore executable was found in the extracted CLI archive.'
}

$cliRoot = Join-Path $downloadRoot ('cli-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cliRoot -Force | Out-Null
Copy-Item -LiteralPath $cliCandidate.FullName -Destination (Join-Path $cliRoot 'msstore.exe') -Force

# Smoke test the exact pinned version.
$versionOutput = (& (Join-Path $cliRoot 'msstore.exe') --version 2>&1) -join ' '
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch [regex]::Escape($expectedVersion)) {
    throw "msstore --version did not report $expectedVersion: $versionOutput"
}

Write-Host "msstore CLI v$expectedVersion installed at $cliRoot" -ForegroundColor Green
[pscustomobject]@{
    Version = $expectedVersion
    ArchiveSha256 = $actualSha256
    CliPath = (Join-Path $cliRoot 'msstore.exe')
    CliRoot = $cliRoot
    DotNetSdk = $cli.DotNetSdkVersion
}