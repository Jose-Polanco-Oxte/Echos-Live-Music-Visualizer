# Direct3D 11 Development — Overview

Use this skill for production Direct3D 11 / DXGI work on modern Windows.

Treat Direct3D 11 as an immediate/deferred GPU command API with implicit resource-state management. Keep device ownership, context ownership, resource lifetime, presentation, threading, and recovery explicit.

Do not import Direct3D 12 concepts such as command queues, descriptor heaps, explicit resource barriers, manual residency, or fences into a D3D11 design unless an actual D3D11.3/11.4 interop feature requires them.

## Source authority

When documentation, wrappers, samples, and old DirectX material disagree, use this order:

1. Current Microsoft Learn documentation for Direct3D 11, DXGI, HLSL, Direct2D interop, and Windows App SDK.
2. The Windows SDK headers and interface definitions actually targeted by the project.
3. Current Microsoft-maintained DirectX libraries and examples where applicable:
   - `microsoft/DirectXTK` for practical Direct3D 11 helpers and patterns.
   - `microsoft/DirectXTex` for texture processing/loading workflows.
   - `microsoft/DirectXMath` for native SIMD math.
4. Current source for the language binding already used by the project.
5. Active graphics debugging tools and their current documentation.

The Windows SDK is the modern DirectX SDK baseline. Do not add the legacy June 2010 DirectX SDK to a new project.

Do not use deprecated D3DX11/D3DXMath as the architectural baseline. Prefer Windows SDK APIs plus maintained replacements such as DirectXTK, DirectXTex, DirectXMesh, UVAtlas, and DirectXMath when their functionality is needed.

Do not copy old UWP, DirectX SDK, SharpDX, Effects 11, or Visual Studio template code without validating it against the current project, Windows target, API version, and binding.

## Establish the project baseline

Before changing graphics code, inspect:

- language: C++, C#/.NET, Rust, or mixed native/managed;
- Windows target/minimum version;
- Windows SDK version;
- Windows App SDK / WinUI 3 version when applicable;
- process architecture: x64, ARM64, x86, ARM64EC;
- packaged vs unpackaged deployment when relevant;
- current D3D11/DXGI interfaces in use;
- feature-level requirements;
- shader model and shader compilation pipeline;
- adapter-selection policy;
- swap-chain model and presentation policy;
- whether Direct2D, DirectWrite, Win2D, Media Foundation, Windows Graphics Capture, or another DirectX component shares the device;
- active .NET/Rust/native binding;
- current debug/profiling tooling.

Do not silently upgrade the Windows SDK, Windows App SDK, target framework, graphics wrapper, shader compiler, or minimum Windows version unless the task requires it.

Do not assume that "DirectX 11", Direct3D API version, feature level, shader model, and DXGI version are the same concept.

## Understand the capability model

Keep these separate:

- **Direct3D API version** — interfaces such as `ID3D11Device`, `ID3D11Device1` … `ID3D11Device5`.
- **Feature level** — hardware/runtime functionality exposed through `D3D_FEATURE_LEVEL`.
- **Shader model** — HLSL bytecode capability.
- **DXGI version** — presentation/adapter interfaces obtained from DXGI objects.
- **Optional feature support** — capabilities queried with `CheckFeatureSupport`, `CheckFormatSupport`, DXGI feature checks, or interface availability.

A D3D11 device may expose feature levels above 11_0 on sufficiently recent systems, but Direct3D 11 itself supports shader model 5.0 as its shader-model ceiling. Do not infer shader model 6 support from a 12_x feature level when using the D3D11 API.

Query capabilities instead of inferring them from GPU brand, driver name, Windows edition, or feature level when the capability is optional.

Use `QueryInterface` for newer device/context/DXGI interfaces and gracefully fall back when the project supports older Windows versions.
