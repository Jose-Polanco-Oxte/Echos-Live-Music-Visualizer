# Requirements and Formula Traceability Report

- **Feature / Increment:** Reliable packaged and unpackaged distribution startup
- **Date:** 2026-08-08
- **Responsible:** Codex
- **Status:** IMPLEMENTED AND VERIFIED

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.5 | `docs/public/spec/requirements-spec.md` section RF6.1 | Echo must start as both packaged MSIX and unpackaged self-contained distributions. The unpackaged build must not require package identity, a separately installed Windows App Runtime, or administrator privileges. | The x64 executable and installed x64 MSIX remain running through a ten-second smoke window. ARM64 outputs compile and pass structural validation. The unpackaged PRI contains the WinUI theme resources. |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship with Formula |
|---|---|---|---|
| RF6.1.5 | `src/ui/EchoVisualizer.csproj` :: GitHub unpackaged profile | `EnableMsixTooling=true`, `WindowsPackageType=None`, `WindowsAppSDKSelfContained=true`, `SelfContained=true` | MSIX tooling merges the WinUI resource graph while the other properties preserve unpackaged, self-contained deployment. |
| RF6.1.5 | `src/ui/EchoVisualizer.csproj` :: Store packaged profile | `WindowsPackageType=MSIX`, `GenerateAppxPackageOnBuild=true`, `WindowsAppSdkDeploymentManagerInitialize=false` | The Store profile always emits a package, retains package identity, and avoids unnecessary Deployment Manager initialization. |
| RF6.1.5 | `src/ui/app.manifest` :: DPI awareness declarations | Microsoft Windows Settings schema URIs for 2005 and 2016 | Correct schema namespaces ensure the Win32 manifest compiler recognizes Per-Monitor V2 DPI awareness in both distributions. |
| RF6.1.5 | `src/ui/EchoVisualizer.csproj` :: `EchoCoreCargo` | `cargo` resolved through PATH and `rust-toolchain.toml` | MSBuild and direct Cargo commands use the same pinned Rust toolchain and its x64/ARM64 targets. |
| RF6.1.5 | `scripts/Build-Distributions.ps1` | Profile, runtime identifier, package version, signing, installation, smoke-test switches | One entrypoint builds and validates the same profiles used locally and by continuous integration. A temporary manifest override supplies a test package version without changing the normative manifest. |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| RF6.1.5 | Run Rust formatting, Clippy, Rust tests, and .NET tests through `Build-Distributions.ps1`. | Any nonzero command exit terminates the pipeline. | PASS: formatting and Clippy clean; 74 Rust and 40 .NET tests passed. |
| RF6.1.5 | Publish GitHub outputs for `win-x64` and `win-arm64`; validate PE architecture, required runtime files, and the primary PRI resource map. | The PRI must contain `Microsoft.UI.Xaml/Themes/themeresources.xbf`; ARM64 is structurally validated on x64 hardware. | PASS: both artifacts validated, including PE architecture and WinUI theme resources. |
| RF6.1.5 | Build signed MSIX bundles for x64 and ARM64; inspect signature, identity, version, architecture, dependencies, capabilities, and payload. | Only the x64 package is installed and launched on the current x64 machine. | PASS: both `0.1.0.8` bundles validated with the development certificate; x64 installed with status `Ok`. |
| RF6.1.5 | Launch unpackaged x64 and installed MSIX x64 for at least ten seconds, then request normal main-window closure. | Early process exit or failure to close normally fails the smoke test. | PASS: both x64 distributions remained active for ten seconds and closed normally; no process remained. |

## Deviations or Decisions

The existing `XamlControlsResources` entry remains unchanged. The failure was
caused by an incomplete unpackaged PRI graph when MSIX tooling was disabled, not
by invalid application XAML. The local test package uses both an explicit
`AppxPackageVersion=0.1.0.8` and a generated manifest override so identity and
assembly projections cannot diverge while the versioned manifest remains
unchanged. The repository's official `0.1.0.6` version is unchanged. The
development publisher identity is retained and is not presented as a Microsoft
Store production identity.
