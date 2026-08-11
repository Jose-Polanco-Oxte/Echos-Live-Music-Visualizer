# Windows Native Interop — Strings, Errors, and COM

## Strings: prefer Unicode Windows APIs

For handwritten Windows interop, prefer explicit UTF-16 / `W` APIs where applicable.

Avoid:

```text
CharSet.Auto
implicit A/W selection
locale-dependent ANSI conversion
```

in new Windows-only code.

When using `LibraryImport`, state string marshalling explicitly where required.

Do not use `[Out] string` for mutable native output buffers. Current .NET guidance warns against this pattern; use an explicit writable buffer such as `char[]`, `Span<char>`, or an appropriate native buffer strategy.

Do not assume every native `char*` is UTF-8.

Determine whether the native ABI uses:

```text
UTF-16
UTF-8
ANSI/code page
BSTR
HSTRING
opaque bytes
```

## A/W function variants

When manually declaring classic Win32 functions, prefer the explicit Unicode entry point:

```text
FunctionNameW
```

when the API provides `A` and `W` forms and the project targets modern Windows.

Do not manually append `W` to generated CsWin32 method names unless required by the generated projection.

Let the authoritative metadata/projection determine the managed surface.

## HRESULT and Win32 errors are different systems

Identify the native error model before writing managed error handling.

Common patterns:

```text
HRESULT
BOOL + GetLastError
NULL + GetLastError
INVALID_HANDLE_VALUE + GetLastError
LSTATUS
DWORD status value
NTSTATUS
socket-specific error
success count / sentinel
```

Do not automatically call `GetLastError` after every native failure.

Only consume last-error state when the API contract says to.

## SetLastError

For handwritten P/Invoke declarations that rely on Win32 last-error state, configure error capture correctly.

Retrieve the error immediately after the native call and before unrelated native calls overwrite thread-local error state.

For modern .NET APIs, prefer:

```csharp
Marshal.GetLastPInvokeError()
```

for P/Invoke captured errors. Microsoft documents it as the preferred name over `GetLastWin32Error`.

Do not infer failure from a nonzero last-error value when the native function itself reported success.

Some successful Windows calls leave the previous last-error value untouched.

## Preserve HRESULT semantics intentionally

Decide whether COM errors should:

```text
remain HRESULT values
```

or:

```text
be projected as managed exceptions
```

Do not accidentally change this behavior while rewriting COM declarations.

Source-generated COM normally maps failing HRESULTs to exceptions unless signature preservation is explicitly requested.

For low-level systems code, retaining explicit HRESULT handling is often useful when:

* specific success codes matter;
* retry/fallback depends on exact HRESULT;
* failure is expected runtime state;
* allocation-free paths matter.

At higher abstraction layers, convert errors into meaningful domain exceptions/results.

## COM: understand the lifetime model

COM interface pointers are reference counted.

Respect:

```text
QueryInterface
AddRef
Release
IUnknown identity
apartment/thread rules
aggregation rules where applicable
```

Never treat a raw COM interface pointer as an unmanaged handle released by `CloseHandle`.

Do not manually `Release` an object that is already owned by a managed COM wrapper unless the interop model explicitly requires it.

Avoid mixing:

```text
runtime COM wrappers
ComWrappers
raw COM pointers
CsWin32 COM interfaces
third-party COM projections
```

within one subsystem without a documented ownership strategy.

## Modern source-generated COM

For custom COM interoperability in modern .NET, consider:

```csharp
[GeneratedComInterface]
[GeneratedComClass]
```

and the source-generated `ComWrappers` infrastructure when the scenario fits.

.NET 8 introduced source generation for `ComWrappers`; unlike runtime-generated COM stubs, it is designed to work with trimming and NativeAOT scenarios.

Do not rewrite working CsWin32-generated COM interfaces manually just to use `GeneratedComInterface`.

Choose one coherent COM projection strategy.

## COM apartments

Before using COM APIs, identify their apartment requirements.

Possible contexts include:

```text
STA
MTA
neutral/agile
apartment-bound object
free-threaded object
```

Do not scatter:

```text
CoInitializeEx
CoUninitialize
```

through random utility methods.

COM initialization belongs to the thread/lifecycle owner.

Do not initialize a thread as MTA when its framework already established STA semantics.

Do not assume a COM interface may be freely invoked from any thread.

## COM interface identity

Never guess interface GUIDs.

Use:

* generated metadata;
* Windows SDK headers/metadata;
* official documentation.

Do not redefine an interface with a copied IID unless generation/projection is impossible.

The vtable method order is ABI.

A missing, extra, or reordered COM method corrupts every subsequent call.

## QueryInterface rather than casting pointers

A COM interface pointer for `IFoo` is not automatically a valid pointer for `IBar`.

Use the projection's `QueryInterface`/cast mechanism that implements COM identity rules.

Do not reinterpret-cast raw interface pointers simply because both interfaces belong to the same object.
