# Requirements and Formula Traceability Report

- **Feature / Increment:** Correction of the release-driven Microsoft Store CD
  pipeline defects found by the post-execution audit
  (PLAN-20260811-RELEASE-CD-HARDENING)
- **Date:** 2026-08-11
- **Responsible:** Repository maintainer / plan-conformance executor
- **Status:** IMPLEMENTED AND LOCALLY VERIFIED; live Partner Center confirmation
  and the first live submission remain operator-gated

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.7 | `docs/public/spec/requirements-spec.md` §RF6.1 | Store version derived deterministically and monotonically at `A.B.C.D → A.B.S.0` (packing base 256); single unsigned `.msixbundle` with exactly one x64 and one ARM64 inner package; published stable GitHub Release is the sole production gate; submission is idempotent, non-deleting, fail-closed and correlates the pending target with version/package/hash | Stable release resolves to the real tag commit; re-runs reuse an exact matching release; conflicts/drafts/pre-releases fail closed; downloaded Store bytes match the manifest and checksum pair before any mutation |
| RF6.1.6 | `docs/public/spec/requirements-spec.md` §RF6.1 | Visual identity parity across MSIX and unpackaged distributions from a common brand source | `Generate-BrandAssets.ps1 -Check` passes; icon sizes/capabilities/architectures derived from `Product.props`, no active duplicate literals |
| RF6.1.1–RF6.1.5, RF6.2–RF6.5 | `docs/public/spec/requirements-spec.md` | Unchanged product behavior | No Rust/C#/XAML/DSP/FFI/rendering source behavior changed by this plan |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship |
|---|---|---|---|
| RF6.1.7 (GitHub provenance, R2/R3/R4/R5) | `scripts/modules/Echo.GitHubRelease.psm1` :: `Invoke-EchoGitHubCommand`, `ConvertTo-EchoJsonDocument`, `Resolve-EchoTagCommitSha`, `Get-EchoGitHubReleaseByTag`, `Test-EchoGitHubReleaseCompatibility`, `Test-EchoChecksumPair` | Tag `vA.B.C.D`; commit SHA-256 (40 hex); asset set {name,size}; `filename → hash` checksum pairs | `gh` output parsed as one JSON document (never per-element); lightweight and annotated tags recurse to a commit; release idempotency only when tag/commit/assets/sizes exact; checksums validated by exact file-name pair |
| RF6.1.7 (release workflow) | `.github/workflows/release.yml` | Real tag SHA; CI gates; manifest + `SHA256SUMS.txt`; exact asset set | Checkout of the real commit; create-draft once, re-use an exact compatible release, fail closed on draft/prerelease/conflict; post-upload asset verification; annotated-tag dereference |
| RF6.1.7 (Store resolve) | `.github/workflows/store-publish.yml` | Tag name, product version, resolved commit | Same tag→SHA as release; checkout that SHA in consuming jobs instead of `target_commitish`; recompute downloaded bundle hash vs manifest record and checksum pair |
| RF6.1.7 (submit/pending correlation, R9/R10/R11/R12) | `scripts/modules/Echo.StoreSubmission.psm1` :: `Get-EchoStoreSubmissionState`, `Test-EchoStoreStateSafeToProceed`, `Invoke-EchoMsStoreCli`, `Test-EchoMsStoreTransientFailure`, `Get-EchoRedactedText` | `CurrentState`, `LatestPublishedVersion`, `PendingTargetVersion`, `PendingPackageName`, `PendingPackageHash`; retry cap/backoff | State, version and pending package are separate data points; `upload` only for NoSubmission/Published with monotonic target; `commit-resume` only for an exact pending match; active states monitor-only; terminal/unknown fail closed 429/5xx retried, auth/validation never; secrets redacted |
| RF6.1.7 (CLI installer, R6) | `scripts/Install-MicrosoftStoreCli.ps1` | msstore `0.3.9`; archive `MSStoreCLI-win-x64.zip`; SHA-256 `bf2f9aa…`; .NET 9 `9.0.316` | Fixed parser interpolation; publisher-checksum mismatch is a hard error; pinned digest authoritative; `--version` smoke test reports the exact pinned version |
| RF6.1.7 (config consumers, R13/R14) | `scripts/Build-Distributions.ps1`, `scripts/New-EchoReleaseManifest.ps1`, `scripts/Test-StoreReleaseArtifact.ps1`, `scripts/modules/Echo.ReleaseMetadata.psm1` | runtime/rust/platform/capabilities/icon-sizes/artifact-type | All derived from `Product.props`; parser rejects unknown items/metadata, missing groups, duplicate architectures, invalid capability names/elements and boolean/scale/width type errors |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| RF6.1.7 (GitHub JSON/tag/release/checksum) | `tests/scripts/Test-ReleaseHardening.ps1` R2/R3/R4/R5 | object vs array vs NDJSON rejection; lightweight vs annotated tag; compatible vs conflicted/draft/prerelease release; exact vs wrong-name vs wrong-hash checksum pair | PASS (local) |
| RF6.1.7 (Store state/correlation) | `Test-ReleaseHardening.ps1` R9/R10 | NoSubmission, Published, PendingCommit matching/conflicting, active, terminal, unknown; separated version/package/hash | PASS (local) |
| RF6.1.7 (retry/redaction) | `Test-ReleaseHardening.ps1` R11 | 429/5xx transient retried and capped; 401/validation never retried; secrets absent from messages | PASS (local) |
| RF6.1.7 (CLI installer) | `Test-ReleaseHardening.ps1` R6 + parser check | zero parse errors; no broken `$expectedVersion:` interpolation remains | PASS (0 parse errors across all scripts/modules) |
| RF6.1.6/RF6.1.7 (config) | `Test-ReleaseHardening.ps1` R13/R14 | unknown item/metadata, missing group, duplicate architecture, invalid capability name/element; config-derived projections | PASS (all fail closed) |
| RF6.1.7 (workflows) | `actionlint` v1.7.12 over all workflows + composite action | no `.items[]`→`ConvertFrom-Json`; full-SHA pins including composite `setup-dotnet`; pinned Windows runner | PASS |
| RF6.1.7 (literal drift) | CI `Audit Distribution Literal Duplicates` | Product ID, PFN, CLI version/asset/hash, artifact type only in `Product.props` and shared module (boundary-aware; packing base and icon sizes excluded as schema constants/structural) | PASS (0 violations) |
| RF6.1.6 (branding) | `Generate-BrandAssets.ps1 -Check` | byte-equivalent generated assets | PASS (local) |
| RF6.1.7 (packaging) | `Test-StoreReleaseArtifact.ps1` on the existing local x64+ARM64 bundle + regenerated manifest | exact `msixbundle` type from config; inner x64+ARM64 | PASS (local, offline) |
| RF6.1.7 (live) | Partner Center read-only confirmation and first authorized submission | product identity, latest published version, bundle compatibility | BLOCKED/OPERATOR-GATED — no credentials in execution environment; requires `microsoft-store-production` secrets and an explicitly authorized stable release |

## Deviations or Decisions

- **Shared provenance module (D2):** `Echo.GitHubRelease.psm1` is the single
  boundary for `gh` JSON parsing, tag dereference and release identity used by
  both `release.yml` and `store-publish.yml`, replacing two divergent inline
  parsers.
- **Release identity = (tag, commit, version, asset set, hashes) (D3):** recovery
  is idempotent only when every component matches; any conflict stops instead of
  deleting/overwriting.
- **State separation (D4):** `CurrentState`, `LatestPublishedVersion`,
  `PendingTargetVersion` and `PendingPackageName/Hash` are independent; no
  textual state is coerced into a version.
- **Limited retries (R11):** only unambiguous 429/5xx failures are retried with a
  capped backoff; auth/validation/identity/monotonicity/unknown never retried.
- **Recovery is destructive-guarded (R12):** `delete-target-draft` requires an
  explicit input and an exact version/package match before deletion.
- **Config centralization (R13/D5):** build projections, manifest and artifact
  validation consume `Product.props`; duplicate active literals are audited.
- **Where the audit findings were corrected:** the malformed archived-plan R16
  row was repaired and a correction notice chained to this plan; the archived
  matrix/checkpoints are superseded by this plan's living compliance matrix
  rather than being silently rewritten.
- **Live gate:** first live submission requires a new stable release, configured
  `microsoft-store-production` Environment secrets, and an authorized operator;
  this report does not claim a live submission.
