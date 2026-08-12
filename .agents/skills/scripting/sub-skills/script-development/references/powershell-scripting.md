# PowerShell Scripting Reference

Develop production-quality PowerShell scripts, tools, and functions using Microsoft best practices.

## Script Structure

```powershell
#Requires -Version 5.1

<#
.SYNOPSIS
    Brief description.
.DESCRIPTION
    Detailed description.
.PARAMETER Name
    Parameter description.
.EXAMPLE
    Example-Usage -Name 'Value'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [switch]$Force
)

begin {
    # One-time setup
}

process {
    foreach ($item in $Name) {
        # Per-item processing
    }
}

end {
    # Cleanup
}
```

## Function Template

```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('CN')]
        [string]$ComputerName = $env:COMPUTERNAME,

        [switch]$PassThru
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Action')) {
            # Implementation
            if ($PassThru) { Write-Output $result }
        }
    }
}
```

## Workflow

### 1. Naming and Conventions
- **Verb-Noun** format with approved verbs (`Get-Verb`)
- **Strong typing** with validation attributes
- **Pipeline support** via `ValueFromPipeline`
- **-WhatIf/-Confirm** for destructive operations

### 2. Parameter Design
```powershell
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [ValidateRange(1, 100)]
    [int]$Count = 10,

    [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
    [string]$LogLevel = 'Info',

    [switch]$Force,

    [nullable[bool]]$Enabled  # Three states: true, false, unspecified
)
```

### 3. Parameter Sets
```powershell
[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(ParameterSetName = 'ByName', Position = 0)]
    [string]$Name,

    [Parameter(ParameterSetName = 'ByID')]
    [int]$ID,

    [Parameter(ParameterSetName = 'ByObject', ValueFromPipeline)]
    [PSObject]$InputObject
)
```

### Common Parameters to Support
| Parameter | Use Case |
|-----------|----------|
| `-Force` | Override warnings/protections |
| `-PassThru` | Return modified objects |
| `-WhatIf` | Preview changes without executing |
| `-Confirm` | Prompt before executing |
| `-Verbose` | Detailed operational info |

### Path Parameters
```powershell
param(
    [Parameter(ParameterSetName = 'Path')]
    [SupportsWildcards()]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'LiteralPath')]
    [Alias('PSPath')]
    [string[]]$LiteralPath
)
```

## Pipeline Support

### Accept Pipeline Input
```powershell
param(
    [Parameter(ValueFromPipeline)]
    [string[]]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string]$Path
)

process {
    foreach ($item in $Name) {
        # Process each item immediately
        Write-Output $result
    }
}
```

### Write Objects Immediately
```powershell
# Good - stream output
foreach ($item in $collection) {
    $result = Process-Item $item
    Write-Output $result
}

# Bad - buffer then output
$results = @()
foreach ($item in $collection) {
    $results += Process-Item $item
}
$results
```

## Key Patterns

### Error Handling
```powershell
try {
    $result = Get-Content -Path $Path -ErrorAction Stop
}
catch [System.IO.FileNotFoundException] {
    Write-Error "File not found: $Path"
    return
}
catch [System.UnauthorizedAccessException] {
    Write-Error "Access denied: $Path"
    return
}
catch {
    Write-Error "Unexpected error: $_"
    throw
}
```

### Terminating vs Non-Terminating Errors
```powershell
# Terminating - stops execution
throw "Critical error occurred"
$PSCmdlet.ThrowTerminatingError($errorRecord)

# Non-terminating - continues execution
Write-Error "Problem with item: $item"
$PSCmdlet.WriteError($errorRecord)
```

### Feedback Methods
```powershell
Write-Warning "File will be overwritten"                 # potential unintended consequences
Write-Verbose "Processing file: $Path"                   # requires -Verbose
Write-Debug   "Variable state: $($var | ConvertTo-Json)" # requires -Debug
Write-Progress -Activity "Processing" -Status "Item $i of $total" -PercentComplete (($i / $total) * 100)
```

### Splatting for Readability
```powershell
$params = @{
    Path        = $sourcePath
    Destination = $destPath
    Recurse     = $true
    Force       = $true
    ErrorAction = 'Stop'
}
Copy-Item @params
```

### Stream Output Immediately
```powershell
foreach ($item in $collection) {
    Process-Item $item | Write-Output
}
```

## Output Patterns

### Return Typed Objects
```powershell
[PSCustomObject]@{
    PSTypeName = 'MyModule.ServerInfo'
    Name       = $server.Name
    Status     = $server.Status
    IPAddress  = $server.IP
}
```

### PassThru Pattern
```powershell
function Set-ItemProperty {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Value,
        [switch]$PassThru
    )

    $item.Property = $Value

    if ($PassThru) {
        Write-Output $item
    }
}
```

### ShouldProcess Pattern
```powershell
function Remove-Item {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Path)

    if ($PSCmdlet.ShouldProcess($Path, 'Delete')) {
        # Perform deletion
    }
}
```

## Code Style

- **Avoid aliases in scripts**: use `Get-ChildItem`, not `ls`; `Where-Object`, not `?`; `ForEach-Object`, not `%`.
- **Use explicit parameter names**: `Get-Process -Name 'notepad'`, not positional.
- **Natural line continuation**: break after operators or pipeline characters; avoid backticks.
- **Comment-based help** for every function (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).

```powershell
function Get-ServerStatus {
    <#
    .SYNOPSIS
        Gets the status of specified servers.

    .DESCRIPTION
        Retrieves operational status including CPU, memory,
        and network information from remote servers.

    .PARAMETER Name
        The server name(s) to query.

    .EXAMPLE
        Get-ServerStatus -Name 'Server01'

        Gets status for Server01.

    .EXAMPLE
        'Server01', 'Server02' | Get-ServerStatus

        Gets status for multiple servers via pipeline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name
    )
    # Implementation
}
```

## Live Verification

Verify module availability and cmdlet syntax against live sources when accuracy is critical. Do not rely on training data for module existence or exact syntax.

**Tools available:**
- **WebFetch** — retrieve and parse documentation URLs (PowerShell Gallery pages, Microsoft Learn).
- **WebSearch** — find correct URLs when the exact path is unknown or to confirm module existence.

### When Verification is Required

| Scenario | Action |
|----------|--------|
| User asks "does module X exist?" | **MUST** verify via PowerShell Gallery |
| Recommending a specific module | **MUST** verify it exists and isn't deprecated |
| Providing exact cmdlet syntax | **SHOULD** verify against Microsoft Learn |
| Module version requirements | **MUST** check gallery for current version |
| General best practices | Static references are sufficient |

### Step 1: Verify Module on PowerShell Gallery
- **WebFetch URL**: `https://www.powershellgallery.com/packages/{ModuleName}`
- **Extract**: module name, latest version, last updated date, total downloads, deprecation/unlisted status.
- **If 404/error**: use WebSearch `{ModuleName} PowerShell module site:powershellgallery.com`.

### Step 2: Verify Cmdlet Syntax
- **WebSearch**: `{Cmdlet-Name} cmdlet site:learn.microsoft.com/en-us/powershell`.
- **WebFetch** the returned URL, extracting complete syntax, required vs optional parameters, and version requirements.
- For PSResourceGet cmdlets, fetch raw markdown directly from `https://raw.githubusercontent.com/MicrosoftDocs/powershell-docs-psget/live/powershell-gallery/powershellget-3.x/Microsoft.PowerShell.PSResourceGet/{Cmdlet-Name}.md`.

### Step 3: Fallback Strategies
If web tools are unavailable:
1. Run the bundled `scripts/Search-Gallery.ps1 -Name '<ModuleName>'` from this skill for module checks.
2. Suggest the user run locally: `Get-Help Cmdlet-Name -Full` and `Get-Command Cmdlet-Name -Syntax`.
3. State uncertainty explicitly: > "I wasn't able to verify this against live documentation. Please confirm the module exists by running: `Find-PSResource -Name 'ModuleName'`"

**Good** (verified with live data):
> "The ImportExcel module (v7.8.10, updated Oct 2024, 17M+ downloads) provides Export-Excel for creating spreadsheets without Excel installed."

**Bad** (unverified claim):
> "Use the Excel-Tools module to export data." ← May not exist!

## Documentation Resources

- **PowerShell Docs**: https://learn.microsoft.com/en-us/powershell/
- **Module Browser**: https://learn.microsoft.com/en-us/powershell/module/
- **PowerShell Gallery**: https://www.powershellgallery.com
- **GitHub Docs (raw)**: https://raw.githubusercontent.com/MicrosoftDocs/PowerShell-Docs/live/reference/
- **PSResourceGet Docs (raw)**: https://raw.githubusercontent.com/MicrosoftDocs/powershell-docs-psget/live/powershell-gallery/powershellget-3.x/Microsoft.PowerShell.PSResourceGet/