---
trigger: always_on
---

# Persistent Plan Routing Rule

This rule defines how agents discover, author, execute, and archive persistent
implementation plans. It complements `general.md` and `context-management.md`.

## Explicit activation gate

The plan lifecycle is opt-in. The fact that a task is complex, cross-cutting,
long-running, or risky does not by itself authorize plan authoring or plan
execution.

| User intent | Required route |
|---|---|
| “Create/formalize/replan a plan” | Load `implementation-plan-authoring`; stop at `READY` unless execution is separately authorized. |
| “Execute/implement/apply/continue this plan” | Load `plan-conformance-execution` for the provided or identified active plan. |
| Ordinary task without a provided plan | Do not load either plan lifecycle skill merely because the task is complex; use direct skills or ask before making broad/risky changes. |

If a user or another agent supplies the plan inline or outside the repository
and explicitly authorizes execution, persist it under `docs/public/plans/active/`
when required by the repository lifecycle. Do not invent additional scope or
decisions while materializing it.

If no plan is provided for an explicitly plan-driven request, stop and ask the
user whether to provide a plan or authorize plan authoring. Do not invoke plan
authoring automatically from this rule.

## Canonical storage and discovery

`docs/public/plans/INDEX.md` is the only plan catalog. Resolve plan work by
reading the index first and then the selected active plan completely.

```text
docs/public/plans/
├── INDEX.md
├── active/
└── archive/
    ├── completed/YYYY/MM/
    ├── superseded/YYYY/MM/
    └── cancelled/YYYY/MM/
```

The archive root may also contain files prefixed `deprecated--`. This is a
migration-only historical exception, not an archive category or valid plan
state. Such files are read-only, non-executable, and cannot be resumed.

## Two-phase routing

### Phase 1: authoring

When the user explicitly asks to create, formalize, or replan a plan, load and
apply `.agents/skills/implementation-plan-authoring/SKILL.md`.

Authoring must finish with:

- a plan persisted under `docs/public/plans/active/`;
- status `READY` and verification state `VERIFIED`;
- checkpoint `CP-001`;
- a current Handoff Snapshot;
- an entry in INDEX.

### Phase 2: conformance execution

When the user explicitly authorizes execution of a provided or identified
active plan, load and apply
`.agents/skills/plan-conformance-execution/SKILL.md`.

Execution must:

- accept only a non-terminal active plan from the new system;
- verify current repository state before changing implementation;
- keep status, requirements, deviations, validation evidence, checkpoints, and
  the Handoff Snapshot current inside the living plan;
- return to authoring when no valid plan exists or material replanning is
  required;
- perform a final conformance audit before moving a terminal plan to its
  category under `archive/` and updating INDEX.

## Valid lifecycle states

New plans may use only:

`DRAFT`, `READY`, `IN_PROGRESS`, `BLOCKED`, `REPLANNING`, `COMPLETED`,
`SUPERSEDED`, or `CANCELLED`.

The historical `deprecated--` filename prefix is never a lifecycle state and
must not be applied to future plans.

## State ownership

- INDEX contains compact catalog state only.
- The living plan contains detailed execution state and task handoff.
- `.agents/state/PROJECT-HANDOFF.md` contains concise global repository state
  and a link to the current plan, without duplicating plan checkpoints.
- `.agents/state/handoffs/` remains available only for non-plan task state that
  would make the global handoff too large.

Do not create alternate catalogs, progress sidecars, or compatibility commands.

## Rehydration sequence

After compaction, context reset, or a new session:

1. read `.agents/context/project.md`;
2. read `.agents/rules/general.md` and applicable rules;
3. select applicable skills;
4. read `.agents/state/PROJECT-HANDOFF.md` for global state;
5. read `docs/public/plans/INDEX.md`;
6. when work is plan-driven, read the selected active plan completely;
7. reconcile the plan snapshot with Git and current repository evidence before
   continuing.
