# Changelog

All notable changes to **Echo Live Music Visualizer** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
