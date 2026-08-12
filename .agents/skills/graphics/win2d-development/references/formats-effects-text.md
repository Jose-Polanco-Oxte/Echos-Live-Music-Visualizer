# Win2D — Formats, Effects, Text, and Geometry

## Bitmaps, formats, and alpha

When there is no special format requirement, `B8G8R8A8UIntNormalized` with premultiplied alpha is the normal safe default for Win2D render targets and similar 2D content.

Use opaque alpha modes when the surface is truly opaque and the chosen API supports them.

Treat premultiplied alpha correctly. Do not feed straight-alpha pixel data into a premultiplied resource without conversion.

Before selecting HDR, floating-point, block-compressed, unusual DXGI formats, or custom buffer precision:

- verify support on `CanvasDevice`;
- verify the entire effect/render/output path accepts the format;
- document why the extra precision or memory format is required.

Do not assume every `DirectXPixelFormat` value is supported by Direct2D/Win2D.

## Effects

Win2D effects form lazy `ICanvasImage` graphs.

Prefer built-in effects and compose them before implementing custom shaders.

For dynamic effects:

- create the graph once when practical;
- update effect properties or sources instead of rebuilding the graph every frame;
- reuse static subgraphs;
- use output caching only when reuse outweighs cache memory and invalidation cost;
- invalidate cached source regions correctly when source pixels change.

For custom C# effects or Direct2D pixel shaders, prefer the current supported ComputeSharp WinUI integration when it satisfies the requirement. For C++ or unsupported scenarios, use Win2D/Direct2D interop deliberately.

Do not implement a custom effect merely to reproduce an existing Win2D/Direct2D effect.

## Text and geometry

Use `DrawText` for simple text.

Use `CanvasTextLayout` when the task needs:

- measurement;
- wrapping;
- hit testing;
- mixed formatting;
- repeated rendering;
- glyph/layout control.

Do not repeatedly construct the same layout in a hot draw loop.

Use `CanvasPathBuilder` and `CanvasGeometry` for nontrivial vector paths. Cache or realize complex, repeatedly drawn geometry only after establishing that tessellation/drawing cost matters.

Keep model-space geometry separate from view transforms when this makes zooming, panning, hit testing, or DPI handling simpler.
