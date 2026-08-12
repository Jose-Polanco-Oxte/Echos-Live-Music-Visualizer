# Win2D — Direct2D/Direct3D Interop and WinUI 3 Integration

## Direct2D / Direct3D interop

Use native interop only when Win2D does not expose the required capability or when resources must be shared with another DirectX component.

When wrapping or unwrapping resources:

- preserve the correct `CanvasDevice`;
- preserve DPI where the wrapper contract requires it;
- preserve pixel format and alpha semantics;
- understand COM lifetime and native resource ownership;
- synchronize access when native Direct2D/Direct3D code and Win2D use the same underlying device/resource;
- use `CanvasDevice.Lock` only for the advanced interop scenarios it is intended for, not as a general application lock.

Do not create parallel D3D/D2D devices accidentally when resources are expected to interoperate.

If sharing an existing Direct3D 11 device is required, prefer creating the `CanvasDevice` from that device rather than copying resources between unrelated devices.

## WinUI 3 integration and cleanup

Keep the render thread independent from page navigation and ordinary UI work.

For managed WinUI applications with Win2D XAML controls, explicitly break control/page reference cycles when the page or host is unloaded:

- call `RemoveFromVisualTree()` on the Win2D control;
- release explicit references that keep the control alive;
- unsubscribe other long-lived event handlers when their owner outlives the page.

This is especially important for navigable pages repeatedly created and destroyed.

Do not use forced `GC.Collect()` as production memory management.
