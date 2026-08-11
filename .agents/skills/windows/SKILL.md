---
name: windows
description: >-
  Root skill that groups the Windows platform sub-skills used in this project.
  This is a router: it lists the sub-skills and tells the agent which one to
  load for the task at hand (Windows API discovery). Use when a Windows platform
  task matches one of those areas; then load the matching sub-skill's SKILL.md.
---

# Windows — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill. See `.agents/rules/skills.md` for the sub-skill
structure.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at `sub-skills/<name>/SKILL.md`.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| WinMD API Search | `sub-skills/winmd-api-search/SKILL.md` | Finding or exploring Windows desktop APIs — camera, file access, notifications, UI controls, AI/ML, sensors, networking. Retrieves full type details from a local WinMD metadata cache. |
|WASAPI development | `sub-skills/wasapi-development/SKILL.md` | Developing audio apps using the Windows Audio Session API (WASAPI). Design, implement, review, debug, and optimize Windows Audio Session API (WASAPI) and Core Audio code on Windows 10/11. |

## Project context

The Windows subsystem covers the platform layer of the visualizer (WinUI 3
client plus the Windows/C++ rendering). Use `winmd-api-search` when a feature
needs a platform capability and you must discover the right API or confirm
exact type/member signatures before writing code. Its scripts generate a local
WinMD cache; run `Update-WinMdCache.ps1` before first use.
