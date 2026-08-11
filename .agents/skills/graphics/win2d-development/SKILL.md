---
name: win2d-development
description: Design, implement, review, debug, and optimize GPU-accelerated 2D graphics with Win2D in WinUI 3 / Windows App SDK applications. Use for CanvasControl, CanvasAnimatedControl, CanvasVirtualControl, CanvasSwapChain, CanvasDevice, bitmaps, geometry, text, effects, DPI, resource lifecycle, device-lost recovery, threading, performance, and Direct2D/Direct3D interop.
---

# Win2D Development

Use this skill for production Win2D work in modern Windows App SDK / WinUI 3 applications.

Treat Win2D as an immediate-mode GPU rendering API layered over Direct2D. Keep rendering architecture, resource ownership, device lifecycle, DPI, and threading explicit.

## Reference documents

This skill is split across modular reference files in `references/`. Load only the document(s) relevant to the current task.

| Reference | Contents | Load when |
| --- | --- | --- |
| [`references/overview.md`](references/overview.md) | Source-authority policy; establishing the project/package baseline. | Starting any Win2D work; orientation. |
| [`references/surface-and-architecture.md`](references/surface-and-architecture.md) | Choosing the rendering surface; separating model state, render description, and GPU resources. | Selecting a control/surface; structuring render code. |
| [`references/resource-lifecycle.md`](references/resource-lifecycle.md) | `CreateResources`, async loading, device/DPI/size resource ownership. | Managing Win2D resource lifecycle. |
| [`references/drawing-and-device.md`](references/drawing-and-device.md) | `CanvasDrawingSession` ownership; device-lost recovery. | Drawing sessions and device recovery. |
| [`references/dpi-and-caching.md`](references/dpi-and-caching.md) | DPI/DIPs/physical pixels; rendering and caching rules. | DPI handling; performance caching. |
| [`references/animation-and-threading.md`](references/animation-and-threading.md) | `CanvasAnimatedControl` game-loop threading; `CanvasVirtualControl`. | Animated or virtualized rendering. |
| [`references/formats-effects-text.md`](references/formats-effects-text.md) | Pixel formats/alpha; effects; text; geometry. | Bitmaps, effects, text, or vector geometry. |
| [`references/interop-and-winui.md`](references/interop-and-winui.md) | Direct2D/Direct3D interop; WinUI 3 integration and cleanup. | Native interop; navigable-page cleanup. |
| [`references/performance-and-debugging.md`](references/performance-and-debugging.md) | Performance workflow; debugging workflow. | Optimizing or debugging rendering. |
| [`references/testing.md`](references/testing.md) | Unit/integration testing, code review checklist, anti-patterns. | Testing and reviewing Win2D code. |
| [`references/workflow.md`](references/workflow.md) | Step-by-step implementation workflow. | Implementing a new or changed rendering feature. |

## How to use

1. Read `references/overview.md` for the source-authority policy and baseline.
2. Read the specific `references/*.md` documents for the task (surface selection, resources, effects, interop, performance, etc.).
3. Apply the guidance to the host project, preserving its existing abstractions and conventions.