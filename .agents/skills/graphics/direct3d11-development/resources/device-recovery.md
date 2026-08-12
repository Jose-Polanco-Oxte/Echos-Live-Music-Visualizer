# Direct3D 11 — Device Removal and Recovery

Device removal is a normal runtime failure mode that must have an explicit recovery path.

Detect relevant DXGI errors returned from present and other GPU-facing operations, including device-removed/reset cases.

When removal is detected:

1. stop submitting work to the invalid device;
2. call `ID3D11Device::GetDeviceRemovedReason` for diagnostics;
3. release swap-chain and device-dependent resources;
4. release contexts/device interfaces;
5. recreate the DXGI/device chain;
6. recreate every device-dependent resource;
7. recreate size-dependent resources;
8. restore logical rendering state from CPU/application state;
9. resume rendering.

Do not attempt to recover by recreating only the RTV or swap chain while retaining resources from the removed D3D11 device.

Treat `DXGI_ERROR_DEVICE_HUNG` as potentially indicating invalid or excessively long GPU work from the application. Record diagnostics; do not enter an infinite recreate/crash loop without identifying the fault.

On modern systems, `ID3D11Device4::RegisterDeviceRemovedEvent` can be used when asynchronous device-removal notification materially improves the architecture.

Make recovery logic testable by separating logical renderer state from COM/GPU object creation.
