[CmdletBinding()]
param(
    [ValidateSet('GitHub', 'Store', 'Both')]
    [string]$Profile = 'Both',

    [string[]]$RuntimeIdentifiers = @('win-x64', 'win-arm64'),

    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$PackageVersion,

    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$BuildVersion,

    [string]$CertificateThumbprint,
    [switch]$SignMsix,
    [switch]$InstallMsix,
    [switch]$SmokeTest,
    [switch]$SkipTests,
    [switch]$NoClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:ProjectPath = Join-Path $script:RepoRoot 'src\ui\EchoVisualizer.csproj'
$script:ManifestPath = Join-Path $script:RepoRoot 'src\ui\Package.appxmanifest'
$script:ProductValidationPath = Join-Path $script:RepoRoot 'scripts\Test-ProductConfiguration.ps1'
$script:BrandingGeneratorPath = Join-Path $script:RepoRoot 'scripts\Generate-BrandAssets.ps1'
$script:ArtifactsRoot = Join-Path $script:RepoRoot 'artifacts'
$script:ProductMetadata = $null
$script:BaseProcessEnvironment = @{}
Get-ChildItem Env: | ForEach-Object {
    $script:BaseProcessEnvironment[$_.Name] = $_.Value
}

$RuntimeIdentifiers = @(
    $RuntimeIdentifiers |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
foreach ($runtimeIdentifier in $RuntimeIdentifiers) {
    if ($runtimeIdentifier -notin @('win-x64', 'win-arm64')) {
        throw "Unsupported runtime identifier: $runtimeIdentifier"
    }
}
if ($RuntimeIdentifiers.Count -eq 0) {
    throw 'At least one runtime identifier is required.'
}

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-NativeTool {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    Write-Host ("{0} {1}" -f $FilePath, ($Arguments -join ' ')) -ForegroundColor DarkGray
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5 wraps native stderr as NativeCommandError. Tools
        # such as Cargo use stderr for ordinary progress even when they succeed,
        # so rely on LASTEXITCODE instead of terminating on that wrapper record.
        $ErrorActionPreference = 'Continue'
        & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath"
    }
}

function Assert-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command was not found in PATH: $Name"
    }
}

function Assert-Version {
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Version must use four numeric components: $Version"
    }

    foreach ($component in $Version.Split('.')) {
        if ([int]$component -gt 65535) {
            throw "Every MSIX version component must be between 0 and 65535: $Version"
        }
    }
}

function Remove-SafeArtifactDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedArtifacts = [System.IO.Path]::GetFullPath($script:ArtifactsRoot).TrimEnd('\') + '\'
    $resolvedTarget = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    if (-not $resolvedTarget.StartsWith($resolvedArtifacts, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the artifacts root: $resolvedTarget"
    }

    if (Test-Path -LiteralPath $Path) {
        $artifactProcesses = Get-CimInstance Win32_Process -Filter "Name = 'EchoVisualizer.exe'" |
            Where-Object {
                $_.ExecutablePath -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath) + '\').StartsWith(
                    $resolvedTarget,
                    [System.StringComparison]::OrdinalIgnoreCase)
            }
        foreach ($artifactProcess in $artifactProcesses) {
            $process = Get-Process -Id $artifactProcess.ProcessId -ErrorAction SilentlyContinue
            if (-not $process) { continue }
            $null = $process.CloseMainWindow()
            if (-not $process.WaitForExit(5000)) {
                Stop-Process -Id $process.Id -Force
                $process.WaitForExit(5000)
            }
        }
        $lastError = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force
                $lastError = $null
                break
            }
            catch {
                $lastError = $_
                Start-Sleep -Milliseconds (250 * $attempt)
            }
        }
        if ($lastError) { throw $lastError }
    }
}

function Find-WindowsSdkTool {
    param([Parameter(Mandatory)][string]$Name)

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path -LiteralPath $kitsRoot)) {
        throw "Windows SDK tools directory was not found: $kitsRoot"
    }

    $candidates = foreach ($directory in Get-ChildItem -LiteralPath $kitsRoot -Directory) {
        $version = $null
        if ([System.Version]::TryParse($directory.Name, [ref]$version)) {
            $candidate = Join-Path $directory.FullName "x64\$Name"
            if (Test-Path -LiteralPath $candidate) {
                [pscustomobject]@{ Version = $version; Path = $candidate }
            }
        }
    }

    $tool = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $tool) {
        throw "Windows SDK tool was not found: $Name"
    }

    return $tool.Path
}

function Import-VisualCppEnvironment {
    param([Parameter(Mandatory)][ValidateSet('win-x64', 'win-arm64')][string]$RuntimeIdentifier)

    # vcvarsall prepends large toolchain paths and is not safe to layer over a
    # prior architecture. Restore the process environment captured at startup
    # before importing the requested target architecture.
    foreach ($variable in Get-ChildItem Env:) {
        if (-not $script:BaseProcessEnvironment.ContainsKey($variable.Name)) {
            [Environment]::SetEnvironmentVariable($variable.Name, $null, 'Process')
        }
    }
    foreach ($entry in $script:BaseProcessEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vsWhere)) {
        throw "Visual Studio locator was not found: $vsWhere"
    }

    $requiredComponent = if ($RuntimeIdentifier -eq 'win-arm64') {
        'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
    }
    else {
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    }
    $vcArchitecture = if ($RuntimeIdentifier -eq 'win-arm64') { 'x64_arm64' } else { 'x64' }
    $installationPath = (& $vsWhere -latest -products '*' -requires $requiredComponent -property installationPath).Trim()
    if (-not $installationPath) {
        throw "Visual Studio component '$requiredComponent' is required for $RuntimeIdentifier."
    }

    $vcVarsAll = Join-Path $installationPath 'VC\Auxiliary\Build\vcvarsall.bat'
    if (-not (Test-Path -LiteralPath $vcVarsAll)) {
        throw "vcvarsall.bat was not found under $installationPath."
    }

    $environmentLines = & $env:ComSpec /d /s /c "call `"$vcVarsAll`" $vcArchitecture >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize the Visual C++ environment for $RuntimeIdentifier."
    }
    foreach ($line in $environmentLines) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $name = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        Set-Item -Path "Env:$name" -Value $value
    }

    $linker = Get-Command link.exe -ErrorAction SilentlyContinue
    if (-not $linker) {
        throw "link.exe is not available after initializing Visual C++ for $RuntimeIdentifier."
    }
    Write-Host "Visual C++ environment: $RuntimeIdentifier ($($linker.Source))" -ForegroundColor DarkGray
}

function Get-ProductMetadata {
    if (-not (Test-Path -LiteralPath $script:ProductValidationPath -PathType Leaf)) {
        throw "Product configuration validator is missing: $script:ProductValidationPath"
    }
    $json = & $script:ProductValidationPath -AsJson
    return ($json | ConvertFrom-Json)
}

function New-VersionedPackageManifest {
    param([Parameter(Mandatory)][string]$Version)

    [xml]$manifest = Get-Content -LiteralPath $script:ManifestPath -Raw
    $namespace = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('f', $manifest.DocumentElement.NamespaceURI)
    $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $namespace)
    $identity.Version = $Version

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("EchoVisualizer-{0}.appxmanifest" -f [guid]::NewGuid().ToString('N'))
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($path, $settings)
    try {
        $manifest.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
    return $path
}

function Resolve-SigningCertificate {
    param(
        [Parameter(Mandatory)][string]$Publisher,
        [string]$RequestedThumbprint
    )

    if ($RequestedThumbprint) {
        $normalized = $RequestedThumbprint.Replace(' ', '').ToUpperInvariant()
        $certificate = Get-ChildItem -Path Cert:\CurrentUser\My |
            Where-Object { $_.Thumbprint -eq $normalized -and $_.HasPrivateKey } |
            Select-Object -First 1
    }
    else {
        $certificate = Get-ChildItem -Path Cert:\CurrentUser\My |
            Where-Object {
                $_.Subject -eq $Publisher -and
                $_.HasPrivateKey -and
                $_.NotAfter -gt (Get-Date)
            } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
    }

    if (-not $certificate) {
        throw "No current-user signing certificate with a private key matches publisher '$Publisher'."
    }

    return $certificate
}

function Get-PlatformForRuntime {
    param([Parameter(Mandatory)][string]$RuntimeIdentifier)
    if ($RuntimeIdentifier -eq 'win-arm64') { return 'arm64' }
    return 'x64'
}

function Get-RustTargetForRuntime {
    param([Parameter(Mandatory)][string]$RuntimeIdentifier)
    if ($RuntimeIdentifier -eq 'win-arm64') { return 'aarch64-pc-windows-msvc' }
    return 'x86_64-pc-windows-msvc'
}

function Assert-PeArchitecture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('win-x64', 'win-arm64')][string]$RuntimeIdentifier
    )

    $expectedMachine = if ($RuntimeIdentifier -eq 'win-arm64') { 0xAA64 } else { 0x8664 }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        $machine = $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }

    if ($machine -ne $expectedMachine) {
        throw ('Unexpected PE architecture for {0}. Expected 0x{1:X4}, found 0x{2:X4}.' -f $Path, $expectedMachine, $machine)
    }
}

function Assert-FileExists {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required artifact file is missing: $Path"
    }
}

function Invoke-BrandAssetCheck {
    param([string]$OutputDirectory)

    if (-not (Test-Path -LiteralPath $script:BrandingGeneratorPath -PathType Leaf)) {
        throw "Brand asset generator is missing: $script:BrandingGeneratorPath"
    }
    if ($OutputDirectory) {
        & $script:BrandingGeneratorPath -Check -OutputDirectory $OutputDirectory
    }
    else {
        & $script:BrandingGeneratorPath -Check
    }
}

function Assert-IcoFrames {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int[]]$ExpectedSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
    )

    Assert-FileExists $Path
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $reserved = $reader.ReadUInt16()
        $type = $reader.ReadUInt16()
        $count = $reader.ReadUInt16()
        if ($reserved -ne 0 -or $type -ne 1) {
            throw "Application icon is not a valid ICO file: $Path"
        }
        $actualSizes = @(
            for ($index = 0; $index -lt $count; $index++) {
                $width = [int]$reader.ReadByte()
                $height = [int]$reader.ReadByte()
                $null = $reader.ReadByte()
                $null = $reader.ReadByte()
                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt32()
                $null = $reader.ReadUInt32()
                if ($width -eq 0) { $width = 256 }
                if ($height -eq 0) { $height = 256 }
                if ($width -ne $height) {
                    throw "Application icon contains a non-square frame (${width}x${height}): $Path"
                }
                $width
            }
        )
    }
    finally {
        $stream.Dispose()
    }

    $actual = @($actualSizes | Sort-Object -Unique)
    $expected = @($ExpectedSizes | Sort-Object -Unique)
    if (($actual -join ',') -ne ($expected -join ',')) {
        throw "Application icon frame mismatch. Expected $($expected -join ', '), found $($actual -join ', '): $Path"
    }
}

function Assert-EmbeddedApplicationIcon {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    if (-not ('Echo.Build.NativeResourceInspector' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Echo.Build
{
    public static class NativeResourceInspector
    {
        private const uint LoadLibraryAsDataFile = 0x00000002;
        private const uint LoadLibraryAsImageResource = 0x00000020;
        private static readonly IntPtr GroupIconResource = new IntPtr(14);

        private delegate bool EnumResourceNameCallback(
            IntPtr module,
            IntPtr type,
            IntPtr name,
            IntPtr parameter);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(
            string fileName,
            IntPtr file,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool EnumResourceNames(
            IntPtr module,
            IntPtr type,
            EnumResourceNameCallback callback,
            IntPtr parameter);

        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr module);

        public static bool HasGroupIcon(string path)
        {
            IntPtr module = LoadLibraryEx(
                path,
                IntPtr.Zero,
                LoadLibraryAsDataFile | LoadLibraryAsImageResource);
            if (module == IntPtr.Zero)
            {
                throw new System.ComponentModel.Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to inspect executable resources: " + path);
            }

            bool found = false;
            EnumResourceNameCallback callback = delegate
            {
                found = true;
                return false;
            };
            try
            {
                EnumResourceNames(module, GroupIconResource, callback, IntPtr.Zero);
                GC.KeepAlive(callback);
                return found;
            }
            finally
            {
                FreeLibrary(module);
            }
        }
    }
}
'@
    }

    if (-not [Echo.Build.NativeResourceInspector]::HasGroupIcon($ExecutablePath)) {
        throw "Executable does not contain an embedded Win32 group icon resource: $ExecutablePath"
    }
}

function Assert-EvaluatedProperties {
    param(
        [Parameter(Mandatory)][ValidateSet('GitHub', 'Store')][string]$BuildProfile,
        [Parameter(Mandatory)][string]$RuntimeIdentifier
    )

    $platform = Get-PlatformForRuntime $RuntimeIdentifier
    $arguments = @(
        'msbuild', $script:ProjectPath, '-nologo',
        '-p:Configuration=Release',
        "-p:Platform=$platform",
        "-p:RuntimeIdentifier=$RuntimeIdentifier"
    )

    if ($BuildProfile -eq 'GitHub') {
        $arguments += '-p:BuildingForGitHub=true'
        $arguments += @(
            '-getProperty:WindowsPackageType',
            '-getProperty:EnableMsixTooling',
            '-getProperty:AppxPackage',
            '-getProperty:WindowsAppSDKSelfContained',
            '-getProperty:WindowsAppSdkUndockedRegFreeWinRTInitialize',
            '-getProperty:SelfContained'
            '-getProperty:ApplicationIcon'
            '-getProperty:EchoProductVersion'
        )
    }
    else {
        $arguments += '-p:BuildingForStore=true'
        $arguments += @(
            '-getProperty:WindowsPackageType',
            '-getProperty:EnableMsixTooling',
            '-getProperty:AppxPackage',
            '-getProperty:GenerateAppxPackageOnBuild',
            '-getProperty:WindowsAppSDKSelfContained',
            '-getProperty:WindowsAppSdkDeploymentManagerInitialize',
            '-getProperty:SelfContained'
            '-getProperty:ApplicationIcon'
            '-getProperty:EchoProductVersion'
        )
    }

    $json = & dotnet @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to evaluate MSBuild properties for $BuildProfile/$RuntimeIdentifier."
    }
    $properties = ($json -join "`n") | ConvertFrom-Json
    $values = $properties.Properties

    if ($BuildProfile -eq 'GitHub') {
        $expected = @{
            WindowsPackageType = 'None'
            EnableMsixTooling = 'true'
            AppxPackage = 'false'
            WindowsAppSDKSelfContained = 'true'
            WindowsAppSdkUndockedRegFreeWinRTInitialize = 'true'
            SelfContained = 'true'
            ApplicationIcon = $script:ProductMetadata.ApplicationIcon
            EchoProductVersion = $script:ProductMetadata.Version
        }
    }
    else {
        $expected = @{
            WindowsPackageType = 'MSIX'
            EnableMsixTooling = 'true'
            AppxPackage = 'true'
            GenerateAppxPackageOnBuild = 'true'
            WindowsAppSdkDeploymentManagerInitialize = 'false'
            SelfContained = 'false'
            ApplicationIcon = $script:ProductMetadata.ApplicationIcon
            EchoProductVersion = $script:ProductMetadata.Version
        }
    }

    foreach ($entry in $expected.GetEnumerator()) {
        $actual = [string]$values.($entry.Key)
        if ($actual -ine $entry.Value) {
            throw "Unexpected $($entry.Key) for $BuildProfile/$RuntimeIdentifier. Expected '$($entry.Value)', found '$actual'."
        }
    }
}

function Assert-PriResources {
    param(
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][string]$MakePriPath
    )

    $primaryPri = @(
        (Join-Path $OutputDirectory 'EchoVisualizer.pri'),
        (Join-Path $OutputDirectory 'resources.pri')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if (-not $primaryPri) {
        throw "No primary application PRI was found in $OutputDirectory."
    }

    $dumpPath = Join-Path ([System.IO.Path]::GetTempPath()) ("echo-pri-{0}.xml" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-NativeTool $MakePriPath @('dump', '/if', $primaryPri, '/of', $dumpPath, '/o')
        if (-not (Select-String -LiteralPath $dumpPath -SimpleMatch 'Microsoft.UI.Xaml/Themes/themeresources.xbf' -Quiet)) {
            throw "The application PRI does not contain Microsoft.UI.Xaml/Themes/themeresources.xbf: $primaryPri"
        }
    }
    finally {
        Remove-Item -LiteralPath $dumpPath -Force -ErrorAction SilentlyContinue
    }
}

function Build-GitHubDistribution {
    param(
        [Parameter(Mandatory)][string]$RuntimeIdentifier,
        [Parameter(Mandatory)][string]$MakePriPath
    )

    Write-Stage "Publishing GitHub unpackaged distribution ($RuntimeIdentifier)"
    Import-VisualCppEnvironment -RuntimeIdentifier $RuntimeIdentifier
    Assert-EvaluatedProperties -BuildProfile GitHub -RuntimeIdentifier $RuntimeIdentifier
    $platform = Get-PlatformForRuntime $RuntimeIdentifier
    $output = Join-Path $script:ArtifactsRoot "github\$RuntimeIdentifier"
    if (-not $NoClean) { Remove-SafeArtifactDirectory $output }

    $arguments = @(
        'publish', $script:ProjectPath,
        '-c', 'Release',
        '-r', $RuntimeIdentifier,
        "-p:Platform=$platform",
        '-p:BuildingForGitHub=true',
        "-p:PublishDir=$output\"
    )
    if ($BuildVersion) {
        $arguments += @(
            "-p:Version=$BuildVersion",
            "-p:AssemblyVersion=$BuildVersion",
            "-p:FileVersion=$BuildVersion",
            "-p:InformationalVersion=$BuildVersion"
        )
    }
    Invoke-NativeTool 'dotnet' $arguments

    foreach ($file in @(
        'EchoVisualizer.exe', 'EchoVisualizer.dll', 'EchoCore.dll',
        'coreclr.dll', 'hostfxr.dll', 'Microsoft.WindowsAppRuntime.dll',
        'Microsoft.UI.Xaml.dll'
    )) {
        Assert-FileExists (Join-Path $output $file)
    }
    Assert-PeArchitecture -Path (Join-Path $output 'EchoVisualizer.exe') -RuntimeIdentifier $RuntimeIdentifier
    Assert-PeArchitecture -Path (Join-Path $output 'EchoCore.dll') -RuntimeIdentifier $RuntimeIdentifier
    Invoke-BrandAssetCheck -OutputDirectory (Join-Path $output 'Assets')
    Assert-IcoFrames -Path (Join-Path $output 'Assets\AppIcon.ico')
    Assert-EmbeddedApplicationIcon -ExecutablePath (Join-Path $output 'EchoVisualizer.exe')
    Assert-PriResources -OutputDirectory $output -MakePriPath $MakePriPath
    Write-Host "Validated GitHub distribution: $output" -ForegroundColor Green
}

function Expand-MsixBundle {
    param(
        [Parameter(Mandatory)][string]$BundlePath,
        [Parameter(Mandatory)][string]$MakeAppxPath,
        [Parameter(Mandatory)][string]$RuntimeIdentifier
    )

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("echo-msix-{0}" -f [guid]::NewGuid().ToString('N'))
    $bundleDirectory = Join-Path $temporaryRoot 'bundle'
    $packageDirectory = Join-Path $temporaryRoot 'package'
    $aggregateAssetsDirectory = Join-Path $temporaryRoot 'aggregate-assets'
    New-Item -ItemType Directory -Path $bundleDirectory, $packageDirectory, $aggregateAssetsDirectory | Out-Null

    try {
        Invoke-NativeTool $MakeAppxPath @('unbundle', '/p', $BundlePath, '/d', $bundleDirectory, '/o')
        $platform = Get-PlatformForRuntime $RuntimeIdentifier
        $innerPackage = Get-ChildItem -LiteralPath $bundleDirectory -Filter '*.msix' -File |
            Where-Object { $_.Name -match "_$platform\.msix$" } |
            Select-Object -First 1
        if (-not $innerPackage) {
            $innerPackage = Get-ChildItem -LiteralPath $bundleDirectory -Filter '*.msix' -File | Select-Object -First 1
        }
        if (-not $innerPackage) {
            throw "No inner MSIX package was found in $BundlePath."
        }

        Invoke-NativeTool $MakeAppxPath @('unpack', '/p', $innerPackage.FullName, '/d', $packageDirectory, '/o')

        $packageIndex = 0
        foreach ($bundlePackage in Get-ChildItem -LiteralPath $bundleDirectory -Filter '*.msix' -File) {
            $expandedDirectory = if ($bundlePackage.FullName -eq $innerPackage.FullName) {
                $packageDirectory
            }
            else {
                $packageIndex++
                $resourceDirectory = Join-Path $temporaryRoot "resource-package-$packageIndex"
                New-Item -ItemType Directory -Path $resourceDirectory | Out-Null
                Invoke-NativeTool $MakeAppxPath @('unpack', '/p', $bundlePackage.FullName, '/d', $resourceDirectory, '/o')
                $resourceDirectory
            }

            $assetDirectory = Join-Path $expandedDirectory 'Assets'
            if (-not (Test-Path -LiteralPath $assetDirectory -PathType Container)) {
                continue
            }
            foreach ($asset in Get-ChildItem -LiteralPath $assetDirectory -File) {
                $destination = Join-Path $aggregateAssetsDirectory $asset.Name
                if (Test-Path -LiteralPath $destination -PathType Leaf) {
                    $existingHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                    $incomingHash = (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash
                    if ($existingHash -ne $incomingHash) {
                        throw "Bundle contains conflicting brand asset projections: $($asset.Name)"
                    }
                    continue
                }
                Copy-Item -LiteralPath $asset.FullName -Destination $destination
            }
        }

        return [pscustomobject]@{
            TemporaryRoot = $temporaryRoot
            PackageDirectory = $packageDirectory
            BrandAssetsDirectory = $aggregateAssetsDirectory
        }
    }
    catch {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Assert-MsixManifest {
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [Parameter(Mandatory)][string]$RuntimeIdentifier,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [Parameter(Mandatory)][pscustomobject]$ExpectedIdentity,
        [Parameter(Mandatory)][string]$BrandAssetsDirectory
    )

    $manifestPath = Join-Path $PackageDirectory 'AppxManifest.xml'
    Assert-FileExists $manifestPath
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    $namespace = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('f', $manifest.DocumentElement.NamespaceURI)
    $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $namespace)
    $application = $manifest.SelectSingleNode('/f:Package/f:Applications/f:Application', $namespace)

    $expectedArchitecture = Get-PlatformForRuntime $RuntimeIdentifier
    if ($identity.Name -ne $ExpectedIdentity.Name -or $identity.Publisher -ne $ExpectedIdentity.Publisher) {
        throw "MSIX identity does not match Package.appxmanifest."
    }
    if ($identity.Version -ne $ExpectedVersion) {
        throw "MSIX version mismatch. Expected $ExpectedVersion, found $($identity.Version)."
    }
    if ($identity.ProcessorArchitecture -ine $expectedArchitecture) {
        throw "MSIX architecture mismatch. Expected $expectedArchitecture, found $($identity.ProcessorArchitecture)."
    }
    if ($application.Id -ne $ExpectedIdentity.ApplicationId) {
        throw "MSIX application entry point must retain application id '$($ExpectedIdentity.ApplicationId)'."
    }
    $properties = $manifest.SelectSingleNode('/f:Package/f:Properties', $namespace)
    $visualElements = $application.SelectSingleNode('*[local-name()="VisualElements"]')
    if ($properties.DisplayName -ne $ExpectedIdentity.DisplayName -or
        $properties.PublisherDisplayName -ne $ExpectedIdentity.PublisherDisplayName -or
        $visualElements.DisplayName -ne $ExpectedIdentity.DisplayName) {
        throw 'MSIX display identity does not match canonical product metadata.'
    }

    $dependency = $manifest.SelectNodes('/f:Package/f:Dependencies/f:PackageDependency', $namespace) |
        Where-Object { $_.Name -like 'Microsoft.WindowsAppRuntime*' } |
        Select-Object -First 1
    if (-not $dependency) {
        throw "MSIX package is missing its Microsoft Windows App Runtime framework dependency."
    }

    $capabilities = $manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Capabilities"]/*') |
        ForEach-Object { $_.Name }
    foreach ($requiredCapability in @('runFullTrust', 'microphone')) {
        if ($capabilities -notcontains $requiredCapability) {
            throw "MSIX package is missing capability '$requiredCapability'."
        }
    }

    foreach ($file in @('EchoVisualizer.exe', 'EchoVisualizer.dll', 'EchoCore.dll', 'resources.pri')) {
        Assert-FileExists (Join-Path $PackageDirectory $file)
    }
    if (Test-Path -LiteralPath (Join-Path $PackageDirectory 'Microsoft.UI.Xaml.dll')) {
        throw "Store MSIX unexpectedly contains app-local Microsoft.UI.Xaml.dll; the profile must remain framework-dependent."
    }
    Assert-PeArchitecture -Path (Join-Path $PackageDirectory 'EchoVisualizer.exe') -RuntimeIdentifier $RuntimeIdentifier
    Assert-PeArchitecture -Path (Join-Path $PackageDirectory 'EchoCore.dll') -RuntimeIdentifier $RuntimeIdentifier
    Invoke-BrandAssetCheck -OutputDirectory $BrandAssetsDirectory
    Assert-IcoFrames -Path (Join-Path $PackageDirectory 'Assets\AppIcon.ico')
    Assert-EmbeddedApplicationIcon -ExecutablePath (Join-Path $PackageDirectory 'EchoVisualizer.exe')
}

function Build-StoreDistribution {
    param(
        [Parameter(Mandatory)][string]$RuntimeIdentifier,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$MakeAppxPath,
        [Parameter(Mandatory)][pscustomobject]$ManifestMetadata,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$SigningCertificate
    )

    Write-Stage "Publishing Store MSIX distribution ($RuntimeIdentifier, version $Version)"
    Import-VisualCppEnvironment -RuntimeIdentifier $RuntimeIdentifier
    Assert-EvaluatedProperties -BuildProfile Store -RuntimeIdentifier $RuntimeIdentifier
    $platform = Get-PlatformForRuntime $RuntimeIdentifier
    $output = Join-Path $script:ArtifactsRoot "store-test\$RuntimeIdentifier"
    if (-not $NoClean) { Remove-SafeArtifactDirectory $output }
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $manifestOverride = New-VersionedPackageManifest -Version $Version

    $arguments = @(
        'publish', $script:ProjectPath,
        '-c', 'Release',
        '-r', $RuntimeIdentifier,
        "-p:Platform=$platform",
        '-p:BuildingForStore=true',
        "-p:PackageManifestOverride=$manifestOverride",
        "-p:Version=$Version",
        "-p:AssemblyVersion=$Version",
        "-p:FileVersion=$Version",
        "-p:InformationalVersion=$Version",
        "-p:AppxPackageDir=$output\",
        "-p:AppxPackageVersion=$Version"
    )
    if ($SigningCertificate) {
        $arguments += @(
            '-p:SignMsix=true',
            "-p:PackageCertificateThumbprint=$($SigningCertificate.Thumbprint)"
        )
    }
    else {
        $arguments += '-p:AppxPackageSigningEnabled=false'
    }
    try {
        Invoke-NativeTool 'dotnet' $arguments
    }
    finally {
        Remove-Item -LiteralPath $manifestOverride -Force -ErrorAction SilentlyContinue
    }

    $bundle = Get-ChildItem -LiteralPath $output -Filter '*.msixbundle' -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $bundle) {
        throw "MSIX bundle was not produced under $output."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $bundle.FullName
    if ($SigningCertificate -and $signature.Status -ne 'Valid') {
        throw "Signed MSIX bundle does not have a valid Authenticode signature: $($signature.Status)"
    }
    if (-not $SigningCertificate -and $signature.Status -notin @('NotSigned', 'UnknownError')) {
        throw "Unexpected unsigned MSIX signature status: $($signature.Status)"
    }

    $expanded = Expand-MsixBundle -BundlePath $bundle.FullName -MakeAppxPath $MakeAppxPath -RuntimeIdentifier $RuntimeIdentifier
    try {
        Assert-MsixManifest `
            -PackageDirectory $expanded.PackageDirectory `
            -RuntimeIdentifier $RuntimeIdentifier `
            -ExpectedVersion $Version `
            -ExpectedIdentity $ManifestMetadata `
            -BrandAssetsDirectory $expanded.BrandAssetsDirectory
    }
    finally {
        Remove-Item -LiteralPath $expanded.TemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Validated Store distribution: $($bundle.FullName)" -ForegroundColor Green
    return $bundle.FullName
}

function Invoke-ProcessSmokeTest {
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [int]$Seconds = 10
    )

    Write-Stage "Smoke-testing unpackaged executable for $Seconds seconds"
    $process = Start-Process -FilePath $ExecutablePath -WorkingDirectory (Split-Path $ExecutablePath) -PassThru
    Start-Sleep -Seconds $Seconds
    if ($process.HasExited) {
        $exitCodeBits = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$process.ExitCode), 0)
        throw ('Unpackaged executable exited early with code 0x{0:X8}.' -f $exitCodeBits)
    }
    if (-not $process.CloseMainWindow()) {
        throw "Unpackaged executable did not expose a main window for normal closure."
    }
    if (-not $process.WaitForExit(5000)) {
        Stop-Process -Id $process.Id -Force
        throw "Unpackaged executable did not close normally within five seconds."
    }
}

function Install-AndSmokeTestMsix {
    param(
        [Parameter(Mandatory)][string]$BundlePath,
        [Parameter(Mandatory)][pscustomobject]$ManifestMetadata,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [int]$Seconds = 10
    )

    Write-Stage "Installing and smoke-testing x64 MSIX version $ExpectedVersion"
    $sameVersionPackage = Get-AppxPackage -Name $ManifestMetadata.Name |
        Where-Object { $_.Version.ToString() -eq $ExpectedVersion } |
        Select-Object -First 1
    if ($sameVersionPackage) {
        # AppX rejects different bits with the same package identity/version.
        # -InstallMsix explicitly authorizes replacement of this current-user
        # test package; the freshly validated bundle remains available if the
        # subsequent registration needs to be retried.
        Write-Host "Removing same-version current-user test package: $($sameVersionPackage.PackageFullName)" -ForegroundColor DarkGray
        Remove-AppxPackage -Package $sameVersionPackage.PackageFullName
    }
    Add-AppxPackage -Path $BundlePath -ForceApplicationShutdown -ForceUpdateFromAnyVersion
    $package = Get-AppxPackage -Name $ManifestMetadata.Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $package -or $package.Version.ToString() -ne $ExpectedVersion) {
        throw "Installed MSIX version does not match expected version $ExpectedVersion."
    }

    $existingIds = @(Get-Process -Name 'EchoVisualizer' -ErrorAction SilentlyContinue | ForEach-Object Id)
    Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($package.PackageFamilyName)!App"

    $process = $null
    $deadline = (Get-Date).AddSeconds(15)
    while (-not $process -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $process = Get-Process -Name 'EchoVisualizer' -ErrorAction SilentlyContinue |
            Where-Object { $existingIds -notcontains $_.Id } |
            Select-Object -First 1
    }
    if (-not $process) {
        throw "Installed MSIX did not start from its AppsFolder identity."
    }

    Start-Sleep -Seconds $Seconds
    $process.Refresh()
    if ($process.HasExited) {
        throw "Installed MSIX process exited before the smoke window completed."
    }
    if (-not $process.CloseMainWindow()) {
        throw "Installed MSIX did not expose a main window for normal closure."
    }
    if (-not $process.WaitForExit(5000)) {
        Stop-Process -Id $process.Id -Force
        throw "Installed MSIX did not close normally within five seconds."
    }
}

Push-Location $script:RepoRoot
try {
    Write-Stage 'Verifying build environment'
    foreach ($command in @('dotnet', 'cargo', 'rustc', 'rustup')) {
        Assert-CommandAvailable $command
    }
    Invoke-NativeTool 'dotnet' @('--version')
    Invoke-NativeTool 'rustc' @('--version')
    Invoke-NativeTool 'cargo' @('--version')

    $manifestMetadata = Get-ProductMetadata
    $script:ProductMetadata = $manifestMetadata
    Invoke-BrandAssetCheck
    Assert-IcoFrames -Path (Join-Path $script:RepoRoot 'src\ui\Assets\AppIcon.ico')
    if (-not $PackageVersion) { $PackageVersion = $manifestMetadata.Version }
    Assert-Version $PackageVersion
    if ($BuildVersion) { Assert-Version $BuildVersion }

    if ($InstallMsix -and -not $SignMsix) {
        throw '-InstallMsix requires -SignMsix.'
    }
    if ($InstallMsix -and $Profile -eq 'GitHub') {
        throw '-InstallMsix requires the Store or Both profile.'
    }
    if ($InstallMsix -and $RuntimeIdentifiers -notcontains 'win-x64') {
        throw '-InstallMsix requires win-x64 in RuntimeIdentifiers on this machine.'
    }

    $makePriPath = Find-WindowsSdkTool 'makepri.exe'
    $makeAppxPath = Find-WindowsSdkTool 'makeappx.exe'

    $signingCertificate = $null
    if ($SignMsix) {
        $signingCertificate = Resolve-SigningCertificate `
            -Publisher $manifestMetadata.Publisher `
            -RequestedThumbprint $CertificateThumbprint
        Write-Host "Using signing certificate: $($signingCertificate.Thumbprint) ($($signingCertificate.Subject))"
    }

    foreach ($runtimeIdentifier in $RuntimeIdentifiers) {
        $rustTarget = Get-RustTargetForRuntime $runtimeIdentifier
        $installedTargets = & rustup target list --installed
        if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate installed Rust targets.' }
        if ($installedTargets -notcontains $rustTarget) {
            Invoke-NativeTool 'rustup' @('target', 'add', $rustTarget)
        }
    }

    if (-not $SkipTests) {
        Write-Stage 'Running quality gates'
        Invoke-NativeTool 'cargo' @('fmt', '--manifest-path', 'src/core/Cargo.toml', '--', '--check')
        Invoke-NativeTool 'cargo' @('clippy', '--manifest-path', 'src/core/Cargo.toml', '--', '-D', 'warnings')
        Invoke-NativeTool 'cargo' @('test', '--manifest-path', 'src/core/Cargo.toml')
        Invoke-NativeTool 'dotnet' @(
            'test', 'tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj',
            '-c', 'Release', '-p:Platform=x64'
        )
    }

    if ($Profile -in @('GitHub', 'Both')) {
        foreach ($runtimeIdentifier in $RuntimeIdentifiers) {
            Build-GitHubDistribution -RuntimeIdentifier $runtimeIdentifier -MakePriPath $makePriPath
        }
    }

    $storeBundles = @{}
    if ($Profile -in @('Store', 'Both')) {
        foreach ($runtimeIdentifier in $RuntimeIdentifiers) {
            $storeBundles[$runtimeIdentifier] = Build-StoreDistribution `
                -RuntimeIdentifier $runtimeIdentifier `
                -Version $PackageVersion `
                -MakeAppxPath $makeAppxPath `
                -ManifestMetadata $manifestMetadata `
                -SigningCertificate $signingCertificate
        }
    }

    if ($SmokeTest) {
        if ($Profile -in @('GitHub', 'Both') -and $RuntimeIdentifiers -contains 'win-x64') {
            Invoke-ProcessSmokeTest -ExecutablePath (Join-Path $script:ArtifactsRoot 'github\win-x64\EchoVisualizer.exe')
        }
        if ($InstallMsix) {
            Install-AndSmokeTestMsix `
                -BundlePath $storeBundles['win-x64'] `
                -ManifestMetadata $manifestMetadata `
                -ExpectedVersion $PackageVersion
        }
    }
    elseif ($InstallMsix) {
        Write-Stage "Installing x64 MSIX version $PackageVersion"
        Add-AppxPackage -Path $storeBundles['win-x64'] -ForceApplicationShutdown -ForceUpdateFromAnyVersion
    }

    Write-Host "`nDistribution pipeline completed successfully." -ForegroundColor Green
}
finally {
    Pop-Location
}
