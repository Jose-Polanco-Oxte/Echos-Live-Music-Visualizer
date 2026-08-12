# Plan Archive

This directory contains terminal plans from the persistent plan system and a
one-time set of legacy planning artifacts preserved during the 2026-08-11 plan
system migration.

## Legacy provenance and policy

The 15 files prefixed `deprecated--` came from the repository's former ignored
local planning store: seven plan documents, their seven readiness sidecars, and
one shared status matrix. They were preserved as separate files so migration
does not manufacture lifecycle states or merge historical records.

These files are read-only historical context. They:

- are not contracts for current implementation;
- cannot be resumed, executed, replanned, or returned to the active catalog;
- do not use the persistent system's lifecycle states;
- must not be used as templates for new plans.

The `deprecated--` prefix is a migration-only filename convention, not a valid
plan status and not an archive subcategory.

## Legacy mapping

| Legacy workstream / artifact | Archived file |
|---|---|
| distribution-runtime-parity plan | [deprecated--distribution-runtime-parity.md](deprecated--distribution-runtime-parity.md) |
| distribution-runtime-parity readiness sidecar | [deprecated--distribution-runtime-parity--ready.md](deprecated--distribution-runtime-parity--ready.md) |
| hifi-multiresolution-dsp-refactor plan | [deprecated--hifi-multiresolution-dsp-refactor.md](deprecated--hifi-multiresolution-dsp-refactor.md) |
| hifi-multiresolution-dsp-refactor readiness sidecar | [deprecated--hifi-multiresolution-dsp-refactor--ready.md](deprecated--hifi-multiresolution-dsp-refactor--ready.md) |
| performance-and-gc-optimization plan | [deprecated--performance-and-gc-optimization.md](deprecated--performance-and-gc-optimization.md) |
| performance-and-gc-optimization readiness sidecar | [deprecated--performance-and-gc-optimization--ready.md](deprecated--performance-and-gc-optimization--ready.md) |
| ui-experience-and-shell-deferred plan | [deprecated--ui-experience-and-shell-deferred.md](deprecated--ui-experience-and-shell-deferred.md) |
| ui-experience-and-shell-deferred readiness sidecar | [deprecated--ui-experience-and-shell-deferred--ready.md](deprecated--ui-experience-and-shell-deferred--ready.md) |
| ui-winui3-spec plan | [deprecated--ui-winui3-spec.md](deprecated--ui-winui3-spec.md) |
| ui-winui3-spec readiness sidecar | [deprecated--ui-winui3-spec--ready.md](deprecated--ui-winui3-spec--ready.md) |
| visual-decibel-spectral-scaling plan | [deprecated--visual-decibel-spectral-scaling.md](deprecated--visual-decibel-spectral-scaling.md) |
| visual-decibel-spectral-scaling readiness sidecar | [deprecated--visual-decibel-spectral-scaling--ready.md](deprecated--visual-decibel-spectral-scaling--ready.md) |
| win2d-gpu-batching-visualizer plan | [deprecated--win2d-gpu-batching-visualizer.md](deprecated--win2d-gpu-batching-visualizer.md) |
| win2d-gpu-batching-visualizer readiness sidecar | [deprecated--win2d-gpu-batching-visualizer--ready.md](deprecated--win2d-gpu-batching-visualizer--ready.md) |
| shared legacy status matrix | [deprecated--legacy-status.md](deprecated--legacy-status.md) |

## Sanitization

Machine-local links embedded in six source files were converted to their
visible repository-relative path text. No private user-directory URI was
published. Six pre-existing trailing-whitespace lines in one historical plan
were normalized so the migrated archive passes repository whitespace checks;
historical wording and file separation were otherwise preserved.

## Persistent archive categories

Plans created by the current system use only these terminal locations:

- `completed/YYYY/MM/`
- `superseded/YYYY/MM/`
- `cancelled/YYYY/MM/`

Current plan discovery always begins at [the plan index](../INDEX.md).
