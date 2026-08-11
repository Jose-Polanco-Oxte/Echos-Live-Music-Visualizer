# Contributing to Echo Visualizer

Thank you for your interest in contributing to Echo Visualizer! This repository is built as a native Windows desktop application featuring strict architectural separation between the high-performance Rust DSP core (`src/core/`) and the WinUI 3 C# application shell (`src/ui/`).

---

## 🛠️ Development Environment Setup

### Prerequisites
1. **Windows 10 (1809+) or Windows 11** (x64 / ARM64).
2. **Visual Studio 2022 / 2026** with the *.NET Desktop Development* workload.
3. **.NET 8 SDK** (configured in `global.json`).
4. **Rust Stable Toolchain** with target `x86_64-pc-windows-msvc` (and optionally `aarch64-pc-windows-msvc`).

---

## 🚀 Workflow & Branching Strategy

1. Create a descriptive feature branch from `dev` or `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Keep commits atomic, well-tested, and well-documented.
3. Run the automated test suites prior to opening a Pull Request:
   ```powershell
   # Rust Core DSP unit tests
   cargo test --manifest-path src/core/Cargo.toml

   # C# UI & FFI unit tests
   dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Release -p:Platform=x64
   ```
4. Open a Pull Request targeting the default branch.

---

## 🧹 Repository Hygiene

- **Generated Artifacts**: Do not commit compiled binaries (`.dll`, `.exe`, `.msix`), output folders (`bin/`, `obj/`, `artifacts/`, `target/`), or IDE state files (`.vs/`). Versioned files under `src/ui/Assets/` are an intentional exception: they are deterministic branding projections and must match the checked-in recipe.
- **Secrets & Certificates**: Never commit private keys (`.pfx`, `.p12`), certificate passwords, or secret tokens. A public `.cer` may be versioned only when it is an intentional, reviewed development trust anchor and contains no private key. CI/CD pipelines use GitHub Actions Secrets securely.
- **Traceability**: When modifying DSP algorithms, band scaling formulas, or audio conditioning modes, update the specification documents under `docs/public/spec/` and append traceability records in `docs/public/traceability/`.
- **Product metadata**: Change official version, product identity and all
  distribution configuration through `build/Product.props`, then synchronize its
  validated projections. Do not bypass `scripts/Test-ProductConfiguration.ps1`.
- **Branding**: Change `docs/public/Echo-Logo-Large.png` or the branding recipes
  in `build/Product.props`, run `scripts/Generate-BrandAssets.ps1`, and verify
  with `-Check`. Do not hand-edit individual scale/target-size outputs and do
  not reintroduce `build/branding.json`.

---

## 🏗️ Local Build Profiles

- **Validate both profiles and run all quality gates**:
  ```powershell
  .\scripts\Build-Distributions.ps1 -Profile Both
  ```
- **Standalone unpackaged build**:
  ```powershell
  .\scripts\Build-Distributions.ps1 -Profile GitHub -RuntimeIdentifiers win-x64 -SkipTests
  ```
- **Packaged MSIX build**:
  ```powershell
  .\scripts\Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64 -SkipTests
  ```

Use the shared script instead of direct `dotnet publish` commands. It validates
effective MSBuild properties, PE architecture, WinUI PRI resources, canonical
metadata, branding assets, package capabilities, and distribution payloads.

---

## 🛒 Microsoft Store Publishing

- **Stable GitHub Release is the authorization boundary**: publishing a stable
  `vA.B.C.D` release triggers the release-driven Store workflow
  (`store-publish.yml`), which submits the exact validated Store bundle to
  `9NJMJFH8J616`. Drafts, prereleases, PRs and pushes cannot reach
  Store production.
- **Store config lives in `build/Product.props`**: the D5 Store version, the
  single x64+ARM64 `.msixbundle` artifact and the pinned Store CLI coordinates
  come from the centralized configuration; never pass version/package
  overrides.
- **Configure the GitHub Environment `microsoft-store-production`** with the
  four secrets named in `Product.props`
  (`PARTNER_CENTER_TENANT_ID`, `PARTNER_CENTER_SELLER_ID`,
  `PARTNER_CENTER_CLIENT_ID`, `PARTNER_CENTER_CLIENT_SECRET`) and optional ZIP
  signing secrets, per `docs/public/publishing/microsoft-store.md`.
- **Never commit credentials.** No StoreBroker configuration or secret values
  are committed; credentials are injected at runtime from the Environment.
- See `docs/public/publishing/microsoft-store.md` and `docs/store/README.md`
  for the full procedure, setup checklist, recovery and monitoring.
