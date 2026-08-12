# Win2D — Implementation Workflow

When asked to add or change Win2D rendering:

1. Inspect project and package versions.
2. Identify static, event-driven, animated, virtualized, offscreen, or manual-present workload.
3. Choose the rendering surface.
4. Define model state and thread ownership.
5. Define device-, DPI-, and size-dependent resource ownership.
6. Implement `CreateResources` and recovery before optimizing draw code.
7. Implement drawing with explicit DIP/alpha/format semantics.
8. Add invalidation/update behavior.
9. Add cleanup and device-lost handling.
10. Validate resize, DPI, navigation, and async loading.
11. Profile before adding caching, lower resolution, batching, or interop.
12. Re-check current Microsoft documentation/source when an API or capability is uncertain.

When a requested API, support claim, or workaround is version-sensitive, verify it against the current Win2D package/repository instead of answering from memory.
