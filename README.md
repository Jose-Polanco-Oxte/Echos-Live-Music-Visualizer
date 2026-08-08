<div align="center">

  <img src="docs/public/Echo-Logo-Large.png" alt="Echo Visualizer Logo" width="180" />

  # Echo Visualizer

  **Ultra-Low Latency, High-Fidelity Real-Time Audio Visualizer for Windows**

  [![Version](https://img.shields.io/badge/version-v0.1.0.4-cyan.svg?style=for-the-badge)](https://github.com/)
  [![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20x64%20%7C%20ARM64-blue.svg?style=for-the-badge)](https://microsoft.com)
  [![Framework](https://img.shields.io/badge/UI-WinUI%203%20%2F%20Windows%20App%20SDK-purple.svg?style=for-the-badge)](https://learn.microsoft.com/windows/apps/winui/winui3/)
  [![Engine](https://img.shields.io/badge/DSP-Rust%20FFI-orange.svg?style=for-the-badge)](https://www.rust-lang.org/)
  [![Acceleration](https://img.shields.io/badge/Graphics-Win2D%20Direct2D%20GPU-brightgreen.svg?style=for-the-badge)](https://github.com/microsoft/Win2D)
  [![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)](LICENSE)

</div>

---

## Overview

**Echo Visualizer** is a native Windows desktop application (supporting x64 and ARM64) engineered to capture high-fidelity real-time system audio (*WASAPI System Loopback* / Microphone Inputs) and render fluid, flicker-free audio spectrum visualizers via hardware-accelerated Direct2D GPU rendering (Win2D).

It bridges a high-performance **Rust DSP Engine** (low-level floating-point processing, multiresolution STFT, ITU-R BS.1770-4 LUFS psychoacoustic calibration) with a modern, responsive user interface built on **WinUI 3 (Windows App SDK)**.

---

## 📦 Distribution Channels & Installation

### 1. GitHub Releases (Standalone / Unpackaged) — Recommended for Portability
Direct download requiring no formal installation or administrator privileges:
1. Navigate to the [Releases](https://github.com/) section of the repository.
2. Download the appropriate `.zip` package for your processor architecture:
   - `EchoVisualizer-vX.Y.Z-win-x64.zip` (Intel/AMD 64-bit systems)
   - `EchoVisualizer-vX.Y.Z-win-arm64.zip` (ARM64 systems / Surface Pro / Copilot+ PCs)
3. Extract the archive into any local directory and run `EchoVisualizer.exe`.

> **Note on Windows SmartScreen / Code Signing**: Unpackaged standalone builds distributed via GitHub Releases may prompt a Windows SmartScreen warning ("Unknown Publisher") if a commercial certificate is not attached. Click *More info -> Run anyway*. For an unprompted installation experience, use the official Microsoft Store package.

### 2. Microsoft Store (MSIX / Packaged)
Recommended channel for secure automatic updates and seamless Store integration. *(Coming soon to the Microsoft Store)*.

---

## ✨ Key Features

| Feature | Description |
| :--- | :--- |
| **WASAPI Loopback Capture** | Continuous zero-latency capture of global system audio output or any active input audio device. |
| **Rust Core DSP Engine** | 12 to 128 band spectral analysis via multiresolution STFT (Blackman-Harris windowing) with compute latency $L_c < 1.5\text{ ms}$ (p99). |
| **Win2D GPU Batching** | Immediate-mode Direct2D primitives rendered on the GPU at 60–144+ FPS without XAML framework overhead. |
| **Spectral Bar Equalizer** | Continuous log-frequency band mappings, asymmetric inertial smoothing (instant attack / exponential decay), and layout modes (*Bottom-Up*, *Top-Down*, *Center-Out/Mirror*). |
| **Chromatic Personalization** | *Audio Mapped* mode (reactive dynamic hue based on spectral centroid) and *Custom Palette* modes (Primary/Secondary R/G/B). |
| **Smart Overlay** | Floating UI controls with automatic cursor auto-hide after 4 seconds of inactivity. |

---

## 🏗️ Architecture

```mermaid
graph TD
    A[WASAPI Audio Input / System Loopback] -->|PCM 48kHz / Hop=512| B(Rust Core DSP Engine - EchoCore.dll)
    B -->|STFT 4096/2048/1024 + LUFS BS.1770-4| C[Lock-Free SPSC Ring Buffer]
    C -->|Zero-Copy FFI Lease| D[WinUI 3 C# Application Shell]
    D -->|Win2D Direct2D GPU Batching| E[Display Output / Render 60-144 FPS]
```

---

## 🛠️ Development Setup & Local Building

### Prerequisites
- **Operating System:** Windows 10 (1809+) or Windows 11 (x64 / ARM64).
- **IDE / SDK:** Visual Studio 2022 / 2026 with *.NET Desktop Development* workload.
- **Runtime:** .NET 8 SDK (`net8.0-windows10.0.26100.0`).
- **Rust Toolchain:** Rust stable (`x86_64-pc-windows-msvc` or `aarch64-pc-windows-msvc`).

### CLI Build Commands

#### Run Unit & FFI Tests
```powershell
# Rust Core DSP unit tests
cargo test --manifest-path src/core/Cargo.toml

# C# UI & FFI unit tests
dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Release -p:Platform=x64
```

#### 1. Build Standalone Unpackaged GitHub Release (x64)
```powershell
dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForGitHub=true
# Output location: artifacts/github/win-x64/
```

#### 2. Build Standalone Unpackaged GitHub Release (ARM64)
```powershell
dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-arm64 -p:BuildingForGitHub=true
# Output location: artifacts/github/win-arm64/
```

#### 3. Build Microsoft Store Packaged MSIX (x64)
```powershell
dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForStore=true -p:Platform=x64
# Output location: artifacts/store/
```

---

## 📁 Repository Structure

```text
Echos-Live-Music-Visualizer/
├── .github/
│   ├── dependabot.yml         # Monthly dependency update configuration
│   └── workflows/
│       ├── ci.yml             # Automated CI Quality Gate workflow
│       ├── release.yml        # Official tag-triggered GitHub Release CD workflow
│       └── store-build.yml    # Manual Microsoft Store MSIX packaging workflow
├── src/
│   ├── core/                  # Audio DSP engine in Rust (EchoCore.dll)
│   └── ui/                    # WinUI 3 C# application shell, Win2D renderers, and Views
├── tests/
│   └── EchoVisualizer.Tests/  # C# unit, integration, and FFI stress tests
├── docs/
│   └── public/                # Specifications, traceability reports, and assets
├── CONTRIBUTING.md            # Contribution guidelines and hygiene rules
├── SECURITY.md                # Security policy and disclosure process
├── CHANGELOG.md               # Version release notes and changelog
└── LICENSE                    # MIT License
```

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.
