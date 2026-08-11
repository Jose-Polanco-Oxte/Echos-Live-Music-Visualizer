# Direct3D 11 — Depth, Stencil, and Multisampling

## Depth and stencil

Create depth/stencil resources at the render size and sample count required by the render path.

Choose format intentionally.

If only depth is needed, do not allocate stencil merely from habit when a more suitable depth format fits the pipeline.

If depth must be shader-readable, use a compatible typeless-resource/view pattern.

Clear depth/stencil only when required by the pass. Do not preserve stale depth accidentally across unrelated passes.

Keep the chosen depth convention consistent across projection matrices, depth clear value, comparison function, and post-processing reconstruction.

## Multisampling

Never assume a sample count or quality level.

Use `CheckMultisampleQualityLevels` for the exact format/sample-count combination.

Modern DXGI flip-model swap chains are not directly multisampled. When MSAA is required:

1. render into a separate multisampled color target;
2. render depth with matching sample count;
3. resolve the color target into the single-sample swap-chain back buffer;
4. present the swap chain.

Do not create an MSAA flip-model back buffer.

Remember that resolving color is not equivalent to resolving arbitrary depth/stencil data. If downstream passes need depth, design a compatible depth strategy.

## Compute shaders and UAVs

Use D3D11 compute when the workload maps well to GPU parallelism and D3D11 feature support is sufficient.

For compute resources:

- create correct structured/raw/typed buffers;
- set `StructureByteStride` correctly for structured buffers;
- request the required SRV/UAV flags;
- validate typed UAV format support where relevant;
- keep thread-group dimensions and dispatch counts within API/hardware limits;
- account for bounds in shaders when dispatch dimensions exceed logical data dimensions.

Unbind UAVs/SRVs before reusing overlapping resources in conflicting roles.

Do not assume `Dispatch` is a CPU/GPU synchronization point.

Avoid readback immediately after dispatch unless the CPU truly requires the result.
