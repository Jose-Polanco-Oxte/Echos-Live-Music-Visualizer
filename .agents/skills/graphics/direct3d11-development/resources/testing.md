# Direct3D 11 — Testing, Review, and Implementation Workflow

## Testing

Separate CPU-side renderer logic from GPU objects so deterministic behavior can be tested without hardware.

Unit test:

- transforms;
- camera/projection math;
- culling inputs;
- draw sorting;
- resource descriptors;
- constant-buffer packing helpers;
- shader permutation selection;
- subresource calculations;
- render-size/DPI calculations;
- device-recovery state machine.

Integration test:

- hardware device creation;
- WARP creation;
- minimum supported feature level;
- shader creation;
- resource/view compatibility;
- render-target and depth creation;
- resize;
- minimized/zero-size transitions;
- MSAA capability fallback;
- tearing capability fallback;
- WinUI 3 panel attachment when applicable;
- offscreen rendering/readback;
- device-recreation abstraction.

Run debug-layer validation in automated smoke tests where the environment supports Graphics Tools.

For image tests, do not assume byte-identical results across GPUs, drivers, formats, antialiasing modes, and color-management paths. Use controlled environments or tolerance-based semantic comparisons.

## Review checklist

Before considering D3D11 work complete, verify:

- [ ] Windows/SDK/app-model assumptions match the actual project.
- [ ] Direct3D API version, feature level, shader model, and DXGI version are not conflated.
- [ ] Legacy DirectX SDK/D3DX dependencies were not introduced unnecessarily.
- [ ] Adapter selection follows an explicit policy.
- [ ] WARP fallback behavior is intentional.
- [ ] Debug layer is available in development paths where practical.
- [ ] Immediate-context thread ownership is explicit.
- [ ] Deferred contexts are used only for a measured reason.
- [ ] COM/GPU resources have deterministic ownership.
- [ ] Stable resources/state objects are not recreated every frame.
- [ ] Resource usage and CPU-access flags match the update pattern.
- [ ] Constant-buffer layout matches HLSL.
- [ ] Texture row/slice pitch and subresources are handled correctly.
- [ ] SRV/RTV/DSV/UAV hazards are explicitly managed.
- [ ] sRGB/linear color intent is correct.
- [ ] Alpha convention is consistent.
- [ ] MSAA support is queried and flip-model presentation resolves from a separate MSAA target.
- [ ] Flip-model swap chain is used for new desktop presentation unless a specific constraint prevents it.
- [ ] Tearing is capability-checked and used only with valid flags.
- [ ] Resize releases/recreates all size-dependent resources correctly.
- [ ] Device removal rebuilds the full device-dependent graph.
- [ ] WinUI 3 integration uses the current `Microsoft.UI.Xaml`/native interop path.
- [ ] Managed/Rust interop respects COM ownership and struct layout.
- [ ] No per-frame readback, shader compilation, or unbounded allocation exists without justification.
- [ ] Performance changes are based on measurements.
- [ ] Debug-layer warnings/errors relevant to the change are resolved.

## Anti-patterns

Reject or refactor these patterns unless a measured, documented requirement justifies them:

- installing or depending on the June 2010 DirectX SDK for a new project;
- using D3DX11/D3DXMath as the modern baseline;
- starting new .NET graphics work on SharpDX;
- assuming "DirectX 11" means feature level 11_0;
- assuming feature level 12_x gives D3D11 Shader Model 6;
- hardcoding one GPU vendor or adapter index;
- forcing the high-performance GPU without a product policy;
- using WARP silently in a performance-critical app;
- calling the immediate context concurrently from arbitrary threads;
- enabling `D3D11_CREATE_DEVICE_SINGLETHREADED` without proving single-thread access;
- creating buffers, views, shaders, or state objects per draw;
- creating large transient COM object graphs every frame;
- using dynamic resources for data that never changes;
- using staging resources as normal render resources;
- using `Map` in ways that repeatedly stall for the GPU;
- calling `Flush()` every frame;
- busy-waiting on `GetData`;
- reading GPU textures back to CPU every frame and reuploading them;
- binding the same subresource simultaneously for conflicting read/write roles;
- using D3D12-style barriers in a D3D11 renderer;
- ignoring row pitch;
- treating straight and premultiplied alpha as interchangeable;
- treating sRGB and linear texture data as interchangeable;
- creating a multisampled flip-model swap chain;
- assuming a requested MSAA level is universally supported;
- recreating shaders/textures on resize;
- recreating only the swap chain after device removal;
- swallowing `DXGI_ERROR_DEVICE_REMOVED`;
- continuing to use COM resources from the old device after recovery;
- blocking the WinUI UI thread on render/GPU completion;
- copying UWP `Windows.UI.Xaml` interop code into WinUI 3 unchanged;
- using PIX as if it were a native first-line D3D11 frame debugger;
- optimizing around draw-call count, state changes, or resolution without profiling.

## Implementation workflow

When asked to add or change Direct3D 11 rendering:

1. Inspect the project, Windows target, language/binding, and existing graphics ownership.
2. Identify the minimum required D3D11 feature level and optional capabilities.
3. Define adapter and WARP fallback policy.
4. Define device/context thread ownership.
5. Define device-dependent, size-dependent, and frame-transient resource ownership.
6. Create/validate device and diagnostics.
7. Create the modern DXGI presentation path if presentation is needed.
8. Implement shader compilation/loading and immutable pipeline resources.
9. Implement textures/buffers/views with correct usage, formats, and update strategy.
10. Implement the frame pipeline with explicit bindings and hazard handling.
11. Add resize handling.
12. Add device-removal recovery before calling the renderer production-ready.
13. Add WinUI 3/native interop rules if hosted in XAML.
14. Validate under the D3D11 debug layer.
15. Test hardware and WARP paths where relevant.
16. Profile CPU, GPU, synchronization, and presentation separately.
17. Optimize only the measured bottleneck.
18. Re-check current Microsoft documentation/source when an API, capability, format, DXGI behavior, or wrapper contract is version-sensitive.

When a proposed solution depends on a Direct3D 11.1/11.2/11.3/11.4 feature, newer DXGI interface, optional format, tearing support, HDR support, or language-binding behavior, verify it against the project's actual runtime target and current authoritative documentation instead of answering from memory.
