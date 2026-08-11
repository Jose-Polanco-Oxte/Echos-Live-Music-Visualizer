# Windows Native Interop — Declarations (CsWin32, LibraryImport, DllImport, WinRT)

## Prefer CsWin32 for Win32 from C#

For Windows SDK Win32 APIs, first attempt to use:

```text
Microsoft.Windows.CsWin32
```

and request only the APIs/types required by the project in:

```text
NativeMethods.txt
```

Example:

```text
CreateEvent
WaitForSingleObject
CloseHandle
```

Generated APIs normally live under:

```text
Windows.Win32
Windows.Win32.PInvoke
```

CsWin32 generates declarations from first-party Win32 metadata and can generate friendly overloads and SafeHandle-aware APIs.

Prefer:

```text
generated Windows SDK metadata
```

over:

```text
PInvoke.net snippets
Stack Overflow declarations
copied signatures from old projects
AI-generated DllImport declarations
manual translations from header files
```

unless generation cannot represent the API correctly.

### Keep NativeMethods.txt minimal

Request the APIs and types actually required.

Do not add entire API families preemptively.

Prefer:

```text
GetWindowLongPtr
SetWindowLongPtr
MONITORINFO
```

over broad uncontrolled generation.

Benefits include:

* easier review;
* less generated surface area;
* clearer dependencies;
* easier migration;
* fewer namespace/type collisions.

When adding a Win32 call, update `NativeMethods.txt` as part of the same change.

## LibraryImport for custom native functions

For modern .NET and native functions not appropriately covered by CsWin32, prefer:

```csharp
[LibraryImport(...)]
static partial ...
```

when supported.

Microsoft's current .NET interop guidance recommends `LibraryImport` when possible on .NET 7+, while `DllImport` remains valid for scenarios that source-generated marshalling cannot support.

Do not replace correct CsWin32-generated Windows APIs with handwritten `LibraryImport` merely because `LibraryImport` is newer.

Use:

```text
CsWin32     → Windows SDK Win32
LibraryImport → custom/native C ABI
```

as the normal distinction.

## DllImport is not the first choice for new Win32 code

Keep existing correct `DllImport` declarations unless migration provides a real benefit.

For new code, handwritten `DllImport` should normally be limited to:

* legacy framework constraints;
* unsupported source-generation scenarios;
* compatibility code;
* a native ABI that cannot be represented cleanly by the preferred generator.

Do not perform mass mechanical conversion without validating:

* string semantics;
* `SetLastError`;
* calling convention;
* structs;
* callbacks;
* COM behavior;
* ownership.

## WinRT is not Win32

Do not P/Invoke a Windows Runtime API simply because it is implemented by Windows.

If the API is surfaced through namespaces such as:

```text
Windows.Storage
Windows.Media
Windows.Graphics
Windows.Devices
Windows.System
```

first use the projected WinRT API.

Modern .NET moved built-in WinRT projection support out of the runtime and into C#/WinRT. Old patterns based on directly casting projected WinRT objects to `IInspectable`-based `[ComImport]` interfaces are not generally valid in modern .NET; use the current WinRT interop classes instead.

Do not transplant UWP-era interop recipes blindly into WinUI 3/.NET applications.
