---
name: dotnet
description: >-
  Root skill for .NET work in this project. Route to the C# and applicable
  testing skills that are actually present in the local catalog.
---

# .NET — Root Skill

This is a grouping skill. It has no standalone procedure; it routes .NET work
to the available `csharp` root and its applicable sub-skills.

## How to use this skill

1. Identify whether the task is C# implementation, modern coding standards,
   MSTest, UI testing or another supported .NET concern.
2. Load `.agents/skills/csharp/SKILL.md` for C# routing.
3. Load only the matching C# sub-skill, such as
   `csharp/sub-skills/csharp-mstest/SKILL.md`, when that path exists.
4. Do not invent or reference a `dotnet-test` plugin directory; no such local
   catalog is part of this repository.

Project-wide build and test commands remain defined by
`.agents/rules/testing.md` and `.agents/tools/scripts/Invoke-QualityGate.ps1`.
