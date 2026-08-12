# Direct3D 11 — Presentation, Swap Chains, and Resize

## Swap chains and presentation

For ordinary modern HWND presentation, prefer DXGI flip model:

- `DXGI_SWAP_EFFECT_FLIP_DISCARD` when preserving previous buffer contents is not required;
- `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL` when its preservation semantics are actually needed.

Do not use legacy blt-model `DISCARD` / `SEQUENTIAL` for a new Windows 10/11 presentation path unless a specific interoperability requirement demands it.

Flip-model requirements include:

- at least two buffers;
- no directly multisampled swap-chain buffers;
- correct back-buffer rebinding after presentation where required by the render loop.

Prefer borderless-window flip-model presentation over fullscreen exclusive unless the product has a concrete reason to own display modes.

### Tearing / VSync

Treat VSync and tearing as an explicit policy.

If presenting with sync interval 0:

- query `DXGI_FEATURE_PRESENT_ALLOW_TEARING`;
- create/resize the swap chain with `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` when supported and desired;
- pass `DXGI_PRESENT_ALLOW_TEARING` only in valid windowed/borderless conditions;
- never combine `DXGI_PRESENT_ALLOW_TEARING` with a nonzero sync interval.

Do not assume disabling VSync automatically removes all frame-rate throttling.

### Frame latency

When low presentation latency matters, consider:

- flip model;
- the frame-latency waitable-object swap-chain option;
- an intentional maximum frame latency;
- a render loop that waits rather than queues unbounded frames.

Do not maximize throughput by allowing arbitrarily deep CPU frame queuing in an interactive application.

## Resize

Treat swap-chain resize as a resource-lifecycle operation.

Before `ResizeBuffers`:

- stop issuing work that targets old size-dependent resources;
- unbind old back-buffer/depth views as required;
- release all application references to swap-chain buffers and views derived from them.

After `ResizeBuffers`:

- reacquire the back buffer;
- recreate RTVs;
- recreate depth/MSAA/size-dependent intermediate targets;
- update viewport/scissor state;
- update projection/aspect-dependent data.

Do not recreate device-independent resources such as shaders and immutable textures on every window resize.

Handle zero/minimized client sizes without trying to create zero-sized render resources.
