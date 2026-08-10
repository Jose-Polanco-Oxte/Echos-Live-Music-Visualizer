# Microsoft Store Publishing Guide

This document describes how Echo Visualizer is published to the Microsoft Store,
from the first manual submission to continuous (automated) delivery.

## 1. Distribution model

| Channel | Packaging | Version | Automation |
| --- | --- | --- | --- |
| GitHub Releases | unpackaged, self-contained ZIP (x64/ARM64) | `A.B.C.D` (e.g. `0.2.0.19`) | `release.yml` on tag |
| Microsoft Store | packaged, framework-dependent MSIX, one `.msix` per architecture | `A.B.C.0` (revision must be 0) | `store-publish.yml` |

The Microsoft Store requires the package version **revision to be zero**
(`A.B.C.0`). The pipeline always derives the Store version from the first three
components of the declared product version, so a submission is never rejected
for a nonzero revision.

## 2. Product identity

Reserved identity (Partner Center -> Product management -> Product identity):

| Field | Value |
| --- | --- |
| Identity Name | `Tun4z.EchoVisualizer` |
| Identity Publisher | `CN=8C71527D-01B9-4285-A94B-1585E7C0DA03` |
| PublisherDisplayName | `Tun4z` |
| Package Family Name | `Tun4z.EchoVisualizer_ga3qxkah0cx76` |
| Store ID | `9NJMJFH8J616` |

These values are declared in `src/ui/Package.appxmanifest` and synchronized in
`build/Product.props` (`EchoPackageIdentityName`, `EchoPackagePublisher`,
`EchoPublisherDisplayName`). `scripts/Test-ProductConfiguration.ps1` validates
that the manifest, product metadata, branding, and distribution agree.

## 3. First submission (manual)

The Store Submission API can only update an existing app, so the **first**
submission must be created manually in Partner Center:

1. Build the Store packages:
   - Local: `scripts/Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64,win-arm64 -SkipTests`
   - Or dispatch `store-build.yml` (`workflow_dispatch`) with `version_override`.
2. In Partner Center -> your app -> Submissions -> Packages, upload the two
   **`.msix`** files (`..._x64.msix` and `..._arm64.msix`) together. Do **not**
   upload the `Dependencies\` folder, and never upload two `.msixbundle`
   files (architecture-neutral bundles collide).
3. Complete the questionnaire:
   - Privacy policy: https://jose-polanco-oxte.github.io/Echos-Live-Music-Visualizer/privacy/
   - `runFullTrust`: justify that the WinUI 3 desktop app runs a full-trust
     Win32 process for WASAPI capture, native Rust DSP, and GPU rendering.
   - Age rating, capabilities (microphone), listing, screenshots, testing notes.
4. Submit for certification.

## 4. Continuous delivery (after the first publication)

Prerequisites in Partner Center (one time):

1. In Partner Center -> Account settings -> User management, associate an Azure
   AD application and assign it the **Manager** role. From that entry, copy the
   **Tenant ID** and **Client ID**, and create a **Client secret**.
2. Configure the repository GitHub Secrets:

   | Secret | Value |
   | --- | --- |
   | `STORE_APP_ID` | Store ID (`9NJMJFH8J616`) |
   | `STORE_CLIENT_ID` | Azure AD application (client) ID |
   | `STORE_CLIENT_SECRET` | Azure AD application secret |
   | `STORE_TENANT_ID` | Azure AD tenant ID |

3. Generate the StoreBroker data snapshot (only needed if you want automated
   listing/metadata updates in addition to packages):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/Initialize-StoreBroker.ps1 -AppId <StoreId>
   ```

   See `docs/store/README.md` for the layout and commit the generated config
   and PDPs (credentials stay empty; secrets are injected at runtime).

## 5. Publishing an update

Dispatch **Microsoft Store Continuous Delivery** (`store-publish.yml`):

| Input | Meaning |
| --- | --- |
| `version_override` | Optional `A.B.C.D`; defaults to the canonical product version. The Store version used is always `A.B.C.0`. |
| `target_publish_mode` | `Immediate`, `Manual`, `SpecificDate`, or `Default` (reuse previous). |
| `publish_date` | Local date/time when `SpecificDate`. |
| `rollout_percentage` | Optional gradual rollout `0-100`. |
| `release` | Optional label for the PDP/Images snapshot. |
| `notes_for_certification` | Optional notes for testers. |
| `dry_run` | Build the payload and print the plan **without** calling the API. |

The workflow:
1. Resolves the Store version (`A.B.C.0`).
2. Builds and validates both architecture-specific `.msix` packages.
3. Installs StoreBroker and submits the update (packages replaced, publish mode
   and rollout applied, auto-commit).

> The Store version must always be **higher** than the previously published one.
> Because only the revision is zeroed, keep the first three components
> increasing across releases (for example pass `version_override=0.2.1.0` for
> the next submission). If a future submission would map to the same
> `A.B.C.0`, Partner Center rejects it.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Packages ... same package full name ... Neutral" | Two bundles were uploaded; submit the two architecture-specific `.msix` files instead. |
| "revision number ... not zero" | Store version was not `A.B.C.0`; the pipeline now forces it. |
| `runFullTrust` warning | Expected for WinUI 3 desktop apps; justify in Properties (section 3). |
| `Update-ApplicationSubmission` "no published submission" | StoreBroker requires at least one previously published submission; do the first one manually. |
| "Missing GitHub Secrets" | Add `STORE_APP_ID`, `STORE_CLIENT_ID`, `STORE_CLIENT_SECRET`, `STORE_TENANT_ID`. |
