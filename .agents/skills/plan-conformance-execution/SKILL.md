---

name: plan-conformance-execution
description: Execute a provided and explicitly authorized persistent software implementation plan while continuously verifying repository state, progress, validation evidence, and conformance with the approved plan. Do not activate merely because work is long-running, complex, or architectural. Maintains the living plan under docs/public/plans, creates resumable checkpoints and handoffs, detects state drift, classifies plan deviations explicitly, prevents silent redesign and scope creep, and archives terminal plans when execution is complete, superseded, or cancelled.
---

# Plan Conformance Execution

Execute an existing implementation plan while continuously proving that:

1. repository state is understood;
2. current work maps to the active plan;
3. plan assumptions remain valid;
4. completed work has evidence;
5. execution can safely resume after interruption;
6. deviations are explicit rather than silently absorbed.

This skill is not blind plan obedience.

Repository reality may invalidate a plan.

The executor must be capable of recognizing that boundary.

## Activation contract

Activate this skill only when both conditions hold:

1. The user explicitly asks to execute, implement, apply, or continue a plan.
2. The plan is provided or identified and can be resolved to a non-terminal
   active plan under `docs/public/plans/active/`.

Do not activate this skill for an ordinary task merely because the task is
complex or because an active plan happens to exist in the repository. If the
user has not authorized plan execution, answer or perform the ordinary task
without entering the plan lifecycle. If the user explicitly requests plan
execution but no plan is available, stop and ask whether to provide one or
authorize plan authoring; do not invoke plan authoring automatically.

When a plan is supplied inline or by another agent, persist it under the active
plan directory when required by the repository lifecycle before execution.
Preserve the supplied scope and decisions while materializing it.

---

# Core execution cycle

For long-running work use:

```text
REHYDRATE
    ↓
VERIFY STATE
    ↓
IDENTIFY ACTIVE STEP
    ↓
CHECK CONFORMANCE
    ↓
EXECUTE BOUNDED CHANGE
    ↓
VALIDATE
    ↓
INSPECT DIFF / RESULT
    ↓
UPDATE PLAN STATE
    ↓
CHECKPOINT
    ↓
NEXT STEP
```

Repeat throughout execution.

Do not treat state recording as optional bookkeeping.

For long-running work it is part of correctness.

---

# 1. Locate the active plan

Require an explicitly supplied or identified plan.

Otherwise inspect:

```text
docs/public/plans/INDEX.md
```

and:

```text
docs/public/plans/active/
```

Identify the plan matching the requested work.

Do not create a second plan merely because execution occurs in a new session or with a new model.

Accept only a plan located under `docs/public/plans/active/` that uses the new
persistent lifecycle. Reject any file whose name begins with `deprecated--`,
regardless of where a caller found or supplied it. Such files are read-only
legacy history and can never be resumed or executed.

If no suitable active plan exists, do not invoke
`implementation-plan-authoring` automatically. Stop and ask the user to
provide a plan or explicitly authorize plan authoring.

---

# 2. Read the complete execution contract

Before modifying code, read the active plan in full.

At minimum understand:

* objective;
* current state snapshot;
* repository baseline;
* requirements;
* in-scope work;
* out-of-scope work;
* design decisions;
* invariants;
* executor discretion;
* change map;
* milestones;
* active step;
* validation strategy;
* compliance matrix;
* replan triggers;
* discoveries;
* decision log;
* deviations;
* latest checkpoints;
* handoff snapshot.

Also load project-level instructions required for implementation.

Never resume from the Handoff Snapshot alone.

It is an optimization for navigation, not a replacement for the execution contract.

---

# 3. Rehydrate execution state

On every new execution session or handoff:

1. read `Current State Snapshot`;
2. read `Handoff Snapshot`;
3. inspect the latest checkpoint;
4. identify the active milestone and step;
5. inspect the current repository state;
6. compare it with the plan's recorded state;
7. inspect uncommitted changes;
8. determine whether those changes belong to:

   * previous execution;
   * the user;
   * another agent;
   * unrelated existing work;
9. determine verification freshness;
10. only then continue.

Do not assume the repository is still at the last recorded checkpoint.

---

# 4. Verify repository state before execution

When Git or another VCS is available, establish:

* current branch/worktree;
* current revision;
* working tree status;
* relevant diff;
* whether expected files exist;
* whether recorded implementation state still matches reality.

Compare this against:

* baseline revision;
* current revision in the plan;
* latest checkpoint;
* Handoff Snapshot.

## Verification states

Maintain one of:

### `VERIFIED`

Current repository state has been reconciled with plan state and required validation evidence is current.

### `STALE`

Implementation has changed since the last verification.

No contradiction is proven, but validation evidence is no longer current.

### `DIVERGED`

Repository reality differs materially from recorded plan state and the difference has not been reconciled.

### `FAILING`

Relevant validation currently fails.

### `BLOCKED`

State cannot currently be verified.

Do not perform substantial new implementation while state is `DIVERGED`.

Reconcile the divergence first.

---

# 5. Detect external state drift

State drift includes:

* commits added since the latest checkpoint;
* unexpected uncommitted modifications;
* symbols moved or removed;
* user changes overlapping active work;
* dependency or configuration changes;
* plan file modified without matching implementation state;
* another agent completing or modifying planned work;
* branch/worktree mismatch.

Drift does not automatically imply error.

Investigate and classify it.

Possible outcomes:

### Compatible drift

Changes are unrelated or compatible.

Reconcile state and create a new checkpoint.

### Plan-relevant drift

Changes alter assumptions, scope, dependencies, architecture, or active implementation.

Re-evaluate conformance.

### Unknown drift

Ownership or meaning cannot be determined safely.

Do not overwrite it.

Record the uncertainty and stop at a safe boundary when necessary.

---

# 6. Set execution state

When beginning valid execution:

```text
Plan status: IN_PROGRESS
```

Update:

* last updated time;
* current revision;
* active milestone;
* active step;
* next action;
* verification state.

If resuming after `BLOCKED`, verify the blocker is actually resolved before changing status.

If resuming after `REPLANNING`, ensure the revised plan is authoritative before continuing.

---

# 7. Know the active step

At all times be able to answer:

```text
Active milestone:
Active step:
Step objective:
Requirements:
Expected locations:
Locked decisions:
Relevant invariants:
Allowed discretion:
Validation:
Completion evidence:
Replan triggers:
```

Every material production change must map to:

* the active step;
* a strict prerequisite of the active step;
* planned validation.

A change with no defensible mapping is potential scope expansion.

---

# 8. Conformance states

Classify compatibility explicitly.

## `CONFORMING`

Reality matches the plan and the implementation is directly described or clearly implied.

**Action:** proceed.

## `LOCAL_VARIATION`

The exact implementation differs in a non-material way while preserving the plan contract.

Must preserve:

* objective;
* architecture;
* ownership;
* interfaces;
* invariants;
* externally intended behavior;
* dependency strategy;
* lifecycle;
* scope.

Examples:

* private helper name differs;
* a private test fixture is needed;
* equivalent internal control flow is clearer.

**Action:** proceed.

Record the variation if it is material enough to help future execution.

## `PLAN_GAP`

A consequential decision is required but the plan does not define enough information to choose safely.

**Action:** do not silently choose.

Resolve from authoritative project evidence if the answer is unambiguous.

Otherwise enter replanning.

## `DEVIATION_REQUIRED`

The objective remains valid but correct implementation requires changing a material part of the approved plan.

Examples:

* unplanned public API change;
* new dependency;
* broader migration;
* different ownership;
* crossing explicit scope boundary.

**Action:** stop affected execution and replan.

## `PLAN_INVALID`

Material evidence proves a plan assumption or design incompatible with repository reality.

**Action:** stop affected execution and replan from evidence.

## `BLOCKED`

Plan remains valid but external conditions prevent safe progress.

**Action:** checkpoint and report blocker.

## `OUT_OF_SCOPE`

Discovered work is not required by the plan.

**Action:** do not perform it.

---

# 9. Conformance decision procedure

For unplanned material work ask:

### A. Does it advance the active step?

No:

`OUT_OF_SCOPE`

### B. Does it violate an invariant, non-goal, scope boundary, or locked decision?

Yes:

`DEVIATION_REQUIRED`

If evidence proves the original plan assumption false:

`PLAN_INVALID`

### C. Is it only local implementation detail?

If it preserves all material contracts:

`LOCAL_VARIATION`

### D. Does the plan provide enough information for the consequential choice?

No:

`PLAN_GAP`

### E. Has repository evidence disproved the system model assumed by the plan?

Yes:

`PLAN_INVALID`

### F. Is additional material scope strictly necessary?

Yes:

`DEVIATION_REQUIRED`

### G. Is progress impossible only because of an external condition?

Yes:

`BLOCKED`

Otherwise:

`CONFORMING`

---

# 10. Never redesign silently

The executor must not silently change:

* architecture;
* ownership;
* public contracts;
* protocol;
* persistence;
* threading;
* synchronization strategy;
* lifecycle;
* security semantics;
* dependency strategy;
* compatibility behavior;
* scope.

If such a change becomes necessary, execution has crossed into replanning.

If the same agent is authorized to plan and execute, make the transition explicit:

```text
Execution state: PLAN_INVALID
Entering replanning.
```

Update the plan before continuing.

Do not redesign first and rewrite the plan afterward to make the work appear compliant.

---

# 11. Execute in bounded increments

For each step:

1. verify prerequisites;
2. inspect exact current code;
3. classify conformance;
4. mark step `IN_PROGRESS`;
5. set verification state `STALE` once material mutation begins;
6. implement the smallest coherent change;
7. run targeted validation;
8. inspect resulting diff;
9. compare implementation against plan;
10. update compliance evidence;
11. mark step `DONE` only if completion evidence exists;
12. create a checkpoint.

Do not mark a step complete merely because code was written.

---

# 12. Step completion proof

A step is `DONE` only when:

* intended behavior exists;
* required files/components are correctly modified;
* relevant invariants hold;
* targeted validation passes;
* resulting diff conforms to scope;
* completion evidence is recorded;
* no unresolved material discrepancy affects the step.

Implementation without proof is still work in progress.

---

# 13. Maintain requirement compliance

Continuously update the plan's Compliance Matrix.

Example:

```markdown
| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Steps 1, 2 | V1 | VERIFIED | Tests X/Y pass |
| R2 | Step 3 | V2 | PARTIAL | Implementation complete; integration pending |
```

Never mark `VERIFIED` from code inspection alone when the plan requires executable validation.

If validation is impossible, use:

`BLOCKED`

not `VERIFIED`.

---

# 14. Validation evidence

Record material validation using:

```markdown
### VAL-007 — <purpose>

- **Checkpoint:** CP-012
- **Command / method:** `...`
- **Result:** PASS | FAIL | BLOCKED
- **Relevant scope:** ...
- **Evidence:** ...
```

Avoid copying massive raw output into the plan.

Include enough information for another executor to know:

* what was run;
* why;
* whether it passed;
* what remains.

Failures that influence design or plan validity must also be recorded under discoveries or deviations.

---

# 15. Test failure classification

A failing test can mean different things.

## Incomplete implementation

Continue the current planned work.

## Implementation defect

Fix implementation.

## Planned behavioral change

Update the test only if the plan explicitly authorizes the behavior change.

## Undocumented invariant discovered

Determine whether it is authoritative.

If it materially conflicts with the plan:

`PLAN_INVALID`

## Pre-existing unrelated failure

`OUT_OF_SCOPE` unless project policy requires a clean baseline.

Do not weaken tests to preserve apparent plan compliance.

---

# 16. Inspect the actual diff

After every material step and before every milestone checkpoint, inspect actual modifications.

For each changed file ask:

1. Which plan step requires this?
2. Which requirement does it support?
3. Which invariant constrains it?
4. Does it modify behavior outside the plan?
5. Does it introduce an unplanned dependency?
6. Does it cross an ownership boundary?
7. Is this change necessary?

A file without a defensible mapping is a scope warning.

---

# 17. Update the Current State Snapshot

Keep the top-of-plan snapshot current.

At every meaningful checkpoint update:

```text
Status
Verification state
Last updated
Current revision
Active milestone
Active step
Completed steps
Last checkpoint
Last validated checkpoint
Next action
Current blockers
Open deviations
```

The snapshot represents current truth.

Historical facts belong in the ledgers below.

---

# 18. Checkpoint policy

Create a checkpoint:

* before implementation begins;
* after each material step;
* after each milestone;
* after material validation;
* before risky or irreversible work when relevant;
* when state divergence is discovered;
* when a deviation is detected;
* before entering replanning;
* after replanning;
* before ending the execution session;
* before handoff;
* before completion.

Use sequential IDs.

```text
CP-001
CP-002
...
```

---

# 19. Checkpoint content

Use:

```markdown
### CP-012 — YYYY-MM-DD HH:MM

- **Plan status:** IN_PROGRESS
- **Verification state:** VERIFIED
- **Active milestone:** M3
- **Active step:** Step 7
- **Repository revision:** ...
- **Working tree:** ...
- **Changes since CP-011:** ...
- **Validation:** ...
- **Validation result:** PASS
- **Conformance:** CONFORMING
- **Compliance changes:** R4 → VERIFIED
- **Open deviations:** None
- **Blockers:** None
- **Next exact action:** ...
```

Checkpoint information must be based on observed state.

Do not write expected future state as if already achieved.

---

# 20. Checkpoint verification rule

A checkpoint is considered validated only when:

* repository state has been inspected;
* relevant changes are understood;
* required targeted validation for completed work has run;
* conformance has been evaluated;
* plan state matches repository state.

Then:

```text
Last validated checkpoint = CP-...
Verification state = VERIFIED
```

If further implementation occurs afterward:

```text
Verification state = STALE
```

until another validation checkpoint is created.

---

# 21. Long-session handoff

Before ending or transferring work, always leave a resumable checkpoint.

Update:

```markdown
## Handoff Snapshot

**Last safe checkpoint:** CP-...

**Verification state:** VERIFIED | STALE | ...

**Current repository state:**  
...

**Completed since previous handoff:**  
...

**Active milestone:**  
...

**Active step:**  
...

**Exact current position:**  
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

**Blockers:**  
...

**Relevant files/symbols:**  
...

**Resume verification:**  
1. ...
2. ...
3. ...
```

The handoff must allow another agent to continue without depending on conversational memory.

---

# 22. Resume protocol

A new executor must not blindly trust the previous snapshot.

Resume using:

```text
READ PLAN
   ↓
READ HANDOFF
   ↓
READ LATEST CHECKPOINT
   ↓
OBSERVE CURRENT REPOSITORY
   ↓
COMPARE
   ↓
RECONCILE DRIFT
   ↓
REVALIDATE IF NEEDED
   ↓
CONTINUE
```

If repository state differs, do not overwrite changes merely to restore the checkpoint.

Determine what happened first.

---

# 23. Discoveries

When new evidence materially affects understanding, update `Surprises & Discoveries`.

Examples:

* undocumented lifecycle behavior;
* hidden coupling;
* unexpected API limitation;
* unplanned platform behavior;
* previously unknown compatibility contract.

Use evidence.

Do not record trivia.

---

# 24. Decisions during execution

Material decisions must enter the Decision Log.

Do not rely on:

* chat context;
* temporary reasoning;
* memory of the executing model.

A future executor should be able to understand why the implementation evolved.

If a decision changes the execution contract, update the relevant normative plan sections as part of replanning.

---

# 25. Deviation reports

For:

* `PLAN_GAP`;
* `DEVIATION_REQUIRED`;
* `PLAN_INVALID`;

record:

```markdown
## Plan Conformance Report

**Active step:**  
...

**Status:** PLAN_GAP | DEVIATION_REQUIRED | PLAN_INVALID

### Expected by the plan
...

### Observed reality
...

### Evidence
...

### Conflict
...

### Impact
...

### Work completed safely
...

### Required planning decision
...

### Recommended direction
...

### Affected requirements
...

### Affected steps
...
```

Also create/update the corresponding `DEV-*` ledger entry.

Do not bury the discrepancy inside a generic status update.

---

# 26. Replanning protocol

When replanning is required:

1. stop affected implementation at a coherent boundary;
2. preserve working tree state;
3. record evidence;
4. set plan status `REPLANNING`;
5. create a checkpoint;
6. update Handoff Snapshot;
7. revise:

   * assumptions;
   * decisions;
   * steps;
   * scope;
   * invariants;
   * validation;
   * compliance mapping;
   * replan triggers;
8. record the change in Decision Log;
9. resolve deviation entries where appropriate;
10. run the planning quality gate;
11. return status to `READY` or `IN_PROGRESS`;
12. create a post-replan checkpoint;
13. continue execution.

Never erase the fact that replanning occurred.

The living plan should show how and why it evolved.

---

# 27. Preserve concurrent and user work

Never assume every uncommitted change belongs to the executor.

Before modifying overlapping files:

* inspect current diff;
* distinguish existing changes;
* preserve unrelated work;
* avoid destructive rollback;
* avoid resetting another agent/user's changes.

When ownership is unclear, treat it as state divergence until understood.

---

# 28. Out-of-scope discoveries

Do not fix unrelated issues merely because they are nearby.

Examples:

* unrelated warnings;
* naming cleanup;
* formatting elsewhere;
* unrelated bug;
* optional refactor;
* obsolete code unrelated to the objective.

Record significant discoveries separately if useful.

Do not expand the plan silently.

---

# 29. Milestone completion gate

Before completing a milestone verify:

* all included steps are `DONE`;
* milestone requirements are satisfied;
* milestone validation passes;
* changed files map to planned work;
* no unresolved material deviations affect it;
* compliance matrix is updated;
* current snapshot is updated;
* checkpoint exists.

Only then advance to the next milestone.

---

# 30. Final conformance audit

Before declaring the plan complete:

* [ ] Every required step is `DONE`.
* [ ] Every required requirement is `VERIFIED`.
* [ ] Every material changed file maps to the plan.
* [ ] Locked decisions were preserved or formally amended.
* [ ] Invariants hold.
* [ ] Out-of-scope work was not silently incorporated.
* [ ] Local variations remained non-material.
* [ ] Targeted validation passes.
* [ ] Required regression validation passes.
* [ ] Required integration/manual validation is complete.
* [ ] Validation evidence is recorded.
* [ ] No unresolved `PLAN_GAP` remains.
* [ ] No unresolved `DEVIATION_REQUIRED` remains.
* [ ] No unresolved `PLAN_INVALID` remains.
* [ ] No unresolved blocker prevents correctness claims.
* [ ] Verification state is `VERIFIED`.
* [ ] Final repository state has been inspected.
* [ ] Final checkpoint exists.
* [ ] Outcomes are documented.

---

# 31. Completion checkpoint

Create a final checkpoint containing:

```text
Plan status: COMPLETED
Verification state: VERIFIED
Final repository revision
Final working tree state
Validation summary
Requirements: all VERIFIED
Open deviations: none
Open blockers: none
Outcome
```

Update `Outcomes & Retrospective`.

Do not mark completion before final evidence exists.

---

# 32. Outcomes & Retrospective

At completion record concisely:

```markdown
## Outcomes & Retrospective

### Delivered
...

### Validation
...

### Differences from original plan
...

### Important discoveries
...

### Decisions worth preserving
...

### Follow-up work
...

### Final result
SUCCESS | PARTIAL | CANCELLED
```

Follow-up work does not automatically belong in the completed plan.

Create a new plan only if that future work is actually approved and non-trivial.

---

# 33. Archive completed plans

After final completion:

1. ensure final checkpoint exists;
2. set status `COMPLETED`;
3. update retrospective;
4. update `INDEX.md`;
5. move plan from:

```text
docs/public/plans/active/
```

to:

```text
docs/public/plans/archive/completed/YYYY/MM/
```

6. ensure it no longer appears under Active;
7. add it to Recently completed if appropriate;
8. keep Recently completed limited to the latest 10 entries.

Do not leave completed plans in `active/`.

Files prefixed `deprecated--` at the archive root are a migration-only
historical exception. They are not completed plans and must never be processed
through this completion workflow.

---

# 34. Archive superseded or cancelled plans

## Superseded

Before archiving:

* record replacement Plan ID/path;
* explain why replacement was necessary;
* update `INDEX.md`.

Move to:

```text
archive/superseded/YYYY/MM/
```

## Cancelled

Record:

* reason;
* state of implementation;
* whether partial changes remain;
* whether rollback occurred;
* any reusable discoveries.

Move to:

```text
archive/cancelled/YYYY/MM/
```

The terminal categories above apply only to plans created by the persistent
system. Never reuse the `deprecated--` prefix for a future terminal plan.

---

# 35. Prevent plan-folder entropy

The executor participates in plan hygiene.

Maintain these invariants:

```text
docs/public/plans/active/
    = only currently actionable plans

docs/public/plans/INDEX.md
    = small current catalog

docs/public/plans/archive/
    = historical plans
```

Do not:

* duplicate plans to preserve revisions;
* create `final`, `final2`, `new`, `updated` copies;
* leave completed plans active;
* list every archived plan in INDEX;
* create a new plan for every execution session.

Plan history belongs inside the living plan and version control.

---

# 36. Final execution statuses

Finish execution in one of:

## `PLAN_EXECUTED`

All work is complete and conforms to the final approved plan.

## `PLAN_EXECUTED_WITH_LOCAL_VARIATIONS`

All work is complete with only permitted non-material variations.

## `PLAN_PARTIALLY_EXECUTED`

Some valid work is complete but a blocker, plan gap, deviation, or invalidation prevents safe completion.

## `PLAN_NOT_EXECUTABLE`

Material evidence invalidates the plan before meaningful safe execution can continue.

The plan file must reflect the same state.

---

# Final rule

Never optimize for appearing to have followed the plan.

Optimize for maintaining a truthful, verifiable relationship between:

```text
INTENT
   ↕
PLAN
   ↕
REPOSITORY STATE
   ↕
VALIDATION EVIDENCE
   ↕
CURRENT EXECUTION STATE
```

At any point during a long-running task, a new competent agent should be able to answer from repository evidence and the living plan:

1. What are we trying to achieve?
2. Why is the implementation designed this way?
3. What has actually been completed?
4. What evidence proves it?
5. What remains?
6. Is repository state still compatible with the plan?
7. Have any assumptions changed?
8. What is the exact next action?
9. Can execution safely continue?

If those questions cannot be answered reliably, execution state is not sufficiently documented.
