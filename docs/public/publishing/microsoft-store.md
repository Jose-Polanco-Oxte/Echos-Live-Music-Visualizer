# Microsoft Store Publishing Guide

This document describes how Echo Visualizer is published to the Microsoft Store
through the release-driven pipeline: a stable GitHub Release is the production
authorization boundary, and an automated Store workflow submits the exact
validated artifact to the application `9NJMJFH8J616`.

> **Status (2026-08-11):** The first submission — Store version `0.2.0.0` —
> has been **certified and published**.
> Store page: https://apps.microsoft.com/store/detail/9NJMJFH8J616
>
> The release-driven Store CD replaces the older StoreBroker manual/continuous
> flow. Partner Center remains the authoritative external state; the manual
> first-time setup below is still required exactly once.

## 1. Distribution model

| Channel | Packaging | Version | Automation |
| --- | --- | --- | --- |
| GitHub Releases | unpackaged, self-contained ZIP (x64/ARM64) | `A.B.C.D` (e.g. `0.2.0.19`) | `release.yml` on tag |
| Microsoft Store | one unsigned `.msixbundle` (one x64 + one ARM64 inner `.msix`) | `A.B.S.0` (D5 transform, revision 0) | `store-publish.yml` triggered by the release |

The Microsoft Store requires the package version **revision to be zero**
(`A.B.C.0`). The D5 transform maps the four-part product version `A.B.C.D` onto
the Store version `A.B.S.0` with `S = C * 256 + D` and a packing base of 256
declared in `build/Product.props`. The transform is injective and monotonic, so
releases such as `0.2.0.19` and `0.2.0.20` never collide.

## 2. Single configuration source

All versioned product and distribution configuration lives in
`build/Product.props` (schema 1): product identity and version, Store Product
ID, Package Family Name, artifact type `msixbundle`, x64/ARM64 architecture
records, target device family, minimum/tested OS versions, capabilities,
branding recipes, the pinned Microsoft Store Developer CLI coordinates and the
GitHub Environment/secret binding names. The only programmatic parser is
`Get-EchoDistributionConfiguration`; the stable machine interface is
`scripts/Test-ProductConfiguration.ps1 -AsJson`.

Never edit a second configuration file and never introduce a `distribution.json`
or `Distribution.props`. `Package.appxmanifest`, `Cargo.toml`, README content
and `src/ui/Assets` are validated projections of `Product.props`.

Store product identity (Partner Center -> Product management -> Product
identity) must match the configured values:

| Field | Value |
| --- | --- |
| Identity Name | `Tun4z.EchoVisualizer` |
| Identity Publisher | `CN=8C71527D-01B9-4285-A94B-1585E7C0DA03` |
| PublisherDisplayName | `Tun4z` |
| Package Family Name | `Tun4z.EchoVisualizer_ga3qxkah0cx76` |
| Store ID | `9NJMJFH8J616` |

`scripts/Test-ProductConfiguration.ps1` validates that the manifest, product
metadata, branding and distribution agree with the centralized configuration.

## 3. First-time external setup (one-time)

The automated pipeline requires an Entra application and a GitHub Environment;
no secret value is ever committed.

1. Confirm the product is `9NJMJFH8J616`, free, already published, and accepts
   MSIX package updates. Record the latest published Store version and any
   pending submission; the next automated release must map above it.
2. In Partner Center -> Account settings, associate the Microsoft Entra tenant.
3. Create a dedicated automation app registration (not a personal/global
   administrator identity) and assign it the Partner Center **Manager** role
   that Microsoft's current Store CLI GitHub Actions guidance requires.
4. Record Tenant ID, Seller ID and Client ID in the operations inventory.
5. Create a client credential with the shortest practical lifetime (target
   under 12 months); record expiry and rotation reminder.
6. In GitHub create Environment `microsoft-store-production` and add the four
   required secrets with the names declared in `build/Product.props`
   `externalBindings.requiredSecrets`:
   `PARTNER_CENTER_TENANT_ID`, `PARTNER_CENTER_SELLER_ID`,
   `PARTNER_CENTER_CLIENT_ID`, `PARTNER_CENTER_CLIENT_SECRET`. If optional ZIP
   signing is enabled, add `SIGNING_CERTIFICATE_BASE64` and
   `SIGNING_CERTIFICATE_PASSWORD` separately.
7. Restrict the Environment deployment branches/tags to the repository's
   release policy. Optional reviewers may be enabled by the owner.
8. Verify the default `GITHUB_TOKEN` is read-only and workflows grant only the
   explicit job permissions they require.
9. Run the read-only status workflow and confirm authentication and product
   identity/version correlation before the first live submission.

## 4. Publishing an update (automated)

1. Merge a new stable release to `main`, create and push the version tag
   `vA.B.C.D` following `.agents/rules/git.md`.
2. `release.yml` dereferences the exact tag SHA, requires successful CI for that
   SHA, builds the GitHub ZIPs and the Store bundle from the same SHA, generates
   the release manifest and checksums, publishes the stable GitHub Release, and
   explicitly dispatches `store-publish.yml`.
3. `store-publish.yml` re-reads the published stable release, verifies the exact
   tag/SHA/version/manifest/asset digest, validates the downloaded bundle, then
   enters the `microsoft-store-production` Environment and queries Partner
   Center. The fail-closed state machine either reports already published,
   resumes a pending commit, uploads a new no-commit draft then commits, or
   stops without mutation.
4. Certification may take up to three business days; `store-status.yml`
   (scheduled every six hours, read-only) follows it to a terminal state and
   retains sanitized reports for 90 days.

## 5. Recovery operations

| Situation | Correct action |
| --- | --- |
| Missing/expired secret or 401/403 | Correct or rotate the Environment secret/role, run the read-only status, then rerun the same release tag. |
| CLI archive/checksum/version mismatch | Inspect the official release/checksum; update the pin only in a reviewed `Product.props` change and rerun tests. |
| Store target `<=` latest published | Choose a new canonical product version whose D5 mapping is greater; never override the Store version. |
| Different pending submission exists | Inspect Partner Center; let it finish/cancel, or authorize and use the guarded `delete-target-draft` recovery only for the exact matched target. |
| Certification failure | Fetch the certification report in Partner Center, fix, and ship a higher product/Store version. |

`delete-target-draft` deletes only a `PendingCommit` draft with the exact target
version and is a destructive administrative operation; it never deletes a
committed or certifying submission.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Expected Store asset ... missing" | The release was published without the Store bundle/manifest; a new stable release is required. |
| "Store preflight failed closed" | Partner Center state is not safe to mutate; inspect the status report and resolve remotely. |
| `runFullTrust` warning | Expected for WinUI 3 desktop apps; justified in Properties. |
| "Missing Partner Center credentials" | The four Environment secrets are not configured; complete section 3. |
| Certification pending for days | Normal; `store-status.yml` reports `IN_PROGRESS` and never claims publication. |