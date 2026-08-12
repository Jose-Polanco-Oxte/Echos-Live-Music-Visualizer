# Direct3D 11 — Interop and WinUI 3 Integration

## WinUI 3 / Windows App SDK integration

For real-time DirectX content embedded in WinUI 3, `SwapChainPanel` is the normal XAML host when the application manages its own swap chain.

Use the current WinUI 3 `Microsoft.UI.Xaml.Controls.SwapChainPanel` API together with the native swap-chain interop contract.

Typical architecture:

1. create the D3D11 device;
2. obtain the relevant DXGI factory;
3. create a composition-compatible swap chain, normally through `IDXGIFactory2::CreateSwapChainForComposition`;
4. acquire the panel's native swap-chain interface;
5. attach the `IDXGISwapChain` with `SetSwapChain`;
6. manage panel size, composition scale, swap-chain size, and presentation.

Do not substitute old `Windows.UI.Xaml`/UWP type names blindly into a WinUI 3 project.

Keep XAML dimensions (DIPs) separate from render-target pixel dimensions. Recalculate physical size from panel size and effective rasterization/composition scale.

When the panel's size or scale changes:

- update swap-chain dimensions as required;
- update any DXGI matrix transform required by the hosting path;
- rebuild size-dependent targets;
- update viewport/projection data.

Keep rendering independent of ordinary UI work. Do not block the WinUI dispatcher with GPU waits or heavy scene rendering.

Respect the binding/runtime's exact ABI path for obtaining the native `SwapChainPanel` interface. C++, C#, and Rust projections do not expose this identically.

If Direct2D/Win2D must share the D3D11 device, create the D3D11 device with BGRA support and prefer shared DXGI resources/device interop over CPU copies.

## Direct2D / DirectWrite / Win2D interop

When mixing 2D and 3D rendering:

- use one compatible DXGI/D3D11 device graph where practical;
- enable BGRA support when required;
- create Direct2D device/context objects from the same underlying DXGI device;
- preserve correct resource ownership and synchronization;
- explicitly finish/end 2D drawing before using the same resource incompatibly from D3D11.

Do not create unrelated D3D11 devices for each graphics library and then copy full frames between them unless isolation is a deliberate requirement.

When Win2D is already the correct abstraction for a 2D layer, do not replace it with raw D3D11 solely for perceived performance without profiling.

## D3D11On12

Use D3D11On12 only when the architecture actually requires D3D11 components to operate over a D3D12 device or when incrementally integrating D3D11-era components into a D3D12 renderer.

Do not introduce D3D11On12 into a pure D3D11 application merely to use newer tooling.

When using D3D11On12:

- follow the wrapped-resource acquire/release contract;
- flush the D3D11On12 context where the interoperability contract requires it;
- keep D3D11 and D3D12 ownership/state transitions explicit.

Treat it as an interop layer, not a free performance upgrade.
