# Win2D — Surface Selection and Architecture

## Choose the rendering surface deliberately

Prefer the highest-level type that satisfies the requirement.

| Scenario | Prefer |
|---|---|
| Mostly static or event-driven drawing | `CanvasControl` |
| Continuous animation or a game-style update/draw loop | `CanvasAnimatedControl` |
| Huge, sparse, scrollable, or partially visible drawing surface | `CanvasVirtualControl` |
| Explicit swap-chain ownership, presentation, buffering, or lower-level animation control | `CanvasSwapChainPanel` + `CanvasSwapChain` |
| Offscreen rasterization | `CanvasRenderTarget` |
| Reusable vector drawing commands or effect input | `CanvasCommandList` |
| Custom host / no built-in Win2D control | `CanvasDevice` plus the appropriate low-level image source, virtual image source, swap chain, or native interop |

Do not reach for `CanvasSwapChain` merely because the content animates. Prefer `CanvasAnimatedControl` when its game-loop and lifecycle policy fit.

Do not use `CanvasAnimatedControl` for content that only changes occasionally. With `CanvasControl`, update state and call `Invalidate()` when a redraw is needed.

Use `CanvasVirtualControl` when virtualization actually reduces drawing or memory cost. Redraw only invalidated regions.

## Separate application state from graphics resources

Keep three concepts distinct:

1. **Model state** — values describing what should be displayed.
2. **Device-independent render description** — layout inputs, paths, colors, effect parameters, immutable scene data.
3. **Device/DPI/size-dependent resources** — bitmaps, render targets, brushes or cached resources tied to a resource creator, DPI, target size, or graphics device.

Do not let UI controls become the authoritative model.

Prefer immutable snapshots, small render-state structures, or bounded producer/consumer handoff between application logic and rendering code.
