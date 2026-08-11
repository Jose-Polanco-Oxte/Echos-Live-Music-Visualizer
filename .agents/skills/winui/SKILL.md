---
name: winui
description: >-
  Root skill that groups the WinUI 3 sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (design, dev workflow, code review,
  packaging, UI testing). Use when a WinUI 3 app task matches one of those
  areas; then load the matching sub-skill's SKILL.md.
---

# WinUI 3 — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill under `sub-skills/`. See
`.agents/rules/skills.md` for the sub-skill structure.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at `sub-skills/<name>/SKILL.md`.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| Design | `sub-skills/winui-design/SKILL.md` | Designing/reviewing UI: layout, control choice, Fluent Design, Light/Dark/High Contrast theming, typography, brushes, accessibility, XAML data-binding. Ships `winui-search.exe` for sample lookup. |
| Dev Workflow | `sub-skills/winui-dev-workflow/SKILL.md` | Creating/opening projects, building and running, error diagnosis, prerequisites. Ships `BuildAndRun.ps1` and the WinUI analyzers. |
| Code Review | `sub-skills/winui-code-review/SKILL.md` | Pre-commit code quality review: MVVM compliance, x:Bind correctness, accessibility, theming, security, performance. |
| Packaging | `sub-skills/winui-packaging/SKILL.md` | MSIX packaging, code signing, certificates, self-contained deployment, CI/CD, Microsoft Store submission. |
| UI Testing | `sub-skills/winui-ui-testing/SKILL.md` | Automated UI testing via `winapp ui` (UIA) — element assertions, interactions, accessibility audits, screenshots — for any Windows desktop app. |

## Project context

The WinUI 3 client is the desktop front end of the visualizer. Start here for
any work touching the app UI, its build/run loop, packaging, or UI tests. Use
`winui-dev-workflow` when working in the project, `winui-design` before writing
XAML, `winui-code-review` before committing, and `winui-packaging` /
`winui-ui-testing` for release and automated verification. The project build
pipeline lives in `.agents/skills/build-full`.
