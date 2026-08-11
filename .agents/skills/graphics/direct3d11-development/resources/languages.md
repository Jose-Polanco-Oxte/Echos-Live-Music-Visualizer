# Direct3D 11 — Language-Specific Guidance

## C++

Prefer:

- Windows SDK headers/libraries;
- RAII COM ownership;
- DirectXMath for math;
- DirectXTK when its helpers reduce boilerplate without obscuring ownership;
- DirectXTex for texture processing/loading scenarios it is designed for.

Do not add D3DX just to obtain old helper APIs.

## C# / .NET

Prefer the actively maintained binding already used by the project.

If choosing a new binding, evaluate current maintenance, Windows App SDK interop requirements, unsafe/COM ergonomics, and API coverage before introducing it.

`Vortice.Windows` is an active .NET binding with Direct3D 11/DXGI coverage and is a reasonable option when a managed wrapper is desired.

`Microsoft.Windows.CsWin32` can expose raw Windows SDK APIs but may require lower-level unsafe COM handling for graphics interfaces. Choose it when generated Win32 interop matches the project's architecture rather than assuming it is a high-level graphics wrapper.

Do not start new Direct3D work on SharpDX; the project is archived and unmaintained.

For managed wrappers:

- dispose deterministic GPU/COM objects;
- do not rely on finalization for GPU memory pressure;
- minimize per-frame managed allocations;
- avoid boxing/LINQ/temporary arrays in hot render loops;
- pin or marshal data only for the shortest valid scope;
- validate struct packing and unmanaged layout used for GPU buffers.

## Rust

Prefer Microsoft's current `windows` / `windows-sys` ecosystem when direct Windows API bindings fit the project.

Enable only the Win32 feature namespaces actually needed, such as Direct3D11, Direct3D, DXGI, foundation/system pieces, and WinUI/native interop dependencies.

Keep `unsafe` boundaries narrow:

- COM pointer creation;
- raw slice/pointer transfer;
- mapped-resource access;
- FFI struct initialization.

Wrap resource ownership and HRESULT handling in safe project-level abstractions rather than spreading raw COM calls across application logic.

Do not use Rust ownership types to imply GPU completion. CPU object lifetime and GPU execution lifetime are separate concerns.
