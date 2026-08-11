# Win2D — Performance and Debugging

## Performance workflow

Do not optimize Win2D by folklore.

When rendering is slow:

1. Determine whether the bottleneck is CPU, GPU, synchronization, allocation/GC, image decoding/upload, fill rate, effect intermediates, text/layout, geometry, or presentation.
2. Measure frame/update/draw time and allocation behavior.
3. Remove repeated resource creation from hot paths.
4. Reduce redundant drawing and invalidation.
5. Cache only expensive stable work.
6. Batch repeated bitmap/sprite operations when applicable.
7. Reduce offscreen intermediates and full-surface effects.
8. Consider render-resolution reduction only if fill rate is the actual constraint.
9. Re-measure after each meaningful change.

Do not use `ForceSoftwareRenderer` as a performance solution. It is useful for diagnostics, compatibility investigation, and controlled testing.

For deeper GPU problems, use appropriate DirectX diagnostics/frame tools rather than guessing from UI symptoms.

## Debugging workflow

For rendering bugs, classify the failure before changing code:

- nothing drawn;
- wrong coordinates or transform;
- wrong DPI/scale;
- clipping;
- incorrect alpha/blending;
- stale resource/device;
- unsupported format/effect;
- resource load not completed;
- wrong thread;
- surface not invalidated/presented;
- size zero or stale render target size;
- device lost;
- resource leak or lifetime error;
- CPU/GPU performance stall.

Then inspect the smallest relevant layer.

Useful checks include:

- `ReadyToDraw`;
- current control size and DPI;
- resource device identity;
- bitmap/render-target DPI and format;
- alpha mode;
- `CreateResources` reason;
- device-lost state;
- thread access;
- whether `Invalidate()` or `Present()` is required;
- whether an async resource operation is still running;
- whether a cached resource references an old device.

Enable graphics debug diagnostics in debug builds when they materially help. Do not ship verbose graphics diagnostics accidentally.
