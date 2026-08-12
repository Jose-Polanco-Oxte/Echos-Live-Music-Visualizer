# Windows CLI (PowerShell + CMD) Reference

A Windows command-line specialist's guide to writing, debugging, and understanding PowerShell (5.1 and 7+) and CMD/Batch commands. PowerShell thinks in **objects**, CMD thinks in **text**.

## When to use

Use this reference for:

- Writing or debugging a PowerShell script, function, module, or one-liner.
- Writing or debugging a CMD.exe command or `.bat`/`.cmd` script.
- Deciding whether to use PowerShell or CMD for a task.
- Windows system administration: services, processes, event logs, registry, scheduled tasks, networking, users/groups.
- Active Directory, WMI/CIM, group policy, or IIS administration.
- Windows file system operations, ACLs, paths, environment variables, or PATH management.
- PowerShell execution policy, UAC elevation, remoting, or WinRM.
- Converting a bash/Linux command to PowerShell or CMD.

## Scope and anti-goals

**In scope:**
- PowerShell 5.1 / 7+ and CMD/Batch command generation.
- Local Windows system administration: files, services, processes, registry, event logs, scheduled tasks, networking, environment variables, ACLs, UAC/elevation, execution policy.
- Converting common bash idioms to PowerShell/CMD.

**Out of scope (do not use this for):**
- Azure / Entra ID / Microsoft Graph administration (use Azure-specific tooling).
- Exchange Online, Intune, SCCM, IIS deep administration.
- PowerShell DSC, PowerShell module authoring, or compiled binary modules (use the `powershell-scripting.md` reference for authoring).
- Full GUI automation, COM interop beyond simple one-liners, or Windows malware analysis.

**Definitions:**
- *New work* — scripts authored today on Windows 10/11, Server 2016+, or cross-platform scenarios. Use `pwsh.exe` unless the target lacks PowerShell 7.
- *Destructive operation* — any command that deletes, overwrites, stops, restarts, reconfigures system state, or modifies the registry. Always preview with `-WhatIf` first.
- *Critical step* — a step that mutates state, runs an external program, accesses a remote resource, or runs unattended. Use `-ErrorAction Stop` or `try/catch`.
- *Untrusted input* — any value from user chat, web requests, environment variables, files not authored by the user, or command output parsed with regex.

## Core principles

1. **Prefer PowerShell 7** (`pwsh.exe`) for new work. Fall back to Windows PowerShell 5.1 (`powershell.exe`) only when required by legacy modules or the environment.
2. **Avoid ambiguous aliases** in script files and examples. Use `Get-ChildItem`, not `ls`; `Where-Object`, not `?`; `ForEach-Object`, not `%`.
3. **Quote paths that contain spaces**. Prefer `Join-Path` over string concatenation for paths.
4. **Explicit encoding**: use `-Encoding UTF8` when reading/writing text files unless the user explicitly needs another encoding.
5. **Prefer CIM over WMI**: use `Get-CimInstance` instead of `Get-WmiObject`.
6. **Destructive operations first show `-WhatIf`**. For example, give `Remove-Item -Recurse -WhatIf` before the real command.
7. **Use `-ErrorAction Stop` or wrap in `try/catch`** for critical steps. Do not silently ignore errors.
8. **Always consider elevation**: note when a command needs "Run as Administrator".
9. **In CMD/batch**, remember `^` is the line-continuation/escape character and `%` variables are expanded at parse time unless delayed expansion is enabled.

## PowerShell vs CMD: which to choose

| Situation | Recommendation |
|-----------|----------------|
| Modern Windows automation, system info, structured output | **PowerShell 7** |
| Need objects, JSON, REST, .NET, modules | **PowerShell 7** |
| Minimal dependency, very old Windows, or boot/recovery | **CMD / batch** |
| Simple file copy/move, `ping`, `ipconfig`, quick checks | Either; prefer PowerShell for composability |
| Legacy `.bat` maintenance | **CMD** |
| Cross-platform scripting (also runs on macOS/Linux) | **PowerShell 7** |

## Common command patterns

### Files and directories

```powershell
# List files recursively, show size nicely
Get-ChildItem -Path 'C:\My Data' -Recurse -File |
    Select-Object Name, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}} |
    Sort-Object SizeMB -Descending

# Create nested directory safely
New-Item -ItemType Directory -Path 'C:\temp\logs' -Force

# Read/Write UTF-8 text
Get-Content -Path 'C:\temp\in.txt' -Encoding UTF8
'hello' | Out-File -FilePath 'C:\temp\out.txt' -Encoding UTF8
```

### Services and processes

```powershell
# Find stopped services that start automatically
Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }

# Restart a service with confirmation preview
Restart-Service -Name Spooler -WhatIf

# Stop a process by name safely
Stop-Process -Name notepad -WhatIf
```

### Registry

```powershell
# Read a value
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseId

# Create a key and value
New-Item -Path 'HKCU:\Software\MyApp' -Force
Set-ItemProperty -Path 'HKCU:\Software\MyApp' -Name 'InstallDir' -Value 'C:\MyApp'
```

### Event logs

```powershell
# Query System log for errors in last 24 hours
Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddHours(-24)}

# Export to CSV
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} |
    Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Export-Csv -Path 'C:\temp\errors.csv' -Encoding UTF8 -NoTypeInformation
```

### Networking

```powershell
# Test connectivity
Test-Connection -ComputerName 8.8.8.8 -Count 4

# Test TCP port
Test-NetConnection -ComputerName example.com -Port 443

# Get network adapters
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
```

### Environment variables

```powershell
# Read
$env:PATH

# Set for current process
$env:MY_VAR = 'value'

# Persist user-scope environment variable
[Environment]::SetEnvironmentVariable('MY_VAR', 'value', 'User')
```

### WMI / CIM

```powershell
# Modern CIM (preferred over Get-WmiObject)
Get-CimInstance -ClassName Win32_ComputerSystem
Get-CimInstance -Query "SELECT * FROM Win32_Process WHERE Name = 'explorer.exe'"

# Common classes: Win32_Process, Win32_Service, Win32_LogicalDisk,
# Win32_OperatingSystem, Win32_Bios, Win32_NetworkAdapterConfiguration
```

### Scheduled tasks

```powershell
# View scheduled tasks
Get-ScheduledTask

# Create a task
$action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File C:\scripts\job.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -TaskName 'MyJob' -Action $action -Trigger $trigger
```

### CMD equivalents

```batch
:: List files recursively
DIR /S /B "C:\My Data"

:: Check service status
sc query Spooler

:: Query event log (classic, limited)
wevtutil qe System /q:"*[System[(Level=2)]]" /f:text /c:5

:: Test connectivity
ping -n 4 8.8.8.8

:: Test TCP port (PowerShell is easier; if only CMD available, use third-party tools)
```

## Error handling and debugging

### PowerShell

```powershell
$ErrorActionPreference = 'Stop'

try {
    Get-Content -Path 'C:\missing.txt' -ErrorAction Stop
} catch [System.Management.Automation.ItemNotFoundException] {
    Write-Warning "File not found: $_"
} catch {
    Write-Error "Unexpected error: $_"
}

# Record everything to a transcript
Start-Transcript -Path 'C:\temp\transcript.log' -Append
# ... commands ...
Stop-Transcript
```

### CMD / Batch

```batch
@echo off
setlocal enabledelayedexpansion
set "errorlevel=0"

somecommand.exe
if errorlevel 1 (
    echo Command failed with error %errorlevel%
    exit /b %errorlevel%
)
```

## Safety rules

1. For any command that deletes, formats, modifies system state, or changes registry values, **first provide a `-WhatIf` (PowerShell) or dry-run version**.
2. Clearly state when a command requires **elevation / Run as Administrator**.
3. Do not suggest disabling execution policy globally with `Set-ExecutionPolicy Unrestricted`. Prefer `RemoteSigned` or bypassing scope for a single invocation: `pwsh -ExecutionPolicy Bypass -File script.ps1` (or `powershell` on 5.1-only systems).
4. Avoid `Invoke-Expression` on untrusted input.
5. Be careful with `-Recurse` and wildcards in `Remove-Item`.

## Expected output format

For each user request, respond with:

1. **Brief answer** (one sentence about what the command does).
2. **The command or script** in a fenced code block, clearly labeled as PowerShell or CMD.
3. **Explanation** of key parts.
4. **Caveats / safety notes** (elevation, `-WhatIf`, execution policy, etc.).
5. If relevant, a **CMD alternative** or **PowerShell alternative**.

Example:

> To list all automatic services that are currently stopped:
>
> ```powershell
> Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
> ```
>
> `Get-Service` returns service objects; `Where-Object` filters on the `StartType` and `Status` properties. No elevation needed unless you intend to start them.
>
> CMD equivalent (less structured):
> ```batch
> sc query type= service state= stopped
> ```

## Agent execution context

If you are running on macOS/Linux, you generally cannot execute PowerShell or CMD commands locally unless `pwsh` is installed. In that case:

1. Prefer generating the command/script for the user to run.
2. If the target is a remote Windows host, suggest WinRM/SSH remoting (`Invoke-Command`, `Enter-PSSession`, or `ssh admin@host`).
3. Destructive or elevation-requiring commands must be confirmed by the user; agents cannot click UAC prompts.