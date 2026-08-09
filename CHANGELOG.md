# Changelog

All notable changes to **Echo Live Music Visualizer** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0.19] - 2026-08-09
### Fixed
- Fixed `AudioEngine::reconfigure` to be transactional regarding the WASAPI
  capture worker restart: a replacement worker is paused behind a start gate
  until the new band count and frame-store state are fully committed, so the
  engine never publishes against a partially-committed configuration.
- Fixed reconfiguration validation on headless/CI machines without an audio
  endpoint: an offline engine (no capture worker) now accepts valid
  reconfigurations, and rejected band configurations preserve the previous DSP
  state.
- Hardened `FrameStore` against stale band-length publications by rejecting
  (and counting as dropped) frames that carry a band count different from the
  active store configuration.

### Release metrics
- Verified defects resolved: 1.
- Unique release files affected: 8.
- Build increment: `max(1, floor(8 / 10)) = 1`.
- Calculated version: `0.2.0.18 -> 0.2.0.19`.

## [0.2.0.18] - 2026-08-08
### Added
- Tag `WindowsAppSdkUndockedRegFreeWinRTInitialize` in `EchoVisualizer.csproj` with `true` value.

### Fixed
- Fixed the unpackaged WinUI build crash caused by an incomplete PRI resource
  graph.


## [0.2.0.17] - 2026-08-08

### Added
- Added deterministic, multi-resolution branding assets and embedded icons for
  packaged and unpackaged x64/ARM64 distributions.
- Added direct microphone and line-input selection through a versioned audio
  device ABI while preserving the existing loopback interface.
- Added capture-activity diagnostics, transactional device replacement, and
  identity-appropriate microphone privacy recovery.
- Added live Windows system-theme synchronization across XAML, the title bar,
  Win2D surfaces, and high-contrast resources.
- Added canonical product metadata and one validated build entry point shared
  by local development and GitHub Actions.

### Fixed
- Fixed the unpackaged WinUI startup crash caused by an incomplete PRI resource
  graph.
- Fixed generic or missing shell/window icons in standalone distributions.
- Fixed silent microphone-selection failures and stale-device persistence.
- Fixed test isolation so the .NET suite cannot overwrite real user theme and
  audio preferences.
- Fixed release workflow version derivation, tag validation, and MSIX identity
  version propagation.

### Release metrics
- Feature increments: 1 (`distribution runtime parity and configuration hardening`).
- Verified defects resolved: 5.
- Unique release files affected: 110.
- Build increment: `max(1, floor(110 / 10)) = 11`.
- Calculated version: `0.1.0.6 -> 0.2.0.17`.

## [0.1.0.6] - 2026-08-08

### Added
- Created dedicated `dev` branch for active local development and agent workflows.
- Registered `EchoCore.dll` as an explicit payload item in `EchoVisualizer.csproj` for full MSIX Appx package compatibility.
- Updated `ColorPalette.xaml` resource dictionary URI for seamless dual packaged/unpackaged support.

## [0.1.0.5] - 2026-08-08

### Added
- Declared explicit PerMonitorV2 High-DPI scaling awareness in `app.manifest` for high-resolution display rendering.

### Fixed
- Fixed GitHub Actions CI toolchain race condition by pre-building Rust `echo_core` library sequentially before test execution.
- Resolved zero-frame ABI v2 lease availability issue in headless CI environments without physical audio hardware.

## [0.1.0.4] - 2026-08-07

### Added
- Multi-channel official distribution pipeline supporting both **Microsoft Store (MSIX)** and **GitHub Releases (Standalone Unpackaged ZIP)** from a single codebase.
- Dedicated MSBuild publishing profiles (`BuildingForGitHub` and `BuildingForStore`) in `EchoVisualizer.csproj`.
- Cross-compilation support for **x64** (`x86_64-pc-windows-msvc`) and **ARM64** (`aarch64-pc-windows-msvc`).
- Automated GitHub Actions CI/CD workflows (`ci.yml`, `release.yml`, `store-build.yml`, and `dependabot.yml`).
- Automated SHA-256 integrity checksum generation (`SHA256SUMS.txt`).

### Changed
- Refactored `EchoCore.dll` deployment targets in MSBuild to dynamically support standalone unpackaged execution.
- Sanitized repository history and `.gitignore` to exclude intermediate build XML exports (`*.pp.xml`), local certificates (`.cer`), and test outputs.
- Comprehensive English documentation update across `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md`.

## [0.1.0.0] - 2026-08-06

### Added
- Initial public release specification and repository architecture.
- WinUI 3 + Win2D hardware-accelerated GPU spectral rendering engine.
- Low-latency WASAPI system audio loopback capture engine in Rust (`EchoCore`).
- Multiresolution STFT analysis (12 to 128 bands) with ITU-R BS.1770-4 LUFS psychoacoustic loudness calibration.
