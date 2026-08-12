# Windows Native Interop — Callbacks, Memory, and DLLs

## Native callbacks

Callbacks are lifetime-sensitive.

Determine:

```text
calling convention
callback lifetime
thread of invocation
reentrancy
context pointer semantics
unregistration protocol
shutdown ordering
```

Modern .NET guidance prefers unmanaged function pointers with `[UnmanagedCallersOnly]` over delegate marshalling when practical.

Example conceptual design:

```text
native registration
    receives:
        function pointer
        context pointer

managed side:
    owns callback registration
    keeps context valid
    unregisters callback
    waits for in-flight callbacks if required
    only then releases state
```

Never let the GC collect a managed delegate while native code can still call it.

## Callback exceptions must not cross ABI boundaries

Do not allow managed exceptions to propagate through an unmanaged callback frame.

Catch at the native boundary.

Translate to:

* HRESULT;
* error code;
* recorded failure state;
* deferred managed exception;

depending on the ABI.

Native callers do not understand arbitrary CLR exception unwinding.

## Calling conventions

The managed declaration must match the native calling convention.

A mismatch can cause memory/stack corruption and fatal crashes.

This matters especially for x86.

On modern Windows x64 and ARM64 there is one platform ABI for ordinary unmanaged calls, while x86 still requires correct distinction among conventions such as stdcall and cdecl.

Never copy an x64-working callback declaration and assume it proves correctness on x86.

## Unsafe code

Unsafe code is acceptable when native ABI access genuinely requires it.

Keep unsafe regions:

```text
small
local
reviewable
ownership-explicit
bounds-aware
well-tested
```

Do not spread pointers through business logic.

Preferred layering:

```text
unsafe/generated interop
        ↓
safe native wrapper
        ↓
application service
        ↓
UI/domain
```

The public application API should normally expose:

```text
managed values
SafeHandle
Span/ReadOnlySpan where lifetime is safe
managed result types
```

rather than raw pointers.

## Pointer lifetime

Never store a pointer returned by native code beyond its documented validity.

Possible lifetimes include:

```text
until next API call
until ReleaseBuffer
until callback returns
until object Release
until module unload
until explicit free
thread-local duration
borrowed process lifetime
```

Copy data when the consumer needs it beyond the native lifetime.

## Native memory allocators must match

A native allocation must be freed using the matching allocator contract.

Do not mix:

```text
malloc        / CoTaskMemFree
CoTaskMemAlloc / free
LocalAlloc    / Marshal.FreeHGlobal
new           / free
SysAllocString / CoTaskMemFree
```

Determine allocation ownership from the API documentation.

If native code transfers ownership to managed code, represent that transfer explicitly.

## Avoid unnecessary manual allocation

Before using:

```text
Marshal.AllocHGlobal
NativeMemory.Alloc
stackalloc
GCHandle
fixed
```

check whether:

* the generated overload already accepts a managed type;
* `Span<T>` can be used;
* a SafeHandle exists;
* the API supplies its own buffer;
* a two-call size/query pattern is available.

Manual unmanaged memory increases the number of lifetime states that must be correct.

## stackalloc

Use `stackalloc` only for small bounded buffers whose maximum size is controlled.

Never stack-allocate directly from arbitrary external input.

For variable or potentially large buffers, use:

```text
ArrayPool<T>
managed arrays
owned native buffers
```

as appropriate.

## Pinning

Pin managed memory only for as long as necessary.

Prefer call-scoped pinning.

Long-lived pins can harm GC behavior.

If native code retains a pointer asynchronously, ordinary call-scoped P/Invoke pinning is not sufficient.

Use an explicitly owned stable buffer strategy.

## Native DLL loading

For application-owned native libraries, explicitly understand:

```text
which DLL is loaded
from which directory
how dependencies are resolved
architecture of the module
packaged/unpackaged behavior
deployment location
```

.NET provides native-library resolution APIs such as `NativeLibrary.SetDllImportResolver` for scenarios requiring controlled resolution.

Do not modify global native search behavior casually.

## DLL search-path security

Do not load an untrusted DLL by bare filename when an attacker-controlled searched directory could satisfy the name.

Windows DLL search order depends on packaging and process configuration. Microsoft explicitly warns that a searched attacker-controlled directory can enable malicious DLL substitution.

For application-owned dependencies, prefer controlled loading from trusted locations.

Avoid using current-working-directory manipulation as a dependency-resolution mechanism.

Do not permanently weaken process-wide DLL search policy to solve one library-loading issue.
