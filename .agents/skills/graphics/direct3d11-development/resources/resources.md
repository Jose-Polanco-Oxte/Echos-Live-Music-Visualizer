# Direct3D 11 — Resource Ownership and Creation Strategy

## Resource ownership and lifetime

Use COM ownership consistently.

C++:

- prefer RAII and `Microsoft::WRL::ComPtr`, `winrt::com_ptr`, or the project's established smart COM pointer;
- do not manually mix raw `AddRef`/`Release` with smart-pointer ownership unless the ABI boundary requires it.

Managed/Rust bindings:

- understand whether wrappers own, borrow, clone/AddRef, or expose raw COM pointers;
- do not construct multiple independent owning wrappers around the same raw pointer without following the binding's ownership contract.

Release GPU resources in dependency-aware scopes. Do not rely on process termination or finalizers to release large GPU allocations.

Give important device objects debug names in development builds.

At shutdown, use the D3D11 debug interfaces to inspect live objects when investigating leaks. Do not interpret known runtime/internal live objects as application leaks without checking ownership.

## Resource creation strategy

Choose `D3D11_USAGE` and CPU-access flags from the real data-flow pattern.

### Immutable

Use `D3D11_USAGE_IMMUTABLE` for resources initialized once and never changed.

Typical uses:

- static vertex/index buffers;
- immutable lookup data;
- textures whose contents never change after creation.

Provide initial data at creation.

### Default

Use `D3D11_USAGE_DEFAULT` for GPU-oriented resources updated through GPU operations or `UpdateSubresource`.

Typical uses:

- render targets;
- depth/stencil textures;
- most GPU textures;
- infrequently updated buffers;
- UAV resources.

### Dynamic

Use `D3D11_USAGE_DYNAMIC` plus appropriate CPU write access for resources rewritten frequently by the CPU.

Prefer:

- `D3D11_MAP_WRITE_DISCARD` when replacing the current logical contents;
- `D3D11_MAP_WRITE_NO_OVERWRITE` only when the program can prove it will not overwrite bytes still referenced by pending GPU work.

A `WRITE_DISCARD` map discards the logical contents of the whole mapped resource. Do not expect untouched portions to remain valid.

For streaming vertex/index/constant data, prefer a bounded linear/ring allocation pattern over creating many tiny buffers every frame.

### Staging

Use `D3D11_USAGE_STAGING` for deliberate CPU↔GPU transfer paths.

Typical uses:

- screenshots;
- texture/buffer readback;
- CPU-side inspection;
- upload workflows where a staging resource is appropriate.

Do not read back GPU data synchronously every frame unless the product requirement justifies the stall.

## CPU/GPU updates

For small or infrequent updates to default resources, `UpdateSubresource` can be appropriate.

For frequently rewritten buffers, dynamic mapping is usually more suitable.

Avoid:

- mapping resources that are still in GPU use in a way that forces the CPU to wait;
- repeatedly updating the same GPU region before earlier commands finish;
- creating and destroying upload resources in tight frame loops;
- `Flush()` as a routine synchronization mechanism.

If the CPU must know whether GPU work completed, use the appropriate query/synchronization primitive instead of guessing from elapsed time.

Do not busy-spin on `GetData`.

## Constant buffers

Keep CPU and HLSL constant-buffer layout explicitly synchronized.

Rules:

- respect 16-byte constant-buffer packing/alignment requirements;
- validate `sizeof` / field offsets against the HLSL layout;
- avoid C++ `bool` or managed layout assumptions that do not match HLSL packing;
- prefer explicit fixed-width scalar/vector representations;
- separate per-frame, per-view, per-material, and per-object data when update frequency differs;
- avoid rewriting a large global constant buffer for every draw when only a small subset changes.

Use Direct3D 11.1 constant-buffer offset/partial-binding APIs only when the target and feature path support them and the batching benefit is real.
