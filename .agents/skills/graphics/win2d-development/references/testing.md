# Win2D — Testing, Review Checklist, and Anti-Patterns

## Testing

Separate deterministic application logic from GPU integration so most behavior can be tested without a graphics device.

Unit test:

- transforms and coordinate math;
- scene/update state;
- invalidation calculations;
- geometry inputs;
- effect parameter calculation;
- animation timing logic;
- resource-state machines.

Integration test:

- resource creation and disposal;
- offscreen rendering with `CanvasRenderTarget`;
- resize;
- DPI changes;
- navigation/unload cleanup;
- pause/resume for animated controls;
- delayed/cancelled resource loading;
- device recreation paths;
- supported hardware/software rendering paths when relevant.

For image comparisons, avoid assuming byte-identical output across GPUs, drivers, font rasterizers, DPI, or antialiasing modes unless the environment is controlled. Prefer tolerances, masks, region comparisons, or semantic pixel assertions.

Test at more than one DPI and at least one non-default scale when rendering correctness depends on sizing.

## Code review checklist

Before considering Win2D work complete, verify:

- [ ] The selected control/surface matches the rendering workload.
- [ ] Project/package assumptions match the actual target.
- [ ] No stale UWP/WinUI 2 guidance was copied blindly.
- [ ] Stable GPU resources are not recreated every frame.
- [ ] `CreateResources` can reconstruct device-dependent state.
- [ ] Async resource loading participates in lifecycle recovery.
- [ ] Device-lost recovery cannot retain old-device resources.
- [ ] Size-dependent resources are recreated on relevant resize.
- [ ] DIP/pixel conversions are explicit.
- [ ] DPI-sensitive resources are handled correctly.
- [ ] Premultiplied alpha and pixel format semantics are correct.
- [ ] Explicit drawing sessions and disposable resources are disposed.
- [ ] Event-owned drawing sessions are not retained or manually disposed.
- [ ] Animated callbacks do not block or access UI unsafely.
- [ ] Per-frame allocations and resource creation are bounded.
- [ ] Effect graphs and intermediate surfaces are reused appropriately.
- [ ] Navigable Win2D controls are detached on unload in managed apps.
- [ ] Rendering behavior is tested across resize/DPI/lifecycle cases.
- [ ] Performance changes were measured rather than assumed.

## Anti-patterns

Reject or refactor these patterns unless a measured, documented requirement justifies them:

- creating `CanvasBitmap`, `CanvasRenderTarget`, `CanvasTextLayout`, complex geometry, brushes, or effect graphs every frame;
- storing a `CanvasDrawingSession` outside its valid scope;
- using a resource after its device was lost/replaced;
- blocking or awaiting indiscriminately inside `CanvasAnimatedControl.Update` or `Draw`;
- reading or mutating XAML UI directly from the game-loop thread;
- treating pixels and DIPs as interchangeable;
- hardcoding 96 DPI as the display model;
- forcing a fixed render resolution without a quality/performance requirement;
- selecting exotic pixel formats without capability checks;
- copying straight-alpha data into premultiplied surfaces unchanged;
- invalidating an entire virtual surface when only a small region changed;
- rebuilding effect graphs for property-only changes;
- using a swap chain when a higher-level control already provides the needed lifecycle;
- assuming old generated WinUI 3 documentation is newer than the package/source;
- leaking navigated Win2D pages through event/reference cycles;
- using GC pressure, UI thread priority, or software rendering to hide an architectural rendering problem.
