# Direct3D 11 — Device and Context Threading

`ID3D11Device` resource-creation operations are designed for multithreaded use unless the device was created as single-threaded.

The immediate context is not a free-for-all concurrent object.

Rules:

- choose one owner thread for the immediate context;
- do not issue immediate-context calls simultaneously from multiple threads;
- do not hide unsafe access behind random locks throughout the codebase;
- if serialization is required, centralize it;
- use `ID3D11Multithread` protection only when a real interop scenario requires runtime serialization and the overhead is acceptable.

A deferred context records commands for later execution by the immediate context. A deferred context:

- does not inherit immediate-context state;
- should have clear single-thread ownership while recording;
- produces an `ID3D11CommandList`;
- does not make every workload faster.

Do not introduce deferred contexts solely because rendering has multiple CPU threads. Measure command-generation cost and driver behavior first.

For many desktop applications, parallel CPU-side scene/update work plus one immediate-context submission thread is simpler and faster than deferred-context command recording.
