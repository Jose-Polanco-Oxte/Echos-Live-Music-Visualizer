# Direct3D 11 — Performance and GPU Timing

## Performance workflow

Do not optimize D3D11 by folklore.

When rendering is slow, first determine whether the bottleneck is:

- CPU simulation;
- draw-call submission;
- state churn;
- shader CPU compilation;
- GPU vertex/geometry work;
- pixel/fill-rate work;
- texture bandwidth;
- overdraw;
- compute dispatch;
- resource upload;
- CPU↔GPU synchronization;
- readback;
- presentation/VSync;
- allocation/GC;
- multi-GPU copy/presentation;
- driver overhead.

Then optimize the measured bottleneck.

Typical improvements:

- move immutable work out of frame loops;
- batch compatible draws;
- use instancing where it reduces submission overhead;
- sort when it meaningfully reduces state/material changes;
- use dynamic ring-buffer patterns for transient geometry/constants;
- avoid unnecessary render-target clears and full-screen passes;
- reduce overdraw;
- reduce render resolution only when fill rate is the real bottleneck;
- precompile shaders;
- avoid GPU readbacks;
- avoid `Flush`;
- avoid blocking `Map`;
- reuse render targets and state objects;
- use mipmaps and appropriate texture formats;
- compress suitable texture assets offline.

Do not replace a correct simple renderer with a complicated deferred-context/state-cache architecture without measurements.

## GPU timing and synchronization diagnostics

Use GPU timestamp/disjoint queries for D3D11 GPU timing where appropriate.

Keep CPU wall-clock timing separate from GPU execution timing.

When using queries:

- issue timestamps around meaningful GPU regions;
- account for asynchronous availability;
- avoid stalling the CPU every frame waiting for results;
- consume measurements after enough frames have elapsed.

Do not infer GPU cost from the duration of a single `Draw` call on the CPU.
