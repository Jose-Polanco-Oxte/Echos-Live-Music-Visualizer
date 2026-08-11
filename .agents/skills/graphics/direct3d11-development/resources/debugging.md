# Direct3D 11 — Debugging and Common Failure Checks

## Debugging

In development builds, enable the D3D11 debug layer when available.

Use `ID3D11InfoQueue` to:

- inspect validation messages;
- break on corruption/error severity during focused debugging;
- filter known noise carefully.

Do not globally suppress warnings simply to obtain a clean log.

Name important GPU objects.

For rendering bugs, classify the problem before modifying code:

- device creation failure;
- unsupported capability;
- shader compilation failure;
- wrong input layout;
- wrong constant-buffer packing;
- missing binding;
- SRV/RTV/UAV hazard;
- wrong viewport/scissor;
- culling/winding issue;
- depth/stencil mismatch;
- alpha/blend issue;
- sRGB/gamma issue;
- stale or resized target;
- incorrect row pitch/subresource;
- MSAA mismatch;
- device removed;
- synchronization stall;
- presentation problem.

Prefer Visual Studio Graphics Diagnostics/GPU Usage or an active D3D11-capable frame debugger such as RenderDoc for native D3D11 frame inspection.

PIX on Windows is primarily a D3D12 tool. D3D11 capture through D3D11On12 is a specialized diagnostic route, not the normal first-line D3D11 debugging workflow.

## Common failure checks

### Black screen

Check:

- successful device/swap-chain creation;
- nonzero render size;
- RTV creation;
- `OMSetRenderTargets`;
- viewport;
- clear color visibility;
- vertex/index buffers;
- input layout;
- topology;
- shaders;
- constant buffers;
- rasterizer culling;
- depth comparison;
- `Present`;
- device-removed result.

Reduce to a clear-only frame before debugging complex content.

### Geometry distorted or missing

Check:

- CPU/HLSL matrix convention;
- row-major vs column-major expectations;
- matrix transpose policy;
- vertex stride/offset;
- input format;
- index format;
- winding order;
- coordinate handedness;
- near/far projection values;
- viewport/aspect ratio.

### Flicker or corruption after resize

Check:

- old back-buffer references still alive;
- old RTV/DSV still bound;
- size-dependent resources not recreated;
- stale viewport;
- zero-sized/minimized window handling;
- incorrect synchronization around resize.

### Device removed

Log:

- `Present`/operation HRESULT;
- `GetDeviceRemovedReason`;
- adapter description;
- feature level;
- relevant debug-layer messages;
- render operation being executed.

Then rebuild the entire device-dependent graph.
