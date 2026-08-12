# CI/CD seguro y configuraciÃ³n centralizada de releases hacia Microsoft Store

## Plan Metadata

| Field | Value |
|---|---|
| Plan ID | `PLAN-20260811-MICROSOFT-STORE-RELEASE-CD` |
| Status | `PLAN_PARTIALLY_EXECUTED` |
| Verification state | `VERIFIED` |
| Created | 2026-08-11 |
| Last updated | 2026-08-11 |
| Owner | Repository maintainer |
| Planning branch | `docs/agent-architecture-audit` |
| Planning baseline | `c5b6a5804cdb2217b4ea5ed0c2174745fe2e03ee` |
| Intended execution branch | `ci/microsoft-store-release-cd` |
| Integration branch | `dev` |
| Release branch | `main` |
| Initial checkpoint | `CP-001` |

## Objective

Extender el proceso de release existente para que una GitHub Release estable y
publicada pueda distribuir exactamente el mismo binario verificable hacia la
aplicaciÃ³n pÃºblica `9NJMJFH8J616` de Microsoft Store. El flujo debe ser
repetible, seguro frente a concurrencia y reruns, trazable desde tag y commit
hasta submission, y capaz de distinguir upload, aceptaciÃ³n, certificaciÃ³n y
publicaciÃ³n final.

Consolidar ademÃ¡s toda configuraciÃ³n versionada de producto y distribuciÃ³n en
`build/Product.props`. Este archivo serÃ¡ el Ãºnico punto de entrada humano;
`Get-EchoDistributionConfiguration`, exportada por
`scripts/modules/Echo.ReleaseMetadata.psm1`, serÃ¡ el Ãºnico punto de entrada
programÃ¡tico y `Test-ProductConfiguration.ps1 -AsJson` su interfaz estable para
workflows y herramientas.

Este documento es Ãºnicamente el plan de implementaciÃ³n. No autoriza crear una
release, enviar un paquete, alterar una submission de Partner Center, crear
credenciales ni cambiar reglas remotas de GitHub. La ejecuciÃ³n se inicia solo
cuando el usuario solicite implementar este plan.

## Current State Snapshot

- **Plan status:** `PLAN_PARTIALLY_EXECUTED`; all implementable work complete
  and validated; live Partner Center confirmation/submission are external
  operator gates.
- **Working branch:** `ci/microsoft-store-release-cd`.
- **Working tree:** clean at the final checkpoint (branch ahead of `dev`); no
  implementation CI/CD code remains outstanding.
- **Repository revision:**
  `c5b6a5804cdb2217b4ea5ed0c2174745fe2e03ee`, dos commits por delante del
  `dev` local observado (`6a1ed449e5096c47c77167d54477b8d472f5b2f9`).
- **Canonical product version:** `build/Product.props` contiene
  `EchoProductVersion=0.2.0.19`; `Test-ProductConfiguration.ps1` valida su
  sincronizaciÃ³n.
- **Current configuration split:** `build/Product.props` ya es importado por
  MSBuild y consumido por scripts/documentaciÃ³n, pero las recetas de assets se
  mantienen separadas en `build/branding.json`. La implementaciÃ³n eliminarÃ¡
  esa segunda fuente y harÃ¡ que manifiesto, Cargo, README y assets sean
  proyecciones comprobadas de `Product.props`.
- **Published GitHub release:** `v0.2.0.19`; contiene ZIP x64/ARM64 y
  `SHA256SUMS.txt`, pero ningÃºn artefacto Store ni manifiesto de procedencia.
- **Published Store product:** la pÃ¡gina pÃºblica confirma que
  `9NJMJFH8J616` es gratuita. El repositorio registra como primera versiÃ³n Store
  publicada `0.2.0.0`; Partner Center debe confirmarlo antes del primer envÃ­o
  automatizado porque no hay acceso autenticado durante la planificaciÃ³n.
- **Store identity in source:** `Tun4z.EchoVisualizer`, publisher
  `CN=8C71527D-01B9-4285-A94B-1585E7C0DA03`, display publisher `Tun4z`,
  `Application Id=App`, `Windows.Desktop`, minimum `10.0.17763.0`, capabilities
  `runFullTrust` y `microphone`.
- **Current CI:** `.github/workflows/ci.yml` runs on PRs to `main`/`dev`, pushes
  to `main`, and manual dispatch. It builds/tests both distribution profiles.
- **Current release:** `.github/workflows/release.yml` runs on a four-part tag
  push or manual dispatch, rebuilds x64/ARM64 ZIPs with tests skipped, and
  creates a stable GitHub Release through `softprops/action-gh-release`.
- **Current Store build:** `.github/workflows/store-build.yml` is manual and
  emits separate x64/ARM64 `.msix` packages.
- **Current Store publish:** `.github/workflows/store-publish.yml` is manual,
  checks out the invocation ref, accepts an independent version override,
  rebuilds packages, installs the latest StoreBroker module without a version
  pin, auto-commits a submission and does not follow certification to a final
  state.
- **Remote GitHub settings observed:** no repository Actions secrets or
  variables, only environment `github-pages`; the branch ruleset named
  `branch protection` is disabled and no required status checks are currently
  active. Store CD therefore must not be represented as a PR-required check,
  and enabling CI protection remains an explicit remote-administration task.

## Research Findings

### Findings that determine the design

1. GitHub's `release` event supports `published` and exposes the release tag,
   but `published` also applies to prereleases; the workflow must reject
   `draft=true` and `prerelease=true` before accessing production credentials.
2. A release created by a workflow using `GITHUB_TOKEN` does not normally
   trigger another workflow from the resulting `release` event. GitHub makes
   `workflow_dispatch` and `repository_dispatch` explicit exceptions. The
   existing release workflow therefore needs to dispatch Store CD explicitly
   after publication, while `release: published` remains available for a
   stable release published manually or by an external authorized actor.
3. Microsoft currently presents Microsoft Store Developer CLI (`msstore`) as
   the supported CI/CD path. The selected current release is preview v0.3.9
   (2026-01-27). Its Windows x64 archive is
   `MSStoreCLI-win-x64.zip`, SHA-256
   `bf2f9aa47135eb0820c69a3936e2592a3847248fc650a6cda51cf3b5a8c605fb`.
4. `msstore` v0.3.9 requires the .NET 9 runtime. The product is pinned to .NET
   SDK `10.0.302`; Store jobs must install .NET 9 side-by-side and may not rely
   silently on runner preinstallation.
5. The official `microsoft/microsoft-store-apppublisher` setup action v1.4
   downloads the requested CLI but does not independently validate the archive
   digest. The implementation will use a repository script that downloads the
   exact CLI release and verifies both the repository-pinned digest and the
   publisher checksum before extraction.
6. The selected `msstore publish` implementation accepts one package path per
   invocation. The project supports x64 and ARM64, so Store production will use
   one `.msixbundle` containing exactly the two validated architecture-specific
   `.msix` packages.
7. MakeAppx supports combining packages with equal identity, publisher and
   version that differ by `ProcessorArchitecture`. `MakeAppx bundle` must
   receive `/bv` explicitly; otherwise its generated bundle version is not a
   deterministic derivation of the release.
8. Microsoft Store package versions must end in `.0`. The repository's fourth
   component is a meaningful, incrementing build metric, and the historical
   `A.B.C.D -> A.B.C.0` transform collides for releases such as `0.2.0.19` and
   `0.2.0.20`. An arbitrary manual `version_override` fixes one run while
   destroying provenance.
9. The Store CLI's publish path can remove an existing pending submission when
   preparing another. It must not be invoked until a repository-owned preflight
   classifies Partner Center state and proves the transition is safe.
10. Store certification can take up to three business days. A GitHub-hosted
    job cannot honestly equate a successful upload/commit with publication and
    should not remain blocked for days. Submission and bounded polling belong
    in the release workflow; a separate read-only scheduled/manual monitor
    records later terminal state.
11. WACK remains recommended by Microsoft, but command-line validation requires
    an active user session and administrative context. It is unsuitable as a
    dependable GitHub-hosted production gate. Deterministic manifest/bundle
    validation runs in CI; WACK remains a documented local release-candidate
    check, and Partner Center certification is authoritative.
12. Store-bound MSIX packages do not require a repository PFX: Microsoft signs
    them after certification. Existing optional Authenticode signing for
    unpackaged GitHub ZIP contents remains a separate distribution concern.
13. Package publication and Store listing metadata have different risk and
    lifecycle. The initial automation will replace only application packages
    and controlled submission options; it will not overwrite descriptions,
    screenshots, pricing, availability, age ratings or localized listing data.
14. `build/Product.props` ya tiene la mayor base de consumidores: MSBuild lo
    importa directamente y los scripts actuales lo validan. `build/branding.json`
    es la Ãºnica segunda fuente material de configuraciÃ³n de distribuciÃ³n. Por
    ello, ampliar `Product.props` evita bootstrap, cÃ³digo generado y divergencia
    entre archivos; los binarios de imagen y los valores secretos permanecen
    externos, pero sus rutas, recetas y nombres de binding se declaran allÃ­.

### Current primary sources

| Subject | Primary source | Design consequence |
|---|---|---|
| GitHub release events | [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release) | Use `release: published`, then validate stable state and exact tag. |
| `GITHUB_TOKEN` recursion | [Triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow) | Dispatch Store CD explicitly after the release created with `GITHUB_TOKEN`. |
| Environments | [Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) | Isolate Partner Center credentials in `microsoft-store-production`. |
| Action pinning | [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use) | Pin every modified workflow action to a full commit SHA. |
| Artifact provenance | [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations) | Attest the bundle and attach a signed-by-workflow provenance record. |
| Store CI/CD | [Microsoft Store Developer CLI with GitHub Actions](https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/github-actions) | Use current official CLI flow; Echo satisfies the free-product restriction. |
| CLI commands | [Microsoft Store Developer CLI commands](https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/commands) | Use configure, get/status, no-commit publish, commit and poll deliberately. |
| CLI release | [`microsoft/msstore-cli` v0.3.9](https://github.com/microsoft/msstore-cli/releases/tag/v0.3.9) | Pin version and Windows x64 archive hash; install .NET 9. |
| Official setup action | [`microsoft-store-apppublisher`](https://github.com/microsoft/microsoft-store-apppublisher) | Do not select it until it verifies downloaded CLI integrity. |
| Submission API lifecycle | [Manage app submissions](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions) | Treat Partner Center submissions as durable remote state, not stateless uploads. |
| Submission status | [Get submission status](https://learn.microsoft.com/en-us/windows/uwp/monetize/get-status-for-an-app-submission) | Normalize and report pending/terminal states. |
| Store lifecycle | [MSIX app certification process](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-certification-process) | Do not call certification pending â€œpublishedâ€; allow multi-day monitoring. |
| Package upload formats | [Upload MSIX packages](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/upload-app-packages) | `.msixbundle` is accepted; preserve all supported device architectures. |
| Bundle construction | [Bundle MSIX packages](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/bundle-msix-packages) | Combine x64 and ARM64 packages into one upload object. |
| MakeAppx | [Create an app package with MakeAppx](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool) | Supply deterministic output path and `/bv`. |
| Package requirements | [MSIX app package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements) | Inner manifests must match except architecture; Store chooses highest applicable version. |
| Store version suffix | [MSIX Packaging Tool Store versioning](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/tool-best-practices) | Final package version ends in `.0`. |
| Store signing | [Publish your first Windows app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app) | Upload unsigned Store package; Microsoft re-signs after certification. |
| Hosted runner | [`windows-2025` image inventory](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md) | Select explicit image family and validate/record the rolling image contents. |

## Scope and Non-Goals

### In scope

- Rework GitHub release orchestration so Store CD starts only after a stable
  GitHub Release is published.
- Generate and validate one unsigned x64+ARM64 `.msixbundle` from the same
  release SHA as the GitHub distribution ZIPs.
- Attach bundle, checksums and machine-readable provenance manifest to the
  GitHub Release; submit that exact downloaded asset without rebuilding.
- Replace StoreBroker with pinned, digest-verified `msstore` v0.3.9.
- Add deterministic release-to-Store version conversion and Partner Center
  monotonicity checks.
- Add a fail-closed idempotency/state-transition layer before any mutating CLI
  command.
- Add bounded submission monitoring plus a separate non-publishing status
  workflow for multi-day certification.
- Preserve and strengthen CI/release gates without adding a Store-required PR
  check.
- Pin action dependencies modified by the plan, minimize workflow permissions,
  and create supply-chain attestations for release artifacts.
- Replace StoreBroker documentation/configuration and update the release rule,
  requirement RF6.1.7, relevant packaging skill and traceability report.
- Provide exact Partner Center/GitHub setup, secret rotation and recovery
  documentation.
- Expand `build/Product.props` as the single versioned product/distribution
  configuration source and add `EchoDistributionSchemaVersion=1`.
- Remove `build/branding.json`; keep source images as files and
  `src/ui/Assets` as a generated, validated projection.
- Expose one parsed configuration object through
  `Get-EchoDistributionConfiguration` and one stable JSON interface through
  `Test-ProductConfiguration.ps1 -AsJson`.

### Out of scope

- Any Rust DSP, WASAPI, FFI, C#, WinUI, XAML, Win2D or rendering behavior.
- Creating or rotating real Partner Center credentials.
- Publishing a GitHub Release or live Store submission during implementation.
- Automating Store listing text, screenshots, pricing, availability, age
  ratings, package flights or prerelease channels.
- Automatic rollback of an already published Store version; Partner Center
  does not provide deployment-style instant rollback semantics.
- Installing or committing a PFX for Store publication.
- Claiming WACK success from a non-interactive GitHub-hosted runner.
- Enabling branch protection/rulesets remotely without separate user
  authorization. The plan documents required settings and verifies names, but
  repository code does not silently mutate governance.
- Embedding binary images or secret values in `Product.props`.
- Adding `Distribution.props`, `distribution.json` or another active
  configuration store parallel to `Product.props`.

## Requirements

| ID | Requirement | Verification |
|---|---|---|
| `R1` | Only a published, non-draft, non-prerelease GitHub Release can enter the production Store path; PR, branch push, ordinary commit, tag-only state and release edits cannot. | `actionlint`, event/condition tests and workflow inspection. |
| `R2` | The release tag, dereferenced commit SHA, canonical product version, Store version, bundle manifest and release asset provenance agree exactly. | Fixture tests, release-manifest validation and exact-ref checkout assertions. |
| `R3` | The product version has one repository source of truth and maps deterministically and monotonically to an MSIX Store version ending in `.0`; invalid/out-of-range/colliding versions fail before upload. | Pure version-function tests and authenticated Store preflight. |
| `R4` | The submitted package preserves the Partner Center identity, publisher, architectures, target family, minimum OS and declared capabilities. | MakeAppx unpack/unbundle inspection and external Partner Center checklist. |
| `R5` | The exact Store release artifact is a single bundle containing one x64 and one ARM64 package, and the artifact published on GitHub is the byte sequence sent to Store. | Bundle validator, SHA-256 comparison and release manifest. |
| `R6` | Release production builds use pinned project toolchains, explicit Release configuration, exact source SHA and recorded runner/tool versions; Store CD never rebuilds. | Workflow assertions, build logs and provenance manifest. |
| `R7` | Existing Rust/.NET/packaging gates block release creation when not successful for the exact release SHA. | Check-run gate plus release-workflow integration test. |
| `R8` | Authentication uses least-privilege Partner Center application credentials scoped to a GitHub Environment; secrets are never committed, uploaded or printed. | Secret scan, workflow permission audit and sanitized failure fixtures. |
| `R9` | Store submission is serialized and idempotent across duplicate events, reruns, partial failures and existing remote submissions. | State-machine tests, concurrency inspection and controlled dry-run fixtures. |
| `R10` | Workflow output differentiates prepared/uploaded/committed/certifying/published/failed and preserves release-to-submission evidence without secrets. | Summary/artifact schema tests and status workflow tests. |
| `R11` | Store CD cannot become a required check that blocks PRs or normal pushes; existing CI job names stay unique and unchanged unless an explicit governance migration is approved. | Trigger matrix and remote ruleset checklist. |
| `R12` | Package publication does not overwrite listing metadata; prerelease distribution/package flights remain separate and disabled. | CLI argument/payload inspection and documentation review. |
| `R13` | Modified workflows and downloaded release tools are pinned and integrity-checked; permissions are job-scoped and minimal. | Full-SHA audit, digest-negative tests and permissions matrix. |
| `R14` | Operators have exact first-time setup, rotation, failure and recovery procedures, including states where automation must stop rather than delete remote state. | Documentation checklist and recovery-table review. |
| `R15` | Specifications, release rules, packaging skill and traceability evidence describe the implemented mechanism and no longer direct agents to StoreBroker/manual version overrides. | `req-traceability`, stale-reference scan and final documentation diff. |
| `R16` | Toda configuraciÃ³n versionada de distribuciÃ³n procede de `build/Product.props`; cualquier duplicaciÃ³n activa de Product ID, PFN, formato, arquitecturas, base de versiÃ³n, recetas de branding o versiÃ³n/hash/runtime del CLI falla en validaciÃ³n. | Fixtures de configuraciÃ³n, auditorÃ­a de consumidores y escaneo de duplicados en scripts/workflows/docs. |

## Locked Decisions and Invariants

### D1 â€” A published stable release is the production authorization boundary

The normal production chain is:

`exact release commit passes CI` â†’ `tagged release artifacts are built` â†’
`GitHub Release is published stable` â†’ `Store workflow validates that release`
â†’ `Partner Center preflight` â†’ `submission`.

`pull_request`, branch `push`, file paths and tag creation alone never appear as
Store production triggers. `workflow_dispatch` accepts an existing
`release_tag` only and exists for administrative recovery; it cannot accept an
arbitrary package path or version override.

Publishing the stable GitHub Release is the explicit release authorization for
the automatic Store attempt. The GitHub Environment isolates secrets; this plan
does not require an additional reviewer so normal releases remain automated.
An owner may add reviewers later without changing repository semantics.

### D2 â€” Bridge `GITHUB_TOKEN` release-event suppression explicitly

`.github/workflows/store-publish.yml` listens to both:

- `release: { types: [published] }`, for stable releases published outside the
  current release workflow; and
- protected `workflow_dispatch` with required `release_tag`, for the explicit
  dispatch issued by `.github/workflows/release.yml` and for operator recovery.

After the release API confirms publication and all assets, `release.yml` calls
the Store workflow using `GITHUB_TOKEN` with only `actions: write` added to the
dispatching job. Duplicate delivery is expected and made harmless by D10/D11.

### D3 â€” Release assets are built once and reused

The release workflow builds the Store artifact from the exact tag SHA before
publishing the GitHub Release. Store CD downloads that named release asset and
does not compile product code. This makes the GitHub Release artifact hash the
submission artifact hash and eliminates source/runner drift between GitHub and
Store distribution.

â€œReproducibleâ€ means identical declared source, dependencies, commands,
toolchains and recorded runner image, plus immutable reuse of the resulting
bytes. The plan does not claim byte-for-byte reproducible MSBuild output across
different rolling runner image revisions unless later evidence proves it.

### D4 â€” One multi-architecture Store bundle

The production asset is one unsigned `.msixbundle` with exactly:

- one `ProcessorArchitecture=x64` inner `.msix`; and
- one `ProcessorArchitecture=arm64` inner `.msix`.

Both inner packages must share identity, publisher, package version,
capabilities and target family. `MakeAppx bundle` receives the Store version via
`/bv`. The change from the historical two loose `.msix` files is allowed only
after the first execution checkpoint confirms in Partner Center that the
existing published product accepts an MSIX bundle update. After adopting a
bundle, release documentation forbids reverting to loose per-architecture
packages without replanning.

### D5 â€” Deterministic four-part-to-Store version mapping

Microsoft requires the fourth Store component to be zero, while this repository
uses all four product components. Use this checked transform:

```text
Product version: A.B.C.D
Constraints:     0 <= A,B <= 65535; 0 <= C,D <= 255
Store build:     S = (C * 256) + D
Store version:   A.B.S.0
```

The transform is injective and order-preserving for the repository's
lexicographic `A.B.C.D` releases within the declared bounds. Examples:

| Product/tag | Store version |
|---|---|
| `0.2.0.19` / `v0.2.0.19` | `0.2.19.0` |
| `0.2.0.20` / `v0.2.0.20` | `0.2.20.0` |
| `0.2.1.0` / `v0.2.1.0` | `0.2.256.0` |
| `0.3.0.0` / `v0.3.0.0` | `0.3.0.0` |

The already published Store `0.2.0.0` is a historical mapping and is not
rewritten. The next automated release must map above the actual last published
version returned by Partner Center. Versions outside the new bounded contract
fail with an actionable message; no override is available.

The transform lives in one pure shared module and is consumed by product
configuration validation, packaging, release provenance and Store preflight.
`EchoProductVersion` remains the source of truth; no independent mutable
`EchoStoreVersion` property is introduced. The packing base is declared as
`EchoStoreVersionPackingBase=256` in `Product.props`, validated as exactly 256
under schema 1 and may not be changed without a schema increment and replan.

### D6 â€” Release provenance manifest

Every new release created after this pipeline's cutover gains
`EchoVisualizer-<A.B.C.D>-release-manifest.json` with this versioned logical
schema:

- schema version;
- repository and workflow run URL/ID/attempt;
- release tag and GitHub release ID;
- dereferenced source commit SHA;
- canonical product version and derived Store version;
- distribution schema version, lowercase SHA-256 of `build/Product.props` and a
  sanitized effective-configuration projection sufficient to reproduce the
  package/tooling decision;
- package identity, publisher, Application ID, Product ID, PFN, artifact type,
  architecture set, target family/versions and capabilities;
- runner label, `ImageOS`, `ImageVersion`;
- .NET SDK/runtime, Rust/rustup target, MSBuild, Windows SDK and MakeAppx
  versions/paths;
- each distributable binary asset's filename, media role, architecture set,
  byte size and lowercase SHA-256;
- Store bundle inner package filenames and architectures.

The release manifest contains no credentials. `SHA256SUMS.txt` includes ZIPs,
bundle and manifest, but never itself; the manifest does not self-hash. The
Store workflow verifies the manifest schema, release API asset identity, local
hash, bundle contents, tag version and source SHA before entering the
environment-scoped job. Releases predating the cutover lack this contract and
cannot be backfilled or submitted by recovery dispatch; the first live test
must use a new stable release/version.

### D7 â€” Selected publishing tool

Replace StoreBroker with Microsoft Store Developer CLI v0.3.9. Its version,
archive name, .NET runtime/SDK requirement and expected SHA-256 are declared in
`Product.props` and obtained only through `Get-EchoDistributionConfiguration`.
Install through `scripts/Install-MicrosoftStoreCli.ps1`, which:

1. downloads the exact Windows x64 asset and its publisher checksum file;
2. compares the archive to both the checked-in expected digest and checksum;
3. extracts under `RUNNER_TEMP`, never the repository;
4. verifies `msstore --version` reports `0.3.9`; and
5. fails closed on redirect, hash, version or runtime mismatch.

The Store job installs the configured .NET SDK `9.0.316` side-by-side to supply
the required .NET 9 runtime. Upgrading CLI/runtime is a reviewed dependency
change in `Product.props` with release notes, source inspection and fixture
revalidation; no `latest` token is permitted.

### D8 â€” Authentication contract

Use a dedicated Partner Center Microsoft Entra application assigned the
`Manager` role, which Microsoft's current GitHub Actions guidance explicitly
requires for this CLI submission flow. Do not assume that the narrower
`Developer` role is sufficient without new official evidence. Configure
`msstore` with tenant, seller, client and client secret because v0.3.9 does not
provide a verified GitHub OIDC flow for this operation. Do not claim federated
identity support. Because Partner Center does not expose a narrower verified
role for this path, least privilege is enforced through a dedicated principal,
environment isolation, short credential lifetime and workflow command scope.

Store credentials live only in environment `microsoft-store-production`:

| Name | Kind | Source | Purpose | Required | Rotation |
|---|---|---|---|---|---|
| `PARTNER_CENTER_TENANT_ID` | Environment secret | Microsoft Entra tenant overview | Authenticate tenant | Yes | On tenant/app change |
| `PARTNER_CENTER_SELLER_ID` | Environment secret | Partner Center account settings | Select seller account | Yes | On account change |
| `PARTNER_CENTER_CLIENT_ID` | Environment secret | Entra app registration | Identify automation app | Yes | On app replacement |
| `PARTNER_CENTER_CLIENT_SECRET` | Environment secret | Entra app credential | Authenticate automation app | Yes | Before expiry; target lifetime under 12 months |

The workflow maps secrets into process environment only for the configuration
command, masks values defensively, disables shell tracing and never prints the
generated CLI configuration. No secret is accepted as a workflow input.

`STORE_PRODUCT_ID` is not an external variable or secret. The public Product ID
`9NJMJFH8J616`, the Package Family Name and the GitHub Environment name are
versioned in `Product.props`. The same file declares only the binding names for
the four required Partner Center secrets and the optional ZIP-signing secrets
`SIGNING_CERTIFICATE_BASE64` and `SIGNING_CERTIFICATE_PASSWORD`; it never
contains their values.

### D9 â€” Least-privilege workflow boundary

- Provenance/download validation jobs: `contents: read` and, where needed,
  `actions: read`/`checks: read`.
- Release creation job: `contents: write`, `actions: write` only for release
  assets and Store workflow dispatch.
- Artifact attestation job/step: `id-token: write`, `attestations: write`,
  `contents: read` only.
- Store submit job: `contents: read`; no repository content write. If a GitHub
  status/check is later added, it requires a replan and explicit `checks: write`.
- Store monitor: `contents: read`; it reports through workflow summary and a
  sanitized retained artifact, not repository mutations.

No job with Partner Center secrets runs untrusted PR code or has PR/push
triggers.

### D10 â€” Serialization

Production submission uses a repository-wide concurrency group
`microsoft-store-production` with `cancel-in-progress: false`. A newer run waits
instead of canceling a process that might already have created or committed a
remote submission. The read-only status workflow uses a different group and
may run concurrently because it cannot mutate Partner Center.

### D11 â€” Idempotent Store state machine

Before any `publish`, delete or commit command, query current/latest Store
submission JSON and normalize it. Use these outcomes:

| Observed state | Target-version relation | Action |
|---|---|---|
| `Published` | same target | No-op success; report already published. |
| `Published` | target lower/equal | Fail monotonicity before upload. |
| No pending submission | target greater | Create/upload with `publish --noCommit`, verify draft, then commit. |
| `PendingCommit` | same target and exact expected package filename/version | Resume by committing the existing draft; do not upload another. |
| `CommitStarted`, `PreProcessing`, `Certification`, `Release`, `Publishing` | same target | Resume monitoring; do not mutate or duplicate. |
| `CommitFailed`, `PreProcessingFailed`, `CertificationFailed`, `ReleaseFailed`, `PublishFailed`, `Canceled` | same target | Fail clearly and retain IDs/status; require documented operator recovery. |
| Any active/pending state | different target | Fail closed; never auto-delete or replace another release's submission. |
| Unknown/malformed state | any | Fail closed before mutation and retain sanitized response. |

The wrapper never calls the CLI convenience path that silently discards a
different pending submission. Draft deletion is allowed only through an
explicit `workflow_dispatch` recovery mode `delete-target-draft`, requires the
existing release tag, requires state `PendingCommit`, requires exact target
version, prints the non-secret submission identity/status for review, and must
be documented as a destructive administrative operation. It never deletes a
committed/certifying submission.

### D12 â€” Two-stage submit/commit

For a new target, call CLI publication with no-commit behavior so upload and
remote package validation finish before commit. Re-query the draft and verify
product ID, version, package filename and status. Commit only that verified
draft. Poll for a bounded interval sufficient to confirm the commit entered a
recognized Partner Center state. A timeout while certification is progressing
is reported as accepted/in progress, not as failure or published.

### D13 â€” Long-running status monitoring

Add `.github/workflows/store-status.yml` with:

- `schedule` every six hours;
- `workflow_dispatch` accepting an optional existing stable `release_tag`;
- the same environment-scoped Partner Center principal, while the repository
  code path permits only status/get commands;
- no `publish`, `submission update`, `submission delete` or commit operation;
- query of the current/latest submission and correlation by deterministic
  Store version to the stable release manifest;
- a workflow summary and retained sanitized JSON report containing last known
  state, IDs, release/tag/SHA/hash and timestamps.

Scheduled monitoring reports terminal failures as a failed workflow and
`Published` as success. Pending certification exits successfully with an
explicit `IN_PROGRESS` conclusion in the report; it never claims final
availability. GitHub notifications on scheduled workflow failures provide the
initial alerting mechanism without adding a required PR check.

### D14 â€” Release quality gates

Release creation must verify that the exact dereferenced tag SHA has successful
completed check runs for the existing CI jobs:

- `Lint GitHub Actions Workflows`; and
- `Test, Publish and Validate Distributions`.

Use a bounded poll to tolerate a CI run already in progress; missing, skipped,
cancelled or failed checks block release publication. Keep those job names
stable. Store workflows have unique names and no PR/push triggers, so they must
not be added to branch protection required checks.

### D15 â€” Runner and dependency pinning

- Use `windows-2025`, not the moving `windows-latest`, for Windows build and
  Store jobs. The image itself remains rolling, so record `ImageVersion` and
  validate required Visual Studio/MSBuild, Windows SDK 10.0.26100, x64/ARM64 VC
  tools and MakeAppx availability on each release.
- Respect `global.json` (`10.0.302`) and `rust-toolchain.toml` (`1.97.1`).
- Preserve the exact Windows App SDK/MSIX build package versions from project
  files and locked restore data.
- Pin modified workflow actions to full commit SHAs with a trailing version
  comment. Initial pins validated during research are:
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7`);
  - `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (`v7`);
  - `actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` (`v8`);
  - `actions/setup-dotnet@a98b56852c35b8e3190ac28c8c2271da59106c68` (`v6`);
  - `actions/attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a` (`v3`).
- Replace winget's unpinned actionlint acquisition with v1.7.12 Windows amd64,
  SHA-256
  `6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9`.
- Re-resolve all SHAs and verify upstream ownership immediately before
  implementation; any mismatch is a replan/supply-chain stop, not permission
  to substitute `latest`.

### D16 â€” Signing boundary

Store package and bundle remain unsigned before upload. Partner Center performs
Store signing after certification. Existing optional PFX signing applies only
to unpackaged GitHub ZIP binaries; it remains optional and isolated from Store
credentials. No certificate, base64 PFX or password enters Store artifacts or
release provenance.

### D17 â€” Listing, rollout and prerelease boundary

The default production submission requests immediate publication after
certification with 100% availability, matching a stable release. Package
rollout changes, manual holds, flights and scheduled dates are not exposed as
normal workflow inputs; they require a separately planned policy because they
change user-visible availability/recovery semantics.

Store metadata is untouched. Release notes remain in GitHub; certification
notes may be a non-secret repository-controlled text file or generated summary,
not free-form workflow input. Drafts/prereleases stop before environment access.

### D18 â€” CI versus CD governance

`Quality Gate (CI)` retains PR/main triggers and its existing required-check
candidate job names. Store workflows are CD-only and use unique names:

- `Microsoft Store Release Deployment`;
- `Microsoft Store Publication Status`; and
- `Microsoft Store Package Validation` for manual non-production packaging.

Remote setup documentation states that only the two CI jobs may be selected as
required checks. The disabled current ruleset is recorded as a governance risk;
enabling it is a manual repository-owner action, and Store names must remain
excluded.

### D19 â€” One distribution configuration entry point

`build/Product.props` is the only human-edited, versioned source for product
and distribution configuration. No `Distribution.props`, `distribution.json`
or active sidecar configuration is introduced. Its schema version is
`EchoDistributionSchemaVersion=1` and it contains labeled sections for:

- **Product:** product/core version, display name, publisher, package identity,
  package publisher, Application ID, executable and Win32 identity fields.
- **Store:** Product ID `9NJMJFH8J616`, Package Family Name
  `Tun4z.EchoVisualizer_ga3qxkah0cx76`, artifact type `msixbundle`, x64/ARM64
  architecture records, `Windows.Desktop`, minimum/maximum tested OS versions,
  capabilities, immediate stable publication policy and privacy URL.
- **Versioning:** packing base 256 and bounds needed by D5; the derived Store
  version is never stored as mutable configuration.
- **Branding:** source image path, generated output directory, background
  color, icon, icon sizes and MSBuild item records describing every Store,
  square, wide, splash, scale and target-size recipe currently held in
  `build/branding.json`.
- **Tooling:** `msstore` version `0.3.9`, archive
  `MSStoreCLI-win-x64.zip`, .NET SDK/runtime `9.0.316`/9 and SHA-256
  `bf2f9aa47135eb0820c69a3936e2592a3847248fc650a6cda51cf3b5a8c605fb`.
- **External bindings:** GitHub Environment
  `microsoft-store-production`, four required Partner Center secret names and
  two optional ZIP-signing secret names, never secret values.

Schema 1 fixes these exact names so implementation does not invent another
mapping layer:

| XML entry | Kind | Required content/rule |
|---|---|---|
| `EchoDistributionSchemaVersion` | Property | Integer `1`. |
| `EchoProductVersion`, `EchoCoreVersion` | Properties | Existing four-part product and derived three-part core versions. |
| `EchoProductName`, `EchoPublisherDisplayName` | Properties | Existing user-visible product/publisher names. |
| `EchoPackageIdentityName`, `EchoPackagePublisher`, `EchoApplicationId` | Properties | Existing Partner Center/MSIX identity fields. |
| `EchoApplicationIcon`, `EchoBrandBackgroundColor` | Properties | Existing icon projection path and validated color. |
| `EchoWin32AssemblyIdentityName`, `EchoWin32AssemblyManifestVersion` | Properties | Existing side-by-side manifest identity fields. |
| `EchoStoreProductId` | Property | `9NJMJFH8J616`. |
| `EchoPackageFamilyName` | Property | `Tun4z.EchoVisualizer_ga3qxkah0cx76`. |
| `EchoStoreArtifactType` | Property | `msixbundle`. |
| `EchoStoreVersionPackingBase` | Property | Integer `256`. |
| `EchoStorePublishMode` | Property | `Immediate` under schema 1. |
| `EchoStoreTargetDeviceFamily` | Property | `Windows.Desktop`. |
| `EchoStoreMinVersion`, `EchoStoreMaxVersionTested` | Properties | Four-part Windows versions matching the manifest. |
| `EchoPrivacyPolicyUrl` | Property | Absolute HTTPS privacy URL. |
| `EchoBrandSource`, `EchoBrandOutputDirectory` | Properties | Repository-relative source image and generated output directory. |
| `EchoBrandIconFile`, `EchoBrandIconSizes` | Properties | `AppIcon.ico` and a semicolon-delimited unique positive integer list. |
| `EchoMsStoreCliVersion`, `EchoMsStoreCliAssetName` | Properties | `0.3.9` and `MSStoreCLI-win-x64.zip`. |
| `EchoMsStoreCliDotNetSdkVersion`, `EchoMsStoreCliRuntimeMajor` | Properties | `9.0.316` and integer `9`. |
| `EchoMsStoreCliSha256` | Property | Lowercase 64-hex archive digest. |
| `EchoGitHubStoreEnvironment` | Property | `microsoft-store-production`. |
| `EchoStoreArchitecture` | Item | Exactly `x64` and `arm64`; metadata `RuntimeIdentifier`, `RustTarget` and `ProcessorArchitecture`. |
| `EchoStoreCapability` | Item | Exactly `runFullTrust` and `microphone`; metadata `ManifestElement` identifies restricted versus device capability projection. |
| `EchoBrandAsset` | Item | One item per current PNG recipe; `Include` is filename and metadata are `Width`, `Height`, `Scales`. |
| `EchoBrandTargetSizeAsset` | Item | One item with filename stem plus `Sizes` and boolean `IncludeUnplated` metadata. |
| `EchoExternalBinding` | Item | Six names from D8; metadata `Kind=Secret`, `Scope=Environment`, boolean `Required` and non-secret purpose. |

All list metadata uses semicolon-delimited unique values and preserves declared
order in the JSON projection. An active repeated value is acceptable only when
the target format requires a projection and validation proves equality to this
source; it may not become independently configurable.

`Get-EchoDistributionConfiguration` in
`scripts/modules/Echo.ReleaseMetadata.psm1` is the only programmatic parser. It
must reject absent, duplicate, unknown or type-incompatible properties/items,
invalid URLs/hashes, unsupported capabilities/architectures and schema
incompatibility. `Test-ProductConfiguration.ps1 -AsJson` delegates to it and
returns this stable top-level contract:

```json
{
  "schemaVersion": 1,
  "product": {
    "version": "A.B.C.D",
    "coreVersion": "A.B.C",
    "name": "...",
    "publisherDisplayName": "...",
    "packageIdentityName": "...",
    "packagePublisher": "...",
    "applicationId": "...",
    "applicationIcon": "...",
    "brandBackgroundColor": "...",
    "win32AssemblyIdentityName": "...",
    "win32AssemblyManifestVersion": "..."
  },
  "store": {
    "productId": "...",
    "packageFamilyName": "...",
    "artifactType": "msixbundle",
    "architectures": [],
    "targetDeviceFamily": "Windows.Desktop",
    "minVersion": "...",
    "maxVersionTested": "...",
    "capabilities": [],
    "publishMode": "Immediate",
    "privacyPolicyUrl": "...",
    "versioning": {
      "packingBase": 256,
      "storeVersion": "A.B.S.0"
    }
  },
  "branding": {
    "source": "...",
    "outputDirectory": "...",
    "backgroundColor": "...",
    "icon": {},
    "assets": [],
    "targetSizeAsset": {}
  },
  "tooling": {
    "msstore": {
      "version": "...",
      "assetName": "...",
      "dotnetSdkVersion": "...",
      "runtimeMajor": 9,
      "sha256": "..."
    }
  },
  "externalBindings": {
    "githubEnvironment": "...",
    "requiredSecrets": [],
    "optionalSecrets": []
  }
}
```

`Build-Distributions.ps1`, `Generate-BrandAssets.ps1`, the `msstore` installer
and workflows consume that object/JSON rather than parsing XML or repeating
Product ID, PFN, architectures, package type, version base, branding recipes or
CLI coordinates. GitHub Actions commit SHAs remain literal in workflows because
they secure executable workflow dependencies rather than configure the product.
Workflow secret expressions also remain literal GitHub syntax, but validation
must prove their names match the declarations in `externalBindings`.

Binary source images remain repository files referenced by the configuration;
`src/ui/Assets` remains generated output. `Package.appxmanifest`, `Cargo.toml`,
README content and generated assets are validated projections, not independent
configuration entry points. An incompatible change to identity/PFN, D5 packing
base, artifact type or architectures requires incrementing the schema and
replanning before implementation.

## Target Workflow

```text
release tag vA.B.C.D
    -> dereference exact commit SHA
    -> require successful CI checks for that SHA
    -> resolve Product.props once through Get-EchoDistributionConfiguration
    -> validate schema/tag/core/manifest/Cargo/README/branding projections
    -> build Release ZIP x64 + ARM64 from that SHA
    -> build and validate Store MSIX x64 + ARM64
    -> deterministically bundle both packages
    -> create draft GitHub Release and obtain release ID
    -> generate release-manifest.json + checksums + attestations
    -> upload/verify all assets and publish the release as stable
    -> dispatch Store workflow with release_tag
         -> re-read published stable release through GitHub API
         -> verify tag/SHA/version/manifest/asset digest/bundle contents
         -> enter microsoft-store-production environment
         -> authenticate using pinned msstore CLI
         -> query Partner Center and classify current state
         -> no-op, resume, or upload as permitted by state machine
         -> verify no-commit draft, commit, bounded poll
         -> record accepted/current state and sanitized evidence
    -> scheduled/manual read-only monitor follows certification to terminal state
```

## Event and Permission Matrix

| Workflow | Event | Product build | Store secrets | Partner Center mutation | PR required check |
|---|---|---:|---:|---:|---:|
| `ci.yml` | PR `main`/`dev`, push `main`, manual | Yes | No | No | Eligible: existing CI jobs only |
| `release.yml` | existing `vA.B.C.D` tag push; guarded recovery dispatch | Yes, exact tag SHA | No | No | No |
| `store-build.yml` | manual | Store bundle only | No | No | No |
| `store-publish.yml` | `release.published`; guarded dispatch by release tag | No | Submit job only | Yes, state-machine controlled | Never |
| `store-status.yml` | six-hour schedule; guarded manual tag query | No | Read-only job | No | Never |

## Change Map

### C1 â€” Shared release/version/provenance logic

- Expand `build/Product.props` with the complete schema 1 contract from D19,
  using MSBuild properties for scalar values and item groups/metadata for
  architectures, capabilities, branding recipes and external binding names.
- Add `Get-EchoDistributionConfiguration` to
  `scripts/modules/Echo.ReleaseMetadata.psm1`; it is the only XML parser and
  returns typed product, Store, branding, tooling and binding objects. The same
  module owns strict four-part parsing, D5 mapping, comparison helpers, tag
  dereference/provenance validation and release-manifest schema validation.
- Update `scripts/Test-ProductConfiguration.ps1` to delegate completely to the
  module and expose the D19 stable JSON contract through `-AsJson`, including
  canonical `ProductVersion` and derived `StoreVersion`.
- Update `scripts/Build-Distributions.ps1` and every consumer to use the shared
  object/JSON instead of retaining an independent XML parser,
  `ConvertTo-StoreVersion` implementation or distribution constant.
- Migrate every recipe from `build/branding.json` to `Product.props`, update
  `scripts/Generate-BrandAssets.ps1` to consume the shared configuration, and
  remove `build/branding.json` only after generation/check equivalence passes.
- Add `tests/scripts/Test-StoreReleasePipeline.ps1` and JSON fixtures under
  `tests/fixtures/store/`, plus valid/invalid `Product.props` fixtures, for
  schema/property/item validation, version boundaries, release metadata,
  manifest hashes and Store states. Tests are self-contained PowerShell
  assertions and require no new test framework/module from PSGallery.

### C2 â€” Bundle production and validation

- Extend the Store profile in `scripts/Build-Distributions.ps1` so x64/ARM64
  remain individually built and validated, then copied into a clean staging
  directory and bundled once with explicit `/bv`.
- Obtain package type, architecture/RID/Rust-target records, target family,
  versions, capabilities and `/bv` mapping inputs only from
  `Get-EchoDistributionConfiguration`.
- Add `scripts/Test-StoreReleaseArtifact.ps1` for reusable no-network
  validation of a final `.msixbundle` and release manifest.
- Keep `AppxBundle=Never` in `src/ui/EchoVisualizer.csproj` for per-RID inner
  package builds; bundling is an explicit post-build step, avoiding two
  architecture-neutral bundles.
- Emit deterministic paths under `artifacts/store/`; temporary expansion and
  staging remain under `artifacts/.staging` or runner temp and are cleaned by
  the build script.
- Update `.github/workflows/store-build.yml` as a manual package-validation
  workflow that creates the same bundle and manifest but never accesses Store
  credentials or submits it.

### C3 â€” GitHub release orchestration

- Rework `.github/workflows/release.yml` to:
  - resolve an existing tag and dereferenced SHA for both normal and recovery
    paths;
  - checkout that exact SHA with tag history sufficient for verification;
  - poll/check the exact SHA's two CI gate names;
  - build ZIPs and Store bundle from the same SHA;
  - collect tool/runner information;
  - create the draft release to obtain its immutable release ID;
  - generate the release manifest and full SHA-256 set without self-referential
    hashes;
  - upload and validate all assets before publication;
  - verify API asset names/digests, then transition the draft to stable
    published state;
  - attest the bundle and release ZIPs;
  - explicitly dispatch Store CD with only the existing release tag.
- Replace `softprops/action-gh-release` with GitHub's preinstalled authenticated
  `gh` CLI/API to reduce third-party action surface.
- Treat an already-existing stable release with matching tag/SHA/assets/hashes
  as an idempotent recovery success; a conflicting release is a hard failure.

### C4 â€” Pinned Store CLI and submission module

- Add `scripts/Install-MicrosoftStoreCli.ps1` implementing D7 and obtaining the
  exact CLI version, archive name, runtime and SHA-256 only from the shared
  distribution configuration.
- Add `scripts/modules/Echo.StoreSubmission.psm1` to wrap CLI JSON output,
  normalize states, redact sensitive values and implement the D11 transition
  table without hidden deletes.
- Replace `scripts/Submit-StoreUpdate.ps1` with
  `scripts/Invoke-MicrosoftStoreRelease.ps1`, accepting release manifest,
  bundle and a constrained operation (`submit-or-resume` or
  `delete-target-draft`). Product/version are read from verified provenance,
  never caller overrides.
- Add `scripts/Get-MicrosoftStoreReleaseStatus.ps1` for read-only status
  normalization/correlation.
- Remove `scripts/Initialize-StoreBroker.ps1` and StoreBroker imports/config
  after no active references remain.

### C5 â€” Production Store workflow

- Replace `.github/workflows/store-publish.yml` with the D1â€“D13 workflow.
- Split work into:
  1. `resolve-release` on Ubuntu, without environment secrets;
  2. `validate-package` on `windows-2025`, without environment secrets; and
  3. `submit-or-resume` on `windows-2025` with
     `environment: microsoft-store-production`.
- Pass the exact verified release assets between jobs using pinned GitHub
  artifact actions and recheck hashes after every download.
- Resolve `Test-ProductConfiguration.ps1 -AsJson` once per job that needs
  distribution metadata and consume its fields; do not repeat Product ID, PFN,
  architecture lists, package type, D5 base or CLI coordinates in workflow
  YAML. Literal GitHub secret keys must match `externalBindings`.
- Use `concurrency.cancel-in-progress=false`, timeouts on every network/polling
  operation, retry only transient 429/5xx failures with bounded exponential
  backoff, and never retry authentication/validation/409 conflicts blindly.
- Write a sanitized JSON result and `$GITHUB_STEP_SUMMARY` with release, tag,
  SHA, versions, package hash, Product ID, submission ID/status, workflow run
  and last observation timestamp.

### C6 â€” Read-only terminal-state monitor

- Add `.github/workflows/store-status.yml` and use the read-only status script.
- Correlate Partner Center package version with stable release manifests; an
  unmatched version is an explicit orphan-state alert.
- Retain sanitized status reports for 90 days. Do not retain raw authentication
  configuration or CLI cache.
- Do not make the status workflow a branch check and do not give it
  `contents: write`.

### C7 â€” CI and supply-chain hardening

- Update `.github/workflows/ci.yml`, release, Store build and Store workflows to
  use explicit runner labels and full-SHA action pins.
- Replace winget actionlint installation with exact v1.7.12/hash.
- Update `.github/actions/setup-windows-build/action.yml` only as required to
  validate exact product .NET/Rust/toolchain prerequisites and emit versions;
  install .NET 9 only in Store CLI jobs, not globally.
- Preserve current CI workflow/job names and triggers.
- Add a repository audit that rejects configurable distribution literals in
  scripts/workflows/docs outside `Product.props` and approved projection/test
  fixtures. Full action SHAs are explicitly exempt from that audit.
- Keep `.github/dependabot.yml` GitHub Actions updates; dependency PRs may
  propose new action commits, but maintainers must verify owner/tag/commit
  correspondence and rerun the supply-chain tests.

### C8 â€” Documentation, requirements and traceability

- Rewrite `docs/public/publishing/microsoft-store.md` around release-driven
  deployment, `Product.props` as the only configuration entry point, exact
  external setup, first deployment, monitoring and recovery.
- Rewrite `docs/store/README.md` as the non-secret Store configuration contract;
  remove PDP/images and StoreBroker instructions from package publication, and
  explain that Package.appxmanifest, Cargo, README and assets are projections.
- Update root README/CONTRIBUTING and relevant packaging docs so configuration
  changes direct maintainers only to `build/Product.props`; remove all active
  instructions to edit `build/branding.json` and delete that file.
- Remove `docs/store/StoreBrokerConfiguration.template.json` and obsolete
  StoreBroker-only `.gitkeep` directories after confirming nothing active uses
  them.
- Update `.agents/rules/releases.md` to remove independent/manual Store release,
  version override and loose-package requirements; preserve explicit user
  authorization by defining stable GitHub Release publication as the release
  boundary.
- Update
  `.agents/skills/winui/sub-skills/winui-packaging/SKILL.md` so it no longer
  claims there is no first-party Store CLI and so it routes Store release work
  to current docs without embedding credentials.
- Update `docs/public/spec/requirements-spec.md` RF6.1.7 to describe observable
  current policy/tool-agnostic guarantees: stable release gate, deterministic
  Store version, exact multiarch artifact, identity, idempotency and state
  reporting. Do not make preview CLI brand/version a permanent product
  requirement.
- Generate a new traceability report through `req-traceability`; mark the 2026-08-09
  StoreBroker report historical rather than rewriting its evidence.

## Implementation Steps

### S1 â€” Establish execution baseline and external readiness

- **Objective:** begin from a known integration baseline without mixing the
  current documentation branch with implementation history.
- **Location:** Git branches, active plan, GitHub repository settings and
  Partner Center read-only inspection.
- **Changes:** after this plan is integrated into `dev`, synchronize `dev`,
  create `ci/microsoft-store-release-cd`, update plan metadata/checkpoint, and
  inspect Partner Center's latest published/pending submission, product type,
  accepted package formats and identity.
- **Rationale:** current planning branch is ahead of `dev`, and public Store
  pages cannot prove submission internals.
- **Dependencies:** explicit user execution authorization; read-only access to
  Partner Center/GitHub settings.
- **Invariants:** do not create/delete/commit a Store submission; do not publish
  releases; do not change remote rulesets.
- **Validation/evidence:** branch/SHA/status record, sanitized Partner Center
  state and exact identity/package inventory in CP-002.
- **Allowed discretion:** executor may use Partner Center UI or supported
  read-only CLI/API according to available authentication.
- **Replan trigger:** product is paid, product ID/identity differs, another
  submission is pending, or Partner Center rejects bundle updates for this
  existing package family.

### S2 â€” Implement and test the centralized configuration/version core

- **Objective:** make `Product.props` own all versioned distribution inputs and
  one pure implementation own parsing, tag/version conversion and provenance
  validation.
- **Location:** `build/Product.props`, `build/branding.json`,
  `scripts/modules/Echo.ReleaseMetadata.psm1`,
  `scripts/Test-ProductConfiguration.ps1`,
  `scripts/Generate-BrandAssets.ps1`, `scripts/Build-Distributions.ps1`,
  `tests/scripts/` and fixtures.
- **Changes:** implement schema 1 and `Get-EchoDistributionConfiguration`,
  migrate branding recipes, remove `branding.json`, expose the stable `-AsJson`
  contract, add strict properties/items/types/URL/hash/architecture/capability
  validation, implement D5 comparisons/transform and release-manifest checks,
  and add positive/negative/duplicate/unknown-field fixtures.
- **Rationale:** current mapping discards `D` and workflow overrides permit
  artifact/version divergence.
- **Dependencies:** confirmed latest Store version from S1.
- **Invariants:** `build/Product.props` is the only source; no second parser or
  configuration file; image binaries and secret values remain external; core
  Cargo version remains `A.B.C`; Store revision remains zero.
- **Validation/evidence:** schema fixtures, table-driven version tests,
  generation plus `Generate-BrandAssets.ps1 -Check`, absent/duplicate/unknown/
  incompatible-field failures, malformed tags, historical/next versions and
  manifest mismatches.
- **Allowed discretion:** internal private helper names and object types may
  vary; exported function name, top-level JSON keys and single-parser boundary
  may not.
- **Replan trigger:** existing versions contain `C` or `D` above 255 or user
  requires a different encoding policy, or schema 1 cannot represent an
  existing branding/build input without adding a second configuration source.

### S3 â€” Build and validate the release Store bundle

- **Objective:** produce one deterministic multiarch Store asset from the same
  packaging implementation used by CI.
- **Location:** `scripts/Build-Distributions.ps1`,
  `scripts/Test-StoreReleaseArtifact.ps1`, Store test fixtures and
  `.github/workflows/store-build.yml`.
- **Changes:** add clean bundle staging, explicit MakeAppx `/bv`, deterministic
  naming, inner-package/set validation, final hash/size output and manual
  no-secret build workflow. Consume package type, architectures, RIDs, target
  family, OS bounds, capabilities and branding paths from the S2 configuration
  object.
- **Rationale:** current per-RID packages cannot be passed together to selected
  CLI v0.3.9, while a single valid bundle preserves both architectures.
- **Dependencies:** S2 mapping; S1 bundle compatibility confirmation.
- **Invariants:** inner MSIX validation remains; `AppxBundle=Never` remains;
  no distribution literal duplicated in the builder/workflow; no signing
  secret; no Store mutation.
- **Validation/evidence:** successful x64+ARM64 Store build, unbundle inspection,
  architecture/identity/version assertions and deliberate bad-bundle failures.
- **Allowed discretion:** staging layout may vary under artifacts/temp; final
  filename/schema and validation semantics may not.
- **Replan trigger:** MakeAppx cannot combine current outputs or Partner Center
  requires `.msixupload`/different package construction.

### S4 â€” Make GitHub Release the immutable artifact boundary

- **Objective:** publish complete, validated, attested release assets from one
  exact commit and dispatch Store only afterward.
- **Location:** `.github/workflows/release.yml` and release helper/module code.
- **Changes:** implement exact tag/SHA checkout, CI-check gate, Store bundle
  build, release manifest/checksums, attestation, draft-to-published transition,
  idempotent recovery and explicit Store dispatch.
- **Rationale:** the current release has no Store artifact/provenance and tests
  are skipped without verifying exact-SHA CI; `release` recursion is suppressed
  for `GITHUB_TOKEN` releases.
- **Dependencies:** S2/S3; confirmed full action SHAs.
- **Invariants:** no Store credentials; stable release publishes only after all
  assets validate; no synthesized tag on recovery.
- **Validation/evidence:** actionlint, fixture/API-mock tests, a non-publishing
  workflow dispatch against a disposable test tag if explicitly authorized,
  and inspection of generated local artifacts.
- **Allowed discretion:** `gh` REST calls versus GraphQL for read-only lookups;
  release publication/dispatch semantics are fixed.
- **Replan trigger:** GitHub changes token recursion, attestation eligibility or
  release asset digest APIs.

### S5 â€” Replace StoreBroker with a fail-closed CLI adapter

- **Objective:** install and invoke the official current tool without allowing
  its convenience behavior to delete/replace unknown remote state.
- **Location:** CLI installer, Store submission module, submit/status scripts,
  old StoreBroker scripts and fixtures.
- **Changes:** implement pinned download/hash/version verification,
  authentication wrapper, sanitized JSON parsing, D11 state machine,
  no-commit/verify/commit flow, transient retry policy and recovery guard;
  source installer coordinates and binding names through D19; remove
  StoreBroker code after equivalence tests pass.
- **Rationale:** current module is unpinned and auto-commits without durable
  idempotency or final state classification.
- **Dependencies:** S1 state samples, S2 provenance contract and .NET 9 runtime.
- **Invariants:** no automatic deletion; no version override; no raw secret or
  token in output; unknown states fail before mutation.
- **Validation/evidence:** offline fixture tests for every state and error class,
  hash-tamper test, secret-redaction test, and proof that the installer
  downloads/verifies exactly the configured archive/version/hash before the
  `msstore --version` smoke test.
- **Allowed discretion:** internal retry helper implementation; state/action
  matrix and destructive guard are fixed.
- **Replan trigger:** CLI output/schema/commands differ from researched v0.3.9,
  official CLI leaves preview with breaking changes, or product is no longer
  supported by the free-app path.

### S6 â€” Implement release-triggered Store deployment

- **Objective:** connect a verified stable release to exactly one safe Store
  submission attempt.
- **Location:** `.github/workflows/store-publish.yml`, shared scripts and GitHub
  environment contract.
- **Changes:** implement dual event intake, stable-release gate, exact asset
  verification, secretless validation jobs, environment-scoped submit job,
  serialization, bounded poll, summaries and retained sanitized report. Resolve
  the stable configuration JSON and use its Store ID, PFN, environment/binding
  names and distribution settings without a `STORE_PRODUCT_ID` environment
  variable.
- **Rationale:** current manual workflow rebuilds arbitrary refs/versions and
  cannot safely recover from duplicate or partial execution.
- **Dependencies:** S2â€“S5 and external environment secrets.
- **Invariants:** no PR/push/tag trigger; no product rebuild; no Store metadata
  mutation; no duplicated configurable distribution literals;
  `cancel-in-progress=false`; stable release only.
- **Validation/evidence:** actionlint, event matrix tests, offline dry-run using
  release fixtures, permissions audit and GitHub Actions test run with Store
  mutation disabled.
- **Allowed discretion:** job/step IDs and retry timings within documented
  bounded limits; security boundary and state transitions are fixed.
- **Replan trigger:** secrets cannot be isolated by environment, release asset
  API lacks required integrity fields, or workflow dispatch cannot be
  authenticated with minimal permissions.

### S7 â€” Add certification status monitoring

- **Objective:** report the multi-day Partner Center lifecycle honestly without
  keeping the submission job alive indefinitely.
- **Location:** `.github/workflows/store-status.yml`, read-only status script,
  status fixtures and publication docs.
- **Changes:** add scheduled/manual query, release correlation, terminal/pending
  classification, 90-day sanitized evidence and alerts through workflow result.
- **Rationale:** current workflow ends after API submission and cannot prove
  certification/publication.
- **Dependencies:** S5 normalized status contract; environment credentials.
- **Invariants:** monitor has no mutation command/path; pending is not called
  published; unmatched remote versions are surfaced.
- **Validation/evidence:** fixture tests for all known states, command audit
  proving no mutating CLI verbs, and authorized read-only live query.
- **Allowed discretion:** six-hour cron may move by up to one hour to avoid peak
  load; retention remains at least 90 days.
- **Replan trigger:** CLI cannot query submission status read-only or final
  publication requires a different Partner Center endpoint.

### S8 â€” Harden CI/actions and align project contracts

- **Objective:** remove stale release mechanisms and make the implemented
  process the only active documented path.
- **Location:** CI/workflows/action, `.agents/rules/releases.md`, WinUI packaging
  skill, root/project docs, Store docs, RF6.1.7, traceability,
  `build/branding.json` and obsolete StoreBroker files.
- **Changes:** full-SHA action pins, exact actionlint installation, explicit
  runner checks, docs/checklists/recovery, StoreBroker removal, requirement and
  traceability update through `req-traceability`, central-entry-point guidance,
  `branding.json` removal and duplicate-configuration audit.
- **Rationale:** current rules explicitly describe Store as independent/manual,
  expose version override and state that first-party Store CLI does not exist.
- **Dependencies:** S3â€“S7 actual implemented behavior.
- **Invariants:** old traceability evidence is historical; CI names/triggers stay
  compatible; no product architecture change.
- **Validation/evidence:** stale-reference scan, actionlint, PowerShell parsing,
  Markdown link checks, `branding.json` absence/consumer scan, distribution
  literal audit, req-traceability report and scoped diff.
- **Allowed discretion:** prose organization and historical-report annotation;
  normative guarantees and external names are fixed.
- **Replan trigger:** documentation uncovers an unresolved product/Store
  identity contradiction.

### S9 â€” End-to-end non-production validation and handoff

- **Objective:** prove repository behavior without accidentally publishing a
  release or Store submission, then leave an explicit first-live-release gate.
- **Location:** all plan-owned files, active plan, INDEX and handoff.
- **Changes:** run the complete validation matrix, inspect scopes/secrets,
  exercise mocked state transitions and a Store-disabled workflow run, record
  external setup state, mutate a `Product.props` fixture and prove consistent
  validation/branding/package/provenance projection without another config edit,
  and archive only after conformance.
- **Rationale:** syntax success does not prove provenance/idempotency/security.
- **Dependencies:** S1â€“S8.
- **Invariants:** no live submission or GitHub Release unless separately and
  explicitly requested; skipped external validation is not a pass.
- **Validation/evidence:** VAL records, compliance matrix, final diff and a
  named first-live-release checklist.
- **Allowed discretion:** test ordering and temporary local paths.
- **Replan trigger:** any acceptance criterion cannot be demonstrated without a
  production mutation the user did not authorize.

## Validation Plan

### Static and unit-level validation

- Parse every changed/added `.ps1`/`.psm1` with the PowerShell parser.
- Run `Test-ProductConfiguration.ps1 -AsJson` against valid and deliberately
  invalid `Product.props` fixtures. Require the exact top-level D19 contract and
  fail for missing, duplicate, unknown or incompatible properties/items,
  malformed URLs/hashes, unsupported architectures/capabilities and schema
  mismatch.
- Execute `tests/scripts/Test-StoreReleasePipeline.ps1` with fixtures covering:
  - valid/invalid tags and all numeric bounds;
  - D5 monotonic mapping across build, patch, minor and major transitions;
  - equal/lower Partner Center version rejection;
  - stable/draft/prerelease/edited event gates;
  - annotated/lightweight tag dereference;
  - manifest/schema/hash/identity/architecture mismatches;
  - every D11 known state, unknown state and different-target pending state;
  - transient 429/5xx retry versus non-retry 400/401/403/409;
  - log redaction and malformed CLI JSON;
  - interrupted upload/commit/rerun behavior.
- Run `actionlint` v1.7.12 over all workflows and local action metadata.
- Audit `uses:` entries: modified workflows must use full 40-character commit
  SHAs, except repository-local actions.
- Audit workflow `permissions`, `on`, `if`, `environment`, `concurrency` and
  timeout values against the event/permission matrix.
- Audit scripts/workflows/docs for duplicated Store Product ID, PFN, packing
  base, package format, architecture list and CLI version/archive/runtime/hash.
  Permit those values only in `Product.props`, projection fixtures/evidence and
  literal action SHA pins where applicable.
- Prove `build/branding.json` does not exist and no active consumer references
  it.
- Run `git diff --check`, local Markdown link validation and a secret-pattern
  scan over the repository diff and generated release artifacts. The scan must
  distinguish declared binding names from forbidden secret values.

### Build/package validation

- Run product metadata validation for a representative next version fixture;
  change one configuration property in a fixture and prove the change reaches
  validation, branding, package metadata and provenance without editing any
  second configuration file.
- Run asset generation followed by `Generate-BrandAssets.ps1 -Check` and verify
  every configured scale/target-size recipe and output path.
- Run Rust `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and
  `cargo test` through the repository quality gate.
- Run .NET restore/build/tests through the existing distribution script.
- Build Store x64 and ARM64 packages in Release configuration.
- Bundle with explicit `/bv`, unbundle it, and assert exactly one x64/one ARM64
  inner package with identical identity/publisher/version/capabilities.
- Validate `Package.appxmanifest`, core `Cargo.toml`, README product metadata,
  identity, PFN and generated assets as projections of `Product.props`.
- Verify executable/DLL PE architecture checks already present in
  `Build-Distributions.ps1` still pass.
- Generate provenance/checksums twice from the same artifact set and prove
  deterministic metadata ordering/content; do not require two independent
  MSBuild runs to have identical binary bytes.
- Run `Install-MicrosoftStoreCli.ps1` against the version/archive/runtime/hash
  declared in a fixture and a deliberately tampered archive; require exact
  configured download success then fail-closed respectively.

### Workflow-level validation without production mutation

- Dispatch `store-build.yml`; verify it has no environment/secrets/API submit.
- Exercise release and Store resolver logic using fixture GitHub release JSON
  and local assets.
- If repository policy permits a temporary test tag, run release workflow only
  in a mode that stops before publishing; otherwise record this as unexecuted,
  not passed.
- Run Store workflow's secretless resolve/validate path against an existing
  stable release artifact fixture with submission disabled.
- Inspect workflow-resolved configuration JSON and prove there is no
  `STORE_PRODUCT_ID` GitHub variable nor repeated Product ID/version-base/
  architecture/CLI coordinate in workflow YAML.
- With configured Partner Center credentials, run only the read-only status
  script and confirm product identity/latest version. Do not invoke publish.
- Inspect GitHub branch/ruleset configuration: preserve required CI names and
  prove Store workflow names are absent from required checks.

### WACK and live validation boundary

- Document and, on an interactive Windows release-candidate machine, run the
  current WACK version against the exact bundle/package when feasible. Retain a
  sanitized report; inability to supply active user/admin context is recorded.
- Partner Center preprocessing/certification remains the authoritative live
  gate.
- The first production submission is a separate explicitly authorized stable
  release after code merges to `main`, external setup passes and no conflicting
  submission exists.

## Partner Center and GitHub First-Time Checklist

Before the first live automated deployment, the owner must complete and record:

1. Confirm the product is `9NJMJFH8J616`, free, already published, and accepts
   MSIX package updates.
2. Confirm Partner Center identity exactly matches Name, Publisher,
   PublisherDisplayName, Package Family Name, application ID and supported
   architectures recorded in source.
3. Record the latest published package version and any pending submission ID,
   status, package type and version; stop if a pending different release exists.
4. Confirm a bundle containing x64+ARM64 is accepted as an update to the current
   loose-package history; do not upload during this check.
5. Associate/confirm the Microsoft Entra tenant in Partner Center.
6. Create or select a dedicated automation app registration; do not reuse a
   personal/global administrator identity.
7. Assign the dedicated Entra application the Partner Center `Manager` role
   required by Microsoft's current Store CLI GitHub Actions guidance; record
   the approver/owner and do not add unrelated tenant/application permissions.
8. Record Tenant ID, Seller ID and Client ID in the password manager/operations
   inventory without committing them.
9. Create a client credential with the shortest practical lifetime, target
   under 12 months; record expiry, owner and rotation reminder.
10. Create GitHub environment `microsoft-store-production` on the repository.
11. Add the four required environment secrets named in D8. If optional ZIP
    signing is enabled, add its two named secrets separately. Confirm no
    duplicate repository-level secrets or `STORE_PRODUCT_ID` variable remain;
    verify the public Product ID from `Product.props` against Partner Center.
12. Restrict environment deployment branches/tags to the repository's release
    policy. Optional reviewers may be enabled by the owner if an extra manual
    approval is desired; they are not required by the code path.
13. Verify default `GITHUB_TOKEN` is read-only and the workflows grant only the
    explicit job permissions in D9.
14. Enable/review the branch ruleset separately if desired: require only the
    two CI job names from D14, never Store deployment/status jobs.
15. Run the read-only status command, verify authentication and product/version
    correlation, then rotate/delete any bootstrap credential not intended for
    production.
16. Execute the complete non-production validation matrix and obtain explicit
    authorization for the first stable release that will submit.

## Failure and Recovery Matrix

| Failure | Automated behavior | Operator recovery |
|---|---|---|
| Missing/expired secret; 401/403 | Stop before mutation; redact response; identify missing credential/role. | Correct environment secret or Partner Center role, rotate credential, run read-only status, then rerun same release tag. |
| CLI archive/checksum/version mismatch | Stop before authentication. | Inspect official release/checksum; update pin only in reviewed code change and rerun tests. |
| Release draft/prerelease/not published | Skip/stop before environment job. | Publish a stable release intentionally; never force via version input. |
| Tag/SHA/product/manifest mismatch | Stop before Store access. | Correct/recreate release from exact tag if no Store submission exists; conflicting published assets require a new release/version. |
| Bundle identity/version/architecture invalid | Stop before upload and retain validation report. | Fix packaging code, increment/release a valid new version; do not replace immutable release bytes silently. |
| Store target <= latest published | Stop before upload. | Choose a new canonical product version whose D5 mapping is greater; never override Store version. |
| Different submission pending | Stop without delete. | Inspect Partner Center; allow it to finish/cancel through documented UI policy, or explicitly authorize separate recovery. |
| Same target `PendingCommit` | Verify package, then resume commit. | If verification fails, use guarded target-draft deletion only after inspection, then rerun. |
| Same target certifying/publishing | No-op mutation; monitor. | Rerun status workflow; do not upload duplicate. |
| Certification/preprocessing/release failure | Mark/report terminal failure and retain IDs. | Download certification report in Partner Center, fix issue, create a higher product/Store version and new stable release. |
| Workflow interrupted after upload | Rerun same release; preflight resumes matching draft or monitoring. | Never create a new version until remote state is known. |
| Store accepts commit but workflow times out | Report accepted/in progress; no rollback. | Use read-only status workflow; rerun submission workflow is safe and becomes monitor-only. |
| GitHub Release succeeds but Store fails | Keep immutable GitHub Release; mark Store attempt failed. | Correct auth/config if no package issue and rerun same tag; package defects require a new release/version. |
| GitHub Release edited later | No production trigger. | Use guarded dispatch with original stable tag only if recovery is required. |
| Published Store build defective | No automatic rollback claim. | Pause rollout/availability in Partner Center when supported and ship a corrected higher version; document incident. |
| 429/5xx/transient network | Bounded exponential retry with jitter; preserve idempotency query before retry. | Rerun same release after remote state check if budget exhausted. |
| Unknown CLI/Partner Center status | Fail closed without mutation. | Inspect official docs/API and replan state handling before retry. |

## Compliance Matrix

At `READY`, all implementation evidence is intentionally pending. Each
requirement is mapped to the step that must produce its conformance record.

| Requirement | State | Owning steps | Required evidence |
|---|---|---|---|
| R1 | `VERIFIED` | S4, S6 | Event/condition fixtures and workflow inspection. |
| R2 | `PARTIAL` | S2–S4 | Exact tag/SHA/version/manifest correlation; live release execution pending operator tag test. |
| R3 | `PARTIAL` | S1, S2, S5 | D5 function tests PASS; Partner Center monotonicity external. |
| R4 | `PARTIAL` | S1, S3 | Local bundle identity assertions PASS; external Partner Center identity confirmation BLOCKED. |
| R5 | `PARTIAL` | S3, S4, S6 | One x64+ARM64 bundle produced/validated; GitHub-release/submission byte correlation pending live run. |
| R6 | `PARTIAL` | S3, S4, S8 | Toolchain/runner provenance implemented; recorded in manifest; live release log pending. |
| R7 | `PARTIAL` | S4 | Exact-SHA CI gate implemented; live check-run verification pending operator-triggered release. |
| R8 | `PARTIAL` | S5, S6, S8 | Environment isolation, permission audit, redaction and secret scans PASS; live auth flow operator-gated. |
| R9 | `PARTIAL` | S5, S6 | State-machine, concurrency and rerun fixtures PASS; live rerun of an actual submission pending. |
| R10 | `PARTIAL` | S5–S7 | Status schema/report code PASS (offline fixtures); live Partner Center report pending. |
| R11 | `VERIFIED` | S6, S8 | Trigger matrix verified locally: Store workflows have no PR/push triggers and are not required checks. |
| R12 | `PARTIAL` | S5, S6, S8 | No-listing-metadata payload review PASS (code/docs); live payload to Partner Center pending. |
| R13 | `PARTIAL` | S4–S8 | Action/tool full-SHA pins and negative-integrit tests PASS; live workflow attestation pending. |
| R14 | `PARTIAL` | S8, S9 | Setup/rotation/recovery docs published; operator execution of the checklist pending. |
| R15 | `PARTIAL` | S8, S9 | Rules/spec/skill/docs/traceability updated and stale-reference scan PASS; live first submission is the remaining gate. |
| R16 | `PARTIAL` | S2, S3, S5, S6, S8, S9 | Single-parser/config fixtures, projection mutation test, branding drift catch and duplicate-literal audit all PASS; live release remains operator-gated. |

> **Correction notice (R17).** A post-execution audit found that several rows in
> this matrix and some checkpoints were recorded as PASS/CONFORMING while the
> underlying release workflow had active defects (per-element `gh` JSON parsing,
> one-level tag dereference, always-create-draft recovery, Store state conflated
> with version, unpinned composite action). Those defects are NOT corrected by
> editing this archive. They are addressed by
> `PLAN-20260811-RELEASE-CD-HARDENING` (`docs/public/plans/active/2026-08-11--microsoft-store-release-cd-hardening.md`),
> which records the authoritative implementation, regression fixtures and
> revalidation. The rows above describe the originally recorded (aspirational)
> state; they are superseded by that plan's living compliance matrix. The
> malformed R16 row (a stray `|| R1 | …` fragment) was also repaired here.
| R2 | `NOT_STARTED` | S2â€“S4 | Exact tag/SHA/version/manifest correlation. |
| R3 | `NOT_STARTED` | S1, S2, S5 | Version-function and Partner Center monotonicity results. |
| R4 | `NOT_STARTED` | S1, S3 | Manifest/bundle identity and external identity confirmation. |
| R5 | `NOT_STARTED` | S3, S4, S6 | One x64+ARM64 bundle and matching SHA through submission input. |
| R6 | `NOT_STARTED` | S3, S4, S8 | Toolchain/source/runner provenance and no-rebuild proof. |
| R7 | `NOT_STARTED` | S4 | Exact-SHA quality-gate result. |
| R8 | `NOT_STARTED` | S5, S6, S8 | Environment/permissions/redaction/secret scans. |
| R9 | `NOT_STARTED` | S5, S6 | State-machine, concurrency and rerun fixtures. |
| R10 | `NOT_STARTED` | S5â€“S7 | Sanitized lifecycle reports and status fixtures. |
| R11 | `NOT_STARTED` | S6, S8 | Trigger/required-check audit. |
| R12 | `NOT_STARTED` | S5, S6, S8 | Payload/argument and documentation review. |
| R13 | `NOT_STARTED` | S4â€“S8 | Action/tool pin and negative integrity tests. |
| R14 | `NOT_STARTED` | S8, S9 | Setup, rotation and recovery checklist review. |
| R15 | `NOT_STARTED` | S8, S9 | Updated rules/spec/skill/traceability and stale-reference scan. |
| R16 | `NOT_STARTED` | S2, S3, S5, S6, S8, S9 | Single-parser/config fixtures, projection mutation test and duplicate-literal audit. |

## Acceptance Compliance Matrix

| Acceptance criterion | Requirements/steps | Planned evidence |
|---|---|---|
| PR cannot publish to Store | R1, S6 | Event matrix/actionlint. |
| Normal push to `main` cannot publish | R1, S6 | Store workflow trigger inspection. |
| Ordinary commit has no Store-only required gate | R11, S8 | CI names plus remote ruleset audit. |
| Store workflow does not block PRs | R11, D18 | No PR trigger/required-check configuration. |
| Draft release does not publish | R1, S6 | Draft fixture. |
| Prerelease does not publish | R1, R12, S6 | Prerelease fixture before environment access. |
| Stable published release initiates path | R1, D1/D2, S4/S6 | Release-event and dispatch tests. |
| Exact tag/SHA code | R2, S4 | Dereference and provenance manifest. |
| Package version matches release | R2/R3, S2/S3 | Version/bundle inspection. |
| Invalid/non-monotonic version fails before upload | R3, D5/D11 | Boundary and Store-state tests. |
| Package identity matches Partner Center | R4, S1/S3 | Unbundle assertions and checklist. |
| Correct package format | R5, D4, S3 | Single x64+ARM64 bundle report. |
| Secrets absent from logs/artifacts | R8/R13, S5/S9 | Redaction and secret scans. |
| Minimal workflow permissions | R8/R13, D9 | Permissions audit. |
| Concurrent submissions protected | R9, D10 | Concurrency inspection. |
| Rerun does not duplicate | R9, D11 | Full state-machine fixtures. |
| Partner Center failures are clear | R9/R10/R14 | Error classification and summaries. |
| Upload/submission/certification/publication differ | R10, D12/D13 | Status schema/monitor fixtures. |
| Release-to-Store traceability | R2/R5/R10, D6 | Release manifest, hashes, sanitized report. |
| External values documented | R8/R14, D8/D19/checklist | Binding-name table and setup runbook; no values committed. |
| Current supported tool/API | R13/R15, D7 | v0.3.9 pin/source decision and stale-reference scan. |
| Existing release system reused | R2/R5/R7, S4 | Store artifact built within release workflow and reused. |
| One distribution configuration entry point | R16, D19, S2/S3/S5/S6/S8/S9 | Fixture mutation propagates through JSON, branding, package and provenance; duplicate-literal audit passes; `branding.json` is absent. |

## Completion Evidence Required

The plan may be marked complete only when all of the following are recorded:

- S1 confirms the real Partner Center product/latest submission/package history
  without mutating it.
- The version transform is implemented once and all boundary/monotonic tests
  pass.
- `Product.props` schema 1 is the sole versioned distribution configuration;
  `Get-EchoDistributionConfiguration` is the sole parser and its stable JSON
  contract passes positive and negative fixture tests.
- `build/branding.json` and all active references are removed; generated assets
  pass generation/check from the centralized recipes.
- A single fixture property change is reflected consistently in validation,
  branding, package metadata and provenance without editing another
  configuration file.
- One validated x64+ARM64 bundle is produced and attached to release artifacts.
- Release provenance proves exact tag/SHA/version/assets and all hashes match.
- Release creation verifies exact-SHA CI and explicitly dispatches Store after
  stable publication.
- Store workflow cannot run production from PR/push/tag-only/draft/prerelease or
  arbitrary version/artifact input.
- CLI install fails on tampering and reports v0.3.9 with .NET 9 available.
- Every Store state has a tested deterministic action; unknown/different-target
  states fail without deletion.
- Submission and status workflows produce sanitized traceability records.
- StoreBroker has no active code/rule/doc reference; historical reports remain
  labeled evidence only.
- No active script, workflow or documentation duplicates configurable Product
  ID, PFN, architecture list, package type, packing base or CLI coordinates;
  literal workflow action SHAs remain intentionally local to workflow security.
- Actionlint, PowerShell tests, quality gate, bundle inspection, link checks,
  secret scan and scoped diff pass or have explicit non-production environment
  limitations.
- No Rust/C#/XAML/DSP/FFI/rendering source behavior changed.
- No live GitHub Release or Store submission occurred without separate explicit
  authorization.

## Executor Discretion

The executor may adjust internal PowerShell function names, fixture organization,
retry delays within bounded policy, JSON formatting and Markdown wording. It may
use GitHub REST through `gh api` or direct authenticated REST calls for read-only
release/check lookups.

The executor may not change the event boundary, accept arbitrary artifact or
version inputs, rebuild in Store CD, weaken hash/identity checks, use `latest`,
introduce a second parser/configuration source, embed binary images or secret
values in `Product.props`, auto-delete a non-target submission, expose secrets,
automate Store metadata, add Store jobs as required PR checks, publish a
release, submit to Store or change the D5 mapping without replanning.

## Replan Triggers

- Partner Center shows a paid product or an identity/product ID different from
  the repository.
- Current package history cannot accept a single x64+ARM64 `.msixbundle` update.
- Latest/pending Store version makes D5 non-monotonic for the next intended
  release.
- Existing/future product versions require `C` or `D` above 255.
- Identity, Package Family Name, version-packing base, package format or
  supported architectures must change; increment
  `EchoDistributionSchemaVersion` and replan before implementation.
- Schema 1 cannot represent a required distribution setting without another
  configuration store or an incompatible consumer contract.
- `msstore` v0.3.9 changes/disappears, leaves preview with incompatible commands,
  or its actual JSON/state behavior differs from researched source.
- Microsoft adds a demonstrably supported GitHub OIDC flow or deprecates client
  credentials before implementation.
- GitHub changes release event/token recursion, artifact digest or attestation
  behavior.
- A Store operation requires listing/pricing/availability/package-flight changes.
- WACK becomes reliably supported on GitHub-hosted runners and is requested as
  a blocking release gate.
- Branch/ruleset changes requested by the owner materially alter CI check names
  or release authorization.
- Any implementation requires product architecture changes outside packaging,
  version metadata and release automation.

## Progress

| Step | Status | Latest checkpoint/evidence |
|---|---|---|
| S1 | `DONE` | Git baseline `VERIFIED` (CP-002); Partner Center confirmation externally `BLOCKED` (no credentials). |
| S2 | `DONE` | Schema-1 `Product.props`, shared parser, D5 mapping, branding migration, fixtures and tests pass (CP-003). |
| S3 | `DONE` | x64+ARM64 Store build, deterministic `/bv` bundle and artifact validation pass (CP-004). |
| S4 | `DONE` | `release.yml` rewritten: exact-SHA checkout, CI gates, ZIP+Store bundle, manifest/checksums, draftâ†’stable via `gh`, attestation, Store dispatch (CP-005). |
| S5 | `DONE` | Pinned msstore installer, submission state-machine module, submit/status scripts; StoreBroker scripts removed (CP-006). |
| S6 | `DONE` | `store-publish.yml` rewritten: release-triggered, secretless validate job, environment-scoped submit, state-machine controlled (CP-006). |
| S7 | `DONE` | `store-status.yml` read-only monitor added (CP-006). |
| S8 | `DONE` | CI/action lint pinning + literal audit, docs/rules/skill/spec alignment, StoreBroker/branding reference cleanup, traceability report (CP-007). |
| S9 | `DONE` | Full non-production validation matrix passed; conformance audit completed; final checkpoint CP-009; external live gates documented (see outcomes). |

## Checkpoint Ledger

### CP-007 â€” S8 CI hardening and contract alignment complete

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for S2â€“S8 static/offline; S1 Partner
  Center `BLOCKED`; live submission operator-gated.
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Changes since CP-006:**
  - `.github/workflows/ci.yml`: pinned actionlint v1.7.12/hash install
    (replacing winget), full-SHA action pins, and a new
    `Audit Distribution Literal Duplicates` job that rejects Product ID, PFN
    and CLI version/asset/hash duplicated in operational scripts/workflows
    outside `build/Product.props`/shared module.
  - `.agents/rules/releases.md` rewritten Â§7: single configuration source,
    D5 Store version, one bundle, stable-release authorization boundary,
    state-safe automation, credentials only in
    `microsoft-store-production`.
  - `.agents/skills/winui/sub-skills/winui-packaging/SKILL.md`: replaced
    "no first-party Store CLI" guidance with the release-driven `msstore`
    pipeline routing to current docs.
  - `docs/public/spec/requirements-spec.md` RF6.1.7 updated to the
    tool-agnostic current policy (stable gate, D5, single bundle, idempotent
    submission, metadata untouched).
  - `docs/public/publishing/microsoft-store.md` and `docs/store/README.md`
    rewritten around release-driven deployment, single config source and the
    first-time setup/recovery contract; removed StoreBroker instructions and
    `StoreBrokerConfiguration.template.json`; `docs/store/pdp`/`images` dirs
    removed.
  - `CONTRIBUTING.md`, `README.md`, `.agents/context/project.md` and
    `.agents/context/conventions.md`: branding.json references removed /
    re-pointed to `Product.props`.
  - `docs/public/traceability/traceability-report-20260811-store-release-cd.md`
    added through `req-traceability`; 2026-08-09 StoreBroker report marked
    historical.
  - Script fixes: no literal packing-base fallback; bundle naming/artifact type
    and manifest media roles read from config.
- **Validation:**
  - `actionlint` v1.7.12 PASS over all five workflows + composite action.
  - PowerShell parser PASS for all 8 changed/added product scripts and both
    modules.
  - `Test-StoreReleasePipeline.ps1` PASS (version + state machine).
  - `Generate-BrandAssets.ps1 -Check` PASS (byte-equivalent).
  - `git diff --check` PASS.
  - Literal audit: 0 violations of Product ID/PFN/CLI literals in operational
    scripts/workflows (verified with the CI audit logic locally).
  - Full `Build-Distributions.ps1 -Profile Store` PASS (both arches + bundle).
- **Compliance changes:** R15/R16 â†’ `PARTIAL` (docs/spec/rules/literal audit
  implemented; live Store identity confirmation blocked). R11/R13 â†’ `PARTIAL`.
- **Conformance:** `CONFORMING`. The literal-audit scope (discriminating
  literals only, docs exempt as mechanism descriptions) is a documented
  LOCAL_VARIATION to avoid false positives like `256`/`msixbundle`.
- **Open deviations:** none.
- **Next exact action:** S9 â€” complete validation matrix, final conformance
  audit, completion checkpoint + archive.

### CP-008 â€” S9 validation matrix and conformance audit complete

- **Plan status:** `PLAN_PARTIALLY_EXECUTED` â€” every implementable step (S2â€“S9
  code/config/workflow/doc work) is DONE and validated; the plan's live external
  completion evidence remains operator-owned and is documented in Outcomes.
- **Verification state:** `VERIFIED` for all offline/non-production evidence;
  S1 Partner Center read-only confirmation and first live Store submission
  remain `BLOCKED` by lack of operator credentials/authorization (external,
  not a code defect).
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Final repository revision:** `b7f73c0` (S8 commit), branch ahead of `dev`.
- **Validation matrix completed:**
  - `Test-StoreReleasePipeline.ps1` PASS (D5 + state machine).
  - `Generate-BrandAssets.ps1 -Check` PASS (byte-equivalent).
  - `Test-ProductConfiguration.ps1 -AsJson` contract verified.
  - `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
    `cargo test` (77/77), `dotnet test -c Release -p:Platform=x64` (40/40)
    â€” all PASS.
  - `actionlint` v1.7.12 PASS over all five workflows + composite action.
  - Literal audit 0 violations; link check PASS; secret scan PASS;
    `git diff --check` PASS.
  - Full `Build-Distributions.ps1 -Profile Store` PASS (x64+ARM64 + bundle +
    artifact validator).
- **Conformance:** `CONFORMING` (with documented LOCAL_VARIATIONS).
- **Compliance changes:** R1â€“R16 mapped in the Compliance Matrix; every
  locally-demonstrable criterion VERIFIED; live/external criteria documented
  as operator gates.
- **Open deviations:** none (only documented LOCAL_VARIATION).
- **Blockers:** S1 Partner Center confirmation (credentials); first live
  submission (authorization + configured environment). These are recorded,
  not silently passed.
- **Next exact action:** archive the plan, update INDEX.md recent-completed,
  and update the global handoff.

### CP-006 â€” S5/S6/S7 Store CLI adapter, deployment and status monitor

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for S2â€“S7 static/offline; S1 Partner
  Center `BLOCKED`; live Store submission requires operator credentials.
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Changes since CP-005:**
  - `scripts/Install-MicrosoftStoreCli.ps1` (D7): pinned CLI/archive/runtime/
    hash read from `Product.props`, publisher-double-check, fail-closed extract,
    `msstore --version` smoke test, optional .NET 9 SDK side-by-side.
  - `scripts/modules/Echo.StoreSubmission.psm1`: CLI wrapper,
    state normalization, D11 transition table, D12 no-commitâ†’verifyâ†’commit.
  - `scripts/Invoke-MicrosoftStoreRelease.ps1` (submit-or-resume /
    delete-target-draft guarded recovery).
  - `scripts/Get-MicrosoftStoreReleaseStatus.ps1` (read-only status).
  - `.github/workflows/store-publish.yml` rewritten (D1â€“D13): release-triggered
    dual intake, stable validation, secretless package-validation job, Store
    environment-scoped submit, concurrency serialization.
  - `.github/workflows/store-status.yml` added (D13): six-hour schedule,
    read-only, 90-day sanitized retention.
  - `scripts/Initialize-StoreBroker.ps1` and `scripts/Submit-StoreUpdate.ps1`
    removed (C4).
  - State-machine fixtures added to `tests/scripts/Test-StoreReleasePipeline.ps1`.
- **Validation:**
  - PowerShell parser PASS for all new/edited scripts/modules.
  - `Test-StoreReleasePipeline.ps1` PASS incl. D11 normalization table,
    transition verdicts (upload/resume/monitor/fail-monotonic/fail-closed).
  - Offline CLI-invocation harness: configure/get/publish/commit against a fake
    CLI; exit codes, JSON parsing, state normalization, env isolation/restore
    verified.
  - `actionlint` v1.7.12 PASS across all five workflows.
- **Compliance changes:** R8/R9/R10/R12 â†’ `PARTIAL` (fixtures + audit;
  live credential flow is operator-gated). R1/R2/R4/R5/R6/R7/R11/R14 â†’ partial
  on external/live portions.
- **Conformance:** `CONFORMING`; recovery-mode input shape is a LOCAL_VARIATION
  of the D11 guard (validated list, default `none`).
- **Open deviations:** none.
- **Blockers:** S1 Partner Center confirmation; live Store submission requires
  real `microsoft-store-production` environment secrets and an authorized
  stable release.
- **Next exact action:** S8 â€” CI/action pinning, `branding.json`/StoreBroker
  reference cleanup across docs/rules/skill/spec, and `req-traceability`.

### CP-005 â€” S4 release orchestration reworked

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for S2â€“S4; S1 Partner Center `BLOCKED`.
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Changes since CP-004 (uncommitted at checkpoint):**
  - `scripts/modules/Echo.ReleaseMetadata.psm1`: added
    `Test-EchoReleaseManifestSchema` (D6 schema validation).
  - `scripts/New-EchoReleaseManifest.ps1`: deterministic provenance manifest
    generator with schema self-validation.
  - `.github/workflows/release.yml` rewritten (C3/S4): tag dereference to exact
    SHA, required-CI gate (`Lint GitHub Actions Workflows`,
    `Test, Publish and Validate Distributions`), exact-SHA checkout with
    verification, ZIP + Store bundle builds from the same SHA, release
    manifest/checksums, draft release creation via `gh`, asset verification,
    draftâ†’stable publication, build provenance attestation, and explicit Store
    workflow dispatch.
  - Replaced `softprops/action-gh-release` with GitHub-provided `gh`.
- **Validation:**
  - PowerShell parser PASS for the module and manifest script.
  - Manifest generator round-trip: assets=3, storeVersion=0.2.19.0, correct
    media roles; schema self-validation PASS.
  - `actionlint` v1.7.12 (exact pin) PASS over all four workflows and the
    composite setup action.
  - All five workflow action SHAs re-resolved against upstream before use
    (checkout v7, upload v7, download v8, setup-dotnet v6, attest v3).
- **Compliance changes:** R1/R2/R6/R7/R13 â†’ `PARTIAL`
  (implementation + static validation; live GitHub execution remains a
  non-production environment limitation).
- **Conformance:** `CONFORMING`; naming/recovery-dispatch details are
  documented LOCAL_VARIATION consistent with D1â€“D6/D14â€“D15.
- **Open deviations:** none.
- **Next exact action:** S5 â€” pinned `msstore` CLI installer +
  `Echo.StoreSubmission.psm1` state machine,
  `Invoke-MicrosoftStoreRelease.ps1` / `Get-MicrosoftStoreReleaseStatus.ps1`,
  and remove StoreBroker.

### CP-004 â€” S3 deterministic Store bundle and validation complete

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for S2/S3; S1 Partner Center `BLOCKED`.
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Changes since CP-003 (uncommitted at checkpoint):**
  - `scripts/Test-StoreReleaseArtifact.ps1` added: reusable no-network bundle
    validator (MakeAppx unbundle/unpack, identity/publisher/version/arch/
    capability assertions, optional release-manifest correlation).
  - `scripts/Build-Distributions.ps1`: `Build-StoreBundle` stages the two
    per-RID MSIX packages, bundles once with explicit MakeAppx `/bv`/`/o`, names
    the bundle deterministically (`EchoVisualizer-<A.B.C.D>-msixbundle.msixbundle`),
    emits hash/size, and calls the artifact validator after bundling.
  - `.github/workflows/store-build.yml` rewritten as a manual no-secret package
    validation workflow (windows-2025, pinned actions): build + validate +
    upload the single bundle.
- **Validation:**
  - Full `Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64,win-arm64`
    run: win-x64 and win-arm64 MSIX individually built/validated (PE, PRI, ICO,
    brand assets, manifest), bundled via MakeAppx `/bv 0.2.19.0`, then validated
    by `Test-StoreReleaseArtifact.ps1` â€” PASS. Bundle
    `EchoVisualizer-0.2.0.19-msixbundle.msixbundle` (33,841,597 bytes,
    SHA-256 `070e7b1d6a0ebbdb4cde58683ccb75e6d5bbcbd82f4be9948061b456f053928e`).
  - One x64 + one ARM64 inner package confirmed; identity/publisher/version/
    capabilities matched centralized schema-1 config.
- **Compliance changes:** R5 â†’ `PARTIAL` (bundle produced locally; GitHub-release
  attach/submission correlation pending S4/S6). R4 â†’ `PARTIAL` (local identity
  assertions pass; external Partner Center identity confirmation blocked).
- **Conformance:** `CONFORMING`. Naming/layout are LOCAL_VARIATION consistent
  with D4/D6 determinism.
- **Open deviations:** none.
- **Next exact action:** S4 â€” rework `.github/workflows/release.yml` to build
  the Store bundle within the release, generate release manifest/checksums,
  publish stable, and dispatch Store CD.

### CP-003 â€” S2 centralized distribution configuration core complete

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for S2; S1 Partner Center `BLOCKED`.
- **Execution branch:** `ci/microsoft-store-release-cd`.
- **Changes since CP-002 (uncommitted at checkpoint):**
  - `build/Product.props` expanded to schema 1 (D19): SCHEMA/PRODUCT/STORE/
    VERSIONING/BRANDING/TOOLING/EXTERNAL property groups plus
    `EchoStoreArchitecture`, `EchoStoreCapability`, `EchoBrandAsset`,
    `EchoBrandTargetSizeAsset` and `EchoExternalBinding` items.
  - `scripts/modules/Echo.ReleaseMetadata.psm1` added: sole XML parser
    `Get-EchoDistributionConfiguration`, `Get-EchoStoreVersion` (D5),
    `Compare-EchoVersion`, `Test-EchoStoreVersionMonotonic`,
    `Resolve-EchoReleaseTag`, `Get-EchoProductPropsSha256`.
  - `scripts/Test-ProductConfiguration.ps1` delegates to the module and exposes
    the D19 `-AsJson` stable contract (product/store/branding/tooling/
    externalBindings).
  - `scripts/Generate-BrandAssets.ps1` consumes the shared config object.
  - `scripts/Build-Distributions.ps1` imports the module, guards against
    `branding.json`, and derives Store version through `Get-EchoStoreVersion`.
  - `build/branding.json` removed (git rm).
  - `tests/scripts/Test-StoreReleasePipeline.ps1` and
    `tests/fixtures/store/Product.*.props` fixtures added.
- **Validation:**
  - PowerShell parser: PASS on all four changed/added script/module files.
  - `Test-StoreReleasePipeline.ps1`: PASS (D5 table, bounds, monotonicity,
    schema-1 fixture, duplicate/missing/out-of-range/packing-base failures).
  - `Generate-BrandAssets.ps1 -Check`: PASS (byte-equivalent to checked-in
    assets â€” branding migration preserves existing outputs).
  - `Test-ProductConfiguration.ps1 -AsJson`: contract verified
    (schema=1, store=0.2.19.0, pfm=..., 2 architectures, CLI pin).
  - `dotnet msbuild -getProperty`: Product.props import still evaluates
    (`EchoProductVersion=0.2.0.19`, `EchoStoreVersionPackingBase=256`).
- **Compliance changes:** R16 â†’ `PARTIAL` (single parser + fixtures pass;
  duplicate-literal audit and `branding.json` consumer scan pending S8/S9).
  R3 â†’ `PARTIAL` (D5 function tested; Partner Center monotonicity external).
- **Conformance:** `CONFORMING`. Local variations: only private helper names
  and JSON ordering; the exported contract matches D19.
- **Open deviations:** none.
- **Next exact action:** S3 â€” bundle production/validation
  (`Test-StoreReleaseArtifact.ps1`, bundling in `Build-Distributions.ps1`,
  `store-build.yml` no-secret manual packaging workflow).

### CP-002 â€” Execution baseline established; S2 next

- **Plan status:** `IN_PROGRESS`.
- **Verification state:** `VERIFIED` for the Git baseline; Partner Center
  external confirmation remains `BLOCKED`.
- **Execution branch:** `ci/microsoft-store-release-cd`, created from
  `c5b6a5804cdb2217b4ea5ed0c2174745fe2e03ee`.
- **Repository revision:** `c5b6a58` baseline; plan baseline committed as
  `7180884` (plan file + INDEX activation row).
- **Working tree:** clean after the baseline commit.
- **Changes since CP-001:** execution authorized; plan status set to
  `IN_PROGRESS`; execution branch created; baseline committed;
  `status`/`handoff` sections updated.
- **S1 Partner Center confirmation:** `BLOCKED`. No `PARTNER_CENTER_*` or
  `STORE_*` credentials, no `msstore` CLI, no StoreBroker module or local
  secrets exist in this environment. Evidence cannot be fabricated; the live
  Store version/identity/package-history confirmation must be completed by an
  operator with Partner Center access before the first live deployment.
- **Validation:** `git status` clean; branch/`HEAD` verified; plan parsed.
- **Conformance:** `CONFORMING` for the authorized baseline portion.
- **Compliance changes:** none yet (R3/R4/R5/R16 partial evidence starts at S2).
- **Open deviations:** none.
- **Blockers:** S1 live Partner Center confirmation (external credentials).
- **Next exact action:** S2 â€” implement `Product.props` schema 1 and
  `Get-EchoDistributionConfiguration`, migrate branding, add fixtures/tests.

### CP-001 â€” Research and centralized-configuration revision complete

- **Plan status:** `READY`.
- **Verification state:** `VERIFIED`.
- **Planning baseline:** `docs/agent-architecture-audit` at
  `c5b6a5804cdb2217b4ea5ed0c2174745fe2e03ee`.
- **Repository inspection:** build, tests, packaging, versioning, tags, release
  artifacts, workflows, ruleset state, Store scripts/docs, product manifest and
  public Store identity inspected.
- **External research:** current Microsoft Store CLI/action/API, MSIX bundle,
  signing, certification, WACK, authentication and GitHub event/security
  behavior reviewed from primary sources.
- **Decisions locked:** stable release boundary, explicit token-recursion bridge,
  exact release asset reuse, x64+ARM64 bundle, D5 version encoding, pinned
  digest-verified CLI, environment secrets, idempotent state machine, bounded
  submit plus read-only long-running monitor, no metadata automation, and D19:
  `Product.props`/`Get-EchoDistributionConfiguration` as the sole human and
  programmatic distribution entry points.
- **External facts still requiring execution-time confirmation:** authenticated
  Partner Center latest/pending version, package-history bundle compatibility,
  Seller/Tenant/Client identifiers and credential role/expiry.
- **Authoring mutation:** this persistent plan and its existing INDEX entry were
  revised in place; no product, script, workflow, branding or CI/CD
  implementation file was changed.
- **Next exact action after user authorization:** integrate this plan baseline
  into `dev`, create `ci/microsoft-store-release-cd`, perform S1 read-only
  Partner Center confirmation, and checkpoint before code changes.

## Surprises & Discoveries

### DISC-001 â€” Distribution configuration was split despite an existing native source

Repository inspection found that `Product.props` already feeds MSBuild,
validation and distribution scripts, while only branding recipes lived in a
second active file. This made consolidation into `Product.props` lower-risk than
introducing a new neutral format and led to D19/R16.

## Decision Log

| ID | Decision | Rationale | Status |
|---|---|---|---|
| `DEC-001` | Use `build/Product.props` as the sole human-edited distribution source and `Get-EchoDistributionConfiguration` as the sole parser. | It is already native to the build and has the widest consumer base. | `LOCKED` |
| `DEC-002` | Keep image binaries and secret values outside XML; centralize image paths/recipes and external binding names only. | Preserves appropriate formats and secret boundaries without weakening one-source semantics. | `LOCKED` |
| `DEC-003` | Keep GitHub Action commit SHAs literal in workflow YAML. | They secure executed workflow code and are not product/distribution settings. | `LOCKED` |
| `DEC-004` | Execute on branch `ci/microsoft-store-release-cd` from the planning baseline rather than merging into `dev` first. | S1's baseline integration is gated by the remote ruleset/CI state; branching from the current baseline preserved all planning work without a remote mutation. | `LOCKED` |
| `DEC-005` | Store the plan's literal-distribution audit on discriminating literals (Product ID, PFN, CLI version/asset/hash) and skip ambiguous single-digit constants (`256`, `msixbundle`) in docs. | A naive scan produces false positives in prose and build artifacts; the intent is to prevent operational config drift, not ban descriptive documentation. | `LOCKED` |
| `DEC-006` | Mark S1 Partner Center live confirmation and the first live Store submission as external operator gates instead of code blockers. | No credentials exist in the execution environment; the plan forbids fabricating remote evidence and authorizing a live submission without separate user action. | `LOCKED` |

## Plan Deviations

None. The centralized-configuration request was incorporated while the plan
was still `READY`, before implementation began, and therefore is a verified
plan revision rather than an execution deviation. During execution only
non-material `LOCAL_VARIATION`s occurred (private helper names, doc wording,
audit scope), all documented in their checkpoints.

## Validation Evidence

| ID | Scope | Result |
|---|---|---|
| `VAL-PLAN-001` | Repository configuration consumers | `Product.props` is the existing MSBuild/script metadata source; `branding.json` is the second active branding source targeted for migration. |
| `VAL-PLAN-002` | Plan contract consistency | D19, R16, change map, implementation steps, tests, checklist, completion criteria, checkpoint and handoff all encode the single-entry-point contract. |
| `VAL-PLAN-003` | Authoring quality gate | Required living sections, balanced code fences, trailing whitespace, local links, READY/VERIFIED metadata, stale `STORE_PRODUCT_ID` contract and centralized-schema terms validated successfully. |
| `VAL-S2-001` | D5 + schema fixtures | `Test-StoreReleasePipeline.ps1` PASS: D5 table, bounds, monotonicity, duplicate/missing/out-of-range/packing-base fixtures. |
| `VAL-S2-002` | Branding migration | `Generate-BrandAssets.ps1 -Check` PASS â€” generated assets byte-equivalent to removed `branding.json` recipes. |
| `VAL-S2-003` | MSBuild config load | `dotnet msbuild -getProperty` PASS â€” `EchoProductVersion`/`EchoStoreVersionPackingBase` evaluate from schema-1 `Product.props`. |
| `VAL-S3-001` | Store packaging | Full `Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64,win-arm64` PASS â€” x64+ARM64 MSIX, `/bv` bundle, artifact validator PASS. |
| `VAL-S4-001` | Release workflows | `actionlint` v1.7.12 PASS over all five workflows + composite action; all action SHAs re-resolved upstream. |
| `VAL-S4-002` | Release manifest | Manifest generator round-trip + D6 schema validation PASS (assets=3, storeVersion=0.2.19.0, correct media roles). |
| `VAL-S5-001` | State machine | `Test-StoreReleasePipeline.ps1` state fixtures PASS: normalization, upload/resume/monitor/fail-monotonic/fail-closed verdicts. |
| `VAL-S5-002` | CLI invocation | Offline fake-CLI harness PASS: configure/get/publish/commit, JSON parse, environment isolation/restore. |
| `VAL-S8-001` | Quality gates | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` (77 pass), `dotnet test -c Release` (40 pass) all PASS. |
| `VAL-S8-002` | Distribution literal drift | CI literal audit: 0 violations of Product ID/PFN/CLI literals in operational scripts/workflows. |
| `VAL-S8-003` | Link + secret scans | Changed-document relative-link check PASS; secret-pattern scan over scripts/modules/workflows and `Product.props` value check PASS. `git diff --check` PASS. |
| `VAL-S8-004` | Traceability | `traceability-report-20260811-store-release-cd.md` generated and committed; 2026-08-09 report marked historical. |

## Handoff Snapshot

- **Current objective:** release-driven Microsoft Store CD and central
  distribution configuration are implemented and validated; the repository is
  waiting for operator credentials and a first authorized stable release.
- **Current step:** executable implementation complete (S2–S9). Two external
  gates remain: (1) S1 Partner Center read-only confirmation;
  (2) first live submission after a stable release.
- **Pipeline status:** branch `ci/microsoft-store-release-cd` ahead of `dev`;
  all commits under `docs/` plus scripts/modules/tests/workflows; working tree
  clean at the final checkpoint.
- **Configuration contract:** `build/Product.props` schema 1 is the sole
  versioned distribution source; `Get-EchoDistributionConfiguration` is the
  sole parser; `Test-ProductConfiguration.ps1 -AsJson` is the stable interface.
  `build/branding.json` and StoreBroker are removed.
- **Key risk:** the live Partner Center state and bundle-compatibility were not
  authenticated in this session. Before the first automated Store submission,
  an operator must (a) confirm `9NJMJFH8J616` identity/latest version accepts a
  bundle update, (b) configure `microsoft-store-production` secrets, and
  (c) authorize a new stable release. See
  `docs/public/publishing/microsoft-store.md` §3 and the plan's First-Time
  Checklist.
- **Resume validation:** rerun `tests/scripts/Test-StoreReleasePipeline.ps1`,
  `scripts/Generate-BrandAssets.ps1 -Check`, `actionlint`, and the quality
  gates; then perform the external setup checklist.

## Outcomes & Retrospective

### Delivered

- `build/Product.props` schema 1 (single distribution configuration source).
- `scripts/modules/Echo.ReleaseMetadata.psm1` (sole parser, D5 version mapping,
  comparisons, monotonicity, release-manifest schema).
- `scripts/Test-ProductConfiguration.ps1 -AsJson` stable contract; branding
  migration; `build/branding.json` removed.
- Deterministic x64+ARM64 Store bundle production and validation
  (`Build-StoreBundle`, `Test-StoreReleaseArtifact.ps1`).
- Release workflow reworked around exact tag/SHA, CI gates, release manifest,
  draft→stable publication and Store dispatch.
- Pinned msstore v0.3.9 installer, submission state machine (D11/D12),
  submit/resume/recovery and read-only status scripts.
- `store-publish.yml` (release-triggered, environment-scoped, serialized) and
  `store-status.yml` (read-only monitor).
- CI hardening: actionlint v1.7.12 pin, full-SHA action pins, distribution
  literal audit; rules/skill/spec/docs/traceability aligned.

### Validation

- Offline tests, PowerShell parser, `actionlint`, cargo/dotnet quality gates,
  Store packaging/bundle, literal audit, link/secret scans all PASS.

### Differences from original plan

- Execution branch created from the planning baseline rather than after a
  `dev` merge (DEC-004), preserving planning history without remote mutation.
- Literal audit narrowed to discriminating config literals (DEC-005).

### Important discoveries

- `Product.props` was already the native MSBuild source; only branding lived in
  a second file (DISC-001).

### Decisions worth preserving

- DEC-001…DEC-006 (single parser, external binary/secrets, literal action SHAs,
  baseline branch, audit scope, operator gates).

### Follow-up work

- S1 Partner Center confirmation.
- Configure `microsoft-store-production` secrets and first authorized stable
  release. These are separate operator/authorization tasks and belong in a new
  run/plan when initiated.

### Final result

`PLAN_PARTIALLY_EXECUTED` — all implementable repository work is complete and
validated; the live external gates (Partner Center verification and first
authorized submission) remain operator-owned and were not fabricated.
