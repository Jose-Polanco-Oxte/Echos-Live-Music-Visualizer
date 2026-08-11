[CmdletBinding()]
param(
    [switch]$RequireRust
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$requiredPaths = @(
    (Join-Path $repositoryRoot 'global.json'),
    (Join-Path $repositoryRoot 'src\core\Cargo.toml'),
    (Join-Path $repositoryRoot 'src\ui\EchoVisualizer.csproj')
)

foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required project path is missing: $path"
    }
}

function Get-ToolVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    $output = @(& $command.Source @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Name $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }

    return [string]::Join(' ', ($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }))
}

$dotnetVersion = Get-ToolVersion -Name 'dotnet' -Arguments @('--version')
if ($null -eq $dotnetVersion) {
    throw 'Required .NET SDK command was not found on PATH.'
}

$cargoVersion = Get-ToolVersion -Name 'cargo' -Arguments @('--version')
$rustcVersion = Get-ToolVersion -Name 'rustc' -Arguments @('--version')

if ($RequireRust -and ($null -eq $cargoVersion -or $null -eq $rustcVersion)) {
    throw 'Rust is required but cargo and/or rustc was not found on PATH.'
}

Write-Host "Toolchain validation passed. .NET: $dotnetVersion"
if ($null -ne $cargoVersion -and $null -ne $rustcVersion) {
    Write-Host "Rust: $cargoVersion; $rustcVersion"
}
else {
    Write-Warning 'Rust is unavailable; Rust checks may be skipped unless -RequireRust is used.'
}
