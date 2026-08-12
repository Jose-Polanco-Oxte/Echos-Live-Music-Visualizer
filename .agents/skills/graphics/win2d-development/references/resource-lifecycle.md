# Win2D — Resource Lifecycle

Use `CreateResources` as the normal lifecycle boundary for resources needed by Win2D controls.

Create expensive or reusable graphics resources once and reuse them. Do not recreate stable bitmaps, geometries, text layouts, brushes, command lists, effect graphs, or render targets every frame without a measured reason.

For asynchronous loading in `CreateResources`, aggregate the work into one operation and pass it to `CanvasCreateResourcesEventArgs.TrackAsyncAction`. Do not start unrelated fire-and-forget resource loads from the handler.

When `CreateResources` is raised because of a new device:

- discard resources associated with the previous device;
- recreate every resource or graph that references them;
- update caches and object graphs that retain old-device resources.

When it is raised because DPI changed:

- recreate resources whose rasterization or physical resolution depends on DPI;
- do not rebuild truly DPI-independent state unnecessarily.

Handle control size changes separately when application-created render targets, swap chains, cached surfaces, or layout resources depend on size.

If resources are loaded later, outside initial `CreateResources`, make that loading cancellable/restartable and compatible with device-lost recovery. Never let a completed background load reattach resources created for an obsolete device.
