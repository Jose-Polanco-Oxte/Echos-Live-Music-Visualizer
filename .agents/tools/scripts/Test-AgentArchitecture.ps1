[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location $repositoryRoot

function Assert-Path {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [ValidateSet('Leaf', 'Container')] [string]$Type = 'Leaf'
    )

    $fullPath = Join-Path $repositoryRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType $Type)) {
        throw "Required $Type is missing: $Path"
    }
}

function Assert-NotIgnored {
    param([Parameter(Mandatory = $true)] [string]$Path)

    git check-ignore -q -- $Path 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "Stable contract is unexpectedly ignored by Git: $Path"
    }
}

function Assert-Ignored {
    param([Parameter(Mandatory = $true)] [string]$Path)

    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $Path))) {
        return
    }

    git check-ignore -q -- $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Local/generated path is unexpectedly visible to Git: $Path"
    }
}

$stablePaths = @(
    '.agents/AGENTS.md',
    '.agents/context/project.md',
    '.agents/rules/general.md',
    '.agents/rules/testing.md',
    '.agents/skills/using-agent-skills/SKILL.md',
    '.agents/skills/sub-agents-execution/SKILL.md',
    '.agents/skills/sub-agents-execution/scripts/run_subagent.py',
    '.agents/tools/scripts/Test-Toolchains.ps1',
    '.agents/tools/scripts/Test-AgentArchitecture.ps1',
    '.agents/tools/scripts/Invoke-QualityGate.ps1',
    'docs/public/plans/INDEX.md'
)

foreach ($path in $stablePaths) {
    Assert-Path -Path $path
    Assert-NotIgnored -Path $path
}

Assert-Path -Path '.agents/roles' -Type Container
Assert-Path -Path 'docs/public/decisions' -Type Container
Assert-Path -Path '.agents/state/PROJECT-HANDOFF.template.md'
Assert-Ignored -Path '.agents/state/PROJECT-HANDOFF.md'
Assert-Ignored -Path '.agents/state/CONTEXT-SNAPSHOT.md'
Assert-Ignored -Path '.agents/tools/scripts/scratch/audit.py'

$expectedRoles = @(
    'general-project-engineer',
    'agent-architecture-auditor',
    'rust-dsp-specialist',
    'winui-visualizer-specialist',
    'requirements-traceability-maintainer',
    'quality-gate-validator'
)
$roleFiles = @(Get-ChildItem (Join-Path $repositoryRoot '.agents/roles') -File |
    Where-Object { $_.Extension -in @('.md', '.txt') } |
    ForEach-Object { $_.BaseName })
$actualRoles = (@($roleFiles | Sort-Object) -join ',')
$requiredRoles = (@($expectedRoles | Sort-Object) -join ',')
if ($actualRoles -ne $requiredRoles) {
    throw "Role catalog mismatch. Expected: $($expectedRoles -join ', '); found: $($roleFiles -join ', ')"
}

foreach ($role in $expectedRoles) {
    $rolePath = Join-Path $repositoryRoot ".agents/roles/$role.md"
    $content = Get-Content -LiteralPath $rolePath -Raw
    if ($content -notmatch '(?m)^---\s*\r?\n' -or $content -notmatch '(?m)^permission:\s*(read-only|safe-edit|yolo)\s*$') {
        throw "Role has invalid frontmatter: $rolePath"
    }
}

$forbiddenReferences = @(
    '.agents/rules/general.md',
    '.agents/rules/releases.md',
    '.agents/skills/using-agent-skills/SKILL.md',
    '.agents/skills/sub-agents-execution/SKILL.md',
    '.agents/skills/decision-writer/SKILL.md',
    '.agents/skills/issues-writer/SKILL.md',
    '.agents/skills/dotnet/SKILL.md'
)
$forbiddenPatterns = @(
    'subagent-work-divider',
    'PROYECT-HANDOFF',
    'docs/pending-features/',
    'docs/traceability/',
    'definition-of-done\.md',
    '(?m)Save as:\s*`?/spec/spec-process-cicd-'
)
foreach ($path in $forbiddenReferences) {
    $text = Get-Content -LiteralPath (Join-Path $repositoryRoot $path) -Raw
    foreach ($pattern in $forbiddenPatterns) {
        if ($text -match $pattern) {
            throw "Forbidden active reference '$pattern' found in $path"
        }
    }
}

$rootInstructions = Get-Content -LiteralPath (Join-Path $repositoryRoot 'AGENTS.md') -Raw
if ($rootInstructions -notmatch 'Build-Distributions\.ps1') {
    throw 'Root AGENTS.md does not reference scripts/Build-Distributions.ps1.'
}

$powerShellFiles = Get-ChildItem $repositoryRoot -Recurse -File -Filter *.ps1 |
    Where-Object { $_.FullName -notmatch '[\\/](target|bin|obj|\.git|scratch)[\\/]' }
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        throw "PowerShell parse errors found in $($file.FullName): $($parseErrors[0].Message)"
    }
}

Write-Host "Agent architecture validation passed. Roles: $($expectedRoles.Count); PowerShell files parsed: $($powerShellFiles.Count)."
