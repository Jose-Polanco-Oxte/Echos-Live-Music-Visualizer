# Direct3D 11 — Pipeline State and HLSL

## Pipeline state

Treat shaders and fixed-function state as reusable device objects.

Cache and reuse:

- rasterizer states;
- blend states;
- depth/stencil states;
- sampler states;
- input layouts;
- shaders.

Do not create state objects per draw.

Avoid redundant state changes when they are a measured CPU cost, but do not build a complex state cache before profiling.

Remember that D3D11 state is associated with the context. Utility rendering code that modifies context state must either:

- own that portion of the frame contract; or
- restore only the state the caller contract requires.

Do not blindly snapshot/restore the entire D3D11 pipeline around every helper call; full state preservation is expensive and often unnecessary.

## HLSL and shaders

Direct3D 11's normal shader target is Shader Model 5.0 or the lower model required by the chosen feature level.

For D3D11:

- use the Windows SDK HLSL/FXC/D3DCompiler toolchain for Shader Model 5 bytecode where appropriate;
- prefer build-time/offline shader compilation for production assets;
- use runtime compilation primarily for development, editors, generated shaders, or explicitly dynamic workflows;
- preserve compiler diagnostics;
- enable debug information and disable optimization only where useful in development builds;
- use optimized shader bytecode in production unless a debugging requirement says otherwise.

Do not introduce DXC/Shader Model 6 merely because it is newer; Shader Model 6 is a Direct3D 12 path, not the normal D3D11 shader target.

Do not use deprecated `D3DXCompile*` APIs.

Keep shader bindings explicit and stable:

- constant-buffer slots;
- SRV slots;
- UAV slots;
- sampler slots;
- vertex input semantics.

If reflection is used to generate or validate bindings, keep it outside hot render loops.

Validate input-layout declarations against the vertex shader input signature. Do not assume a C/C++/C# struct layout automatically matches HLSL semantics or packed vertex data.

## Color, alpha, and sRGB

Treat color space as part of the rendering contract.

Typical rule:

- color/albedo/UI textures authored in sRGB should normally be sampled through an sRGB view;
- normal maps, masks, roughness/metalness, depth, and other numeric data should normally remain linear;
- lighting and blending should operate in the intended linear space.

Do not fix gamma problems with arbitrary shader powers when the real problem is an incorrect resource/view color-space interpretation.

For swap-chain output, choose format and render-target view semantics deliberately.

When using transparency with composition, ensure the swap-chain alpha mode and shader output agree on straight vs premultiplied alpha. Do not mix alpha conventions implicitly.

HDR is a separate presentation path. When HDR is required:

- query current output and swap-chain capabilities;
- choose a supported HDR-capable format/color space;
- set the DXGI color space explicitly;
- apply the intended tone-mapping/output transform;
- handle transitions between HDR/SDR displays.

Do not assume that an HDR-capable GPU means the active output is currently HDR-capable or configured for HDR.
