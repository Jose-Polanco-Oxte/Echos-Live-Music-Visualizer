# Test-StoreReleaseArtifact.ps1
#
# Reusable, no-network validation of a final Store `.msixbundle` and optional
# release manifest, using the same centralized configuration parser as the
# rest of the pipeline.
#
# Usage (from repository root):
#   .\scripts\Test-StoreReleaseArtifact.ps1 `
#       -BundlePath artifacts\store\EchoVisualizer-A.B.C.D.msixbundle `
#       [-ExpectedProductVersion A.B.C.D] `
#       [-ReleaseManifestPath path\to\release-manifest.json]
#
# Asserts exactly one x64 and one ARM64 inner package with matching identity,
# publisher, version, capabilities and architecture records from schema 1.
# Requires the Windows SDK MakeAppx tool.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundlePath,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$ExpectedProductVersion,
    [string]$ReleaseManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$modulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$config = Get-EchoDistributionConfiguration

$bundleFull = [System.IO.Path]::GetFullPath($BundlePath)
if (-not (Test-Path -LiteralPath $bundleFull -PathType Leaf)) {
    throw "Store bundle is missing: $bundleFull"
}
$expectedExtension = '.' + $config.Store.ArtifactType
if (-not $bundleFull.EndsWith($expectedExtension, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Store artifact must be a $expectedExtension bundle: $bundleFull"
}

# Locate MakeAppx.
function Find-MakeAppx {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path -LiteralPath $kitsRoot)) {
        throw "Windows SDK tools directory was not found: $kitsRoot"
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath $kitsRoot -Directory | Sort-Object Name -Descending)) {
        $version = $null
        if ([System.Version]::TryParse($directory.Name, [ref]$version)) {
            $candidate = Join-Path $directory.FullName 'x64\makeappx.exe'
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }
    throw 'Windows SDK makeappx.exe was not found.'
}

function Invoke-NativeCheck {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

$makeAppx = Find-MakeAppx

# Expected values from centralized configuration.
$expectedIdentityName = $config.Product.PackageIdentityName
$expectedPublisher = $config.Product.PackagePublisher
$expectedArches = @($config.Store.Architectures | ForEach-Object { $_.ProcessorArchitecture })
$expectedCapabilities = @($config.Store.Capabilities | ForEach-Object { $_.Name })

$storeVersion = if ($ExpectedProductVersion) {
    Get-EchoStoreVersion -ProductVersion $ExpectedProductVersion -PackingBase $config.Store.Versioning.PackingBase
}
else {
    $config.Store.Versioning.StoreVersion
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("echo-artifact-{0}" -f [guid]::NewGuid().ToString('N'))
$bundleDir = Join-Path $temporaryRoot 'bundle'
New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
try {
    Invoke-NativeCheck $makeAppx @('unbundle', '/p', $bundleFull, '/d', $bundleDir, '/o') | Out-Null

    $innerPackages = @(Get-ChildItem -LiteralPath $bundleDir -Filter '*.msix' -File)
    if ($innerPackages.Count -ne 2) {
        throw "Store bundle must contain exactly two inner packages; found $($innerPackages.Count): $($innerPackages.Name -join ', ')"
    }

    $seenArches = @()
    foreach ($pkg in $innerPackages) {
        $pkgDir = Join-Path $temporaryRoot ("inner-{0}" -f $pkg.BaseName)
        New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
        Invoke-NativeCheck $makeAppx @('unpack', '/p', $pkg.FullName, '/d', $pkgDir, '/o') | Out-Null

        $manifestPath = Join-Path $pkgDir 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Inner package $($pkg.Name) is missing AppxManifest.xml."
        }
        [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
        $ns = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
        $ns.AddNamespace('f', $manifest.DocumentElement.NamespaceURI)
        $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $ns)
        $properties = $manifest.SelectSingleNode('/f:Package/f:Properties', $ns)

        if ($identity.Name -cne $expectedIdentityName) {
            throw "Inner package $($pkg.Name) identity mismatch. Expected '$expectedIdentityName', found '$($identity.Name)'."
        }
        if ($identity.Publisher -cne $expectedPublisher) {
            throw "Inner package $($pkg.Name) publisher mismatch."
        }
        if ($identity.Version -cne $storeVersion) {
            throw "Inner package $($pkg.Name) version mismatch. Expected '$storeVersion', found '$($identity.Version)'."
        }
        $arch = [string]$identity.ProcessorArchitecture
        if ($arch -notin $expectedArches) {
            throw "Inner package $($pkg.Name) has unsupported ProcessorArchitecture '$arch'."
        }
        if ($arch -in $seenArches) {
            throw "Store bundle contains a duplicate architecture package: $arch"
        }
        $seenArches += $arch

        $actualCapabilities = @(
            $manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Capabilities"]/*') |
                ForEach-Object { $_.Name }
        )
        foreach ($cap in $expectedCapabilities) {
            if ($actualCapabilities -notcontains $cap) {
                throw "Inner package $($pkg.Name) is missing centralized capability '$cap'."
            }
        }
    }

    $sortedSeen = @($seenArches | Sort-Object)
    $sortedExpected = @($expectedArches | Sort-Object)
    if (($sortedSeen -join ',') -ne ($sortedExpected -join ',')) {
        throw "Store bundle architecture set mismatch. Expected '$($sortedExpected -join ', ')', found '$($sortedSeen -join ', ')'."
    }

    # Optional release-manifest correlation.
    if ($ReleaseManifestPath) {
        $manifestReview = Get-Content -LiteralPath $ReleaseManifestPath -Raw | ConvertFrom-Json
        $manifestProductVersion = $manifestReview.product.version
        if ($ExpectedProductVersion -and $manifestProductVersion -ne $ExpectedProductVersion) {
            throw "Release manifest product version '$manifestProductVersion' does not match '$ExpectedProductVersion'."
        }
        $bundleFileName = Split-Path $bundleFull -Leaf
        $storeAssets = @($manifestReview.assets | Where-Object { $_.mediaRole -eq 'store-bundle' })
        if ($storeAssets.Count -eq 0) {
            throw 'Release manifest does not list a store-bundle asset.'
        }
        $storeAssetNames = @($storeAssets | ForEach-Object { $_.filename })
        if ($storeAssetNames -notcontains $bundleFileName) {
            throw "Release manifest store-bundle asset does not match downloaded bundle '$bundleFileName'."
        }
    }

    $assetHash = (Get-FileHash -LiteralPath $bundleFull -Algorithm SHA256).Hash.ToLowerInvariant()
    $assetSize = (Get-Item -LiteralPath $bundleFull).Length

    Write-Host "Store bundle validated: $bundleFull ($assetSize bytes, SHA256 $assetHash)" -ForegroundColor Green
    Write-Host "Inner packages: $($innerPackages.Name -join ', ')" -ForegroundColor DarkGray

    [pscustomobject]@{
        BundlePath = $bundleFull
        StoreVersion = $storeVersion
        Architectures = ($seenArches -join ',')
        Sha256 = $assetHash
        SizeBytes = $assetSize
    }
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}