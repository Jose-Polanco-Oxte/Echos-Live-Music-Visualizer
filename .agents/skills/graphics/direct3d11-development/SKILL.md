---
name: direct3d11-development
description: Design, implement, review, debug, and optimize modern Direct3D 11 rendering on Windows 10/11. Use for D3D11 devices and contexts, DXGI adapters and swap chains, shaders/HLSL, buffers, textures, resource views, render targets, depth/stencil, compute, synchronization, multithreading, device-lost recovery, WinUI 3 SwapChainPanel integration, C++/.NET/Rust interop, graphics diagnostics, and performance work.
---

# Direct3D 11 Development

Use this skill for production Direct3D 11 / DXGI work on modern Windows.

Treat Direct3D 11 as an immediate/deferred GPU command API with implicit resource-state management. Keep device ownership, context ownership, resource lifetime, presentation, threading, and recovery explicit.

## Reference documents

This skill is split across modular reference files in `resources/`. Load only the document(s) relevant to the current task.

| Reference | Contents | Load when |
| --- | --- | --- |
| [`resources/overview.md`](resources/overview.md) | Source-authority policy; establishing the project baseline; capability model (API version / feature level / shader model / DXGI). | Starting any D3D11 work; orientation. |
| [`resources/architecture.md`](resources/architecture.md) | Graphics ownership model; device and adapter creation; WARP fallback; device-creation flags. | Designing structure; creating the device. |
| [`resources/threading.md`](resources/threading.md) | Immediate-context thread ownership; deferred contexts. | Multi-threaded rendering. |
| [`resources/resources.md`](resources/resources.md) | COM resource ownership; usage/CPU-access strategy; CPU/GPU updates; constant buffers. | Managing buffers and their update patterns. |
| [`resources/textures-and-views.md`](resources/textures-and-views.md) | Textures, resource views, typeless resources, subresources, binding hazards. | Textures/views and bindings. |
| [`resources/pipeline-and-shaders.md`](resources/pipeline-and-shaders.md) | Pipeline state; HLSL/Shader Model 5; color, alpha, sRGB, HDR. | Shaders, state, color space. |
| [`resources/color-depth-msaa.md`](resources/color-depth-msaa.md) | Depth/stencil, multisampling, MSAA resolve, compute/UAVs. | Depth, MSAA, or compute. |
| [`resources/presentation.md`](resources/presentation.md) | Swap chains, flip model, tearing/VSync, frame latency, resize. | Presentation and resize. |
| [`resources/device-recovery.md`](resources/device-recovery.md) | Device removal detection and full recovery. | Handling device loss. |
| [`resources/interop.md`](resources/interop.md) | WinUI 3 `SwapChainPanel`; Direct2D/DirectWrite/Win2D interop; D3D11On12. | Hosting in XAML or mixing 2D/3D. |
| [`resources/languages.md`](resources/languages.md) | C++/C#/.NET/Rust binding guidance. | Language-specific interop. |
| [`resources/performance.md`](resources/performance.md) | Performance workflow; GPU timing queries. | Optimizing or profiling. |
| [`resources/debugging.md`](resources/debugging.md) | Debug layer, debugging workflow, common failure checks. | Debugging rendering. |
| [`resources/testing.md`](resources/testing.md) | Unit/integration testing, review checklist, anti-patterns, implementation workflow. | Testing, reviewing, and implementing. |

## How to use

1. Read `resources/overview.md` for the source-authority policy and baseline.
2. Read the specific `resources/*.md` documents for the task (device creation, resources, presentation, recovery, interop, performance, etc.).
3. Apply the guidance to the host project, preserving its existing abstractions and conventions.
