[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$RequireRust,
    [switch]$SkipDotNet,
    [switch]$SkipRust
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rustToolchainBin = Join-Path $env:USERPROFILE '.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin'
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$preferredRustBin = if (Test-Path $rustToolchainBin) { $rustToolchainBin } else { $cargoBin }
if ((Test-Path $preferredRustBin) -and -not (($env:PATH -split ';') -contains $preferredRustBin)) {
    $env:PATH = "$preferredRustBin;$env:PATH"
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$uiProjectPath = Join-Path $repositoryRoot 'src/ui/EchoVisualizer.csproj'
$testProjectPath = Join-Path $repositoryRoot 'tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj'
$productPropsPath = Join-Path $repositoryRoot 'build/Product.props'
$coreManifestPath = Join-Path $repositoryRoot 'src/core/Cargo.toml'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Command
    )

    Write-Host "`n==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

Push-Location $repositoryRoot
try {
    if (-not $SkipDotNet) {
        & (Join-Path $PSScriptRoot 'Test-Toolchains.ps1')
        if (-not (Test-Path -LiteralPath $productPropsPath -PathType Leaf)) {
            throw "UI build prerequisite is missing: $productPropsPath. Restore or recover the repository product metadata before running the full quality gate."
        }
        Invoke-CheckedCommand 'Restore UI project' { dotnet restore $uiProjectPath }
        Invoke-CheckedCommand 'Restore test project' { dotnet restore $testProjectPath }
        Invoke-CheckedCommand 'Build UI project' { dotnet build $uiProjectPath --configuration $Configuration --no-restore '-p:Platform=x64' }

        if (Test-Path -LiteralPath $testProjectPath -PathType Leaf) {
            Invoke-CheckedCommand 'Build test project' { dotnet build $testProjectPath --configuration $Configuration --no-restore '-p:Platform=x64' }
            Invoke-CheckedCommand 'Run .NET tests' { dotnet test $testProjectPath --configuration $Configuration --no-build --no-restore '-p:Platform=x64' }
        }
        else {
            Write-Host '[skipped] .NET tests: configured test project is absent.'
        }
    }

    if (-not $SkipRust) {
        $cargoAvailable = $null -ne (Get-Command cargo -ErrorAction SilentlyContinue)
        $rustcAvailable = $null -ne (Get-Command rustc -ErrorAction SilentlyContinue)
        if ($cargoAvailable -and $rustcAvailable) {
            Invoke-CheckedCommand 'Check Rust formatting' { cargo fmt --manifest-path $coreManifestPath -- --check }
            Invoke-CheckedCommand 'Run Rust lints' { cargo clippy --manifest-path $coreManifestPath --all-targets -- -D warnings }
            Invoke-CheckedCommand 'Run Rust tests' { cargo test --manifest-path $coreManifestPath }
        }
        elseif ($RequireRust) {
            & (Join-Path $PSScriptRoot 'Test-Toolchains.ps1') -RequireRust
        }
        else {
            Write-Warning '[skipped] Rust formatting, clippy, and tests: cargo and/or rustc are unavailable.'
        }
    }

    Write-Host "`nQuality gate completed successfully."
}
finally {
    Pop-Location
}
