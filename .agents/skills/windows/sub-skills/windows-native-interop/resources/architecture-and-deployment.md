# Windows Native Interop — Architecture and Deployment

## Architecture

Interop code must be evaluated for:

```text
x64
ARM64
x86 — only if project supports it
```

Check:

* pointer sizes;
* `nint`/`nuint`;
* structure layout;
* calling convention;
* native DLL architecture;
* COM server architecture;
* callback signatures.

Do not derive pointer size from:

```text
OperatingSystem.Is64BitOperatingSystem
```

when the relevant value is the **process architecture**.

A 32-bit process can run on 64-bit Windows.

## AnyCPU

Do not assume `AnyCPU` means native dependencies become architecture-independent.

Generated Win32 declarations can be architecture-safe, but a bundled native DLL still has a concrete machine architecture.

If native binaries are shipped, verify deployment/RID strategy separately.

## Windows version gating

Before calling an API introduced after the project's minimum Windows version:

1. identify the API's minimum supported version;
2. compare against project support policy;
3. provide a guarded path or raise the minimum version;
4. test the fallback.

Do not use OS version checks as substitutes for understanding whether an API is dynamically available.

Prefer the project's established platform-compatibility strategy.

## Packaging model matters

A desktop application may be:

```text
packaged
unpackaged
packaged with external location
with identity
without identity
AppContainer
full-trust desktop
```

These models can change:

* DLL resolution;
* activation;
* registry/file access;
* COM behavior;
* Windows Runtime capabilities;
* package-relative paths.

Do not assume a packaged WinUI 3 app behaves exactly like an unpackaged executable at native boundaries.

## NativeAOT and trimming

If the project uses NativeAOT or trimming, treat runtime-generated interop as a compatibility concern.

CsWin32's default mode uses runtime marshalling and is not automatically NativeAOT-compatible; Microsoft documents additional AOT configuration for CsWin32.

Modern source-generated mechanisms such as:

```text
LibraryImport
GeneratedComInterface
ComWrappers source generation
```

should be considered where they fit the ABI.

Do not enable `DisableRuntimeMarshalling` without auditing the entire project's interop surface.

## Keep interop behind an abstraction

Do not allow `PInvoke.*` calls to spread indiscriminately throughout ViewModels and application logic.

Prefer:

```text
WindowsApi / NativeMethods-generated layer
        ↓
focused native wrapper
        ↓
domain-specific service
```

Example:

```text
PInvoke.GetWindowLong(...)
PInvoke.SetWindowLong(...)
        ↓
WindowStyleService
        ↓
application behavior
```

The wrapper should own:

* conversions;
* lifetime;
* error translation;
* version checks;
* retries where valid.

This makes native assumptions testable and replaceable.

## Thread affinity

Many native Windows objects are thread-affine.

Examples can include:

* HWND interaction;
* COM apartment-bound interfaces;
* hooks;
* message queues;
* some graphics resources.

Do not make a wrapper "thread-safe" merely by putting `lock` around calls.

Thread-safe and thread-affine are different properties.

Marshal work to the owning thread where required.

## Reentrancy

Native Windows calls may pump messages, invoke callbacks, send synchronous messages, or indirectly reenter managed code.

Do not assume:

```text
native call starts
→ no managed code runs
→ native call returns
```

Protect lifecycle invariants against legitimate reentrancy.

Avoid holding broad application locks while calling unknown/reentrant native APIs.

## Error translation

At the low-level interop boundary, preserve exact native diagnostics:

```text
HRESULT
Win32 error code
native status value
API name
relevant parameters
```

At higher layers, map them into domain-relevant outcomes.

Example:

```text
ERROR_ACCESS_DENIED
    ↓
NativeWindowOperationException
    ↓
user-visible explanation if appropriate
```

Do not throw generic:

```text
Exception("Native call failed")
```

and discard the underlying error.

## Expected native failure is not exceptional system corruption

Some native failures are normal control-flow states:

```text
resource already exists
device unavailable
operation not supported
buffer too small
timeout
access denied due to policy
optional interface unavailable
```

Model expected outcomes deliberately.

Do not retry every failure.

Never infinitely retry a deterministic HRESULT/error code.

## Logging

Interop diagnostics should include:

```text
API/function name
HRESULT or Win32 error
symbolic error name where known
process architecture
OS version/build when compatibility matters
native DLL path/version when relevant
input flags
resource state
thread/apartment when relevant
```

Do not log:

* raw pointer contents;
* arbitrary native buffers;
* passwords/tokens;
* sensitive process memory.

Do not log every high-frequency native call.
