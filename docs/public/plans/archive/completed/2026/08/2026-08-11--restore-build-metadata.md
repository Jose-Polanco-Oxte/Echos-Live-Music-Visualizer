# Plan: Restaurar metadatos canónicos de build

## Current State Snapshot

- **Plan ID:** `PLAN-20260811-RESTORE-BUILD-METADATA`
- **Status:** COMPLETED
- **Verification state:** VERIFIED
- **Created:** 2026-08-11 12:56
- **Last updated:** 2026-08-11 13:01
- **Branch/worktree:** `docs/agent-architecture-audit`, working tree already contains unrelated architecture-audit and solution-restore changes
- **Baseline revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Current revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Active milestone:** M2 — Regression validation and archival
- **Active step:** Complete; archive plan
- **Completed steps:** 2 / 2
- **Last checkpoint:** CP-004
- **Last validated checkpoint:** CP-004
- **Next action:** Move this completed plan to the completed archive and update the index
- **Current blockers:** None for restoration; full packaging remains environment-dependent
- **Open plan deviations:** None
- **Supersedes:** —
- **Superseded by:** —

## Objective

Restore the canonical build metadata that was accidentally removed from the
repository so that the UI project, product-configuration validator, branding
generator, and distribution scripts can evaluate the same official properties
that existed immediately before the deletion commit.

## Context and Evidence

- `src/ui/EchoVisualizer.csproj` imports `build/Product.props` at line 2.
- `scripts/Test-ProductConfiguration.ps1` requires both `build/Product.props`
  and `build/branding.json`.
- `scripts/Generate-BrandAssets.ps1` reads `build/branding.json`.
- Both files were deleted by commit `a279fb4` and exist in `a279fb4^`.
- `git show a279fb4^:build/Product.props` contains the canonical product
  version `0.2.0.19`, core version `0.2.0`, product identity, publisher,
  application metadata, Win32 identity, and branding color.
- `git show a279fb4^:build/branding.json` contains the canonical logo source,
  asset dimensions/scales, icon sizes, and target-size asset recipe.
- The requested correction is a restoration, not a metadata redesign or version
  change.

## Repository Baseline

- **Branch:** `docs/agent-architecture-audit`
- **HEAD:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** dirty with pre-existing user/agent changes, including the
  solution fixture removal and architecture documentation changes. Those files
  are outside this plan and must remain untouched.
- **Relevant baseline failures:** direct UI build fails with `MSB4019` because
  `build/Product.props` is absent; product configuration validation cannot run
  because both canonical build files are absent.

## Requirements

### R1 — Restore canonical product properties

Restore `build/Product.props` byte-for-byte from `a279fb4^` so the existing
official product metadata is available to MSBuild and distribution tooling.

### R2 — Restore canonical branding recipe

Restore `build/branding.json` byte-for-byte from `a279fb4^` because the product
validator and asset generator require it as the companion build configuration.

### R3 — Preserve existing product behavior and scope

Do not change Rust, C#, XAML, manifests, package versions, product version,
solution membership, architecture, or generated assets as part of this fix.

### R4 — Prove the build configuration is usable

Validate the restored metadata through the project validator, branding check,
solution restore, UI build evaluation, and the existing .NET regression tests.
Record environment-limited checks explicitly rather than treating them as
passes.

## In Scope

- `build/Product.props`
- `build/branding.json`
- The active plan and `docs/public/plans/INDEX.md` required to record execution
  state.
- Targeted validation of configuration, restore, build, and tests.

## Out of Scope

- Recreating or changing product metadata values.
- Updating the product version or Store identity.
- Regenerating checked-in branding assets unless validation proves the restored
  recipe is inconsistent with existing assets and the user authorizes that
  follow-up.
- Modifying `EchoVisualizer.sln` beyond the already completed fixture isolation.
- Modifying Rust, C#, XAML, manifests, DSP, FFI, WASAPI, Win2D, or rendering.
- Committing, pushing, merging, or publishing.

## Design Decisions

### D1 — Restore from repository history, not manual reconstruction

Use `git show a279fb4^:<path>` as the source for both files. This preserves the
exact values and formatting that were previously accepted by the project.

### D2 — Restore both companion build files

Restore `Product.props` and `branding.json` together because the validator and
distribution pipeline define them as a coupled canonical metadata/branding
configuration. Restoring only `Product.props` would leave the build control
layer incomplete.

### D3 — Treat generated assets as validation output

Do not overwrite generated assets during this task. First use the existing
`Generate-BrandAssets.ps1 -Check` contract to determine whether the restored
recipe matches the checked-in projections.

## Invariants

- **I1:** Official metadata remains exactly the values from `a279fb4^`.
- **I2:** `src/ui/EchoVisualizer.csproj` can resolve its existing import without
  changing the project file.
- **I3:** Product and branding validators remain the authority for consistency
  across manifests, Cargo metadata, README, changelog, and assets.
- **I4:** No product source or architecture behavior changes.
- **I5:** Existing unrelated working-tree changes are preserved.

## Executor Discretion

### Allowed without replanning

- Use an equivalent read-only Git extraction command to restore the exact parent
  revision content.
- Use targeted MSBuild, PowerShell, .NET, and test commands needed to validate
  the restored files.
- Update plan checkpoints, evidence, and the plan index.

### Locked by the plan

- The source revision for both files is `a279fb4^`.
- No hand-edited metadata values are allowed.
- No generated asset rewrite is allowed in this plan.
- No unrelated working-tree cleanup or Git history operation is allowed.

## Change Map

| ID | Location | Expected change | Requirement |
|---|---|---|---|
| C1 | `build/Product.props` | Restore exact canonical MSBuild property file from `a279fb4^` | R1 |
| C2 | `build/branding.json` | Restore exact canonical branding recipe from `a279fb4^` | R2 |
| C3 | `docs/public/plans/INDEX.md` | Register this plan and later its terminal result | Execution state |

## Dependency Map

1. Confirm parent revision contents and current working-tree ownership.
2. Restore both canonical files.
3. Validate product metadata and branding projections.
4. Validate solution restore, UI build evaluation, and .NET regression tests.
5. Inspect diff, record final checkpoint, archive the completed plan, and update
   the plan index.

# Execution Plan

## Milestone 1 — Restore canonical build metadata

**Outcome:** Both deleted build-control files exist with exact historical
content, and the product validator can read them.

**Entry conditions:** Parent revision contents are verified; no active plan
covers this restoration; unrelated changes are understood.

**Exit conditions:** R1 and R2 are satisfied and targeted metadata checks pass.

### Step 1 — Restore historical build files

**Status:** DONE

**Objective:** Restore `build/Product.props` and `build/branding.json` from
`a279fb4^` without changing their contents.

**Requirements:** R1, R2

**Location:** `build/Product.props`, `build/branding.json`.

**Changes:** Extract the exact parent-revision blobs into the two paths. Do not
edit values or normalize the files beyond the historical content.

**Rationale:** The deletion commit is identified and the immediately preceding
revision is the authoritative source requested by the user.

**Dependencies:** None beyond baseline verification.

**Invariants:** I1, I2, I5.

**Validation:** Compare each restored file with `git show a279fb4^:<path>`;
run `scripts/Test-ProductConfiguration.ps1` and
`scripts/Generate-BrandAssets.ps1 -Check`.

**Completion evidence:** Both files are present, exact comparisons pass, and
the validators report success or a specifically documented unrelated asset
drift.

**Allowed discretion:** Equivalent extraction command; no content edits.

**Replan triggers:** Parent content is unavailable or differs from the values
required by current manifests/specification; either condition would require an
explicit metadata decision.

## Milestone 2 — Regression validation and archival

**Outcome:** The restored build configuration is consumable by the solution and
the existing test suite without unrelated changes.

**Entry conditions:** Step 1 is complete and metadata validation passes.

**Exit conditions:** R3 and R4 are verified, final diff is scoped, and the plan
is archived as completed.

### Step 2 — Validate build and regression surfaces

**Status:** DONE

**Objective:** Prove the restored import and companion metadata work through
the solution restore, UI build, and existing tests.

**Requirements:** R3, R4

**Location:** `EchoVisualizer.sln`, `src/ui/EchoVisualizer.csproj`,
`tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj`, and validation
scripts.

**Changes:** No source changes expected; only record validation evidence.

**Rationale:** The original user-visible failure was a missing build import, and
the solution restore correction must remain intact.

**Dependencies:** Step 1.

**Invariants:** I2, I3, I4, I5.

**Validation:** Run `dotnet restore EchoVisualizer.sln`; build the UI project
with the repository-supported configuration; run the .NET tests; run
`git diff --check`; inspect status to ensure no `src/` or `tests/` changes.
Run Rust validation only if the restored metadata changes any Rust-facing build
surface; otherwise record it as not applicable to this configuration-only fix.

**Completion evidence:** Restore and UI build no longer fail because of
`Product.props`; tests pass; no unrelated product files change; any external
environment limitation is recorded as BLOCKED/SKIPPED.

**Allowed discretion:** Choose the least expansive supported build command that
proves MSBuild evaluation and compilation; do not package or install.

**Replan triggers:** Metadata mismatch, required source modification, generated
asset inconsistency requiring regeneration, or a build failure unrelated to
the restored files that requires a product-code change.

## Verification and State

### Validation Strategy

- V1: exact blob comparison against `a279fb4^` for both restored files.
- V2: `scripts/Test-ProductConfiguration.ps1`.
- V3: `scripts/Generate-BrandAssets.ps1 -Check`.
- V4: `dotnet restore EchoVisualizer.sln`.
- V5: targeted UI build/evaluation and existing .NET tests.
- V6: `git diff --check`, status inspection, and scope assertion.

## Compliance Matrix

| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Step 1 / C1 | V1, V2, V4, V5 | VERIFIED | Exact parent hash; product validator, restore, and UI build pass |
| R2 | Step 1 / C2 | V1, V3 | VERIFIED | Exact parent hash; branding projection check passes |
| R3 | Step 2 / C3 | V6 | VERIFIED | No `src/` or `tests/` changes; diff check passes |
| R4 | Step 2 | V2–V6 | VERIFIED | Restore, build, tests, metadata, branding, and scope checks pass |

## Replan Triggers

- Historical files do not satisfy current product configuration checks.
- Restoring the files exposes a required source, dependency, or architecture
  change outside this plan.
- Existing branding assets do not match the historical recipe and regeneration
  would modify tracked assets.
- A concurrent change overlaps either `build/Product.props` or
  `build/branding.json`.

## Risks

- The historical metadata may reveal an unrelated pre-existing projection drift;
  classify it before changing anything.
- A full UI/package build may remain limited by installed Windows SDK, native
  toolchain, or packaging prerequisites; such limitations do not invalidate
  successful metadata validation.

# Living Execution Record

## Progress

- M1 / Step 1: DONE
- M2 / Step 2: DONE

## Checkpoint Ledger

### CP-001 — 2026-08-11 12:56

- **Plan status:** READY
- **Verification state:** VERIFIED
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** pre-existing architecture, documentation, and solution
  changes present; no build metadata files currently present
- **Changes since previous checkpoint:** Initial plan created.
- **Validation:** Parent revision contents, deletion history, project import,
  validators, and plan catalog inspected.
- **Validation result:** PASS for planning evidence; implementation pending.
- **Conformance:** CONFORMING
- **Compliance changes:** None; all requirements pending implementation.
- **Open deviations:** None
- **Blockers:** None for restoration
- **Next exact action:** Set plan `IN_PROGRESS`, restore both files from
  `a279fb4^`, and run V1–V3.

### CP-002 — 2026-08-11 12:58

- **Plan status:** IN_PROGRESS
- **Verification state:** VERIFIED
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** Initial plan and plan-index changes added; pre-existing
  architecture, documentation, and solution changes preserved.
- **Changes since CP-001:** Execution authorized and started.
- **Validation:** Historical deletion source rechecked; no overlapping build
  metadata changes found.
- **Validation result:** PASS
- **Conformance:** CONFORMING
- **Compliance changes:** None; restoration pending.
- **Open deviations:** None
- **Blockers:** None
- **Next exact action:** Add the exact parent-revision content for
  `build/Product.props` and `build/branding.json`.

### CP-003 — 2026-08-11 13:00

- **Plan status:** IN_PROGRESS
- **Verification state:** VERIFIED
- **Active milestone:** M2
- **Active step:** Step 2
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** `build/Product.props` and `build/branding.json` restored;
  unrelated pre-existing changes preserved.
- **Changes since CP-002:** Restored both files exactly from `a279fb4^`.
- **Validation:** Exact Git blob hashes, `Test-ProductConfiguration.ps1`, and
  `Generate-BrandAssets.ps1 -Check` all passed.
- **Validation result:** PASS
- **Conformance:** CONFORMING
- **Compliance changes:** R1 and R2 -> VERIFIED.
- **Open deviations:** None
- **Blockers:** None identified
- **Next exact action:** Run V4-V6 and complete the final conformance audit.

### CP-004 — 2026-08-11 13:01

- **Plan status:** COMPLETED
- **Verification state:** VERIFIED
- **Active milestone:** M2 complete
- **Active step:** Complete; archive plan
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** Restored build metadata is the only new product/build
  content from this plan; unrelated prior changes remain untouched.
- **Changes since CP-003:** Solution restore, UI build, test build, 40 .NET
  tests, diff check, exact hashes, and source-scope assertion completed.
- **Validation:** V4-V6 passed. UI build emitted one environment warning about
  missing `mspdbcmf.exe` for symbols but produced the DLL and test MSIX with
  zero errors.
- **Validation result:** PASS
- **Conformance:** CONFORMING
- **Compliance changes:** R1-R4 -> VERIFIED.
- **Open deviations:** None
- **Blockers:** None
- **Next exact action:** Archive this completed plan and update `INDEX.md`.

## Surprises & Discoveries

### DISC-001 — Companion branding recipe was deleted with Product.props

**Observed:** `build/Product.props` and `build/branding.json` were both deleted
by `a279fb4`.

**Evidence:** `git log --all --diff-filter=D -- build` and parent tree listing.

**Impact:** Restoring only `Product.props` would leave the product validator
and branding pipeline incomplete.

**Plan effect:** Local scope expansion to restore the directly coupled canonical
branding recipe; no architecture or behavior change.

## Decision Log

### DEC-001 — Restore both files from the immediate parent revision

**Date:** 2026-08-11

**Context:** The user confirmed the deleted build properties were correct.

**Decision:** Restore both deleted build-control files byte-for-byte from
`a279fb4^`.

**Rationale:** This is the last known accepted canonical state and avoids
inventing product or branding metadata.

**Affected requirements/steps:** R1, R2, Step 1.

**Plan amendment required:** No.

## Plan Deviations

None.

## Validation Evidence

### VAL-001 — Exact restoration source

- **Checkpoint:** CP-003
- **Command / method:** `git hash-object` compared with
  `git rev-parse a279fb4^:<path>` for both restored files.
- **Result:** PASS
- **Relevant scope:** `build/Product.props`, `build/branding.json`
- **Evidence:** Both actual hashes equal their parent-revision hashes.

### VAL-002 — Product metadata consistency

- **Checkpoint:** CP-003
- **Command / method:** `scripts/Test-ProductConfiguration.ps1`
- **Result:** PASS
- **Relevant scope:** Product properties, package manifest, Win32 manifest,
  Cargo version, README, changelog, and icon.
- **Evidence:** Canonical version `0.2.0.19` and all required projections
  validated successfully.

### VAL-003 — Branding projection consistency

- **Checkpoint:** CP-003
- **Command / method:** `scripts/Generate-BrandAssets.ps1 -Check`
- **Result:** PASS
- **Relevant scope:** `build/branding.json` and `src/ui/Assets`
- **Evidence:** Brand assets validated successfully.

### VAL-004 — Solution restore

- **Checkpoint:** CP-004
- **Command / method:** `dotnet restore EchoVisualizer.sln --verbosity minimal`
- **Result:** PASS
- **Relevant scope:** Product solution with its two current projects.
- **Evidence:** All projects are up to date for restore; no NU1605 errors.

### VAL-005 — UI build and .NET regression tests

- **Checkpoint:** CP-004
- **Command / method:** UI project build, test project build, and 40 .NET
  tests with `--no-restore`/`--no-build` as applicable.
- **Result:** PASS
- **Relevant scope:** `src/ui/EchoVisualizer.csproj` and
  `tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj`.
- **Evidence:** UI DLL and test MSIX produced; test build had 0 warnings and 0
  errors; 40 tests passed. One non-blocking `mspdbcmf.exe` symbols warning was
  emitted by Windows SDK tooling.

### VAL-006 — Scope and repository hygiene

- **Checkpoint:** CP-004
- **Command / method:** `git diff --check`; status inspection; assertion that
  `src/` and `tests/` have no changes.
- **Result:** PASS
- **Relevant scope:** Plan changes and pre-existing working-tree state.
- **Evidence:** No whitespace errors; no source/test changes; restored files
  hash exactly to the historical blobs.

## Handoff Snapshot

**Last safe checkpoint:** CP-004

**Verification state:** VERIFIED

**Current repository state:** Branch `docs/agent-architecture-audit` at
`a279fb4`; `build/Product.props` and `build/branding.json` are restored and
validated; unrelated working-tree changes must be preserved.

**Completed:** Both canonical build files restored; product/branding validation,
solution restore, UI build, test build, 40 .NET tests, diff check, and scope
assertion passed.

**In progress:** None; plan is complete and ready for archival.

**Next exact action:** Archive this plan under
`docs/public/plans/archive/completed/2026/08/` and remove it from Active in
`docs/public/plans/INDEX.md`.

**Do not repeat:** Do not reconstruct or modernize metadata manually; do not
remove or reset existing solution/documentation changes.

**Pending validation:** None.

**Open discoveries:** DISC-001.

**Open decisions:** None.

**Open deviations:** None.

**Known blockers:** None. The UI build emitted only a non-blocking symbols
warning for missing `mspdbcmf.exe`.

**Files currently relevant:** `build/Product.props`, `build/branding.json`,
`src/ui/EchoVisualizer.csproj`, `scripts/Test-ProductConfiguration.ps1`,
`scripts/Generate-BrandAssets.ps1`.

**Commands needed to resume verification:**

```powershell
git diff -- build/Product.props build/branding.json
.\scripts\Test-ProductConfiguration.ps1
.\scripts\Generate-BrandAssets.ps1 -Check
dotnet restore EchoVisualizer.sln
```

# Completion

## Completion Criteria

- R1–R4 are `VERIFIED`.
- Both files exactly match `a279fb4^`.
- Product and branding validation pass.
- Solution restore and targeted build/test validation pass, or limitations are
  explicitly recorded.
- No unrelated files are modified by this plan.
- Final checkpoint and retrospective are recorded.
- Plan is archived under `docs/public/plans/archive/completed/2026/08/`.

## Outcomes & Retrospective

### Delivered

Restored `build/Product.props` and `build/branding.json` byte-for-byte from
`a279fb4^`, recovering the canonical product and branding build configuration.

### Validation

Product configuration and branding checks passed; solution restore passed; the
UI built and produced a test MSIX; the test project built; 40 .NET tests passed;
and scope/diff checks passed.

### Differences from original plan

None. The plan intentionally restored the companion branding recipe after
history showed it had been deleted in the same commit.

### Important discoveries

The deletion commit removed both build-control files, not only `Product.props`.

### Decisions worth preserving

Canonical build metadata must be restored from repository history rather than
reconstructed manually when the historical values are authoritative.

### Follow-up work

None required for this correction. The non-blocking `mspdbcmf.exe` symbols
warning is an environment/tooling prerequisite, not a product build failure.

### Final result

`SUCCESS`
