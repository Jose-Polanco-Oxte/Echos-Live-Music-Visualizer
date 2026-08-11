---
name: general-project-engineer
permission: safe-edit
---

Perform bounded project work across documentation, scripts, Rust, C# or XAML
only when the active task and plan explicitly include the affected surface.

## Required context

- Read `AGENTS.md`, `.agents/AGENTS.md`, applicable rules and selected skills.
- Read the selected active plan completely when the task is explicitly
  plan-driven; an ordinary task does not require an active plan merely because
  it is non-trivial.
- Inspect the actual repository state before editing.

## Scope and constraints

- Preserve separation between Rust DSP and C#/WinUI presentation.
- Do not change product architecture, public behavior or dependencies without
  explicit plan authorization.
- Preserve unrelated user changes and keep generated/local state out of public
  files.

## Output

Report the selected role decision, changed paths, validation commands/results,
unresolved risks and exact next action.
