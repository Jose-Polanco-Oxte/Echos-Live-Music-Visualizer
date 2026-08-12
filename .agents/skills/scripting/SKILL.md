---
name: scripting
description: >-
  Root skill that groups the scripting sub-skills used in this project. This is
  a router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (script development, automation opportunity
  detection). Use when a scripting task matches one of those areas; then load
  the matching sub-skill's SKILL.md.
---

# Scripting — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill under `sub-skills/`. See
`.agents/rules/skills.md` for the sub-skill structure.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md`.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| Script Development | `sub-skills/script-development/SKILL.md` | Writing/debugging PowerShell, CMD, GUI, Gallery workflows, or automating recorded processes. |
| Automation Opportunity Detection | `sub-skills/automation-oportunity-detection/SKILL.md` | Detecting/recommending automation opportunities. |

> Note: `automation-oportunity-detection` wraps a vendored third-party
> `agent-sh/skillers` plugin. Its `SKILL.md` is the adapted entry point that
> explains the whole pipeline and how to run it; keep the vendored tree under
> `agent-sh/skillers/` read-only.

## Project context

This project's scripting needs focus on automating Windows development and
build tooling. Prefer `sub-skills/script-development/SKILL.md` for anything that
writes or runs shell scripts; use the automation-detection sub-skill when asked
to find automation opportunities rather than to produce scripts directly.