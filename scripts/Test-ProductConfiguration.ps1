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
$brandingRecipePath = Join-Path $repoRoot 'build/branding.json'

function Get-RequiredXmlValue {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)][string]$LocalName
    )

    $node = $Document.SelectSingleNode(
        "/*[local-name()='Project']/*[local-name()='PropertyGroup']/*[local-name()='$LocalName']"
    )
    if (-not $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) {
        throw "Product property '$LocalName' is missing from $productPropsPath."
    }
    return $node.InnerText.Trim()
}

function Assert-FourPartVersion {
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Product version must use A.B.C.D: $Version"
    }
    foreach ($component in $Version.Split('.')) {
        if ([int]$component -gt 65535) {
            throw "Product version components must be between 0 and 65535: $Version"
        }
    }
}

foreach ($requiredPath in @($productPropsPath, $manifestPath, $win32ManifestPath, $cargoPath, $readmePath, $changelogPath, $brandingRecipePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required product configuration file is missing: $requiredPath"
    }
}

[xml]$productProps = Get-Content -LiteralPath $productPropsPath -Raw
$metadata = [ordered]@{
    Version = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoProductVersion'
    CoreVersion = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoCoreVersion'
    DisplayName = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoProductName'
    PublisherDisplayName = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoPublisherDisplayName'
    Name = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoPackageIdentityName'
    Publisher = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoPackagePublisher'
    ApplicationId = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoApplicationId'
    ApplicationIcon = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoApplicationIcon'
    BackgroundColor = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoBrandBackgroundColor'
    Win32AssemblyIdentityName = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoWin32AssemblyIdentityName'
    Win32AssemblyManifestVersion = Get-RequiredXmlValue -Document $productProps -LocalName 'EchoWin32AssemblyManifestVersion'
}

Assert-FourPartVersion $metadata.Version
$expectedCoreVersion = ($metadata.Version.Split('.')[0..2] -join '.')
if ($metadata.CoreVersion -ne $expectedCoreVersion) {
    throw "EchoCoreVersion must match the first three product-version components. Expected $expectedCoreVersion, found $($metadata.CoreVersion)."
}
if ($ExpectedVersion -and $ExpectedVersion -ne $metadata.Version) {
    throw "Requested official version $ExpectedVersion does not match canonical version $($metadata.Version)."
}

[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$identity = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
$properties = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Properties']")
$application = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']")
$visualElements = $application.SelectSingleNode("*[local-name()='VisualElements']")
if (-not $identity -or -not $properties -or -not $application -or -not $visualElements) {
    throw 'Package.appxmanifest is missing required identity or visual metadata.'
}

$manifestChecks = [ordered]@{
    'Identity.Name' = @($identity.Name, $metadata.Name)
    'Identity.Publisher' = @($identity.Publisher, $metadata.Publisher)
    'Identity.Version' = @($identity.Version, $metadata.Version)
    'Properties.DisplayName' = @($properties.DisplayName, $metadata.DisplayName)
    'Properties.PublisherDisplayName' = @($properties.PublisherDisplayName, $metadata.PublisherDisplayName)
    'Application.Id' = @($application.Id, $metadata.ApplicationId)
    'VisualElements.DisplayName' = @($visualElements.DisplayName, $metadata.DisplayName)
    'VisualElements.BackgroundColor' = @($visualElements.BackgroundColor, $metadata.BackgroundColor)
}

$brandingRecipe = Get-Content -LiteralPath $brandingRecipePath -Raw | ConvertFrom-Json
if ($brandingRecipe.backgroundColor -cne $metadata.BackgroundColor) {
    throw "Branding background mismatch. Expected $($metadata.BackgroundColor), found $($brandingRecipe.backgroundColor)."
}
$recipeFiles = @($brandingRecipe.assets | ForEach-Object { [string]$_.file })
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
        throw "Package manifest asset is not defined by the branding recipe: $assetReference"
    }
}
if ($metadata.ApplicationIcon -notmatch '^Assets[\\/](?<file>[^\\/]+)$' -or
    $Matches.file -cne [string]$brandingRecipe.icon.file) {
    throw "Canonical application icon does not match the branding recipe: $($metadata.ApplicationIcon)"
}

[xml]$win32Manifest = Get-Content -LiteralPath $win32ManifestPath -Raw
$assemblyIdentity = $win32Manifest.SelectSingleNode("/*[local-name()='assembly']/*[local-name()='assemblyIdentity']")
$executionLevel = $win32Manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
$supportedOs = $win32Manifest.SelectSingleNode("//*[local-name()='supportedOS']")
$dpiAware = $win32Manifest.SelectSingleNode("//*[local-name()='dpiAware']")
$dpiAwareness = $win32Manifest.SelectSingleNode("//*[local-name()='dpiAwareness']")
if (-not $assemblyIdentity -or
    $assemblyIdentity.Name -cne $metadata.Win32AssemblyIdentityName -or
    $assemblyIdentity.Version -cne $metadata.Win32AssemblyManifestVersion) {
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
foreach ($entry in $manifestChecks.GetEnumerator()) {
    $actual = [string]$entry.Value[0]
    $expected = [string]$entry.Value[1]
    if ($actual -cne $expected) {
        throw "Package.appxmanifest $($entry.Key) mismatch. Expected '$expected', found '$actual'."
    }
}

$cargoText = Get-Content -LiteralPath $cargoPath -Raw
$cargoMatch = [regex]::Match($cargoText, '(?m)^version\s*=\s*"(?<version>\d+\.\d+\.\d+)"\s*$')
if (-not $cargoMatch.Success -or $cargoMatch.Groups['version'].Value -ne $metadata.CoreVersion) {
    $actualCargoVersion = if ($cargoMatch.Success) { $cargoMatch.Groups['version'].Value } else { '<missing>' }
    throw "Cargo package version mismatch. Expected $($metadata.CoreVersion), found $actualCargoVersion."
}

$readmeText = Get-Content -LiteralPath $readmePath -Raw
$readmeMatch = [regex]::Match($readmeText, 'version-v(?<version>\d+\.\d+\.\d+\.\d+)')
if (-not $readmeMatch.Success -or $readmeMatch.Groups['version'].Value -ne $metadata.Version) {
    $actualReadmeVersion = if ($readmeMatch.Success) { $readmeMatch.Groups['version'].Value } else { '<missing>' }
    throw "README version badge mismatch. Expected $($metadata.Version), found $actualReadmeVersion."
}

$changelogText = Get-Content -LiteralPath $changelogPath -Raw
$escapedVersion = [regex]::Escape($metadata.Version)
if ($changelogText -notmatch "(?m)^## \[$escapedVersion\](?:\s|$)") {
    throw "CHANGELOG does not contain an entry for canonical version $($metadata.Version)."
}

$iconPath = Split-Path $manifestPath
foreach ($pathSegment in ($metadata.ApplicationIcon -split '[\\/]')) {
    $iconPath = Join-Path $iconPath $pathSegment
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "Canonical application icon is missing: $iconPath"
}

$result = [pscustomobject]$metadata
if ($AsJson) {
    $result | ConvertTo-Json -Compress
}
else {
    $result
}
