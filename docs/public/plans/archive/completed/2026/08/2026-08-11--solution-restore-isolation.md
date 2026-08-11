# Aislamiento del restore del producto en `EchoVisualizer.sln`

## Current State Snapshot

- **Plan ID:** `PLAN-20260811-SOLUTION-RESTORE-ISOLATION`
- **Status:** `COMPLETED`
- **Verification state:** `VERIFIED`
- **Created:** 2026-08-11
- **Last updated:** 2026-08-11
- **Branch/worktree:** `docs/agent-architecture-audit`; existing task-owned
  changes from the agent-architecture audit are preserved.
- **Baseline revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Current revision:** same baseline, uncommitted working tree.
- **Active milestone:** M1 — isolate product solution membership.
- **Active step:** none; Step 2 completed.
- **Completed steps:** 2 / 2
- **Last checkpoint:** `CP-004`
- **Last validated checkpoint:** `CP-004`
- **Next action:** archive this completed plan and update the plan index.
- **Current blockers:** None.
- **Open plan deviations:** None.

## Objective

Make the standard Visual Studio/NuGet restore for `EchoVisualizer.sln` operate
only on the Echo product projects, so the solution-level restore does not fail
because of unrelated educational/test fixtures shipped with the agent skills.

## Context and Evidence

The solution currently contains 96 `.csproj` entries: 94 under
`.agents/skills/dotnet/dotnet-test/.../fixtures/` and only two product entries:
`src/ui/EchoVisualizer.csproj` and
`tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj`.

The solution restore fails with `NU1605` in four fixtures because their package
graphs intentionally contain incompatible direct/transitive versions:

- `Microsoft.NET.Test.Sdk` 17.12.0 versus MSTest requiring at least 17.13.0;
- `Microsoft.Testing.Extensions.TrxReport` 1.5.3 versus a transitive minimum of
  1.6.0.

Restoring the two product projects individually succeeds. The fixture files are
valid skill resources and must remain in the repository; only their membership
in the product solution is incorrect.

## Requirements

| ID | Requirement | Evidence |
|---|---|---|
| R1 | `EchoVisualizer.sln` contains only product projects needed for ordinary development and tests. | `dotnet sln list` shows exactly the UI and product test projects. |
| R2 | Skill fixtures remain available on disk and are not deleted or altered. | Files under `.agents/skills/**` remain present; scoped diff contains no fixture changes. |
| R3 | Solution restore succeeds without fixture-induced NU1605 errors. | `dotnet restore EchoVisualizer.sln` exits 0. |
| R4 | Product build/test behavior remains unchanged. | Product project build/tests and Rust validation remain applicable and pass or are explicitly blocked by existing prerequisites. |

## In Scope

- Remove non-product `.agents` project entries and their solution membership
  metadata from `EchoVisualizer.sln`.
- Remove orphaned `.agents` solution-folder metadata if the solution tool leaves
  it behind, while preserving the actual `.agents` directory.
- Update this plan and the plan index with execution evidence.

## Out of Scope

- Deleting or editing any `.agents/skills` fixture.
- Changing NuGet package versions or suppressing `NU1605`.
- Changing `src/`, `tests/`, product architecture, runtime behavior or package
  dependencies.
- Creating a separate fixture solution unless validation proves the current
  solution cannot be cleaned without one.

## Design Decisions

### D1 — Product solution membership is the correction boundary

Remove fixture projects from `EchoVisualizer.sln` rather than normalizing their
intentional package graphs. The failure is caused by solution membership, not by
the product dependency graph; changing fixture packages would damage skill
examples and hide real compatibility cases.

### D2 — Preserve fixture resources

The `.agents` fixtures remain available for skill evaluation and standalone
commands. They are not product projects and therefore do not belong to the
ordinary product solution.

### D3 — Validate both aggregate and individual paths

The aggregate solution restore must pass, and the two product project restores
must continue to pass independently. This prevents a solution-only cosmetic fix
from masking a product project problem.

## Invariants

- **I1:** Exactly two product `.csproj` entries remain in the solution.
- **I2:** No `.agents/` fixture file is deleted or modified.
- **I3:** No package version, product source, test source or architecture change
  is introduced.
- **I4:** The solution remains loadable by `dotnet sln` and Visual Studio.
- **I5:** No warning suppression or restore property is added to hide NU1605.

## Change Map

| ID | Location | Expected change | Requirement |
|---|---|---|---|
| C1 | `EchoVisualizer.sln` project entries and solution-folder metadata | Retain `src/ui/EchoVisualizer.csproj` and `tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj`; remove `.agents` fixture membership and orphan mappings. | R1, R3 |
| C2 | `docs/public/plans/active/2026-08-11--solution-restore-isolation.md` | Record execution status, validation and final checkpoint. | R1–R4 |
| C3 | `docs/public/plans/INDEX.md` | Catalog the active plan, then move it to completed archive after validation. | Plan lifecycle |

## Dependency Map

1. Confirm the exact solution project set and working-tree ownership.
2. Update solution membership only.
3. Validate solution structure and restore.
4. Run product regression checks, inspect scope and archive the plan.

## Execution Plan

### Milestone M1 — Correct solution membership

Entry condition: the project inventory and NU1605 failure are confirmed.
Exit condition: only two product projects are listed and all `.agents` fixture
files remain untouched.

#### Step 1 — Remove fixture projects from the solution

**Status:** `DONE`  
**Objective:** Make `EchoVisualizer.sln` enumerate only the two product projects.  
**Location:** `EchoVisualizer.sln`; project entries, solution-folder entries and
`NestedProjects` mappings.  
**Changes:** Remove every solution project whose path is under `.agents\`,
including associated solution-folder metadata that is no longer referenced.
Retain the UI and product-test entries exactly as they are.  
**Rationale:** Prevent NuGet from restoring unrelated fixtures while preserving
their standalone skill use.  
**Dependencies:** None beyond the baseline inventory.  
**Invariants:** I1–I5.  
**Validation:** `dotnet sln EchoVisualizer.sln list`; compare paths against the
expected two entries; `git diff -- EchoVisualizer.sln`; assert no `.agents`
fixture files changed.  
**Completion evidence:** `dotnet sln list` returns exactly two product
projects and the solution is parseable.  
**Allowed discretion:** Use `dotnet sln remove` or an equivalent deterministic
solution-file edit; remove only validated `.agents` membership.  
**Replan triggers:** A product project depends on a fixture; removing entries
requires changing product project references; or solution metadata cannot be
cleaned without altering product configuration.

### CP-003 — 2026-08-11

- **Plan status:** `IN_PROGRESS`
- **Verification state:** `VERIFIED`
- **Active milestone:** M1
- **Active step:** Step 2
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** `EchoVisualizer.sln` now contains only the two product
  projects; no `.agents/skills` files were modified or deleted.
- **Changes since CP-002:** Removed 94 validated fixture project entries and
  their solution membership metadata from the solution.
- **Validation:** `dotnet sln EchoVisualizer.sln list` reports exactly two
  projects; solution remains parseable.
- **Validation result:** `PASS`
- **Conformance:** `CONFORMING`
- **Compliance changes:** R1 and R2 → `VERIFIED`.
- **Open deviations:** None.
- **Blockers:** None.
- **Next exact action:** run aggregate and individual restores, then product
  tests and final scope inspection.

#### Step 2 — Restore and regression validation

**Status:** `DONE`  
**Objective:** Prove the original restore error is eliminated without weakening
NuGet validation.  
**Location:** `EchoVisualizer.sln`, `src/ui/EchoVisualizer.csproj`,
`tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj`, `src/core/Cargo.toml`.  
**Changes:** No additional implementation change is expected; update only plan
evidence.  
**Rationale:** The user-visible issue is the solution restore failure.  
**Dependencies:** Step 1.  
**Invariants:** I1–I5.  
**Validation:** solution restore; individual product restores; product test
build/test; Rust format, clippy and tests where prerequisites are available;
`git diff --check`.  
**Completion evidence:** aggregate restore exits 0, no NU1605 appears, product
tests pass, and scoped diff contains no product source or fixture changes.  
**Allowed discretion:** Record an environment-limited build as `BLOCKED`, never
as a pass, if a pre-existing prerequisite such as `build/Product.props` is
missing.  
**Replan triggers:** Aggregate restore still evaluates fixture projects; a
product restore fails independently; or a required product change is exposed.

## Validation Strategy

- Static: `dotnet sln list`, solution path assertions, `git diff --check` and
  scoped diff review.
- Restore: aggregate solution restore plus both individual product restores.
- Regression: existing .NET tests and Rust format/clippy/tests.
- Scope: no changes under `src/` or `tests/`, and no changes under
  `.agents/skills/`.

## Compliance Matrix

| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Step 1 / C1 | V1 | VERIFIED | `dotnet sln list` → exactly 2 product projects |
| R2 | Step 1 / I2 | V2 | VERIFIED | Fixture files remain present; no `.agents/skills` changes |
| R3 | Step 2 / C1 | V3 | VERIFIED | Solution restore exits 0 without NU1605 |
| R4 | Step 2 | V4 | VERIFIED | 40 .NET tests and 77 Rust tests pass; UI build blocker documented |

## Replan Triggers

- The product solution requires an `.agents` project reference for compilation.
- The solution parser cannot remove fixture membership without changing product
  project configuration.
- Product restore or tests fail independently of fixture projects.
- The existing working-tree changes overlap the solution in a way that makes
  ownership unclear.

## Risks

- Removing solution-folder metadata may change only the IDE grouping, not build
  behavior; verify the final solution remains parseable.
- The UI build may remain environment-limited by the previously observed missing
  `build/Product.props`; this does not justify modifying product metadata in this
  correction.

## Checkpoint Ledger

### CP-001 — 2026-08-11

- **Plan status:** `READY`
- **Verification state:** `VERIFIED`
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** Existing agent-architecture audit changes are present and
  preserved; this plan is newly added.
- **Changes since baseline:** Confirmed 96 solution projects, 94 fixture
  projects, 2 product projects and four NU1605 fixture failures.
- **Validation:** Individual product restores pass; solution restore fails with
  the documented fixture-induced NU1605 errors.
- **Validation result:** `PASS` for baseline diagnosis.
- **Conformance:** `CONFORMING`
- **Open deviations:** None.
- **Blockers:** None for the planned solution cleanup.
- **Next exact action:** remove only `.agents` project membership from the
  solution.

### CP-002 — 2026-08-11

- **Plan status:** `IN_PROGRESS`
- **Verification state:** `VERIFIED`
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** Existing audit changes plus this active plan/index entry;
  no solution mutation performed yet.
- **Changes since CP-001:** Execution authorized; plan transitioned from
  `READY` to `IN_PROGRESS`.
- **Validation:** Baseline project inventory and restore diagnosis remain
  current.
- **Validation result:** `PASS`
- **Conformance:** `CONFORMING`
- **Open deviations:** None.
- **Blockers:** None.
- **Next exact action:** remove only `.agents` project membership from the
  solution and inspect the resulting diff.

## Surprises & Discoveries

### DISC-001 — The solution contains agent fixtures

**Observed:** `dotnet sln list` reports 96 projects, 94 of them under
`.agents/skills/dotnet/dotnet-test`.

**Evidence:** `EchoVisualizer.sln`; `dotnet sln list`; solution restore output.

**Impact:** Ordinary solution restore evaluates intentionally incompatible
fixture package graphs and fails before product development can continue.

**Plan effect:** Local variation; remove solution membership while retaining
fixture files.

## Decision Log

### DEC-001 — Keep fixtures, remove solution membership

**Date:** 2026-08-11  
**Context:** The solution includes 94 skill fixtures that are not product
projects.  
**Decision:** Remove only fixture membership from `EchoVisualizer.sln`.  
**Rationale:** It fixes the actual failure boundary without changing package
examples, suppressing NuGet errors or deleting resources.  
**Affected requirements/steps:** R1–R4; Steps 1–2.  
**Plan amendment required:** No.

## Plan Deviations

None.

## Validation Evidence

### VAL-001 — Solution membership

- **Checkpoint:** CP-004
- **Command / method:** `dotnet sln EchoVisualizer.sln list`
- **Result:** PASS
- **Relevant scope:** `EchoVisualizer.sln`
- **Evidence:** Exactly `src\\ui\\EchoVisualizer.csproj` and
  `tests\\EchoVisualizer.Tests\\EchoVisualizer.Tests.csproj` remain; no
  `.agents` path occurs in the solution.

### VAL-002 — Aggregate and individual restore

- **Checkpoint:** CP-004
- **Command / method:** `dotnet restore EchoVisualizer.sln`; individual
  restores for both product projects.
- **Result:** PASS
- **Relevant scope:** NuGet solution/project restore.
- **Evidence:** All three commands exit 0; the previous fixture-induced NU1605
  errors no longer appear.

### VAL-003 — Product .NET regression

- **Checkpoint:** CP-004
- **Command / method:** Build and test `tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj` in Debug x64.
- **Result:** PASS
- **Relevant scope:** Product test project.
- **Evidence:** Build succeeds with 0 warnings/errors; 40 tests pass.

### VAL-004 — Rust regression

- **Checkpoint:** CP-004
- **Command / method:** `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`.
- **Result:** PASS
- **Relevant scope:** Existing Rust core validation.
- **Evidence:** 77 tests pass; formatting and clippy pass.

### VAL-005 — Scope and fixture preservation

- **Checkpoint:** CP-004
- **Command / method:** `git diff --check`, scoped status/diff review and
  existence checks for representative fixture projects.
- **Result:** PASS
- **Relevant scope:** Solution-only correction.
- **Evidence:** No fixture was deleted or modified; no product source/test
  file changed; `EchoVisualizer.sln` is the only implementation file changed.

### VAL-006 — Environment-limited UI build

- **Checkpoint:** CP-004
- **Command / method:** Existing project prerequisite inspection.
- **Result:** BLOCKED
- **Relevant scope:** `src/ui/EchoVisualizer.csproj` build.
- **Evidence:** `build/Product.props` is absent in the pre-existing checkout and
  is imported by the UI project. This correction does not fabricate or modify
  product metadata. The solution restore itself passes.

### CP-004 — 2026-08-11

- **Plan status:** `COMPLETED`
- **Verification state:** `VERIFIED`
- **Active milestone:** M1 complete
- **Active step:** none
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** Solution membership corrected; prior task changes preserved;
  no fixture/product source changes.
- **Changes since CP-003:** Aggregate restore, individual restores, .NET tests,
  Rust format/clippy/tests and scope checks completed.
- **Validation:** VAL-001 through VAL-006.
- **Validation result:** `PASS_WITH_DOCUMENTED_UI_BUILD_BLOCKER`
- **Conformance:** `CONFORMING`
- **Compliance changes:** R1–R4 → `VERIFIED`.
- **Open deviations:** None.
- **Blockers:** UI build prerequisite `build/Product.props` remains absent from
  the baseline checkout; unrelated to solution restore.
- **Next exact action:** archive the plan and update INDEX.

## Handoff Snapshot

**Last safe checkpoint:** CP-004  
**Verification state:** VERIFIED  
**Current repository state:** `EchoVisualizer.sln` contains only the two
product projects; all 94 skill fixtures remain on disk.  
**Completed:** Solution cleanup, aggregate/individual restores, .NET and Rust
regression checks, and scope review.  
**In progress:** None; plan is ready for archival.  
**Next exact action:** Move this completed plan to the completed archive and
update `docs/public/plans/INDEX.md`.  
**Do not repeat:** Do not modify fixture package versions or delete fixture
files. Do not fabricate the missing `build/Product.props` as part of this fix.  
**Pending validation:** None for the restore correction. The UI build remains
environment-limited by the pre-existing missing product metadata.  
**Open discoveries:** DISC-001.  
**Open decisions:** None.  
**Open deviations:** None.  
**Blockers:** None for solution restore; UI build prerequisite remains outside
this correction.  
**Relevant files/symbols:** `EchoVisualizer.sln`, the two product `.csproj`
files, `.agents/skills/dotnet/dotnet-test/**/fixtures/`.  
**Resume verification:**
1. Confirm the archived plan exists and the active plan path is absent.
2. Confirm INDEX lists the plan under Recently completed.

## Completion Criteria

- All four requirements are `VERIFIED`.
- The solution lists exactly the two product projects.
- Aggregate and individual product restores succeed.
- Existing tests pass or a pre-existing environment blocker is explicitly
  recorded as `BLOCKED` without claiming a full pass.
- No fixture or product source file changes exist.
- Final checkpoint and retrospective are recorded before archiving.

## Outcomes & Retrospective

### Delivered

Removed the 94 `.agents` fixture projects from the product solution while
retaining every fixture file. `EchoVisualizer.sln` now represents only the UI
and product test projects.

### Validation

Aggregate and individual restores pass, 40 .NET tests pass, and 77 Rust tests
pass with formatting and clippy clean. The UI build remains blocked by the
pre-existing missing `build/Product.props` prerequisite.

### Differences from original plan

None. The solution membership boundary was the planned correction.

### Important discoveries

The solution had 94 agent-skill fixtures registered as product projects; their
intentional package-version matrices caused the NU1605 restore failure.

### Decisions worth preserving

Skill fixtures remain standalone resources and must not be added to the product
solution again.

### Follow-up work

Restore `build/Product.props` in the appropriate product/build task before
attempting a complete UI build or distribution validation.

### Final result

`PLAN_EXECUTED`
