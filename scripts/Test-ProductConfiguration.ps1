[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$ExpectedVersion,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$productPropsPath = Join-Path $repoRoot 'build/Product.props'
$manifestPath = Join-Path $repoRoot 'src/ui/Package.appxmanifest'
$win32ManifestPath = Join-Path $repoRoot 'src/ui/app.manifest'
$cargoPath = Join-Path $repoRoot 'src/core/Cargo.toml'
$readmePath = Join-Path $repoRoot 'README.md'
$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'

# Sole parser: Echo.ReleaseMetadata.psm1. Scripts never parse Product.props
# independently nor read a second configuration store (D19/R16).
$modulePath = Join-Path $PSScriptRoot 'modules\Echo.ReleaseMetadata.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Shared distribution configuration parser is missing: $modulePath"
}
Import-Module $modulePath -Force -DisableNameChecking

foreach ($requiredPath in @($productPropsPath, $manifestPath, $win32ManifestPath, $cargoPath, $readmePath, $changelogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required product configuration file is missing: $requiredPath"
    }
}

$metadata = Get-EchoDistributionConfiguration -Path $productPropsPath

if ($ExpectedVersion -and $ExpectedVersion -ne $metadata.Product.Version) {
    throw "Requested official version $ExpectedVersion does not match canonical version $($metadata.Product.Version)."
}

[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$identity = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
$properties = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Properties']")
$dependencies = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Dependencies']/*[local-name()='TargetDeviceFamily']")
$application = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']")
$visualElements = $application.SelectSingleNode("*[local-name()='VisualElements']")
if (-not $identity -or -not $properties -or -not $dependencies -or -not $application -or -not $visualElements) {
    throw 'Package.appxmanifest is missing required identity or visual metadata.'
}

$manifestChecks = [ordered]@{
    'Identity.Name' = @($identity.Name, $metadata.Product.PackageIdentityName)
    'Identity.Publisher' = @($identity.Publisher, $metadata.Product.PackagePublisher)
    'Identity.Version' = @($identity.Version, $metadata.Product.Version)
    'Properties.DisplayName' = @($properties.DisplayName, $metadata.Product.Name)
    'Properties.PublisherDisplayName' = @($properties.PublisherDisplayName, $metadata.Product.PublisherDisplayName)
    'Dependencies.TargetDeviceFamily.Name' = @($dependencies.Name, $metadata.Store.TargetDeviceFamily)
    'Dependencies.TargetDeviceFamily.MinVersion' = @($dependencies.MinVersion, $metadata.Store.MinVersion)
    'Dependencies.TargetDeviceFamily.MaxVersionTested' = @($dependencies.MaxVersionTested, $metadata.Store.MaxVersionTested)
    'Application.Id' = @($application.Id, $metadata.Product.ApplicationId)
    'VisualElements.DisplayName' = @($visualElements.DisplayName, $metadata.Product.Name)
    'VisualElements.BackgroundColor' = @($visualElements.BackgroundColor, $metadata.Product.BrandBackgroundColor)
}
foreach ($entry in $manifestChecks.GetEnumerator()) {
    $actual = [string]$entry.Value[0]
    $expected = [string]$entry.Value[1]
    if ($actual -cne $expected) {
        throw "Package.appxmanifest $($entry.Key) mismatch. Expected '$expected', found '$actual'."
    }
}

# Capabilities must match the centralized manifest declarations.
$manifestCapabilities = @(
    $manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Capabilities"]/*') |
        ForEach-Object { $_.Name }
)
foreach ($configuredCapability in $metadata.Store.Capabilities) {
    if ($manifestCapabilities -notcontains $configuredCapability.Name) {
        throw "Package.appxmanifest is missing capability '$($configuredCapability.Name)'."
    }
}
$expectedCapabilityNames = @($metadata.Store.Capabilities | ForEach-Object { $_.Name } | Sort-Object -Unique)
$actualCapabilityNames = @($manifestCapabilities | Sort-Object -Unique)
if (($expectedCapabilityNames -join ',') -ne ($actualCapabilityNames -join ',')) {
    throw "Package.appxmanifest capabilities do not match centralized configuration ('$($expectedCapabilityNames -join ', ')' vs '$($actualCapabilityNames -join ', ')')."
}

# Branding assets must match the manifest asset references.
$recipeFiles = @($metadata.Branding.Assets | ForEach-Object { [string]$_.File })
$manifestAssetReferences = @(
    [string]$properties.Logo,
    [string]$visualElements.Square150x150Logo,
    [string]$visualElements.Square44x44Logo,
    [string]$visualElements.SelectSingleNode('*[local-name()="DefaultTile"]').Wide310x150Logo,
    [string]$visualElements.SelectSingleNode('*[local-name()="SplashScreen"]').Image
)
foreach ($assetReference in $manifestAssetReferences) {
    if ($assetReference -notmatch '^Assets[\\/](?<file>[^\\/]+)$' -or
        $recipeFiles -cnotcontains $Matches.file) {
        throw "Package manifest asset is not defined by the centralized branding recipes: $assetReference"
    }
}
if ($metadata.Product.ApplicationIcon -notmatch '^Assets[\\/](?<file>[^\\/]+)$' -or
    $Matches.file -cne [string]$metadata.Branding.Icon.File) {
    throw "Canonical application icon does not match the centralized branding recipe: $($metadata.Product.ApplicationIcon)"
}

[xml]$win32Manifest = Get-Content -LiteralPath $win32ManifestPath -Raw
$assemblyIdentity = $win32Manifest.SelectSingleNode("/*[local-name()='assembly']/*[local-name()='assemblyIdentity']")
$executionLevel = $win32Manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
$supportedOs = $win32Manifest.SelectSingleNode("//*[local-name()='supportedOS']")
$dpiAware = $win32Manifest.SelectSingleNode("//*[local-name()='dpiAware']")
$dpiAwareness = $win32Manifest.SelectSingleNode("//*[local-name()='dpiAwareness']")
if (-not $assemblyIdentity -or
    $assemblyIdentity.Name -cne $metadata.Product.Win32AssemblyIdentityName -or
    $assemblyIdentity.Version -cne $metadata.Product.Win32AssemblyManifestVersion) {
    throw 'Win32 manifest assembly identity does not match canonical product metadata.'
}
if (-not $executionLevel -or $executionLevel.Level -cne 'asInvoker' -or $executionLevel.UiAccess -cne 'false') {
    throw 'Win32 manifest must run asInvoker with uiAccess disabled.'
}
if (-not $supportedOs -or $supportedOs.Id -cne '{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}') {
    throw 'Win32 manifest must retain Windows 10/11 compatibility awareness.'
}
if (-not $dpiAware -or $dpiAware.InnerText.Trim() -cne 'true/PM' -or
    $dpiAware.NamespaceURI -cne 'http://schemas.microsoft.com/SMI/2005/WindowsSettings' -or
    -not $dpiAwareness -or $dpiAwareness.InnerText.Trim() -cne 'PerMonitorV2, PerMonitor' -or
    $dpiAwareness.NamespaceURI -cne 'http://schemas.microsoft.com/SMI/2016/WindowsSettings') {
    throw 'Win32 manifest Per-Monitor V2 DPI declarations are missing or malformed.'
}

$cargoText = Get-Content -LiteralPath $cargoPath -Raw
$cargoMatch = [regex]::Match($cargoText, '(?m)^version\s*=\s*"(?<version>\d+\.\d+\.\d+)"\s*$')
if (-not $cargoMatch.Success -or $cargoMatch.Groups['version'].Value -ne $metadata.Product.CoreVersion) {
    $actualCargoVersion = if ($cargoMatch.Success) { $cargoMatch.Groups['version'].Value } else { '<missing>' }
    throw "Cargo package version mismatch. Expected $($metadata.Product.CoreVersion), found $actualCargoVersion."
}

$readmeText = Get-Content -LiteralPath $readmePath -Raw
$readmeMatch = [regex]::Match($readmeText, 'version-v(?<version>\d+\.\d+\.\d+\.\d+)')
if (-not $readmeMatch.Success -or $readmeMatch.Groups['version'].Value -ne $metadata.Product.Version) {
    $actualReadmeVersion = if ($readmeMatch.Success) { $readmeMatch.Groups['version'].Value } else { '<missing>' }
    throw "README version badge mismatch. Expected $($metadata.Product.Version), found $actualReadmeVersion."
}

$changelogText = Get-Content -LiteralPath $changelogPath -Raw
$escapedVersion = [regex]::Escape($metadata.Product.Version)
if ($changelogText -notmatch "(?m)^## \[$escapedVersion\](?:\s|$)") {
    throw "CHANGELOG does not contain an entry for canonical version $($metadata.Product.Version)."
}

$iconRelative = if ($metadata.Product.ApplicationIcon -match '^Assets[\\/](?:[^\\/]+[\\/])?(?<file>[^\\/]+)$') {
    $Matches.file
}
else {
    $metadata.Product.ApplicationIcon
}
$iconDir = Split-Path $manifestPath
foreach ($pathSegment in ($metadata.Product.ApplicationIcon -split '[\\/]')) {
    $iconDir = Join-Path $iconDir $pathSegment
}
if (-not (Test-Path -LiteralPath $iconDir -PathType Leaf)) {
    throw "Canonical application icon is missing: $iconDir"
}

if ($AsJson) {
    $projection = [ordered]@{
        schemaVersion = $metadata.SchemaVersion
        product = [ordered]@{
            version = $metadata.Product.Version
            coreVersion = $metadata.Product.CoreVersion
            name = $metadata.Product.Name
            publisherDisplayName = $metadata.Product.PublisherDisplayName
            packageIdentityName = $metadata.Product.PackageIdentityName
            packagePublisher = $metadata.Product.PackagePublisher
            applicationId = $metadata.Product.ApplicationId
            applicationIcon = $metadata.Product.ApplicationIcon
            brandBackgroundColor = $metadata.Product.BrandBackgroundColor
            win32AssemblyIdentityName = $metadata.Product.Win32AssemblyIdentityName
            win32AssemblyManifestVersion = $metadata.Product.Win32AssemblyManifestVersion
        }
        store = [ordered]@{
            productId = $metadata.Store.ProductId
            packageFamilyName = $metadata.Store.PackageFamilyName
            artifactType = $metadata.Store.ArtifactType
            architectures = @(
                $metadata.Store.Architectures | ForEach-Object {
                    [ordered]@{
                        include = $_.Include
                        runtimeIdentifier = $_.RuntimeIdentifier
                        rustTarget = $_.RustTarget
                        processorArchitecture = $_.ProcessorArchitecture
                    }
                }
            )
            targetDeviceFamily = $metadata.Store.TargetDeviceFamily
            minVersion = $metadata.Store.MinVersion
            maxVersionTested = $metadata.Store.MaxVersionTested
            capabilities = @(
                $metadata.Store.Capabilities | ForEach-Object {
                    [ordered]@{
                        name = $_.Name
                        manifestElement = $_.ManifestElement
                    }
                }
            )
            publishMode = $metadata.Store.PublishMode
            privacyPolicyUrl = $metadata.Store.PrivacyPolicyUrl
            versioning = [ordered]@{
                packingBase = $metadata.Store.Versioning.PackingBase
                storeVersion = $metadata.Store.Versioning.StoreVersion
            }
        }
        branding = [ordered]@{
            source = $metadata.Branding.Source
            outputDirectory = $metadata.Branding.OutputDirectory
            backgroundColor = $metadata.Branding.BackgroundColor
            icon = [ordered]@{
                file = $metadata.Branding.Icon.File
                sizes = @($metadata.Branding.Icon.Sizes)
            }
            assets = @(
                $metadata.Branding.Assets | ForEach-Object {
                    [ordered]@{
                        file = $_.File
                        width = $_.Width
                        height = $_.Height
                        scales = @($_.Scales)
                    }
                }
            )
            targetSizeAsset = @(
                $metadata.Branding.TargetSizeAsset | ForEach-Object {
                    [ordered]@{
                        fileStem = $_.FileStem
                        sizes = @($_.Sizes)
                        includeUnplated = $_.IncludeUnplated
                    }
                }
            )
        }
        tooling = [ordered]@{
            msstore = [ordered]@{
                version = $metadata.Tooling.MsStore.Version
                assetName = $metadata.Tooling.MsStore.AssetName
                dotnetSdkVersion = $metadata.Tooling.MsStore.DotNetSdkVersion
                runtimeMajor = $metadata.Tooling.MsStore.RuntimeMajor
                sha256 = $metadata.Tooling.MsStore.Sha256
            }
        }
        externalBindings = [ordered]@{
            githubEnvironment = $metadata.ExternalBindings.GitHubEnvironment
            requiredSecrets = @(
                $metadata.ExternalBindings.RequiredSecrets | ForEach-Object {
                    [ordered]@{ name = $_.Name; purpose = $_.Purpose }
                }
            )
            optionalSecrets = @(
                $metadata.ExternalBindings.OptionalSecrets | ForEach-Object {
                    [ordered]@{ name = $_.Name; purpose = $_.Purpose }
                }
            )
        }
    }
    $projection | ConvertTo-Json -Depth 8
}
else {
    $metadata
}