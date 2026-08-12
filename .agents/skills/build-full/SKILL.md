---
name: build-full
description: >-
  Compile, test, and deploy the Echos Live Music Visualizer application from source.
  Handles environment verification, Rust and C# unit tests, MSIX packaging, and installation.
  Use when building EchoVisualizer from the repository, whether for development or production deployment.
  Requires .NET SDK, Rust toolchain, and PowerShell (Windows). A public development certificate can be trusted per-user.
license: Proprietary
compatibility: >-
  Windows only (PowerShell). Requires: .NET 8 SDK (per global.json),
  Rust + Cargo, Visual Studio Build Tools or similar C++ toolchain.
  Must be executed from repository root. Administrator rights are not required when the certificate is trusted for the current user.
metadata:
  author: EchoVisualizer Team
  version: "1.0"
  target-platform: Windows x64 and ARM64
  min-dotnet-version: "8.0"
---

# Echos Build & Deploy Skill

Build and deploy the Echos Live Music Visualizer application from source with automated testing and MSIX packaging.

## Prerequisites

Before running any build step, ensure your environment is correctly configured:

1. **Clone and navigate to the repository root**
2. **.NET SDK 8.0+** installed and available in PATH (`dotnet --info` should work)
3. **Rust toolchain** installed (`rustc --version` and `cargo --version` should work)
   - If `cargo` is not in PATH, the script uses the default Cargo location: `$env:USERPROFILE\.cargo\bin\cargo.exe`
4. **C++ Build Tools** (Visual Studio Build Tools or equivalent) for native library compilation
   - Install `Microsoft.VisualStudio.Component.VC.Tools.ARM64` when building or validating ARM64 outputs from an x64 machine.
5. **PowerShell 7+ or Windows PowerShell 5.1+** (all scripts execute in PowerShell)

## Quickstart: Full Build & Deploy (One Command)

If all prerequisites are met, run this single command from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/Build-Distributions.ps1 -Profile Both
```

This executes the entire pipeline in sequence:
1. Verifies the environment
2. Runs Rust DSP engine tests
3. Runs C# unit and FFI integration tests
4. Compiles the application and Rust core
5. Generates and structurally validates the MSIX package

**Stop on first error:** If any step fails, the script halts. Review the error message and see [Troubleshooting](#troubleshooting) below.

---

## Step-by-Step Build Process

If you prefer manual control or need to troubleshoot individual steps:

### Step 1: Verify Environment

Confirm that all tools are installed and discoverable:

```powershell
# Check .NET SDK
dotnet --info

# Check Rust and Cargo
rustc --version
cargo --version

# (Optional) Test that the Rust toolchain can compile
cargo --version
```

**Expected output:**
- `dotnet` reports version 8.0 or later
- `rustc` and `cargo` show recent versions
- No "command not found" errors

### Step 2: Run All Tests

Execute the test suite for both Rust and C#:

```powershell
# Run Rust DSP engine tests
cargo test --manifest-path src/core/Cargo.toml

# Run C# unit tests and FFI integration tests
dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj `
  -c Debug `
  -p:Platform=x64
```

**What this checks:**
- Rust audio DSP core compiles and passes all unit tests
- C# UI layer compiles and passes unit tests
- FFI (Foreign Function Interface) between C# and Rust works correctly
- No breaking changes in recent commits

**If tests fail:** Review the error output. Common issues are listed in [Troubleshooting](#troubleshooting).

### Step 3: Build and Publish Binaries

Compile and structurally validate the self-contained GitHub profile through the
same entry point used by CI:

```powershell
.\scripts\Build-Distributions.ps1 `
  -Profile GitHub `
  -RuntimeIdentifiers win-x64 `
  -SkipTests
```

**Output location:** `artifacts/github/win-x64/`

**What happens:**
- Canonical product metadata and generated branding are checked before compilation
- MSBuild invokes `cargo build --release` for the Rust core
- Rust native library (`echo_core.dll`) is compiled and embedded
- C# assemblies are linked and optimized
- All dependencies are bundled into the output directory
- PE architecture, PRI resources, runtime payload, loose branding, and embedded executable icon are validated

### Step 4: Trust the Development Certificate (One-Time Setup)

Before installing the `.msix` package, the local development certificate must
be trusted. Use the current-user trust store so elevation is not required:

```powershell
Import-Certificate `
  -FilePath .\EchoDev.cer `
  -CertStoreLocation Cert:\CurrentUser\TrustedPeople
```

**What this does:**
- Installs `EchoDev.cer` (the development signing certificate) into the Windows certificate store
- Allows Windows to recognize and install locally-signed MSIX packages without security warnings
- Only needs to run once per machine

The public `.cer` contains no private signing key. Signing still requires a
matching certificate with a private key in `Cert:\CurrentUser\My`.

### Step 5: Generate and Install the MSIX Package

Create a Windows app package and install it as a native Windows application:

```powershell
# Build and validate the MSIX package
.\scripts\Build-Distributions.ps1 `
  -Profile Store `
  -RuntimeIdentifiers win-x64 `
  -PackageVersion 0.2.0.17 `
  -SignMsix

# Install the most recently generated MSIX bundle
$msixPath = (Get-ChildItem .\artifacts\store-test\win-x64\*.msixbundle -Recurse | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Add-AppxPackage -Path $msixPath
```

**Output location:** `artifacts/store-test/win-x64/` directory

**What happens:**
- The MSIX bundle is created with all dependencies embedded
- Windows registers the app in the app store / Start menu
- Shortcuts and file associations are configured
- App can be launched like any other Windows application
- Uninstall works through Settings → Apps → Installed Apps

---

## Workflow Checklist

Use this to track progress through a full build and deploy:

- [ ] **Prerequisites verified** — Run Step 1 and confirm all tools are available
- [ ] **Tests pass** — Run Step 2 and address any failures before continuing
- [ ] **Binaries built** — Run Step 3 and confirm output under `artifacts/github/`
- [ ] **Certificate trusted** — Run Step 4 once (or verify it's already installed)
- [ ] **MSIX generated and installed** — Run Step 5 and launch the app from Start menu

---

## Gotchas

### Cargo not in PATH
**Problem:** Running `cargo --version` returns "command not found"

**Solution:** Cargo is installed in `$env:USERPROFILE\.cargo\bin\cargo.exe`. Either:
- Add this directory to your PATH permanently, or
- Run cargo commands with the full path: `& "$env:USERPROFILE\.cargo\bin\cargo.exe" build`

### Tests fail with "Platform mismatch" or "x64 not found"
**Problem:** Test command fails because the x64 platform isn't recognized

**Solution:** Ensure the C++ build tools (Visual Studio Build Tools or similar) are installed. If already installed, try:
- Repair the Visual Studio installation
- Clear the build cache: `dotnet clean`
- Rebuild: `dotnet build -c Release -p:Platform=x64`

### MSIX installation fails with "No matching Certificates"
**Problem:** `Add-AppxPackage` fails with "Certificate not found" or "Signature verification failed"

**Solution:**
- Verify the certificate is trusted for the current user:
  ```powershell
  Get-ChildItem Cert:\CurrentUser\TrustedPeople | Where-Object { $_.Subject -like "*EchoDev*" }
  ```
  If no result, re-run Step 4.
- Alternatively, add the `-ForceApplicationShutdown` flag when installing:
  ```powershell
  Add-AppxPackage -Path $msixPath -ForceApplicationShutdown
  ```

### "The system cannot find the path specified" during distribution publish
**Problem:** The Rust core library path isn't found during the build

**Solution:**
- Ensure you're running the command from the repository root directory
- Verify `src/core/Cargo.toml` exists
- Manually run `cargo test --manifest-path src/core/Cargo.toml` to ensure Rust compilation works in isolation

### PowerShell execution policy blocks the script
**Problem:** Running a script fails with "cannot be loaded because running scripts is disabled"

**Solution:** Run the script with `-ExecutionPolicy Bypass`:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/Build-Distributions.ps1 -Profile Both
```

Or set the execution policy for the current user (permanent in the current session):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Troubleshooting

### Build succeeds but app won't start
- **Check Windows version:** The project targets Windows 10.0.26100.0+. If on an older build of Windows 10, update to Windows 11 or later.
- **Check platform consistency:** Confirm the requested RID is correct and verify the accepted output under `artifacts/github/<rid>/` or `artifacts/store-test/<rid>/`.

### Tests pass locally but fail in CI/CD
- **Environment differences:** CI agents may not have the same C++ toolchain or build cache. Always run the full test suite before commit.
- **Rust toolchain version:** If CI uses a different Rust version, consider using `rust-toolchain.toml` to pin the version.

### MSIX app uninstalls itself after installation
- This typically means the certificate expired or is untrusted. Re-run Step 4 to reinstall the certificate.

### Slow builds or timeouts
- **First build is slow:** The first `cargo` invocation downloads and caches the Rust standard library (~200MB+). Subsequent builds are faster.
- **Increase timeout:** If running in CI with aggressive timeouts, increase the timeout for the `dotnet build` and `cargo test` steps.

---

## Advanced: Headless / CI/CD Deployment

For automated builds in CI/CD pipelines:

1. **Pre-install the certificate** in the CI agent's certificate store during setup (see Step 4)
2. **Use the full pipeline script** with environment variables:
   ```powershell
   $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = $true
   $env:DOTNET_CLI_TELEMETRY_OPTOUT = $true
   & scripts/Build-Distributions.ps1 -Profile Both
   ```
3. **Capture the MSIX path** for artifact archiving:
   ```powershell
   $msix = (Get-ChildItem .\artifacts\store-test\win-x64\*.msixbundle -Recurse | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
   Write-Host "MSIX_PATH=$msix" >> $env:GITHUB_ENV  # For GitHub Actions
   ```

---

## Output Artifacts

After a successful build:

| Artifact | Location | Purpose |
|----------|----------|---------|
| **Binaries** | `artifacts/github/win-x64/` | Portable executable and dependencies |
| **MSIX Bundle** | `artifacts/store-test/win-x64/EchoVisualizer_A.B.C.D_x64.msixbundle` | Windows app installer |
| **Native Rust lib** | `artifacts/github/win-x64/EchoCore.dll` | Audio DSP engine (compiled from Rust) |

---

## Next Steps

- **Launch the app:** Click the EchoVisualizer shortcut in Start menu or run from the installed app location
- **Uninstall:** Settings → Apps → Installed Apps → Find "EchoVisualizer" → Uninstall
- **Develop:** Modify source code and re-run the full pipeline for incremental testing and deployment
- **Distribute:** Sign the MSIX with a production certificate and publish via Microsoft Store or direct distribution

---

## See Also

- **Rust Core Documentation:** `src/core/README.md`
- **C# UI Project:** `src/ui/EchoVisualizer.csproj`
- **Test Suite:** `tests/EchoVisualizer.Tests/`
