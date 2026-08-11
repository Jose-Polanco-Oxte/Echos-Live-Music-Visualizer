---

name: implementation-plan-authoring
description: Create precise, implementation-ready, persistent software engineering plans from requirements, project context, documentation, code, tests, architecture, and repository evidence. Use only when the user explicitly asks to create, formalize, or replan a plan, or explicitly asks to author a plan before implementation. Do not activate merely because work is non-trivial. Produces living execution documents under docs/public/plans with explicit scope, decisions, invariants, dependencies, verification gates, progress state, checkpoints, handoff state, and replan triggers so another agent can execute the work without rediscovering hidden decisions.
---

# Implementation Plan Authoring

Create implementation plans that function as persistent execution contracts.

A plan is not:

* a short checklist;
* a conversational summary;
* a brainstorm;
* a list of files to edit;
* a temporary planning response.

A plan must preserve enough verified context, decisions, execution state, and validation criteria for a different agent to continue the work correctly after a long interruption or context reset.

## Core principle

> Plan explicitly enough that execution requires implementation judgment, not architectural rediscovery.

The planner owns ambiguity reduction.

The executor may make local implementation decisions only inside boundaries explicitly left open by the plan.

## Activation contract

This skill is opt-in. Activate it only when the user explicitly requests plan
authoring, plan formalization, replanning, or a plan-first workflow. Do not
create a plan automatically because a task is complex, cross-cutting,
long-running, or risky.

If the user requests work without providing a plan and the task cannot be
executed safely without one, ask whether they want a plan authored or want to
provide one. Do not author and execute a plan in the same step unless the user
explicitly authorizes both actions.

Authoring ends at `READY`; implementation belongs to the separate
`plan-conformance-execution` skill after explicit execution authorization.

---

# 1. Plan storage architecture

Use:

```text
docs/public/plans/
├── INDEX.md
├── active/
│   ├── 2026-08-11--audio-device-recovery.md
│   └── 2026-08-14--renderer-lifecycle-refactor.md
└── archive/
    ├── completed/
    │   └── 2026/
    │       └── 08/
    ├── superseded/
    │   └── 2026/
    │       └── 08/
    └── cancelled/
        └── 2026/
            └── 08/
```

Only non-terminal plans belong in `active/`.

Terminal plans must be archived.

Do not allow `active/` to become a historical dump.

## Terminal states

These states must be archived:

* `COMPLETED`
* `SUPERSEDED`
* `CANCELLED`

These states remain in `active/`:

* `DRAFT`
* `READY`
* `IN_PROGRESS`
* `BLOCKED`
* `REPLANNING`

## Legacy archive exception

The root of `docs/public/plans/archive/` may contain historical files whose
names begin with `deprecated--`. They are read-only artifacts from the former
planning system:

* `deprecated` is a filename prefix, not a lifecycle state;
* these files are not candidates for discovery, resumption, extension,
  replacement, or execution;
* they remain at the archive root rather than entering a terminal-state
  category;
* never apply this prefix to a new plan.

---

# 2. Plan discovery before creation

Before creating a new plan:

1. Inspect `docs/public/plans/INDEX.md`.
2. Inspect relevant plans under `docs/public/plans/active/`.
3. Search for plans matching:

   * the same objective;
   * the same feature;
   * the same bug;
   * the same subsystem;
   * the same architectural migration;
   * a previous version of the same work.

Do not create a new plan when an existing active plan represents the same work.

Ignore `deprecated--*` files during executable-plan discovery. They may be read
only as historical context when explicitly relevant.

Prefer:

* resuming it;
* extending it;
* formally replanning it.

Create a replacement only if the previous plan is no longer the correct execution contract.

When replacing a plan:

1. mark the old plan `SUPERSEDED`;
2. record `Superseded by`;
3. create the replacement;
4. record `Supersedes`;
5. move the old plan to `archive/superseded/YYYY/MM/`;
6. update `INDEX.md`.

## One-workstream rule

There should normally be only one active plan for one coherent implementation objective.

Do not create:

```text
fix-audio-1.md
fix-audio-new.md
fix-audio-final.md
fix-audio-final-2.md
```

Use the plan lifecycle instead.

---

# 3. Naming

Use:

```text
YYYY-MM-DD--short-descriptive-slug.md
```

Example:

```text
2026-08-11--wasapi-device-recovery.md
```

Keep the filename stable while the plan remains active.

The date represents initial plan creation, not every revision.

Use a durable internal Plan ID:

```text
PLAN-20260811-WASAPI-DEVICE-RECOVERY
```

The Plan ID does not change during replanning.

---

# 4. INDEX.md policy

`docs/public/plans/INDEX.md` is the entry point for discovering plan state.

It is a catalog, not a complete history.

Maintain:

```markdown
# Implementation Plans

## Active

| Plan | Status | Area | Updated | Current step |
|---|---|---|---|---|
| [...] | IN_PROGRESS | Audio | ... | Step 4 |

## Blocked / Replanning

| Plan | Status | Reason | Updated |
|---|---|---|---|

## Recently completed

Keep only the most recent 10 completed plans here.

| Plan | Completed | Outcome |
|---|---|---|

## Archive

- Completed: `archive/completed/`
- Superseded: `archive/superseded/`
- Cancelled: `archive/cancelled/`
```

Do not list every historical plan individually in `INDEX.md`.

Historical discovery belongs to the archive hierarchy and repository search.

Whenever a plan is:

* created;
* renamed;
* started;
* blocked;
* replanned;
* completed;
* superseded;
* cancelled;

update `INDEX.md` in the same coherent change.

---

# 5. Public-document safety

Plans are stored under `docs/public/plans`.

Therefore never persist:

* passwords;
* secrets;
* access tokens;
* private keys;
* credentials;
* private customer data;
* sensitive production values;
* unnecessary machine-specific private paths.

Refer to protected information symbolically.

Example:

```text
Use the configured signing credential.
```

Do not copy the credential into the plan.

---

# 6. Planning mode

Unless explicitly authorized to implement:

* inspect but do not modify production implementation;
* do not convert investigation into opportunistic coding;
* prefer read-only repository operations;
* builds, tests, analyzers, searches, diagnostics, and repository history may be used to establish facts;
* creating or updating the plan and plan index is allowed.

---

# 7. Establish authoritative context

Before designing the plan, identify and inspect the sources governing the work.

Prefer evidence in this order when applicable:

1. explicit user requirements;
2. project agent instructions;
3. project policies;
4. specifications;
5. architecture documentation;
6. domain documentation;
7. development conventions;
8. implementation;
9. tests;
10. build and deployment infrastructure;
11. issue/history information relevant to the behavior.

Do not assume documentation and implementation agree.

When they conflict:

1. record the conflict;
2. determine the authoritative source using project policy;
3. incorporate the resolution into the plan.

---

# 8. Separate facts, assumptions, and unknowns

Every material planning premise belongs conceptually to one of:

## Confirmed

Directly supported by evidence.

## Assumed

Reasonable but not yet proven.

Material assumptions should be verified before the plan becomes `READY`.

## Unknown

Cannot currently be established.

An unresolved unknown is acceptable only if:

* it cannot reasonably be resolved during planning;
* execution can resolve it safely;
* the plan gives an explicit resolution procedure;
* different outcomes would not require materially different architecture.

Otherwise keep the plan in `DRAFT` or `BLOCKED`.

Never disguise assumptions as verified facts.

---

# 9. Reconstruct current state

Do not plan from filenames alone.

Trace the relevant behavior.

Identify as applicable:

* entry points;
* call paths;
* data flow;
* state transitions;
* ownership;
* lifecycle;
* threading;
* concurrency;
* synchronization;
* public contracts;
* internal contracts;
* persistence;
* configuration;
* external APIs;
* framework integration;
* platform behavior;
* error handling;
* tests;
* build paths;
* packaging;
* deployment consequences.

Understand why the existing implementation has its current shape before proposing its replacement.

---

# 10. Establish the repository baseline

When version control is available, record the planning baseline.

At minimum:

```text
Branch:
HEAD revision:
Working tree state:
Baseline validation:
```

Do not assume a clean working tree.

Distinguish:

* pre-existing changes;
* planner-created documentation changes;
* unrelated concurrent modifications.

This baseline allows a future executor to determine whether repository reality has drifted since planning.

---

# 11. Translate requirements into obligations

Every material requirement must map through:

```text
Requirement
    ↓
Design decision
    ↓
Implementation step
    ↓
Validation
    ↓
Completion evidence
```

If a requirement has no implementation consequence, explain why.

If a proposed implementation step maps to no requirement, architectural necessity, or validation requirement, reconsider whether it belongs in scope.

Assign identifiers:

```text
R1
R2
R3
```

for traceability.

---

# 12. Define the execution contract

Before creating steps, define:

## Objective

Describe the observable final state.

## In scope

Explicit implementation surfaces and behaviors.

## Out of scope

Adjacent work that must not be performed.

## Design decisions

For each important decision record:

* decision;
* rationale;
* evidence;
* affected boundaries;
* consequences.

Use identifiers:

```text
D1
D2
D3
```

Do not delegate major design choices to execution.

## Invariants

Record properties that must remain true.

Use:

```text
I1
I2
I3
```

Examples:

* public API compatibility remains unchanged;
* audio callbacks remain non-blocking;
* persistence format remains backward compatible;
* renderer ownership remains unchanged;
* no new dependency is introduced.

## Executor discretion

Explicitly separate:

### Allowed without replanning

Examples:

* local variable naming;
* private helper extraction;
* equivalent internal control flow;
* assertion organization;
* formatting;
* minor private implementation choices.

### Locked by the plan

Normally includes:

* architecture;
* ownership;
* public APIs;
* dependency strategy;
* persistence formats;
* threading model;
* security semantics;
* lifecycle;
* externally observable behavior.

---

# 13. Build the change map

Use exact verified locations whenever possible.

```markdown
| ID | Area | Location | Expected change | Requirement |
|---|---|---|---|---|
| C1 | Audio lifecycle | `AudioEngine.cs` / `RecoverAsync` | Centralize recovery sequencing | R2 |
```

Do not fabricate paths or symbols for specificity.

When exact location cannot yet be identified, define a bounded discovery target.

---

# 14. Determine execution dependencies

Before ordering steps determine:

* compilation dependencies;
* interface-before-implementation requirements;
* migrations;
* test baselines;
* compatibility requirements;
* generated-code dependencies;
* deployment dependencies;
* integration ordering.

Steps must follow technical dependency order.

Identify genuinely parallel work when useful.

Do not label tightly coupled changes as parallel merely because different files are involved.

---

# 15. Milestones and steps

Long plans should be divided into milestones.

Example:

```text
Milestone 1 — Establish behavioral baseline
Milestone 2 — Introduce lifecycle contract
Milestone 3 — Migrate recovery implementation
Milestone 4 — Remove obsolete path
Milestone 5 — Full validation
```

Each milestone must define:

* outcome;
* included steps;
* entry conditions;
* exit conditions;
* validation gate.

Every material step must include:

## Step N — Specific outcome

**Status**

`NOT_STARTED | IN_PROGRESS | DONE | BLOCKED | INVALIDATED`

**Objective**

Concrete result.

**Requirements**

IDs implemented by this step.

**Location**

Verified files, symbols, components, tests, configuration, or bounded discovery locations.

**Changes**

Actual behavior to implement.

**Rationale**

Why this design belongs here.

**Dependencies**

Previous steps or contracts required.

**Invariants**

Relevant invariant IDs.

**Validation**

Specific checks proving this step.

**Completion evidence**

What must be demonstrably true before marking `DONE`.

**Allowed discretion**

Local choices available to the executor.

**Replan triggers**

Discoveries that invalidate the step or plan.

---

# 16. Ban vague planning

Do not use standalone instructions such as:

* update the service;
* fix error handling;
* refactor;
* add tests;
* ensure compatibility;
* integrate the behavior;
* clean up implementation.

Describe:

* what changes;
* where;
* how behavior changes;
* why;
* what must not change;
* how correctness is proven.

Specificity is information density, not arbitrary verbosity.

Do not shorten a step if compression removes information required by a future executor.

---

# 17. Validation strategy

Validation is part of the implementation contract.

Plan:

* targeted tests;
* regression tests;
* integration tests;
* negative cases;
* failure paths;
* boundary conditions;
* static analysis;
* compilation;
* linting;
* packaging;
* deployment checks;
* platform-specific checks;
* manual validation when unavoidable.

For bug fixes, include a regression test whenever reasonably possible.

For behavior-preserving refactors, validation must establish behavioral parity.

Avoid relying exclusively on:

```text
Run all tests.
```

Specify targeted validation first.

---

# 18. Requirement compliance matrix

Create and maintain:

```markdown
## Compliance matrix

| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Steps 1, 2 | V1 | PENDING | — |
| R2 | Step 3 | V2, V3 | PENDING | — |
```

Allowed states:

* `PENDING`
* `PARTIAL`
* `VERIFIED`
* `FAILED`
* `BLOCKED`

A plan cannot become `COMPLETED` while a required requirement remains anything other than `VERIFIED`.

---

# 19. State verification model

The plan must distinguish implementation status from verification status.

Use:

## Repository verification state

### `VERIFIED`

Current repository state has been reconciled with the latest checkpoint and required validation is current.

### `STALE`

Work occurred after the latest verification checkpoint.

The repository may be correct, but the recorded evidence is no longer sufficient.

### `DIVERGED`

Repository state differs materially from the state expected by the plan/checkpoint and has not yet been reconciled.

### `FAILING`

Relevant validation currently fails.

### `BLOCKED`

Verification cannot currently be completed.

Never present a plan as fully verified while its verification state is `STALE`, `DIVERGED`, `FAILING`, or `BLOCKED`.

---

# 20. Current State Snapshot

Every active plan must contain a small, continuously updated control section near the top.

Use:

```markdown
## Current State Snapshot

- **Plan ID:** PLAN-...
- **Status:** READY
- **Verification state:** VERIFIED
- **Created:** YYYY-MM-DD
- **Last updated:** YYYY-MM-DD HH:MM
- **Branch/worktree:** ...
- **Baseline revision:** ...
- **Current revision:** ...
- **Active milestone:** ...
- **Active step:** ...
- **Completed steps:** 0 / N
- **Last checkpoint:** CP-...
- **Last validated checkpoint:** CP-...
- **Next action:** ...
- **Current blockers:** None
- **Open plan deviations:** None
- **Supersedes:** —
- **Superseded by:** —
```

This snapshot is the first place a resuming agent should inspect.

Do not make the executor reconstruct current state by reading the entire plan history.

---

# 21. Checkpoint strategy

Plans for long-running tasks must use explicit checkpoints.

Create checkpoints at least:

1. when planning becomes `READY`;
2. before implementation starts;
3. after every completed material step;
4. after each milestone;
5. after material validation;
6. when a plan discrepancy is discovered;
7. after replanning;
8. before handing work to another agent or ending an execution session;
9. before final completion.

Checkpoint IDs:

```text
CP-001
CP-002
CP-003
```

Each checkpoint records:

```markdown
### CP-003 — 2026-08-11 17:42

- **Plan status:** IN_PROGRESS
- **Verification state:** VERIFIED
- **Active milestone:** M2
- **Active step:** Step 4
- **Repository revision:** ...
- **Working tree:** ...
- **Changes since previous checkpoint:** ...
- **Validation performed:** ...
- **Validation result:** PASS
- **Conformance state:** CONFORMING
- **Open issues:** None
- **Next exact action:** ...
```

Do not paste full build/test logs into routine checkpoints.

Record:

* command;
* result;
* meaningful summary;
* location of external logs/artifacts when applicable.

Detailed evidence belongs only where needed.

---

# 22. Checkpoint compaction

Long-running plans may accumulate many checkpoints.

Preserve auditability without allowing routine records to dominate the document.

After completing a milestone:

* retain milestone boundary checkpoints;
* retain checkpoints associated with failures;
* retain checkpoints associated with decisions;
* retain checkpoints associated with deviations;
* retain replanning checkpoints;
* retain the latest checkpoint;
* routine successful intermediate checkpoints may be compacted into a concise milestone summary if project policy permits it.

Never compact away evidence needed to explain why a decision or deviation occurred.

---

# 23. Required living-state sections

Every long-running plan must contain:

## Progress

Current milestone/step status.

## Current State Snapshot

Authoritative resumability state.

## Compliance Matrix

Requirements versus verified evidence.

## Checkpoint Ledger

Execution snapshots.

## Surprises & Discoveries

Unexpected repository or runtime facts.

## Decision Log

Material decisions made after initial planning.

## Plan Deviations

Conformance exceptions and their resolution.

## Validation Evidence

Meaningful verification results.

## Handoff Snapshot

Exact resumption instructions.

## Outcomes & Retrospective

Final result after completion.

These sections are execution state, not optional commentary.

---

# 24. Surprises & Discoveries

Record material discoveries.

Use:

```markdown
### DISC-003 — <short description>

**Observed:**  
...

**Evidence:**  
...

**Impact:**  
...

**Plan effect:**  
None | Local variation | Replan required
```

Do not record every trivial implementation observation.

Record discoveries that could matter to:

* architecture;
* correctness;
* future execution;
* validation;
* scope;
* ownership;
* lifecycle;
* compatibility.

---

# 25. Decision Log

Record post-planning material decisions.

```markdown
### DEC-004 — <decision>

**Date:**  
...

**Context:**  
...

**Decision:**  
...

**Rationale:**  
...

**Affected requirements/steps:**  
...

**Plan amendment required:** Yes | No
```

Do not silently change an original design decision.

---

# 26. Plan deviation ledger

Use:

```markdown
### DEV-002 — <description>

**Detected during:** Step 4

**Classification:**  
LOCAL_VARIATION | PLAN_GAP | DEVIATION_REQUIRED | PLAN_INVALID

**Expected:**  
...

**Observed:**  
...

**Impact:**  
...

**Resolution:**  
...

**Plan amendment:**  
...

**Status:**  
OPEN | RESOLVED
```

`DEVIATION_REQUIRED` and `PLAN_INVALID` normally require replanning before affected execution continues.

---

# 27. Handoff Snapshot

Before pausing long-running work or transferring execution to another agent, update:

```markdown
## Handoff Snapshot

**Last safe checkpoint:** CP-...

**Current repository state:**  
...

**Completed:**  
...

**In progress:**  
...

**Next exact action:**  
...

**Do not repeat:**  
...

**Pending validation:**  
...

**Open discoveries:**  
...

**Open decisions:**  
...

**Open deviations:**  
...

**Known blockers:**  
...

**Files currently relevant:**  
...

**Commands needed to resume verification:**  
...
```

Avoid vague handoffs such as:

> Continue Step 4.

The next action must be specific enough to resume directly.

---

# 28. Replan triggers

Explicitly identify conditions requiring replanning.

Typical triggers:

* required abstraction does not exist;
* ownership differs materially;
* API lacks necessary capability;
* dependency strategy fails;
* public API must change unexpectedly;
* migration becomes necessary;
* tests establish an incompatible invariant;
* concurrency assumptions are invalid;
* performance constraints invalidate design;
* security constraints invalidate design;
* lifecycle differs from expected;
* significant out-of-scope work becomes mandatory.

Replanning is a valid state transition, not execution failure.

---

# 29. Plan lifecycle

Use:

```text
DRAFT
  ↓
READY
  ↓
IN_PROGRESS
  ├──→ BLOCKED
  ├──→ REPLANNING
  │       ↓
  │     READY / IN_PROGRESS
  ├──→ SUPERSEDED
  ├──→ CANCELLED
  ↓
COMPLETED
```

## DRAFT → READY

Allowed only after the quality gate passes.

## READY → IN_PROGRESS

Occurs when execution begins.

## IN_PROGRESS → REPLANNING

Use when plan validity must be reconsidered.

## IN_PROGRESS → COMPLETED

Allowed only after final validation and compliance audit.

---

# 30. Archival policy

When a plan reaches a terminal state, remove it from `active/`.

### Completed

Move:

```text
docs/public/plans/active/<plan>.md
```

to:

```text
docs/public/plans/archive/completed/YYYY/MM/<plan>.md
```

### Superseded

Move to:

```text
archive/superseded/YYYY/MM/
```

### Cancelled

Move to:

```text
archive/cancelled/YYYY/MM/
```

Then update `INDEX.md`.

Do not create a separate archival copy while leaving the original active file behind.

The terminal plan itself remains the historical source of truth.

Historical `deprecated--*` files at the archive root are a migration exception
only. They are not completed, superseded, or cancelled plans under this
lifecycle and must never be moved into those categories by authoring work.

---

# 31. Completion requirements

A plan may become `COMPLETED` only if:

* all required steps are `DONE`;
* all requirements are `VERIFIED`;
* final targeted validation passes;
* required regression validation passes;
* relevant invariants are confirmed;
* no unresolved `PLAN_GAP` exists;
* no unresolved `DEVIATION_REQUIRED` exists;
* no unresolved `PLAN_INVALID` exists;
* required documentation is complete;
* outcomes are recorded;
* final checkpoint exists;
* verification state is `VERIFIED`.

---

# 32. Required plan structure

Use this structure unless project policy defines a stricter one.

```markdown
# Plan: <name>

## Current State Snapshot
...

## Objective
...

## Context and Evidence
...

## Repository Baseline
...

## Requirements
...

## In Scope
...

## Out of Scope
...

## Design Decisions
...

## Invariants
...

## Executor Discretion

### Allowed without replanning
...

### Locked by the plan
...

## Change Map
...

## Dependency Map
...

# Execution Plan

## Milestone 1 — ...
...

### Step 1 — ...
...

# Verification and State

## Validation Strategy
...

## Compliance Matrix
...

## Replan Triggers
...

## Risks
...

# Living Execution Record

## Progress
...

## Checkpoint Ledger
...

## Surprises & Discoveries
...

## Decision Log
...

## Plan Deviations
...

## Validation Evidence
...

## Handoff Snapshot
...

# Completion

## Completion Criteria
...

## Outcomes & Retrospective
...
```

---

# 33. Initial READY checkpoint

Before handing the plan to execution:

1. complete the plan;
2. run the quality gate;
3. set status `READY`;
4. set verification state `VERIFIED`;
5. create `CP-001`;
6. populate the Handoff Snapshot;
7. update `INDEX.md`.

The plan is then safe for another agent to consume.

Authoring ends at this boundary. When implementation is authorized, hand the
persisted active plan to `plan-conformance-execution`; do not execute the plan
inside this authoring workflow.

---

# 34. Quality gate

Before marking `READY`, verify:

* [ ] Objective is observable.
* [ ] Relevant repository evidence was inspected.
* [ ] Baseline repository state is recorded.
* [ ] Facts and assumptions are distinguished.
* [ ] Requirements have IDs.
* [ ] Requirements map to implementation and validation.
* [ ] Scope is explicit.
* [ ] Non-goals are explicit.
* [ ] Material design decisions are made.
* [ ] Invariants are explicit.
* [ ] Change surfaces are identified.
* [ ] Steps follow technical dependencies.
* [ ] Steps describe behavior, not just filenames.
* [ ] Validation is specific.
* [ ] Completion evidence is defined.
* [ ] Executor discretion is explicit.
* [ ] Replan triggers are explicit.
* [ ] Compliance matrix exists.
* [ ] Current State Snapshot exists.
* [ ] Handoff Snapshot exists.
* [ ] Initial checkpoint exists.
* [ ] `INDEX.md` reflects this plan.
* [ ] No duplicate active plan already covers the same work.
* [ ] Another competent executor can continue using only repository state, project instructions, and this plan.

The final test is:

> Could a new executor resume this work after losing the planner's conversation context without reconstructing a missing architectural or behavioral decision?

If not, the plan is not ready.
