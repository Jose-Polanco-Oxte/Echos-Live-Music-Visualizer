# Direct3D 11 — Architecture and Device Creation

## Architecture

Prefer a clear graphics ownership model such as:

```text
GraphicsDevice
├── DXGI factory / adapter policy
├── ID3D11Device
├── immediate ID3D11DeviceContext
├── optional newer device/context interfaces
├── optional deferred contexts
├── presentation surface(s)
│   ├── swap chain
│   ├── back-buffer RTV
│   └── size-dependent depth/MSAA resources
├── device-dependent resources
│   ├── shaders
│   ├── state objects
│   ├── static buffers
│   ├── textures/views
│   └── immutable pipelines/material data
└── frame/transient resources
    ├── dynamic upload buffers
    ├── temporary render targets
    ├── queries
    └── per-frame constants
```

Keep **device-dependent**, **size-dependent**, **DPI-dependent**, and **frame/transient** resources distinguishable so resize and device-loss recovery do not require guessing what must be rebuilt.

Do not let a page, window, or UI control become the sole owner of unrecoverable GPU state.

## Device and adapter creation

For modern desktop applications, prefer explicit DXGI factory/device creation over legacy one-call setup when the application needs adapter selection, tearing, modern flip presentation, or diagnostic control.

When choosing an adapter:

- respect an existing application policy;
- use DXGI enumeration rather than vendor-specific assumptions;
- use `IDXGIFactory6::EnumAdapterByGpuPreference` only when a GPU-preference policy is actually desired;
- do not force the discrete/high-performance adapter without a product requirement;
- skip software adapters when choosing hardware unless software rendering is requested;
- use the adapter passed to `D3D11CreateDevice` with `D3D_DRIVER_TYPE_UNKNOWN`.

When no explicit adapter policy is needed, the default hardware adapter is usually sufficient.

Use WARP as:

- a fallback when hardware device creation is unavailable and software rendering is acceptable;
- a useful CI/test/diagnostic backend;
- an intentional compatibility path.

Do not silently fall back to WARP for an application whose performance requirements require hardware acceleration. Surface the fallback in diagnostics.

Do not use the reference rasterizer as a production fallback.

### Device creation flags

Use flags deliberately:

- `D3D11_CREATE_DEVICE_DEBUG` in debug/development configurations when the SDK debug layer is available;
- `D3D11_CREATE_DEVICE_BGRA_SUPPORT` when Direct2D, Win2D, XAML/DirectX interop, or another BGRA-dependent component requires it;
- `D3D11_CREATE_DEVICE_SINGLETHREADED` only when the program can prove that the device and immediate context will never be used across threads.

Do not enable `SINGLETHREADED` as a generic optimization.

If debug-device creation fails specifically because the debug layer is unavailable, make the development behavior explicit. Do not treat that failure as evidence that Direct3D itself is unavailable.

Request feature levels in descending order based on the actual product baseline. Store the returned feature level and branch only where functionality really differs.
