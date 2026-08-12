# Windows Native Interop — Types, Handles, and Structures

## Native types must preserve ABI meaning

Translate native declarations by **size, signedness, pointer semantics, and ownership**, not by visual similarity.

Examples:

```text
BYTE        → byte
WORD        → ushort
DWORD       → uint
LONG        → int
ULONG       → uint
LONGLONG    → long
ULONGLONG   → ulong
SIZE_T      → nuint
SSIZE_T     → nint
INT_PTR     → nint
UINT_PTR    → nuint
LONG_PTR    → nint
ULONG_PTR   → nuint
LPARAM      → nint
WPARAM      → nuint
LRESULT     → nint
HRESULT     → 32-bit signed value / generated HRESULT type
```

Windows defines pointer-precision integer types specifically so their size tracks the target architecture.

Never model pointer-sized Windows values as `int` simply because the code works on one machine.

## Handles are typed resources, not generic integers

Distinguish:

```text
HWND
HANDLE
HDC
HBITMAP
HICON
HKEY
HMODULE
HGLOBAL
SC_HANDLE
SOCKET
```

even when their underlying machine representation is pointer-sized.

Different handle types have different ownership and release functions.

Never assume:

```text
all handles → CloseHandle
```

Examples of distinct lifetime APIs include:

```text
HANDLE        → often CloseHandle
HKEY          → RegCloseKey
HDC           → DeleteDC or ReleaseDC depending acquisition
HGDIOBJ       → DeleteObject
find handle   → FindClose
service handle → CloseServiceHandle
local allocation → LocalFree
COM task allocation → CoTaskMemFree
```

Always determine the release function from the API that created/acquired the resource.

## Prefer SafeHandle for owned native handles

Use `SafeHandle` or a correct existing derived type for owned unmanaged resources whenever practical.

Current .NET interop guidance explicitly recommends `SafeHandle` and discourages finalizers as the primary ownership mechanism for unmanaged handles.

A safe-handle implementation must correctly define:

```text
invalid value(s)
release function
ownership
thread-safety assumptions
```

Do not create one universal `SafeWin32Handle` if different resource families require different cleanup functions.

Prefer existing framework/CsWin32 safe-handle types where they match the API contract.

## Owned vs borrowed resources

Every native handle or pointer must have an explicit ownership classification.

Use concepts such as:

```text
Owned
Borrowed
TransferredToCallee
TransferredToCaller
SharedReferenceCounted
PinnedForCall
PinnedUntilCallbackRemoved
ValidUntilReleaseBuffer
ValidUntilNextCall
ProcessLifetime
```

Do not infer ownership from whether a value is an `IntPtr`.

Document non-obvious lifetime behavior near the abstraction boundary.

## Invalid handle values differ by API

Do not assume all failure handles equal zero.

Windows APIs may use:

```text
NULL
INVALID_HANDLE_VALUE
another sentinel
HRESULT
BOOL + GetLastError
```

Read the function's documented return contract.

A generic check such as:

```csharp
if (handle == IntPtr.Zero)
```

is incorrect for APIs whose failure value is `INVALID_HANDLE_VALUE`.

## Do not close pseudo-handles

Some Windows APIs return borrowed or pseudo-handles that must not be closed.

Always inspect the API's ownership contract before wrapping a handle as owning.

Do not put a borrowed handle into a `SafeHandle` configured to release it.

## BOOL is not C++ bool

Windows `BOOL` is a 32-bit integer type.

Native C/C++ `bool` / `_Bool` can have a different representation.

Current .NET guidance explicitly warns that boolean representation is a common interop bug.

Do not write:

```csharp
bool
```

from intuition alone.

Match the native declaration or rely on generated metadata.

## Structures must match native layout

For any handwritten structure, verify:

```text
field order
field type
field size
signedness
alignment
packing
union layout
fixed buffers
pointer-sized fields
nested structs
architecture-specific fields
```

Do not add `Pack = 1` to "fix" a size mismatch unless the native declaration actually uses that packing.

Use:

```csharp
[StructLayout(LayoutKind.Sequential)]
```

when the native structure is sequential.

Use:

```csharp
[StructLayout(LayoutKind.Explicit)]
[FieldOffset(...)]
```

for actual unions/explicit layouts.

The structure's pass mode also matters: native `T`, `T*`, and `T**` are different contracts. Microsoft documents that managed value/reference choices must preserve those levels of indirection.

## cbSize / dwSize fields

Many Win32 structures require a size field before the call.

When the native API specifies this pattern, initialize it from the actual structure size:

```text
cbSize
dwSize
Size
```

Do not copy a hardcoded number from documentation or an x86 example.

Use the layout that corresponds to the exact target structure/version.

## Versioned native structures

Never assume the newest structure version is valid on every supported Windows release.

When APIs offer:

```text
FOO
FOO_V2
FOOEX
FOO2
```

or size-gated members, verify:

* minimum OS version;
* expected `cbSize`;
* fallback behavior.

Prefer the smallest version that satisfies the feature requirements when compatibility matters.

## Preserve generated native types at the boundary

When CsWin32 generates:

```text
HWND
RECT
BOOL
HRESULT
HANDLE
WINDOW_STYLE
```

prefer using those generated strongly typed representations in the lowest interop layer.

Convert to application-specific types only above the boundary.

Do not immediately flatten every generated value to `IntPtr`, `int`, and `uint`.

Strong types prevent accidental mixing of unrelated native concepts.

## Avoid magic constants

Use generated constants and enums.

Prefer:

```csharp
WINDOW_STYLE.WS_VISIBLE
```

over:

```csharp
0x10000000
```

Prefer named HRESULT/Win32 constants where available.

If a required constant is missing from metadata, verify it from current Windows SDK documentation before introducing it manually.
