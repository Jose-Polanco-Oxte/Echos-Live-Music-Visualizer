# PowerShell Gallery & Module Reference

**PowerShell Gallery** (https://www.powershellgallery.com) is the central repository for PowerShell modules, scripts, and DSC resources.

**PSResourceGet** (`Microsoft.PowerShell.PSResourceGet`) is the modern replacement for PowerShellGet:
- Ships with PowerShell 7.4+
- Faster and more reliable than legacy PowerShellGet
- Uses `*-PSResource` cmdlet naming

### Legacy vs Modern Cmdlets
| Legacy (PowerShellGet) | Modern (PSResourceGet) |
|------------------------|------------------------|
| `Find-Module` | `Find-PSResource` |
| `Install-Module` | `Install-PSResource` |
| `Update-Module` | `Update-PSResource` |
| `Uninstall-Module` | `Uninstall-PSResource` |
| `Get-InstalledModule` | `Get-InstalledPSResource` |
| `Publish-Module` | `Publish-PSResource` |

## Setup

### Check Installed Version
```powershell
Get-Module -Name PowerShellGet -ListAvailable
Get-Module -Name Microsoft.PowerShell.PSResourceGet -ListAvailable
```

### Install/Update PSResourceGet
```powershell
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force
Update-Module -Name Microsoft.PowerShell.PSResourceGet
```

### Configure Repository
```powershell
Get-PSResourceRepository                 # view registered repositories
Register-PSResourceRepository -PSGallery # register PSGallery if not present
Set-PSResourceRepository -Name PSGallery -Priority 50   # lower = higher priority
Set-PSResourceRepository -Name PSGallery -Trusted       # avoid trust prompts
```

## Finding Modules

```powershell
# Basic search
Find-PSResource -Name 'Az.Compute'

# Wildcards
Find-PSResource -Name 'Az.*'

# Search by tag
Find-PSResource -Tag 'Azure', 'Cloud'

# All versions
Find-PSResource -Name 'Pester' -Version '*'

# Version range
Find-PSResource -Name 'Az' -Version '[5.0,7.0)' -Prerelease

# Find by command / DSC resource
Find-PSResource -CommandName 'Invoke-RestMethod'
Find-PSResource -DscResourceName 'File' -Repository PSGallery
```

### Version Range Syntax (NuGet)
| Syntax | Meaning |
|--------|---------|
| `1.0.0` | Exact version |
| `[1.0,2.0]` | >= 1.0 AND <= 2.0 |
| `[1.0,2.0)` | >= 1.0 AND < 2.0 |
| `(1.0,)` | > 1.0 |
| `[,2.0]` | <= 2.0 |

## Installing Modules

```powershell
# Latest stable
Install-PSResource -Name 'Az.Compute'

# Specific version / prerelease
Install-PSResource -Name 'Pester' -Version '5.0.0'
Install-PSResource -Name 'Az' -Prerelease

# Scope
Install-PSResource -Name 'PSReadLine' -Scope CurrentUser   # no admin
Install-PSResource -Name 'PSReadLine' -Scope AllUsers      # requires admin

# Trust repository for this install
Install-PSResource -Name 'Module' -TrustRepository
```

## Managing Modules

```powershell
# List / filter installed
Get-InstalledPSResource
Get-InstalledPSResource -Name 'Az.*'

# Update
Update-PSResource -Name 'Az.Compute'
Update-PSResource -Name '*'        # all

# Uninstall (version-specific)
Uninstall-PSResource -Name 'Pester' -Version '4.0.0'

# Save without installing (offline use)
Save-PSResource -Name 'Az.Compute' -Path 'C:\OfflineModules'
```

## Publishing Modules

```powershell
# Manifest requirements
@{
    RootModule        = 'MyModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    Author            = 'Your Name'
    Description       = 'Module description'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-MyFunction', 'Set-MyFunction')
    Tags              = @('Utility', 'Automation')
}

# Publish (API key from gallery account settings)
Publish-PSResource -Path './MyModule' -ApiKey $apiKey -Repository PSGallery

# Dry run
Publish-PSResource -Path './MyModule' -ApiKey $apiKey -WhatIf
```

## Common Patterns

### Install if Missing
```powershell
function Ensure-Module {
    param([string]$Name, [string]$MinVersion)

    $installed = Get-InstalledPSResource -Name $Name -ErrorAction SilentlyContinue

    if (-not $installed -or ($MinVersion -and $installed.Version -lt $MinVersion)) {
        Install-PSResource -Name $Name -Scope CurrentUser -TrustRepository
    }

    Import-Module $Name
}

Ensure-Module -Name 'Az.Compute' -MinVersion '5.0.0'
```

### Bulk Install from List
```powershell
$modules = @(
    @{ Name = 'Pester'; Version = '5.0.0' }
    @{ Name = 'PSReadLine' }
    @{ Name = 'Az.Accounts' }
)

foreach ($mod in $modules) {
    $params = @{
        Name            = $mod.Name
        Scope           = 'CurrentUser'
        TrustRepository = $true
    }
    if ($mod.Version) { $params.Version = $mod.Version }

    Install-PSResource @params
}
```

## Search-Gallery.ps1 Helper

The bundled `scripts/Search-Gallery.ps1` wraps `Find-PSResource` (with legacy `Find-Module` fallback) for formatted module search:

```powershell
.\scripts\Search-Gallery.ps1 -Name 'Az.*'
.\scripts\Search-Gallery.ps1 -Tag 'Azure', 'Cloud' -First 10
.\scripts\Search-Gallery.ps1 -Command 'Invoke-RestMethod'
.\scripts\Search-Gallery.ps1 -DscResource 'File' -First 5
```

Parameters: `-Name` (wildcards), `-Tag`, `-Command`, `-DscResource`, `-Type` (Module/Script/All), `-Prerelease`, `-First` (default 20).

## Module Recommendations

These are common starting points — **always verify via the Live Verification workflow before recommending**:

| Category | Popular Modules |
|----------|----------------|
| **Azure** | `Az`, `Az.Compute`, `Az.Storage` |
| **Testing** | `Pester`, `PSScriptAnalyzer` |
| **Console** | `PSReadLine`, `Terminal-Icons` |
| **Secrets** | `Microsoft.PowerShell.SecretManagement` |
| **Web** | `Pode` (web server), `PoshRSJob` (async) |
| **GUI** | `WPFBot3000`, `PSGUI` |

## Useful Links

- **PowerShell Gallery**: https://www.powershellgallery.com
- **Gallery Status**: https://raw.githubusercontent.com/PowerShell/PowerShellGallery/master/psgallery_status.md
- **Module Browser**: https://learn.microsoft.com/en-us/powershell/module/
- **PSResourceGet Docs**: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/