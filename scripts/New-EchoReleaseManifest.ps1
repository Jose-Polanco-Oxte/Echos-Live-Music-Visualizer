# New-EchoReleaseManifest.ps1
#
# Generates the versioned release provenance manifest (D6) entirely from the
# centralized distribution configuration and observed artifact hashes. No
# credentials or mutable caller inputs are accepted: version, identity, Store
# coordinates and CLI pin come from build/Product.props.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$SourceCommitSha,
    [Parameter(Mandatory)][string[]]$AssetPaths,
    [string]$ReleaseId,
    [string]$WorkflowRunId,
    [string]$WorkflowRunUrl,
    [string]$RunnerLabel,
    [string]$ImageOs,
    [string]$ImageVersion,
    [string]$DotnetVersion,
    [string]$RustVersion,
    [string]$MsBuildVersion,
    [string]$WindowsSdkVersion,
    [string]$MakeAppxVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$propsPath = Join-Path $repoRoot 'build\Product.props'
$modulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$config = Get-EchoDistributionConfiguration
$productVersion = $config.Product.Version

if ($Tag -notmatch '^v(?<version>\d+\.\d+\.\d+\.\d+)$') {
    throw "Release tag must use vA.B.C.D: $Tag"
}
if ($Matches.version -ne $productVersion) {
    throw "Release tag version '$($Matches.version)' does not match canonical product version '$productVersion'."
}
if ($SourceCommitSha -notmatch '^[0-9a-f]{40}$') {
    throw "Source commit SHA must be a 40-character lowercase hex SHA-256: $SourceCommitSha"
}

$storeVersion = $config.Store.Versioning.StoreVersion
$propsSha256 = Get-EchoProductPropsSha256 -Path $propsPath

$assetRecords = @(
    foreach ($asset in $AssetPaths) {
        $full = [System.IO.Path]::GetFullPath($asset)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Release asset is missing: $full"
        }
        $fileName = Split-Path $full -Leaf
        $byteSize = (Get-Item -LiteralPath $full).Length
        $sha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        $artifactType = $config.Store.ArtifactType
        $mediaRole = switch -Regex ($fileName) {
            '\.zip$' { if ($fileName -match 'arm64') { 'github-zip-arm64' } else { 'github-zip-x64' } }
            ("\.$([regex]::Escape($artifactType))$") { 'store-bundle' }
            'release-manifest\.json$' { 'release-manifest' }
            'SHA256SUMS\.txt$' { 'checksums' }
            default { 'other' }
        }
        [pscustomobject]@{
            filename = $fileName
            mediaRole = $mediaRole
            sizeBytes = $byteSize
            sha256 = $sha
        }
    }
)
$assetRecords = @($assetRecords | Sort-Object filename)

$innerBundle = @(
    foreach ($asset in $assetRecords) {
        if ($asset.mediaRole -eq 'store-bundle') {
            'x64'
            'arm64'
        }
    }
)

$manifest = [ordered]@{
    schemaVersion = 1
    repository = @{ name = (Split-Path (Split-Path $repoRoot -Parent) -Leaf) }
    workflow = @{
        runId = $WorkflowRunId
        runUrl = $WorkflowRunUrl
    }
    release = @{
        tag = $Tag
        releaseId = $ReleaseId
        sourceCommitSha = $SourceCommitSha
    }
    product = @{
        version = $productVersion
        coreVersion = $config.Product.CoreVersion
        storeVersion = $storeVersion
        name = $config.Product.Name
        publisherDisplayName = $config.Product.PublisherDisplayName
        packageIdentityName = $config.Product.PackageIdentityName
        packagePublisher = $config.Product.PackagePublisher
        applicationId = $config.Product.ApplicationId
    }
    configuration = @{
        schemaVersion = $config.SchemaVersion
        productPropsSha256 = $propsSha256
    }
    store = @{
        productId = $config.Store.ProductId
        packageFamilyName = $config.Store.PackageFamilyName
        artifactType = $config.Store.ArtifactType
        architectures = @($config.Store.Architectures | ForEach-Object { $_.ProcessorArchitecture } | Sort-Object)
        targetDeviceFamily = $config.Store.TargetDeviceFamily
        minVersion = $config.Store.MinVersion
        maxVersionTested = $config.Store.MaxVersionTested
        capabilities = @($config.Store.Capabilities | ForEach-Object { $_.Name } | Sort-Object)
        publishMode = $config.Store.PublishMode
        privacyPolicyUrl = $config.Store.PrivacyPolicyUrl
    }
    runner = @{
        label = $RunnerLabel
        imageOs = $ImageOs
        imageVersion = $ImageVersion
    }
    toolchain = @{
        dotnetSdk = $DotnetVersion
        rust = $RustVersion
        msbuild = $MsBuildVersion
        windowsSdk = $WindowsSdkVersion
        makeAppx = $MakeAppxVersion
        msstore = @{
            version = $config.Tooling.MsStore.Version
            assetName = $config.Tooling.MsStore.AssetName
            dotnetSdkVersion = $config.Tooling.MsStore.DotNetSdkVersion
            runtimeMajor = $config.Tooling.MsStore.RuntimeMajor
            sha256 = $config.Tooling.MsStore.Sha256
        }
    }
    assets = $assetRecords
    storeBundleInnerArchitectures = $innerBundle
}

$outPath = Join-Path $repoRoot ("artifacts\EchoVisualizer-$productVersion-release-manifest.json")
New-Item -ItemType Directory -Path (Split-Path $outPath) -Force | Out-Null
$json = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))

# Validation: the manifest must round-trip through the schema validator.
$null = Test-EchoReleaseManifestSchema -Path $outPath -Configuration $config

Write-Host "Release manifest written: $outPath" -ForegroundColor Green
[pscustomobject]@{
    Path = $outPath
    ProductVersion = $productVersion
    StoreVersion = $storeVersion
    Sha256 = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash.ToLowerInvariant()
}