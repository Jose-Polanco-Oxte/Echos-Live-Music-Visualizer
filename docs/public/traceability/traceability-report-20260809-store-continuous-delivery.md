# Requirements and Formula Traceability Report

- **Feature / Increment:** Microsoft Store continuous publishing
- **Date:** 2026-08-09
- **Responsible:** Agent (dev branch)
- **Status:** IMPLEMENTED AND VERIFIED LOCALLY

> **Update (2026-08-11):** The first Store submission (`0.2.0.0`) was
> **certified and published** (https://apps.microsoft.com/store/detail/9NJMJFH8J616).
> The continuous delivery pipeline in this report is now usable for subsequent
> Store updates.

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.7 | `docs/public/spec/requirements-spec.md` section RF6.1 | Microsoft Store packages must use version `A.B.C.0` (revision zero), emit one `.msix` per supported architecture (x64/ARM64) with its own `ProcessorArchitecture`, and allow automated submission through the Store submission API while preserving reserved identity, `runFullTrust`/`microphone` capabilities, a public privacy-policy URL, and strictly increasing Store versions. | The pipeline produces `..._x64.msix` and `..._arm64.msix` with `ProcessorArchitecture="x64"`/`"arm64"` and `Version="A.B.C.0"`; `store-publish.yml` submits updates via StoreBroker; Store versions must increase across submissions. |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship with Formula |
|---|---|---|---|
| RF6.1.7 | `src/ui/EchoVisualizer.csproj` :: Store profile | `AppxBundle=Never` | Produces one architecture-specific `.msix` per runtime identifier instead of per-architecture bundles that are architecture-neutral and collide in Partner Center. |
| RF6.1.7 | `scripts/Build-Distributions.ps1` :: `ConvertTo-StoreVersion`, `Build-StoreDistribution`, `Expand-StorePackage` | Store version = `A.B.C.0` derived from the declared `A.B.C.D` | Forces the revision to zero; validates the package identity, version, and `ProcessorArchitecture` against the canonical metadata. |
| RF6.1.7 | `.github/workflows/store-publish.yml` | `version_override`, `target_publish_mode`, `publish_date`, `rollout_percentage`, `dry_run` | Builds both `.msix` packages, then submits an update through StoreBroker with the requested publish mode/rollout. |
| RF6.1.7 | `scripts/Submit-StoreUpdate.ps1` | `AppId`, `StoreVersion`, `BundlePaths`, `TargetPublishMode`, `PackageRolloutPercentage` | Generates the submission payload with `New-SubmissionPackage` and calls `Update-ApplicationSubmission` (replace packages, auto-commit) using environment-injected credentials. |
| RF6.1.7 | `scripts/Initialize-StoreBroker.ps1`, `docs/store/` | `AppId`, PDP snapshot, images | One-time bootstrap of the StoreBroker configuration and listing snapshot (no secrets committed). |
| RF6.1.7 | `docs/public/publishing/microsoft-store.md` | — | Operational guide covering identity, first manual submission, secrets, continuous delivery, and troubleshooting. |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| RF6.1.7 | `store-build.yml` CI run produces Store packages; inspect `AppxManifest.xml` from inside each `.msix`. | Both x64 and arm64 packages must have distinct `ProcessorArchitecture` and identical `Name`/`Publisher`/`Version=A.B.C.0`. | PASS: verified `..._x64.msix` (`ProcessorArchitecture="x64"`) and `..._arm64.msix` (`ProcessorArchitecture="arm64"`), both `Tun4z.EchoVisualizer`, `0.2.0.0`. |
| RF6.1.7 | `scripts/Build-Distributions.ps1 -Profile Store` validates identity and architecture via `Assert-MsixManifest`. | Nonzero revision or wrong architecture fails the build. | PASS: CI runs `31340423818` completed green. |
| RF6.1.7 | `actionlint` on `.github/workflows/store-publish.yml`; PowerShell parse of `Submit-StoreUpdate.ps1` and `Initialize-StoreBroker.ps1`. | Any workflow/syntax error fails. | PASS: lint and parse clean. |
| RF6.1.7 | First submission was created manually in Partner Center (privacy policy URL, `runFullTrust` justification, microphone declaration). | StoreBroker cannot create the first submission; it only updates published ones. | PASS: first submission published (Store version `0.2.0.0`, 2026-08-11); continuous updates now available. |

## Deviations or Decisions

The first submission is inherently manual because the Store Submission API can
only update an existing app. The continuous pipeline therefore targets updates
after the initial publication. Packages are unsigned by design (the Store signs
on publish), framework-dependent (Windows App Runtime supplied by the Store),
and the Store version uses revision zero per Microsoft's acceptance rule while
the GitHub release keeps the full `A.B.C.D` product version. The reserved
Partner Center identity (`Tun4z.EchoVisualizer`, `CN=8C71527D-…-1585E7C0DA03`)
replaced the earlier development publisher identity in both
`Package.appxmanifest` and `build/Product.props`.