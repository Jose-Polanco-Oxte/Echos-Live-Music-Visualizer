param(
    [int]$CommitCount = 8,
    [switch]$RunBuild,
    [switch]$RunTests,
    [string]$OutputPath = ".agents/state/CONTEXT-SNAPSHOT.md"
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Title,
        [string[]]$Content
    )

    [void]$Builder.AppendLine("## $Title")
    [void]$Builder.AppendLine()

    if ($null -eq $Content -or $Content.Count -eq 0) {
        [void]$Builder.AppendLine("_None._")
    }
    else {
        [void]$Builder.AppendLine('```text')

        foreach ($line in $Content) {
            [void]$Builder.AppendLine($line)
        }

        [void]$Builder.AppendLine('```')
    }

    [void]$Builder.AppendLine()
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $result = & git @Arguments 2>$null
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')"
    }

    return @($result)
}

# ---------------------------------------------------------------------------
# Locate repository
# ---------------------------------------------------------------------------

try {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
}
catch {
    throw "This script must be executed inside a Git repository."
}

if (-not $repoRoot) {
    throw "Unable to determine Git repository root."
}

Set-Location $repoRoot

$outputFullPath = Join-Path $repoRoot $OutputPath
$outputDirectory = Split-Path -Parent $outputFullPath

if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Repository state
# ---------------------------------------------------------------------------

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"

$branch = (Invoke-Git @("branch", "--show-current")) -join ""

if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "(detached HEAD)"
}

$head = (Invoke-Git @("rev-parse", "--short", "HEAD")) -join ""

$status = Invoke-Git @(
    "status",
    "--short",
    "--branch"
)

$recentCommits = Invoke-Git @(
    "log",
    "-n",
    "$CommitCount",
    "--date=short",
    "--pretty=format:%h | %ad | %an | %s"
)

$trackedChanges = Invoke-Git @(
    "diff",
    "--name-status"
)

$stagedChanges = Invoke-Git @(
    "diff",
    "--cached",
    "--name-status"
)

$diffStat = Invoke-Git @(
    "diff",
    "--stat"
)

$stagedDiffStat = Invoke-Git @(
    "diff",
    "--cached",
    "--stat"
)

$untrackedFiles = Invoke-Git @(
    "ls-files",
    "--others",
    "--exclude-standard"
)

$ignoredFilesSample = @(
    & git ls-files `
        --others `
        --ignored `
        --exclude-standard 2>$null |
        Select-Object -First 50
)

$remotes = Invoke-Git @(
    "remote",
    "-v"
)

# ---------------------------------------------------------------------------
# Implementation plan discovery
# ---------------------------------------------------------------------------

$plansIndexPath = Join-Path $repoRoot "docs/public/plans/INDEX.md"
$plansIndex = @()
if (Test-Path $plansIndexPath) {
    $plansIndex = @(Get-Content -Path $plansIndexPath -Encoding UTF8)
}
else {
    $plansIndex = @("_No implementation plan index found at docs/public/plans/INDEX.md_")
}

# ---------------------------------------------------------------------------
# Project discovery
# ---------------------------------------------------------------------------

$solutionFiles = @(
    Get-ChildItem `
        -Path $repoRoot `
        -Recurse `
        -File `
        -Include *.sln, *.slnx `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj|\.git|\.vs)[\\/]'
    } |
    ForEach-Object {
        $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    }
)

$projectFiles = @(
    Get-ChildItem `
        -Path $repoRoot `
        -Recurse `
        -File `
        -Include *.csproj, *.fsproj, *.vbproj `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj|\.git|\.vs)[\\/]'
    } |
    ForEach-Object {
        $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    }
)

# ---------------------------------------------------------------------------
# Optional validation
# ---------------------------------------------------------------------------

$buildResult = @()
$testResult = @()

if ($RunBuild) {
    Write-Host "Running build..." -ForegroundColor Cyan

    $buildOutput = @(& dotnet build --nologo 2>&1)
    $buildExitCode = $LASTEXITCODE

    $buildResult += "Exit code: $buildExitCode"
    $buildResult += ""
    $buildResult += $buildOutput

    if ($buildExitCode -ne 0) {
        Write-Warning "Build failed. Snapshot will still be generated."
    }
}

if ($RunTests) {
    Write-Host "Running tests..." -ForegroundColor Cyan

    $testOutput = @(& dotnet test --nologo --no-restore 2>&1)
    $testExitCode = $LASTEXITCODE

    $testResult += "Exit code: $testExitCode"
    $testResult += ""
    $testResult += $testOutput

    if ($testExitCode -ne 0) {
        Write-Warning "Tests failed. Snapshot will still be generated."
    }
}

# ---------------------------------------------------------------------------
# Generate snapshot
# ---------------------------------------------------------------------------

$builder = [System.Text.StringBuilder]::new()

[void]$builder.AppendLine("# Context Snapshot")
[void]$builder.AppendLine()
[void]$builder.AppendLine("> Auto-generated repository state for agent context compaction.")
[void]$builder.AppendLine(">")
[void]$builder.AppendLine("> This file is ephemeral evidence, not the project's source of truth.")
[void]$builder.AppendLine("> Reconcile it with `PROJECT-HANDOFF.md` for global state and the selected active plan for detailed execution state.")
[void]$builder.AppendLine()

[void]$builder.AppendLine("Generated: **$timestamp**  ")
[void]$builder.AppendLine("Branch: **$branch**  ")
[void]$builder.AppendLine("HEAD: **$head**")
[void]$builder.AppendLine()

Write-Section $builder "Git status" $status

Write-Section $builder "Staged changes" $stagedChanges

Write-Section $builder "Unstaged tracked changes" $trackedChanges

Write-Section $builder "Untracked files" $untrackedFiles

Write-Section $builder "Unstaged diff summary" $diffStat

Write-Section $builder "Staged diff summary" $stagedDiffStat

Write-Section $builder "Recent commits" $recentCommits

Write-Section $builder "Git remotes" $remotes

Write-Section $builder "Implementation plans index (docs/public/plans/INDEX.md)" $plansIndex

Write-Section $builder "Solutions" $solutionFiles

Write-Section $builder "Projects" $projectFiles

if ($ignoredFilesSample.Count -gt 0) {
    Write-Section `
        $builder `
        "Ignored files sample (maximum 50)" `
        $ignoredFilesSample
}

if ($RunBuild) {
    Write-Section $builder "Build validation" $buildResult
}
else {
    [void]$builder.AppendLine("## Build validation")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("_Not executed. Run this script with `-RunBuild` to include it._")
    [void]$builder.AppendLine()
}

if ($RunTests) {
    Write-Section $builder "Test validation" $testResult
}
else {
    [void]$builder.AppendLine("## Test validation")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("_Not executed. Run this script with `-RunTests` to include it._")
    [void]$builder.AppendLine()
}

# ---------------------------------------------------------------------------
# Agent instructions
# ---------------------------------------------------------------------------

[void]$builder.AppendLine("## Agent compaction instructions")
[void]$builder.AppendLine()
[void]$builder.AppendLine("Use this snapshot together with the current repository state.")
[void]$builder.AppendLine()
[void]$builder.AppendLine("Before treating conversational context as disposable:")
[void]$builder.AppendLine()
[void]$builder.AppendLine("1. Read `.agents/state/PROJECT-HANDOFF.md`.")
[void]$builder.AppendLine("2. Read `docs/public/plans/INDEX.md` and, for plan-driven work, the selected active plan in full.")
[void]$builder.AppendLine("3. Reconcile the snapshot, global handoff, living plan, and actual repository.")
[void]$builder.AppendLine("4. Update the active plan's Current State Snapshot, checkpoint, validation evidence, and Handoff Snapshot when plan state changed.")
[void]$builder.AppendLine("5. Update `PROJECT-HANDOFF.md` with only concise global state and the active-plan link; do not duplicate plan checkpoints or detailed execution state.")
[void]$builder.AppendLine("6. Remove obsolete or superseded information from the global handoff.")
[void]$builder.AppendLine("7. Do not copy large logs or diffs into either handoff.")
[void]$builder.AppendLine("8. Treat repository files as the source of truth.")
[void]$builder.AppendLine("9. After the living plan and global handoff are current, previous conversational implementation history may be treated as disposable.")
[void]$builder.AppendLine()

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

$builder.ToString() |
    Set-Content `
        -Path $outputFullPath `
        -Encoding UTF8

Write-Host ""
Write-Host "Context snapshot generated:" -ForegroundColor Green
Write-Host "  $outputFullPath"
Write-Host ""
Write-Host "Branch: $branch"
Write-Host "HEAD:   $head"
Write-Host ""

if ($RunBuild) {
    Write-Host "Build exit code: $buildExitCode"
}

if ($RunTests) {
    Write-Host "Tests exit code: $testExitCode"
}
