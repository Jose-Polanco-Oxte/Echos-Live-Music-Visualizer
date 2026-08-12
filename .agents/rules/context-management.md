---
trigger: always_on
---

# Context Management

Use the repository compaction script:

```powershell
.\.agents\tools\scripts\compact-context.ps1
```

If build validation is useful for the current task:

```powershell
.\.agents\tools\scripts\compact-context.ps1 -RunBuild
```

If both build and test state are important:

```powershell
.\.agents\tools\scripts\compact-context.ps1 -RunBuild -RunTests
```

After the script runs, read:

1. `.agents/state/CONTEXT-SNAPSHOT.md`;
2. `.agents/state/PROJECT-HANDOFF.md`;
3. `docs/public/plans/INDEX.md`;
4. the selected active plan in full when the task is plan-driven.

Reconcile those files against actual Git and repository state. Keep
`PROJECT-HANDOFF.md` limited to global current state and a link to the active
plan. Keep plan-specific status, decisions, checkpoints, validation evidence,
deviations, and continuation instructions in the living plan.

Do not copy raw logs, large diffs, full source files, command transcripts, or
information trivially recoverable from Git into handoffs.

## Rehydration after compaction

After compaction, context reset, agent handoff, or a new agent session, rebuild
working context in this order:

1. `.agents/context/project.md`;
2. `.agents/rules/`, with `general.md` at highest operational priority;
3. applicable skills from `.agents/skills/`;
4. `.agents/state/PROJECT-HANDOFF.md`;
5. `docs/public/plans/INDEX.md` and the selected active plan;
6. applicable policies and only the project references required by the task.

Supporting references include the public specification, architecture,
conventions, domain context, roles, tools, and integrations. Do not reread the
entire repository automatically.

When explicitly instructed to compact context, execute this complete procedure
and continue from the newly persisted state unless told to stop.
