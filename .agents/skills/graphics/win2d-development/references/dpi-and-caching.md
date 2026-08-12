# Win2D — DPI, Pixels, and Caching

## DPI, DIPs, and physical pixels

Win2D drawing coordinates are normally DIPs.

Do not mix DIPs and physical pixels implicitly.

Use `ConvertDipsToPixels` / `ConvertPixelsToDips` when crossing that boundary and choose rounding intentionally where pixel alignment matters.

Remember:

- controls track display DPI automatically;
- bitmap-like resources such as `CanvasBitmap`, `CanvasRenderTarget`, and `CanvasSwapChain` carry DPI;
- `CanvasDevice` has no inherent DPI;
- `CanvasCommandList` is vector drawing state and has no inherent raster DPI.

When creating an offscreen target from `CanvasDevice`, supply an intentional DPI. When creating it from `ICanvasResourceCreatorWithDpi`, prefer the resource creator's DPI unless the scenario requires a different raster resolution.

Do not hardcode 96 DPI as a universal rendering assumption.

If high-DPI fill rate is the performance bottleneck, consider an intentional `DpiScale` reduction only after profiling. Treat reduced resolution as a visual-quality tradeoff, not a default optimization.

## Rendering and caching rules

Keep the draw path bounded and predictable.

Prefer:

- precomputed geometry for stable shapes;
- `CanvasCachedGeometry` when profiling shows complex repeated geometry is expensive;
- `CanvasTextLayout` for repeated, measured, formatted, or hit-tested text;
- `CanvasCommandList` for reusable vector command sequences and reusable effect inputs;
- `CanvasRenderTarget` when an intermediate must be rasterized;
- `CanvasSpriteBatch` for large sprite workloads when the current platform supports the required API;
- reuse of brushes, layouts, bitmaps, and effect objects when their contents are stable.

Avoid:

- per-frame file or stream I/O;
- per-frame bitmap decoding;
- per-frame GPU resource creation;
- unnecessary CPU↔GPU readback;
- rebuilding large text layouts or geometries on every draw;
- unbounded temporary allocations in animation loops;
- rasterizing vector content early without a reason.

Cache only what has a useful reuse lifetime. Caching dynamic content can increase memory traffic and synchronization cost.
