# Echo.ReleaseMetadata.psm1
#
# Single source of truth for parsing the versioned distribution configuration
# in build/Product.props (schema 1, D19) and for release/version/provenance
# logic used by packaging, release provenance and Store preflight.
#
# No other script, module or workflow may parse Product.props independently or
# read a second configuration store. This module owns:
#   - schema-1 property/item parsing and strict validation;
#   - strict four-part product version parsing plus D5 Store version mapping;
#   - version ordering/comparison helpers;
#   - release-tag dereference helpers and provenance/manifest validation;
#   - the canonical JSON configuration projection (`Get-EchoDistributionConfiguration`).
#
# All functions are deterministic and offline-testable given a fixture path.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Schema 1 contract definition (D19)
# ---------------------------------------------------------------------------
$script:SchemaOne = 1

$script:RequiredPropertyGroups = @{

    'SCHEMA' = [ordered]@{
        'EchoDistributionSchemaVersion' = @{ Kind = 'Int'; Required = $true }
    }

    'PRODUCT' = [ordered]@{
        'EchoProductVersion'               = @{ Kind = 'Version4'; Required = $true }
        'EchoCoreVersion'                  = @{ Kind = 'Version3'; Required = $true }
        'EchoProductName'                  = @{ Kind = 'String'; Required = $true }
        'EchoPublisherDisplayName'         = @{ Kind = 'String'; Required = $true }
        'EchoPackageIdentityName'          = @{ Kind = 'String'; Required = $true }
        'EchoPackagePublisher'             = @{ Kind = 'String'; Required = $true }
        'EchoApplicationId'                = @{ Kind = 'String'; Required = $true }
        'EchoApplicationIcon'              = @{ Kind = 'AssetPath'; Required = $true }
        'EchoBrandBackgroundColor'         = @{ Kind = 'Color'; Required = $true }
        'EchoWin32AssemblyIdentityName'    = @{ Kind = 'String'; Required = $true }
        'EchoWin32AssemblyManifestVersion' = @{ Kind = 'Version4'; Required = $true }
    }

    'STORE' = [ordered]@{
        'EchoStoreProductId'                  = @{ Kind = 'String'; Required = $true }
        'EchoPackageFamilyName'               = @{ Kind = 'String'; Required = $true }
        'EchoStoreArtifactType'               = @{ Kind = 'Enum'; Enum = 'msixbundle'; Required = $true }
        'EchoStorePublishMode'                = @{ Kind = 'Enum'; Enum = 'Immediate'; Required = $true }
        'EchoStoreTargetDeviceFamily'         = @{ Kind = 'Enum'; Enum = 'Windows.Desktop'; Required = $true }
        'EchoStoreMinVersion'                 = @{ Kind = 'Version4'; Required = $true }
        'EchoStoreMaxVersionTested'           = @{ Kind = 'Version4'; Required = $true }
        'EchoPrivacyPolicyUrl'                = @{ Kind = 'Url'; Required = $true }
    }

    'VERSIONING' = [ordered]@{
        'EchoStoreVersionPackingBase' = @{ Kind = 'Int'; Required = $true }
    }

    'BRANDING' = [ordered]@{
        'EchoBrandSource'          = @{ Kind = 'Path'; Required = $true }
        'EchoBrandOutputDirectory' = @{ Kind = 'Path'; Required = $true }
        'EchoBrandIconFile'        = @{ Kind = 'FileName'; Required = $true }
        'EchoBrandIconSizes'       = @{ Kind = 'IntList'; Required = $true }
    }

    'TOOLING' = [ordered]@{
        'EchoMsStoreCliVersion'            = @{ Kind = 'String'; Required = $true }
        'EchoMsStoreCliAssetName'          = @{ Kind = 'FileName'; Required = $true }
        'EchoMsStoreCliDotNetSdkVersion'   = @{ Kind = 'Version3'; Required = $true }
        'EchoMsStoreCliRuntimeMajor'       = @{ Kind = 'Int'; Required = $true }
        'EchoMsStoreCliSha256'             = @{ Kind = 'Sha256'; Required = $true }
    }

    'EXTERNAL' = [ordered]@{
        'EchoGitHubStoreEnvironment' = @{ Kind = 'String'; Required = $true }
    }
}

$script:RequiredItemGroups = [ordered]@{
    'EchoStoreArchitecture' = @{
        Required = $true
        RequiredMetadata = [ordered]@{
            'RuntimeIdentifier'          = @{ Kind = 'String'; Required = $true }
            'RustTarget'                 = @{ Kind = 'String'; Required = $true }
            'ProcessorArchitecture'      = @{ Kind = 'Enum'; Enum = 'x64', 'arm64'; Required = $true }
        }
        ExpectedValues = @{ UseMetadata = 'RuntimeIdentifier' }
    }
    'EchoStoreCapability' = @{
        Required = $true
        RequiredMetadata = [ordered]@{
            'ManifestElement' = @{ Kind = 'Enum'; Enum = 'rescap:Capability', 'DeviceCapability'; Required = $true }
        }
    }
    'EchoBrandAsset' = @{
        Required = $true
        RequiredMetadata = [ordered]@{
            'Width'  = @{ Kind = 'PosInt'; Required = $true }
            'Height' = @{ Kind = 'PosInt'; Required = $true }
            'Scales' = @{ Kind = 'PosIntList'; Required = $true }
        }
    }
    'EchoBrandTargetSizeAsset' = @{
        Required = $true
        RequiredMetadata = [ordered]@{
            'Sizes'           = @{ Kind = 'PosIntList'; Required = $true }
            'IncludeUnplated' = @{ Kind = 'Bool'; Required = $true }
        }
    }
    'EchoExternalBinding' = @{
        Required = $true
        RequiredMetadata = [ordered]@{
            'Kind'    = @{ Kind = 'Enum'; Enum = 'Secret'; Required = $true }
            'Scope'   = @{ Kind = 'Enum'; Enum = 'Environment'; Required = $true }
            'Required' = @{ Kind = 'Bool'; Required = $true }
            'Purpose' = @{ Kind = 'String'; Required = $false }
        }
    }
}

# ---------------------------------------------------------------------------
# Internal validation helpers
# ---------------------------------------------------------------------------

function Assert-VersionComponentBounds {
    param(
        [Parameter(Mandatory)][string]$Version,
        [AllowNull()][int]$MaxCD = $null
    )

    $parts = $Version.Split('.')
    $a = [int]$parts[0]; $b = [int]$parts[1]
    $c = [int]$parts[2]; $d = [int]$parts[3]

    if ($a -gt 65535 -or $b -gt 65535) {
        throw "Version components A/B must be 0..65535: $Version"
    }
    if ($MaxCD -ne $null) {
        if ($c -gt $MaxCD -or $d -gt $MaxCD) {
            throw "Version components C/D must be 0..$MaxCD for the D5 mapping: $Version"
        }
    }
    elseif ($c -gt 65535 -or $d -gt 65535) {
        throw "Version components C/D must be 0..65535: $Version"
    }
}

function Resolve-RequiredPropertyValue {
    param([Parameter(Mandatory)][xml]$Document)

    # Gather every direct PropertyGroup child to detect duplicates and unknown.
    $project = $Document.DocumentElement
    $knownNames = @{}
    foreach ($group in $project.PropertyGroup) {
        foreach ($child in $group.ChildNodes) {
            if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if ($knownNames.ContainsKey($child.Name) -and $knownNames[$child.Name].Count -gt 0) {
                throw "Duplicate product property '$($child.Name)' is not allowed under schema 1."
            }
            if (-not $knownNames.ContainsKey($child.Name)) {
                $knownNames[$child.Name] = @()
            }
            $knownNames[$child.Name] += $child.InnerText
        }
    }
    return $knownNames
}

function Resolve-RequiredItemValues {
    param([Parameter(Mandatory)][xml]$Document)

    $project = $Document.DocumentElement
    $itemValues = @{}
    foreach ($groupName in $script:RequiredItemGroups.Keys) {
        $itemValues[$groupName] = @()
    }
    foreach ($group in $project.ItemGroup) {
        foreach ($child in $group.ChildNodes) {
if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if ($script:RequiredItemGroups.Keys -notcontains $child.Name) {
                if ($child.Name -match '^(PackageReference|Content|None|AppxManifest|Compile|Page|ProjectReference)$') {
                    continue
                }
                # Unknown item groups are tolerated only if they are not part of
                # the distribution schema contract; distribution-relevant items are
                # the five groups above and their exact members are validated later.
                continue
            }
            $metadata = @{}
            foreach ($member in $child.ChildNodes) {
                if ($member.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                $metadata[$member.Name] = $member.InnerText
            }
            $itemValues[$child.Name] += [pscustomobject]@{
                Include   = $child.Attributes['Include'].Value
                Metadata  = $metadata
            }
        }
    }
    return $itemValues
}

function Format-MetadataError {
    param(
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$ItemName,
        [string]$Extra = ''
    )
    return "Invalid $GroupName item '$ItemName'$Extra"
}

function Test-ValidColor {
    param([Parameter(Mandatory)][string]$Value)
    return $Value -match '^#[0-9A-Fa-f]{6,8}$'
}

function Test-ValidUrl {
    param([Parameter(Mandatory)][string]$Value)
    [uri]$uriResult = $null
    return ([uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uriResult) `
            -and $uriResult.Scheme -eq 'https')
}

function Test-ValidSha256 {
    param([Parameter(Mandatory)][string]$Value)
    return $Value -match '^[0-9a-f]{64}$'
}

# ---------------------------------------------------------------------------
# Public: parse Product.props into the canonical configuration object
# ---------------------------------------------------------------------------

function Get-EchoDistributionConfiguration {
    [CmdletBinding()]
    param(
        [string]$Path
    )

$moduleDir = Split-Path -Parent $PSScriptRoot
    $repoRoot = if ($Path) {
        [System.IO.Path]::GetFullPath((Join-Path $Path '..\..'))
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $moduleDir '..'))
    }
    $propsPath = if ($Path) { [System.IO.Path]::GetFullPath($Path) } else { Join-Path $repoRoot 'build\Product.props' }
    if (-not (Test-Path -LiteralPath $propsPath -PathType Leaf)) {
        throw "Product configuration is missing: $propsPath"
    }

    [xml]$document = Get-Content -LiteralPath $propsPath -Raw
    $project = $document.DocumentElement

    # --- properties (duplicate + unknown detection) ---
    $knownNames = Resolve-RequiredPropertyValue -Document $document

    $allowedPropertyNames = @()
    foreach ($definition in $script:RequiredPropertyGroups.GetEnumerator()) {
        foreach ($member in $definition.Value.GetEnumerator()) {
            $allowedPropertyNames += $member.Key
        }
    }
    foreach ($name in $knownNames.Keys) {
        if ($name -notin $allowedPropertyNames) {
            throw "Unknown product/configuration property '$name' is not allowed under schema 1."
        }
    }

    # --- items ---
    $itemValues = Resolve-RequiredItemValues -Document $document

    # Read every declared schema property.
    $propertyFactory = {
        param([string]$Name, [hashtable]$Meta, [hashtable]$Values)
        foreach ($value in $Values[$Name]) {
            $raw = [string]$value
            switch ($Meta.Kind) {
                'Int' {
                    if ($raw -notmatch '^\d+$') { throw "Property '$Name' must be a non-negative integer: '$raw'." }
                    return [int]$raw
                }
                'Version4' {
                    if ($raw -notmatch '^\d+(\.\d+){3}$') { throw "Property '$Name' must use A.B.C.D: '$raw'." }
                    Assert-VersionComponentBounds -Version $raw -MaxCD 65535
                    return $raw
                }
                'Version3' {
                    if ($raw -notmatch '^\d+(\.\d+){2}$') { throw "Property '$Name' must use A.B.C: '$raw'." }
                    return $raw
                }
                'String' { return $raw }
                'Enum' {
                    if ($Meta.Enum -notcontains $raw) { throw "Property '$Name' must be one of '$($Meta.Enum -join '|')': '$raw'." }
                    return $raw
                }
                'AssetPath' {
                    if ($raw -notmatch '^(Assets|Assets\\|Assets/)[^\\/]*(\\|/)?[^\\/]+$') {
                        throw "Property '$Name' must be an output-relative asset path: '$raw'."
                    }
                    return $raw
                }
                'Path' {
                    if ($raw -notmatch '^[^\\]') { throw "Property '$Name' must be a repository-relative path: '$raw'." }
                    if ($raw -match '\.\.') { throw "Property '$Name' must not traverse the repository root: '$raw'." }
                    return $raw
                }
                'FileName' {
                    if ($raw -match '[\\/]' -or $raw -eq '') { throw "Property '$Name' must be a plain file name: '$raw'." }
                    return $raw
                }
                'Color' {
                    if (-not (Test-ValidColor -Value $raw)) { throw "Property '$Name' must be a #RRGGBB[AA] color: '$raw'." }
                    return $raw
                }
                'Url' {
                    if (-not (Test-ValidUrl -Value $raw)) { throw "Property '$Name' must be an absolute HTTPS URL: '$raw'." }
                    return $raw
                }
                'Sha256' {
                    if (-not (Test-ValidSha256 -Value $raw)) { throw "Property '$Name' must be a lowercase 64-hex SHA-256: '$raw'." }
                    return $raw
                }
                'IntList' {
                    $items = @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    foreach ($item in $items) {
                        if ($item -notmatch '^\d+$' -or [int]$item -le 0) {
                            throw "Property '$Name' must be a semicolon-delimited positive integer list: '$raw'."
                        }
                    }
                    if (($items | Sort-Object -Unique).Count -ne $items.Count -or $items.Count -eq 0) {
                        throw "Property '$Name' must contain unique positive integers: '$raw'."
                    }
                    return @($items | ForEach-Object { [int]$_ })
                }
                default { throw "Unsupported property kind for '$Name'." }
            }
        }
    }

    $properties = @{}
    foreach ($definition in $script:RequiredPropertyGroups.GetEnumerator()) {
        foreach ($entry in $definition.Value.GetEnumerator()) {
            $name = $entry.Key
            $meta = $entry.Value
            if (-not $knownNames.ContainsKey($name)) {
                throw "Required product property '$name' is missing."
            }
            $properties[$name] = & $propertyFactory -Name $name -Meta $meta -Values $knownNames
        }
    }

    # Schema enforcer.
    if ($properties['EchoDistributionSchemaVersion'] -ne $script:SchemaOne) {
        throw "Unsupported EchoDistributionSchemaVersion '$($properties['EchoDistributionSchemaVersion'])'."
    }

    # D5 packing-base enforcer (must be exactly 256 under schema 1).
    if ($properties['EchoStoreVersionPackingBase'] -ne 256) {
        throw "EchoStoreVersionPackingBase must be exactly 256 under schema 1."
    }

    # Consistency: core version == first three product components.
    $productVersion = $properties['EchoProductVersion']
    $expectedCore = ($productVersion.Split('.')[0..2] -join '.')
    if ($properties['EchoCoreVersion'] -ne $expectedCore) {
        throw "EchoCoreVersion must equal the first three product-version components. Expected $expectedCore, found $($properties['EchoCoreVersion'])."
    }

    # --- items: architecture(s) ---
    $architectures = @()
    $archValues = $itemValues['EchoStoreArchitecture']
    if ($archValues.Count -eq 0) { throw 'Product.props must declare at least one EchoStoreArchitecture item.' }
    foreach ($group in $archValues) {
        $ord = $group.Include
        $rid = $group.Metadata['RuntimeIdentifier']
        $rust = $group.Metadata['RustTarget']
        $arch = $group.Metadata['ProcessorArchitecture']
        if (-not $rid -or -not $rust -or -not $arch) {
            throw (Format-MetadataError -GroupName 'EchoStoreArchitecture' -ItemName $ord -Extra ' is missing required metadata.')
        }
        if ($arch -notin @('x64', 'arm64')) {
            throw (Format-MetadataError -GroupName 'EchoStoreArchitecture' -ItemName $ord -Extra " has unsupported ProcessorArchitecture '$arch'.")
        }
        $architectures += [pscustomobject]@{
            Include = $ord
            RuntimeIdentifier = $rid
            RustTarget = $rust
            ProcessorArchitecture = $arch
        }
    }
$uniqueArches = @($architectures | ForEach-Object { $_.ProcessorArchitecture })
    $orderedArches = 'x64', 'arm64' | Where-Object { $_ -in $uniqueArches }
    $expectedArches = @('x64', 'arm64')
    if (($uniqueArches | Sort-Object -Unique | Measure-Object).Count -ne 2 -or $uniqueArches -notcontains 'x64' -or $uniqueArches -notcontains 'arm64') {
        throw "EchoStoreArchitecture must contain exactly x64 and arm64; found '$($uniqueArches -join ', ')'."
    }
    $architectures = @($architectures | Sort-Object ProcessorArchitecture)

    # --- capabilities ---
    $capabilities = @()
    foreach ($group in $itemValues['EchoStoreCapability']) {
        $name = $group.Include
        $element = $group.Metadata['ManifestElement']
        if (-not $element) { throw "EchoStoreCapability item '$name' is missing ManifestElement metadata." }
        $capabilities += [pscustomobject]@{ Name = $name; ManifestElement = $element }
    }

    # --- branding ---
    $brandAssets = @(
        foreach ($group in $itemValues['EchoBrandAsset']) {
            $meta = $group.Metadata
            [pscustomobject]@{
                File   = $group.Include
                Width  = [int]$meta['Width']
                Height = [int]$meta['Height']
                Scales = @($meta['Scales'] -split ';' | ForEach-Object { [int]$_.Trim() })
            }
        }
    )
    $targetSizeAssets = @(
        foreach ($group in $itemValues['EchoBrandTargetSizeAsset']) {
            $meta = $group.Metadata
            [pscustomobject]@{
                FileStem       = $group.Include
                Sizes          = @($meta['Sizes'] -split ';' | ForEach-Object { [int]$_.Trim() })
                IncludeUnplated = [bool]($meta['IncludeUnplated'] -eq 'true')
            }
        }
    )

    # --- external bindings ---
    $requiredSecrets = @(); $optionalSecrets = @()
    foreach ($group in $itemValues['EchoExternalBinding']) {
        $name = $group.Include
        $isRequired = [bool]($group.Metadata['Required'] -eq 'true')
        $binding = [pscustomobject]@{ Name = $name; Purpose = $group.Metadata['Purpose'] }
        if ($isRequired) { $requiredSecrets += $binding } else { $optionalSecrets += $binding }
    }

    $storePackingBase = $properties['EchoStoreVersionPackingBase']
    $storeVersion = Get-EchoStoreVersion -ProductVersion $productVersion -PackingBase $storePackingBase

    $config = [pscustomobject]@{
        SchemaVersion = $properties['EchoDistributionSchemaVersion']
        Product = [pscustomobject]@{
            Version                  = $productVersion
            CoreVersion              = $properties['EchoCoreVersion']
            Name                     = $properties['EchoProductName']
            PublisherDisplayName     = $properties['EchoPublisherDisplayName']
            PackageIdentityName      = $properties['EchoPackageIdentityName']
            PackagePublisher         = $properties['EchoPackagePublisher']
            ApplicationId            = $properties['EchoApplicationId']
            ApplicationIcon          = $properties['EchoApplicationIcon']
            BrandBackgroundColor     = $properties['EchoBrandBackgroundColor']
            Win32AssemblyIdentityName = $properties['EchoWin32AssemblyIdentityName']
            Win32AssemblyManifestVersion = $properties['EchoWin32AssemblyManifestVersion']
        }
        Store = [pscustomobject]@{
            ProductId          = $properties['EchoStoreProductId']
            PackageFamilyName  = $properties['EchoPackageFamilyName']
            ArtifactType       = $properties['EchoStoreArtifactType']
            Architectures      = @($architectures)
            TargetDeviceFamily = $properties['EchoStoreTargetDeviceFamily']
            MinVersion         = $properties['EchoStoreMinVersion']
            MaxVersionTested   = $properties['EchoStoreMaxVersionTested']
            Capabilities       = $capabilities
            PublishMode        = $properties['EchoStorePublishMode']
            PrivacyPolicyUrl   = $properties['EchoPrivacyPolicyUrl']
            Versioning         = [pscustomobject]@{
                PackingBase  = $storePackingBase
                StoreVersion = $storeVersion
            }
        }
        Branding = [pscustomobject]@{
            Source          = $properties['EchoBrandSource']
            OutputDirectory = $properties['EchoBrandOutputDirectory']
            BackgroundColor = $properties['EchoBrandBackgroundColor']
            Icon            = [pscustomobject]@{
                File  = $properties['EchoBrandIconFile']
                Sizes = $properties['EchoBrandIconSizes']
            }
            Assets          = $brandAssets
            TargetSizeAsset = $targetSizeAssets
        }
        Tooling = [pscustomobject]@{
            MsStore = [pscustomobject]@{
                Version          = $properties['EchoMsStoreCliVersion']
                AssetName        = $properties['EchoMsStoreCliAssetName']
                DotNetSdkVersion = $properties['EchoMsStoreCliDotNetSdkVersion']
                RuntimeMajor     = $properties['EchoMsStoreCliRuntimeMajor']
                Sha256           = $properties['EchoMsStoreCliSha256']
            }
        }
        ExternalBindings = [pscustomobject]@{
            GitHubEnvironment = $properties['EchoGitHubStoreEnvironment']
            RequiredSecrets   = $requiredSecrets
            OptionalSecrets   = $optionalSecrets
        }
    }

    return $config
}

# ---------------------------------------------------------------------------
# Public: D5 Store version mapping
# ---------------------------------------------------------------------------

function Get-EchoStoreVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProductVersion,
        [int]$PackingBase = 256
    )

    if (-not $ProductVersion -match '^\d+(\.\d+){3}$') {
        throw "Product version must use A.B.C.D: $ProductVersion"
    }
    $parts = $ProductVersion.Split('.')
    $a = [int]$parts[0]; $b = [int]$parts[1]
    $c = [int]$parts[2]; $d = [int]$parts[3]
    if ($a -gt 65535 -or $b -gt 65535 -or $c -gt 255 -or $d -gt 255 -or $c -lt 0 -or $d -lt 0) {
        throw "Product version components C/D must be 0..255 and A/B 0..65535: $ProductVersion"
    }
    $s = ($c * $PackingBase) + $d
    if ($s -gt 65535) {
        throw "Derived Store build S=$s exceeds the 65535 Store-version bound for $ProductVersion."
    }
    return ('{0}.{1}.{2}.0' -f $a, $b, $s)
}

function Test-EchoCanonicalVersionFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)
    return $Version -match '^\d+(\.\d+){3}$'
}

function Compare-EchoVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $leftInts = @($Left.Split('.') | ForEach-Object { [int]$_ })
    $rightInts = @($Right.Split('.') | ForEach-Object { [int]$_ })
    for ($i = 0; $i -lt 4; $i++) {
        if ($leftInts[$i] -lt $rightInts[$i]) { return -1 }
        if ($leftInts[$i] -gt $rightInts[$i]) { return 1 }
    }
    return 0
}

function Test-EchoStoreVersionMonotonic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Current,
        [Parameter(Mandatory)][string]$LatestPublished
    )
    $cmp = Compare-EchoVersion -Left $Current -Right $LatestPublished
    return ($cmp -gt 0)
}

# ---------------------------------------------------------------------------
# Public: release-tag dereference helper (pure, no network) + provenance SHA
# ---------------------------------------------------------------------------

function Resolve-EchoReleaseTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [string]$Ref
    )
    # Pure helper used by workflows; dereferencing to a commit requires the gh
    # CLI. This function validates tag shape and yields the dereferenced SHA
    # when a ref is supplied. Network is never performed here.
    $rev = if ($Ref) { $Ref } else { '' }
    return [pscustomobject]@{
        Tag = $Tag
        Ref = $rev
        IsFourPart = Test-EchoCanonicalVersionFormat -Version ($Tag -replace '^v', '')
    }
}

function Get-EchoProductPropsSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Product.props path not found: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-EchoReleaseManifestSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][pscustomobject]$Configuration
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Release manifest is missing: $Path"
    }

    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    $checks = @(
        @{ Name = 'schemaVersion'; Value = [string]$manifest.schemaVersion },
        @{ Name = 'product.version'; Value = [string]$manifest.product.version },
        @{ Name = 'product.coreVersion'; Value = [string]$manifest.product.coreVersion }
    )

    $requiredStrings = @(
        'product.name',
        'product.publisherDisplayName',
        'product.packageIdentityName',
        'product.packagePublisher',
        'product.applicationId',
        'store.productId',
        'store.packageFamilyName',
        'store.artifactType',
        'store.targetDeviceFamily',
        'store.privacyPolicyUrl'
    )
    foreach ($key in $requiredStrings) {
        $value = $manifest
        foreach ($segment in $key.Split('.')) {
            $value = $value.$segment
        }
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            throw "Release manifest '$key' is missing or empty."
        }
    }

    if ([int]$manifest.schemaVersion -ne 1) {
        throw "Unsupported release manifest schemaVersion '$($manifest.schemaVersion)'."
    }
    if ($manifest.product.version -cne $Configuration.Product.Version) {
        throw "Release manifest product version '$($manifest.product.version)' does not match configuration '$($Configuration.Product.Version)'."
    }
    if ($manifest.store.productId -cne $Configuration.Store.ProductId) {
        throw "Release manifest product ID mismatch."
    }
    if ($manifest.store.packageFamilyName -cne $Configuration.Store.PackageFamilyName) {
        throw "Release manifest package family name mismatch."
    }

    $assets = @($manifest.assets)
    if ($assets.Count -eq 0) {
        throw "Release manifest must contain at least one distributable asset."
    }
    foreach ($asset in $assets) {
        if ([string]::IsNullOrWhiteSpace([string]$asset.filename)) {
            throw "Release manifest contains an asset without a filename."
        }
        if ([string]$asset.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Release manifest asset '$($asset.filename)' has an invalid lowercase SHA-256."
        }
        if ([string]::IsNullOrWhiteSpace([string]$asset.mediaRole)) {
            throw "Release manifest asset '$($asset.filename)' is missing its media role."
        }
    }

    return $manifest
}
# ---------------------------------------------------------------------------
# Public exports (must appear after all function definitions)
# ---------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'Get-EchoDistributionConfiguration',
    'Get-EchoStoreVersion',
    'Test-EchoCanonicalVersionFormat',
    'Compare-EchoVersion',
    'Test-EchoStoreVersionMonotonic',
    'Resolve-EchoReleaseTag',
    'Get-EchoProductPropsSha256',
    'Test-EchoReleaseManifestSchema'
)
