# Direct3D 11 — Textures, Views, and Binding Hazards

## Textures and views

A resource is storage. A view defines how the pipeline accesses compatible storage.

Use:

- `ID3D11ShaderResourceView` for shader reads;
- `ID3D11RenderTargetView` for render-target writes;
- `ID3D11DepthStencilView` for depth/stencil access;
- `ID3D11UnorderedAccessView` for unordered shader read/write access.

Use typeless resources only when multiple compatible typed interpretations are required.

Examples include:

- linear vs sRGB views of compatible color storage;
- depth resources that must also be sampled;
- compatible typed views over a shared resource family.

Do not reinterpret a typeless resource with an unrelated format merely because the bit width matches.

When a depth texture must also be sampled, create a typeless resource format and compatible DSV/SRV formats. Do not expect a regular depth-stencil typed resource to become a shader resource automatically.

Use `D3D11CalcSubresource` or an equivalent correct calculation for mip/array subresource indices. Do not hand-roll inconsistent indexing.

Respect row pitch and slice pitch. Never assume texture rows are tightly packed when mapping or copying.

## Resource binding hazards

Do not bind the same subresource for conflicting read/write roles at the same time.

Typical hazards:

- SRV + RTV;
- SRV + DSV write access;
- SRV + UAV write access;
- UAV + RTV when overlapping;
- copying from/to a resource while it is still bound incompatibly.

The runtime may null conflicting bindings and the debug layer may report warnings, but application code should manage transitions deliberately.

Before reusing a resource in a conflicting role:

1. unbind the old view from relevant shader/output stages;
2. bind the new role;
3. keep ownership/state tracking simple enough to audit.

Do not add D3D12-style resource barriers to solve D3D11 hazards. D3D11 manages GPU resource states internally; your responsibility is legal binding and ordering through the API.
