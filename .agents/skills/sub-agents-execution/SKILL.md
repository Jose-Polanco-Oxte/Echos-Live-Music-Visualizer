---
name: sub-agents-execution
description: Delegate a bounded task to an external CLI agent when delegation is useful and authorized. Role selection is optional and model-driven.
allowed-tools: Bash Read
---

# Sub-Agents — External CLI Delegation

Use this skill only when a task benefits from an isolated external agent. The
calling model remains responsible for selecting the task, scope, validation and
final synthesis.

## Role decision

Before launching, decide whether the delegated task needs:

- no role overlay;
- one reusable role from `.agents/roles/`;
- multiple compatible roles, supplied in order; or
- a task-local role declared in the prompt because the catalog has no close
  match.

An empty role directory does not prevent generic launch. A role is context, not
an execution prerequisite. Never treat `.agents/AGENTS.md` as a role.

## Discovery

List available permanent roles when selection matters:

```powershell
python .agents\skills\sub-agents-execution\scripts\run_subagent.py --list --cwd <absolute-repository-path>
```

The default discovery directory is `<cwd>/.agents/roles`; `--agents-dir` or
`SUB_AGENTS_DIR` may point to an isolated catalog. Discovery is informational
and is not a gate for launching without a role.

## Execution

The task prompt must have a specific subject, bounded scope, expected output
and validation request. The `--agent` argument is optional and repeatable:

```powershell
# No role overlay
python .agents\skills\sub-agents-execution\scripts\run_subagent.py `
  --prompt "Inspect the active plan and report unresolved path references." `
  --cwd C:\path\to\repository

# One role
python .agents\skills\sub-agents-execution\scripts\run_subagent.py `
  --agent agent-architecture-auditor `
  --prompt "Audit active agent instructions and return evidence." `
  --cwd C:\path\to\repository

# Multiple compatible roles
python .agents\skills\sub-agents-execution\scripts\run_subagent.py `
  --agent requirements-traceability-maintainer `
  --agent quality-gate-validator `
  --prompt "Validate the specification changes and report gaps." `
  --cwd C:\path\to\repository
```

When no catalog role fits, state the ad-hoc role directly in the prompt with
its objective, required context, permission boundary and output format. Do not
create a permanent role merely for a one-off task.

An explicitly named catalog role that does not exist is an error. Do not
silently substitute another specialization. Selected roles are composed in
argument order; the launcher applies the most restrictive selected permission.

## Backends and permissions

- Use `--cli` only when the caller explicitly selects a supported backend.
- Role frontmatter may provide backend/model/effort, but conflicting selected
  role values must be resolved before launch or rejected with a clear error.
- Read-only is the effective permission whenever any selected role requires it.
- Read the provider-specific `references/codex.md` before the first external
  Codex CLI execution.

## Response handling

The script returns JSON with `status`, `result`, `exit_code`, `cli` and an error
when applicable. Treat `success`, `partial` and `error` distinctly. Review the
result against the requested output and validate any proposed repository change
before integrating it.
