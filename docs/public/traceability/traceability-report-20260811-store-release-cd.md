# Requirements and Formula Traceability Report

- **Feature / Increment:** Release-driven Microsoft Store continuous delivery
  with centralized distribution configuration (PLAN-20260811-MICROSOFT-STORE-RELEASE-CD)
- **Date:** 2026-08-11
- **Responsible:** Repository maintainer / plan-conformance executor
- **Status:** IMPLEMENTED AND LOCALLY VERIFIED; live Partner Center confirmation pending operator credentials

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.7 | `docs/public/spec/requirements-spec.md` §RF6.1 | Store version derived deterministically and monotonically at `A.B.C.D → A.B.S.0` with packing base 256; single unsigned `.msixbundle` with one x64 and one ARM64 inner package; stable GitHub Release gate; idempotent, non-deleting Store submission; listing metadata untouched | Stable release only enters production; derived Store version ends in `.0`; bundle has exactly x64+ARM64; remote state preflight before mutation; re-runs are safe |
| RF6.1.6 | `docs/public/spec/requirements-spec.md` §RF6.1 | Visual identity parity across MSIX and unpackaged distributions from a common brand source | Generated assets and recipes centralized in `build/Product.props`; `Generate-BrandAssets.ps1 -Check` passes byte-equivalent |
| RF6.1.1–RF6.1.5, RF6.2 | `docs/public/spec/requirements-spec.md` | Unchanged product behavior | No Rust/C#/XAML/DSP/FFI/rendering source behavior changed by this plan |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship with Formula |
|---|---|---|---|
| RF6.1.7 (config) | `build/Product.props` :: `EchoStoreVersionPackingBase`, `EchoStoreProductId`, `EchoPackageFamilyName`, `EchoStoreArtifactType`, `EchoStoreArchitecture` items, `EchoStoreCapability` items | `S = C*256 + D`; Product ID `9NJMJFH8J616`; PFN `Tun4z.EchoVisualizer_ga3qxkah0cx76`; artifact type `msixbundle`; architectures `x64`,`arm64`; capabilities `runFullTrust`,`microphone` | Single versioned source; schema 1 parser rejects absent/duplicate/unknown/type-incompatible fields, invalid URL/hash, unsupported capabilities/architectures, packing base != 256 |
| RF6.1.7 (parser) | `scripts/modules/Echo.ReleaseMetadata.psm1` :: `Get-EchoDistributionConfiguration`, `Get-EchoStoreVersion`, `Compare-EchoVersion`, `Test-EchoStoreVersionMonotonic`, `Test-EchoReleaseManifestSchema` | Four-part product version bounds A,B ≤ 65535, C,D ≤ 255 | D5 mapping `S = (C*256)+D`; Store version `A.B.S.0`; monotonic and injective |
| RF6.1.7 (interface) | `scripts/Test-ProductConfiguration.ps1` `-AsJson` | Stable D19 contract (product/store/branding/tooling/externalBindings) | Workflows/scripts consume one JSON contract; no second parser |
| RF6.1.6 (branding) | `scripts/Generate-BrandAssets.ps1`, `build/Product.props` `EchoBrandAsset`/`EchoBrandTargetSizeAsset` | Icon sizes, scales 100–400, target sizes 16–256 | Byte-equivalent to the removed `build/branding.json` recipes (validated via `-Check`) |
| RF6.1.7 (packaging) | `scripts/Build-Distributions.ps1` :: `Build-StoreBundle` | Store version via `/bv`; deterministic name `EchoVisualizer-<A.B.C.D>-msixbundle.msixbundle` | MakeAppx `bundle /bv`; artifact validator asserts exactly one x64 + one ARM64 inner package |
| RF6.1.7 (validation) | `scripts/Test-StoreReleaseArtifact.ps1` | Bundle identity/publisher/version/architecture/capabilities | Unbundles and unpacks each inner package; optional release-manifest correlation |
| RF6.1.7 (release) | `.github/workflows/release.yml` | Tag `vA.B.C.D`, exact referenced SHA, CI gates (`Lint GitHub Actions Workflows`, `Test, Publish and Validate Distributions`) | Draft→stable via `gh`; release manifest/checksums; Store workflow dispatch |
| RF6.1.7 (submit) | `scripts/modules/Echo.StoreSubmission.psm1`, `scripts/Invoke-MicrosoftStoreRelease.ps1` | D11 state machine; D12 no-commit→verify→commit | Preflight classifies state; unknown/different-target states fail closed; no automatic deletion |
| RF6.1.7 (monitor) | `.github/workflows/store-status.yml`, `scripts/Get-MicrosoftStoreReleaseStatus.ps1` | Six-hour schedule; 90-day sanitized retention | Read-only; `IN_PROGRESS` never reported as published |
| RF6.1.7 (CLI) | `scripts/Install-MicrosoftStoreCli.ps1` | msstore `0.3.9`; archive `MSStoreCLI-win-x64.zip`; SHA-256 `bf2f9aa…`; .NET 9 `9.0.316` | Pinned coordinates read from config; digest fail-closed |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| RF6.1.7 (D5) | `tests/scripts/Test-StoreReleasePipeline.ps1` | `0.2.0.19→0.2.19.0`, boundary C/D > 255, monotonic equal/lower rejection, packing base != 256 fixture | PASS (local) |
| RF6.1.7 (schema) | `Get-EchoDistributionConfiguration` fixture matrix | duplicate property, missing property, unknown property, out-of-range version, packing-base mismatch | PASS (all fail closed) |
| RF6.1.7 (state machine) | `Test-StoreReleasePipeline.ps1` | published→upload, pendingcommit→resume, certification→monitor, equal published→fail-monotonic, terminal→fail-closed, unknown normalization | PASS (local) |
| RF6.1.7 (CLI invocation) | offline fake-CLI harness | configure/get/publish/commit exit codes, JSON parse, environment isolation/restore | PASS (local) |
| RF6.1.7 (packaging) | Full `Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64,win-arm64` | x64+ARM64 MSIX build; `/bv 0.2.19.0`; bundle `EchoVisualizer-0.2.0.19-msixbundle.msixbundle` (33,841,597 bytes, SHA-256 `070e7b…`); artifact validator | PASS (local build) |
| RF6.1.7 (workflows) | `actionlint` v1.7.12 over all workflows + composite action | Draft/prerelease guards, no PR/push triggers, full-SHA pins | PASS |
| RF6.1.7 (literal drift) | CI `Audit Distribution Literal Duplicates` | Product ID, PFN, CLI version/asset/hash present only in `Product.props` and shared module | PASS (0 violations) |
| RF6.1.7 (live) | Partner Center read-only confirmation | Product identity, latest published version, bundle-compatibility | BLOCKED — no credentials in execution environment; requires operator with `microsoft-store-production` secrets |

## Deviations or Decisions

- **D5 version encoding** replaces the older revision-only `A.B.C.0` transform so build numbers do not collide.
- **One multi-architecture bundle** replaces two loose per-architecture `.msix` submissions (current CLI `msstore` v0.3.9 accepts one package path per invocation).
- **StoreBroker removed**: the official Microsoft Store Developer CLI (`msstore` v0.3.9) is used, installed with a pinned, digest-verified archive from `Product.props`.
- **Stable GitHub Release is the production authorization boundary**: `workflow_dispatch` accepts only an existing `release_tag`; no arbitrary version/package inputs.
- **Centralized configuration (schema 1)**: `build/Product.props` is the single human-edited source; `build/branding.json` and StoreBroker config are removed; all scripts/workflows consume `Get-EchoDistributionConfiguration`/`-AsJson`.
- **Live gate**: first live submission requires a new stable release, configured `microsoft-store-production` Environment secrets, and an authorized operator; this report does not claim a live submission.