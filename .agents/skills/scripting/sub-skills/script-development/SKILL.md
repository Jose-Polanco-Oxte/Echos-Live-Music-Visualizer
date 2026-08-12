---
name: script-development
description: >-
  Develop, review, and debug Windows shell automation and scripts. Covers
  PowerShell scripting best practices, PowerShell module/GUI development and
  Gallery usage, PowerShell + CMD Windows CLI administration, and converting
  screen recordings of manual processes into working automation. Use when
  writing PowerShell code, creating Windows Forms/WPF interfaces, working with
  PowerShell Gallery modules, running or debugging Windows administration
  commands, converting bash to PowerShell/CMD, or automating a recorded manual
  process. Load the matching reference for the task at hand.
---

# Script Development

Develop, review, and debug Windows scripts and shell automation using
production-quality practices.

## Reference documents

This skill is split across modular reference files in `references/`. Load only
the document(s) relevant to the current task.

| Reference | Contents | Load when |
| --- | --- | --- |
| [`references/powershell-scripting.md`](references/powershell-scripting.md) | Script/function structure, parameter design, pipeline support, error handling, output patterns, code style, live module/cmdlet verification. | Writing or reviewing PowerShell scripts/functions/modules. |
| [`references/powershell-gallery.md`](references/powershell-gallery.md) | PSResourceGet vs PowerShellGet, finding/installing/managing/publishing modules, `Search-Gallery.ps1` helper. | Working with PowerShell Gallery modules. |
| [`references/powershell-gui.md`](references/powershell-gui.md) | Windows Forms, WPF/XAML, controls, layout, events, GUI templates. | Building PowerShell GUIs or dialogs. |
| [`references/windows-cli.md`](references/windows-cli.md) | PowerShell + CMD/Batch command generation, Windows administration (files, services, registry, event logs, scheduled tasks, networking, WMI/CIM), safety rules. | Running or writing Windows CLI commands/administration. |
| [`references/automate-this.md`](references/automate-this.md) | Analyzing a screen recording of a manual process, reconstructing the workflow, and proposing/building automation at three tiers. | Automating a recorded manual process. |

## How to use

1. Choose the matching reference from the table above.
2. Follow its instructions; additional supporting files live in `scripts/`.
3. For PowerShell module recommendations or cmdlet syntax, always verify against
   live documentation using the Live Verification workflow in
   `references/powershell-scripting.md`.