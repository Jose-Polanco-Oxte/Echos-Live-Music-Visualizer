# Project Overview — Echo Live Music Visualizer

## 1. Product Summary & Intent
**Echo Live Music Visualizer** is a high-performance Windows x64 and ARM64 real-time audio visualizer application. It captures live system audio via WASAPI Loopback (or direct audio input), processes signal data through a low-latency multiresolution DSP engine written in Rust, passes extracted energy frames across a zero-copy FFI boundary, and renders 60+ FPS visual representations in WinUI 3 using Win2D and Direct3D 11.

## 2. Core Technology Stack
- **DSP Core (`src/core/`)**: Rust (`x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`), `cargo`. Real-time audio capture, STFT windowing, ERB filterbanks, feature extraction (RMS, Centroid, Onset, LUFS), Master Peak Scaler, FFI ABI v1/v2.
- **UI & Presentation (`src/ui/`)**: C# / WinUI 3, .NET 8 / Windows SDK, Direct3D 11 / Win2D rendering engine.
- **Testing & Benchmarks (`tests/`)**: Rust unit/integration tests, C# xUnit test suite (`tests/EchoVisualizer.Tests`), offline performance benchmarks.
- **Packaging & Delivery**: Validated unpackaged and MSIX builds via `scripts/Build-Distributions.ps1`. All versioned product and distribution configuration lives in `build/Product.props` (schema 1); deterministic branding projections are defined by its branding recipes and `scripts/Generate-BrandAssets.ps1`.

## 3. Directory Layout & Module Ownership
- `src/core/`: Exclusive Rust domain. WASAPI capture, resampling, STFT, energy bands, LUFS measurement, Master Peak scaler, ABI memory layouts.
- `src/ui/`: Exclusive C# / WinUI 3 domain. Shell UI, `AudioCoreService`, view models, Direct3D/Win2D visualizers, visual presets.
- `tests/`: Integration, FFI boundary, and performance benchmark suites.
- `docs/`: Technical specifications (`docs/public/spec/`), traceability matrix (`docs/public/traceability/`).
- `.agents/`: Operational configuration layer for AI agents (rules, context, roles, skills, handoffs, policies).

## 4. Developer Environment & Requirements
- **OS**: Windows 11 / 10 x64.
- **IDE**: Visual Studio 2026 (with Desktop .NET and Windows SDK components).
- **Toolchains**:
  - .NET SDK (specified via `global.json`).
  - Rust Stable (target `x86_64-pc-windows-msvc`, executable located at `C:\Users\tony\.cargo\bin\cargo.exe`).
  - Visual C++ x64/x86 and ARM64 build tools for native cross-compilation.
- **Hardware Requirement**: Physical active WASAPI audio output device for full runtime capture testing.

## 5. Mandatory Agent Operating Rules
1. **Separation of Concerns**: Keep audio DSP strictly inside Rust (`src/core/`) and UI logic strictly inside C# (`src/ui/`).
2. **Normative Specs First**: Read `docs/public/spec/` before altering DSP equations, scaling parameters, or UI render behavior.
3. **Traceability Requirement**: Every functional or DSP change requires a traceability record in `docs/public/traceability/REQ-TRACE-YYYYMMDD-[feature].md` and corresponding inline code references.
4. **Mandatory Execution Workflow**: Run automated unit/FFI tests after any modification before declaring task completion.
