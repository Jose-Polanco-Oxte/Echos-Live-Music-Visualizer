# Migrate to the persistent two-phase plan system

## Plan Metadata

| Field | Value |
|---|---|
| Plan ID | `PLAN-20260811-PLAN-SYSTEM-MIGRATION` |
| Status | `COMPLETED` |
| Verification state | `VERIFIED` |
| Created | 2026-08-11 |
| Last updated | 2026-08-11 |
| Owner | Repository maintainers |
| Authorized branch | `chore/plan-system-migration` |
| Observed base | `dev` at `6a1ed449e5096c47c77167d54477b8d472f5b2f9` |
| Final archive path | `docs/public/plans/archive/completed/2026/08/2026-08-11--plan-system-migration.md` |

## Objective

Replace the legacy local plan-store workflow with a persistent two-phase
system in which `implementation-plan-authoring` creates implementation-ready
plans and `plan-conformance-execution` executes, validates, checkpoints, and
archives them. Preserve all unrelated local work and keep application, build,
Store, release, product, and branding behavior outside this migration.

## Current State Snapshot

- **Status:** `COMPLETED`
- **Verification state:** `VERIFIED`
- **Active step:** none.
- **Completed:** `S1` through `S6`.
- **Repository revision:** `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- **Branch:** `chore/plan-system-migration`
- **Open deviations/blockers:** none.

## Scope

### In scope

- Route non-trivial planning and authorized execution through the two named
  skills.
- Make `docs/public/plans/INDEX.md` the only plan catalog.
- Store current execution state, checkpoints, validation, and handoff inside
  the living plan.
- Preserve global repository state only in `.agents/state/PROJECT-HANDOFF.md`.
- Archive the 15 legacy artifacts as read-only `deprecated--*` files at the
  root of `docs/public/plans/archive/`.
- Update context compaction to consume the new index and active plan model.
- Retire the legacy command interface and storage contract without
  compatibility shims.

### Out of scope

- Application code, product behavior, builds, packaging, Store publishing,
  releases, branding, or dependency changes.
- Rust or .NET validation and distribution builds.
- Commit, push, tag, pull request, or release creation.
- Reclassification of legacy plans into new lifecycle states.

## Requirements

| ID | Requirement | Verification |
|---|---|---|
| `R1` | Directives route non-trivial planning to `implementation-plan-authoring` and authorized execution to `plan-conformance-execution`. | Targeted reference audit and directive inspection. |
| `R2` | `docs/public/plans/INDEX.md` is the sole catalog; living plans contain detailed state, checkpoints, evidence, and handoff. | Index, active-plan, and handoff inspection. |
| `R3` | Exactly 15 legacy artifacts are preserved in the archive root with `deprecated--` names, sanitized of private local links, and are non-executable history. | Inventory and content scans. |
| `R4` | Context compaction reads the new index, points to the active plan for detail and to `PROJECT-HANDOFF.md` for global state, and regenerates successfully. | PowerShell parse, execution, and snapshot inspection. |
| `R5` | Legacy storage and commands are retired from active directives and automation; the former local plan store no longer exists. | Repository reference audit and path assertion. |
| `R6` | Unrelated dirty work is preserved and no out-of-scope product files are modified by this migration. | Baseline-versus-final status and scoped diff review. |

## Locked Decisions and Invariants

- New plans use only `DRAFT`, `READY`, `IN_PROGRESS`, `BLOCKED`,
  `REPLANNING`, `COMPLETED`, `SUPERSEDED`, or `CANCELLED`.
- `deprecated` is a migration-only filename prefix, never a plan state or
  archive category.
- Legacy plans and their readiness sidecars remain separate files; sidecars become
  `deprecated--<slug>--ready.md`.
- Historical `deprecated--*` files are read-only and cannot be resumed or
  executed.
- Machine-local URI links become plain repository-relative text; no private
  machine paths, secrets, credentials, or tokens enter public plan files.
- The four legacy plan-query/execution commands are removed without a
  compatibility layer.
- User-owned changes that predate this plan remain untouched.

## Pre-existing Working Tree Changes

The following paths were dirty before this migration and are not owned by it,
except that the pre-existing `AGENTS.md` planning section is intentionally
extended in place while preserving its content:

- `AGENTS.md`
- `CHANGELOG.md`
- `EchoVisualizer.sln`
- `README.md`
- `build/Product.props` (deleted)
- `build/branding.json` (deleted)
- `docs/public/publishing/microsoft-store.md`
- `docs/public/traceability/traceability-report-20260809-store-continuous-delivery.md`
- `docs/store/README.md`
- the initial untracked `docs/public/plans/` scaffold

## Architecture and Data Flow

1. `implementation-plan-authoring` persists a `READY`, `VERIFIED` plan with
   `CP-001`, a Handoff Snapshot, and an INDEX entry.
2. `plan-conformance-execution` resolves the plan through INDEX, validates the
   repository snapshot, changes it to `IN_PROGRESS`, updates checkpoints and
   evidence, performs the final audit, and archives terminal plans.
3. `compact-context.ps1` reads INDEX for catalog state; detailed work state
   remains in the current plan and global state remains in PROJECT-HANDOFF.

## Progress

| Step | Description | Requirements | Status |
|---|---|---|---|
| `S1` | Protect the dirty baseline, create the authorized branch, persist this plan, `CP-001`, and the INDEX entry. | `R2`, `R6` | `DONE` |
| `S2` | Rewrite root and `.agents` directives for two-phase routing and correct context discovery. | `R1`, `R2`, `R5` | `DONE` |
| `S3` | Synchronize authoring and execution skills, including the legacy archive exception and cross-phase handoff. | `R1`, `R3`, `R5` | `DONE` |
| `S4` | Move, rename, sanitize, document, inventory, and retire the legacy plan store. | `R3`, `R5` | `DONE` |
| `S5` | Update compaction, INDEX, global handoff, and regenerate the context snapshot. | `R2`, `R4` | `DONE` |
| `S6` | Run the scoped conformance audit, record final evidence, complete the plan, and archive it. | `R1`-`R6` | `DONE` |

## Validation Plan

- Assert the 15 expected `deprecated--*` artifacts exist under the archive
  root and the former local plan store does not.
- Assert migrated files all begin `deprecated--` and appear in neither Active
  nor Recently completed.
- Search active repository instructions and automation for legacy paths,
  sidecars, and retired commands; allow occurrences only in historical files.
- Scan all `docs/public/plans/` content for machine-local URIs, user profile paths,
  secret values, tokens, and credentials.
- Parse and execute `.agents/tools/scripts/compact-context.ps1` without builds
  or tests; inspect its generated snapshot.
- Validate local Markdown link targets in INDEX, archive README, and this plan.
- Run `git diff --check` only for trackable migration-owned paths.
- Inspect final status against the pre-existing baseline.

## Compliance Matrix

| Requirement | Steps | Evidence | State |
|---|---|---|---|
| `R1` | `S2`, `S3`, `S6` | Active reference audit is clean; directive and skill boundaries inspected. | `VERIFIED` |
| `R2` | `S1`, `S2`, `S5`, `S6` | INDEX is the sole catalog; plan/global state ownership and links validated. | `VERIFIED` |
| `R3` | `S3`, `S4`, `S6` | Exactly 15 artifacts present; naming, placement, local-path, and secret scans pass. | `VERIFIED` |
| `R4` | `S5`, `S6` | PowerShell parser and no-build/no-test execution pass; generated snapshot uses INDEX only. | `VERIFIED` |
| `R5` | `S2`, `S3`, `S4`, `S6` | Old store absent and active legacy-reference audit clean. | `VERIFIED` |
| `R6` | `S1`, `S6` | Final branch, HEAD, dirty-path set, and scoped change surfaces match the approved ownership model. | `VERIFIED` |

## Decision Log

| ID | Date | Decision | Rationale |
|---|---|---|---|
| `DEC-001` | 2026-08-11 | Keep the 15 legacy files directly in the archive root with a `deprecated--` prefix. | Preserves history without pretending legacy artifacts implement the new state model. |
| `DEC-002` | 2026-08-11 | Remove retired commands and storage paths without compatibility aliases. | Avoids two sources of truth and forces deterministic discovery through INDEX. |
| `DEC-003` | 2026-08-11 | Do not commit or push during execution. | The approved contract requires later explicit authorization. |

## Surprises & Discoveries

- The first privacy scan correctly detected that this migration plan quoted a
  prohibited URI prefix as validation documentation. The wording was changed
  to describe the class of URI without embedding it; the repeated scan passed.
- One historical plan contained six trailing-whitespace lines. They were
  mechanically normalized and documented in the archive guide so scoped
  whitespace validation can pass without changing its meaning.

## Validation Evidence

### VAL-001 — Legacy inventory and storage retirement

- Exactly 15 expected `deprecated--*` files were present after migration.
- The source store contained zero files before its empty directory hierarchy
  was removed.

### VAL-002 — Active routing and public safety

- Active directives and automation contain no legacy store, progress-sidecar,
  status-matrix, or retired-command references.
- Public plans contain no private local path/URI or recognized secret value.

### VAL-003 — Context compaction

- PowerShell parser result: clean.
- Script execution: exit code 0 without build or tests.
- Generated snapshot names `docs/public/plans/INDEX.md` and contains no legacy
  plan-routing reference.

### VAL-004 — Catalog and documentation integrity

- INDEX contains no deprecated artifact under Active or Recently completed.
- Local Markdown link targets in INDEX, archive README, and the living plan
  resolve successfully.
- Scoped tracked diff check and public-plan trailing-whitespace scan pass.

### VAL-005 — Final conformance and scope

- Branch remains `chore/plan-system-migration` at the observed base revision.
- The dirty-path set equals the approved pre-existing paths plus the new public
  plan tree; no out-of-scope tracked path was introduced by this migration.
- All six requirements are `VERIFIED`; no deviation or blocker is open.

### VAL-006 — Post-archive reconciliation

- The completed plan exists only at its terminal path and `active/` contains no
  plan file.
- INDEX lists the migration only under Recently completed with outcome
  `PLAN_EXECUTED`; all relevant Markdown links resolve.
- The final regenerated context snapshot contains the terminal INDEX state and
  no active legacy-routing reference.
- The repeated privacy, reference, syntax, inventory, working-tree, staging,
  diff, and whitespace gates passed after archival.

## Deviation Ledger

No deviations.

## Checkpoints

### CP-001 — Plan authored and verified

- Plan status: `READY`
- Verification state: `VERIFIED`
- Repository revision: `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- Branch: `chore/plan-system-migration`
- Working tree: pre-existing dirty paths recorded above; no paths cleaned or
  restored.
- Validation: approved contract mapped to requirements, steps, invariants, and
  validation; INDEX entry created.
- Next action: activate `plan-conformance-execution` and begin directive
  migration.

### CP-002 — Conformance execution started

- Plan status: `IN_PROGRESS`
- Verification state: `STALE`
- Repository revision: `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- Branch: `chore/plan-system-migration`
- Working tree: unchanged pre-existing paths plus this plan and INDEX.
- Completed: branch protection and plan persistence (`S1`).
- Active step: directive migration (`S2`).
- Next action: rewrite plan routing and context-management rules.

### CP-003 — Directives, skills, and legacy archive migrated

- Plan status: `IN_PROGRESS`
- Verification state: `STALE`
- Repository revision: `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- Branch: `chore/plan-system-migration`
- Completed: `S2`, `S3`, and `S4`.
- Evidence: root and `.agents` rules use the two-phase lifecycle; both skills
  define the cross-phase boundary and legacy rejection; exactly 15 legacy
  files exist under the archive root; six files had machine-local links
  converted to visible path text; the old store was empty before removal.
- Open deviations/blockers: none.
- Active step: `S5`.
- Next action: validate and run the updated compaction script, then refresh the
  global handoff and generated snapshot.

### CP-004 — Compaction and pre-archive audit passed

- Plan status: `IN_PROGRESS`
- Verification state: `STALE` until final archival reconciliation.
- Repository revision: `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- Branch: `chore/plan-system-migration`
- Completed: `S5`; `R1` through `R5` are verified.
- Validation: `VAL-001` through `VAL-004` passed after the two documented
  non-semantic content corrections.
- Open deviations/blockers: none.
- Active step: `S6`.
- Next action: perform the final repository-state comparison, mark all
  requirements verified, update INDEX/global handoff, and archive this plan.

### CP-005 — Completion checkpoint

- Plan status: `COMPLETED`
- Verification state: `VERIFIED`
- Final repository revision: `6a1ed449e5096c47c77167d54477b8d472f5b2f9`
- Final branch: `chore/plan-system-migration`
- Final working tree: intentionally dirty; all pre-existing unrelated changes
  preserved, migration-owned public files untracked, no files staged.
- Validation summary: `VAL-001` through `VAL-006` passed; Rust/.NET builds and
  tests correctly not run because application code is out of scope.
- Requirements: all `VERIFIED`.
- Open deviations: none.
- Open blockers: none.
- Outcome: `PLAN_EXECUTED`.

## Handoff Snapshot

- Current status: `COMPLETED`; verification is `VERIFIED`.
- Completed: `S1` through `S6`.
- Active: none.
- Remaining: none.
- Open deviations/blockers: none.
- Repository base: `dev` at `6a1ed449e5096c47c77167d54477b8d472f5b2f9`.
- Terminal location:
  `docs/public/plans/archive/completed/2026/08/2026-08-11--plan-system-migration.md`.

## Outcomes & Retrospective

### Delivered

- A single public plan catalog and persistent two-phase lifecycle.
- Synchronized authoring/execution directives and skills.
- A documented, sanitized, read-only 15-file legacy archive.
- Context compaction aligned with INDEX, the living plan, and concise global
  handoff ownership.

### Validation

All scoped inventory, reference, privacy, secret, syntax, execution, snapshot,
link, whitespace, Git-scope, and conformance checks passed.

### Differences from original plan

No material differences. Two non-semantic archive/documentation corrections
were required by the planned validation gates and are recorded under
Surprises & Discoveries.

### Important discoveries

Quoting a forbidden machine-local URI pattern inside a public validation plan
can itself violate the content gate; describe the class without reproducing the
literal prefix.

### Decisions worth preserving

Keep INDEX small, keep detailed execution state in the living plan, keep the
global handoff concise, and never treat `deprecated--*` history as executable.

### Follow-up work

None required for this migration. Commit and push remain subject to separate
explicit authorization.

### Final result

`SUCCESS` — `PLAN_EXECUTED`.
