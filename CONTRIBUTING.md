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

- **Generated Artifacts**: Do not commit compiled binaries (`.dll`, `.exe`, `.msix`), output folders (`bin/`, `obj/`, `artifacts/`, `target/`), or IDE state files (`.vs/`).
- **Secrets & Certificates**: Never commit private keys (`.pfx`), local developer certificates (`.cer`), or secret tokens to Git. CI/CD pipelines use GitHub Actions Secrets securely.
- **Traceability**: When modifying DSP algorithms, band scaling formulas, or audio conditioning modes, update the specification documents under `docs/public/spec/` and append traceability records in `docs/public/traceability/`.

---

## 🏗️ Local Build Profiles

- **Standalone Unpackaged Build (GitHub Releases)**:
  ```powershell
  dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForGitHub=true
  ```
- **Packaged MSIX Build (Microsoft Store)**:
  ```powershell
  dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForStore=true -p:Platform=x64
  ```
