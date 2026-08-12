# Microsoft Store Configuration Contract (`docs/store/`)

This directory documents the **non-secret** configuration contract for the
Microsoft Store release pipeline. It no longer contains StoreBroker data; all
versioned configuration lives in `build/Product.props` and all credentials live
only in the GitHub Environment `microsoft-store-production`.

## Layout

```text
docs/store/
├── README.md                          # This contract (no secrets)
```

No `StoreBrokerConfiguration.json`, PDP snapshots, screenshots or images are
committed here. `scripts/Initialize-StoreBroker.ps1` and the associated
configuration template have been removed.

## What is authoritative

| Concern | Location |
| --- | --- |
| Product identity, version, PFN, Store ID | `build/Product.props` schema 1 |
| Store artifact type, architectures, capabilities, OS bounds | `build/Product.props` |
| Branding source/recipes and generated outputs | `build/Product.props` + `scripts/Generate-BrandAssets.ps1` |
| Pinned Store CLI coordinates | `build/Product.props` (`tooling.msstore`) |
| Secret binding names and GitHub Environment | `build/Product.props` (`externalBindings`) |
| Programmatic parser | `scripts/modules/Echo.ReleaseMetadata.psm1` |
| Stable machine interface | `scripts/Test-ProductConfiguration.ps1 -AsJson` |
| Release + submission procedure | `docs/public/publishing/microsoft-store.md` |

`Package.appxmanifest`, `src/core/Cargo.toml`, README content and
`src/ui/Assets` are validated **projections** of `Product.props` and are not
independent configuration entry points.

## Credentials

Partner Center secrets are never committed. They are stored only as GitHub
Environment secrets named in `Product.props`:
`PARTNER_CENTER_TENANT_ID`, `PARTNER_CENTER_SELLER_ID`,
`PARTNER_CENTER_CLIENT_ID`, `PARTNER_CENTER_CLIENT_SECRET`, plus the optional
`SIGNING_CERTIFICATE_BASE64` and `SIGNING_CERTIFICATE_PASSWORD` for ZIP signing.

## Version rule

The Store version derives deterministically from the product version
(`A.B.C.D → A.B.S.0`, packing base 256) and always ends in revision zero. The
production artifact is a single unsigned `.msixbundle` with one x64 and one
ARM64 inner package; never submit loose per-architecture packages or two bundles
after the bundle flow is active.

## Mandatory provenance and pending identity

Every release no-op and every Store mutation is gated on complete, exact
evidence:

- A GitHub release can only be a **no-op** when it records the resolved commit
  SHA (`target_commitish`) that matches the tag's 40-character commit hash. No
  marker, a branch, malformed or mismatched commit always **fails closed**.
- `Published` uploads only when a valid canonical latest published version is
  present; only `NoSubmission` may upload without a prior version.
- `PendingCommit` commit/delete requires **all** of Store version, bundle name,
  package family name and recomputed SHA-256 to be present and match the target.
  Missing or mismatched fields fail closed; partial checks never authorise a
  mutation.

See `docs/public/publishing/microsoft-store.md` for the full procedure.