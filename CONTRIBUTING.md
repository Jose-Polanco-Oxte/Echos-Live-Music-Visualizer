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
- **Product metadata**: Change official version and product identity through `build/Product.props`, then synchronize its validated projections. Do not bypass `scripts/Test-ProductConfiguration.ps1`.
- **Branding**: Change `docs/public/Echo-Logo-Large.png` or `build/branding.json`, run `scripts/Generate-BrandAssets.ps1`, and verify with `-Check`. Do not hand-edit individual scale/target-size outputs.

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

- **First submission is manual** in Partner Center. Build the Store packages
  with `scripts/Build-Distributions.ps1 -Profile Store -RuntimeIdentifiers win-x64,win-arm64`
  and upload the two architecture-specific `.msix` files together (version
  `A.B.C.0`). Do not upload bundles or the `Dependencies\` folder.
- **Continuous updates** are automated with the **Microsoft Store Continuous
  Delivery** workflow (`store-publish.yml`) using StoreBroker. Configure the
  GitHub Secrets `STORE_APP_ID`, `STORE_CLIENT_ID`, `STORE_CLIENT_SECRET` and
  `STORE_TENANT_ID`, then dispatch with `version_override`, `target_publish_mode`,
  `rollout_percentage`, etc. Use the `dry_run` input to preview without
  submitting.
- **Never commit credentials.** StoreBroker configuration lives in
  `docs/store/` without secrets; credentials are injected at submission time.
- See `docs/public/publishing/microsoft-store.md` and `docs/store/README.md`
  for the full procedure.
