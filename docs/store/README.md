# Store Broker Data (`docs/store/`)

This directory feeds the Microsoft Store continuous delivery pipeline
(`.github/workflows/store-publish.yml`). It is intentionally versioned **without
credentials**; authentication is injected at submission time from GitHub
Actions Secrets.

## Layout

```text
docs/store/
├── StoreBrokerConfiguration.json   # Generated once (see below); no secrets
├── StoreBrokerConfiguration.template.json
├── pdp/                            # Store listing metadata (PDP.xml per locale)
└── images/                         # Store listing screenshots per release/locale
```

## One-time generation (first submission published 2026-08-11)

StoreBroker can only update an app that already has at least one published
submission. The first submission (Store version `0.2.0.0`) is now published, so
the prerequisite is met and you can run the one-time bootstrap:

```powershell
# Requires STORE_CLIENT_ID / STORE_CLIENT_SECRET / STORE_TENANT_ID (or interactive)
powershell -ExecutionPolicy Bypass -File scripts/Initialize-StoreBroker.ps1 -AppId <StoreId>
```

That script:
1. Installs/imports StoreBroker.
2. Authenticates with Partner Center.
3. Generates `StoreBrokerConfiguration.json`.
4. Snapshots the current listing into `pdp/<lang>/PDP.xml`.

Then:
- Set `imagesRootPath` to `docs/store/images` and drop screenshots at
  `docs/store/images/<release>/<lang-code>/*.png` following the StoreBroker
  layout.
- Keep `clientId` / `tenantId` / `clientSecret` empty in the committed config.
  Credentials come from the environment at submission time.

## GitHub Secrets required by `store-publish.yml`

| Secret | Value |
| --- | --- |
| `STORE_APP_ID` | Store ID from Partner Center -> App identity (e.g. `9NJMJFH8J616`) |
| `STORE_CLIENT_ID` | Azure AD app Client ID (StoreBroker user) |
| `STORE_CLIENT_SECRET` | Azure AD app Client secret |
| `STORE_TENANT_ID` | Azure AD tenant ID |

## Version rule

Microsoft Store requires the package version revision to be zero (`A.B.C.0`).
The pipeline derives the Store version from the declared product version and
produces one architecture-specific `.msix` per runtime identifier (x64 and
arm64). Upload them together; never upload two bundles.
