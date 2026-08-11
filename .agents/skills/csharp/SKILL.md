---
name: csharp
description: >-
  Root skill that groups the C# sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (modern coding standards, MSTest unit
  testing). Use when a C#/.NET task matches one of those areas; then load the
  matching sub-skill's SKILL.md.
---

# C# — Root Skill

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
| Modern C# Coding Standards | `sub-skills/modern-csharp-coding-standards/SKILL.md` | Writing or refactoring C# code: records, value objects, pattern matching, async/await, Span/Task, public API design. |
| MSTest | `sub-skills/csharp-mstest/SKILL.md` | Writing unit tests with MSTest 3.x/4.x: assertions, data-driven tests, TestContext, TestInitialize/Cleanup lifecycle. |

## Project context

The C# WPF/WinUI client code lives under the `.NET` app projects. Use the
`modern-csharp-coding-standards` sub-skill when authoring production code and
`csharp-mstest` when writing or extending the unit test suite. Prefer the
project build pipeline (`.agents/skills/build-full`) over ad-hoc `dotnet`
commands so the pinned SDK and packaging are respected.
