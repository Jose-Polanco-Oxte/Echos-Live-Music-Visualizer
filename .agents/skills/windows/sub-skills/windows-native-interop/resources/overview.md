# Windows Native Interop — Overview and API Selection

Use this skill when managed Windows code must cross into:

* Win32;
* COM;
* Windows Runtime interop;
* native DLLs;
* C ABI functions;
* native callbacks;
* Windows handles;
* HWND-based desktop APIs;
* unmanaged memory or structures.

The goal is not merely to make a native call compile.

The goals are:

1. Correct ABI representation.
2. Correct ownership and lifetime.
3. Correct Windows API selection.
4. Safe and deterministic resource release.
5. Correct behavior on x64, ARM64, and any supported x86 target.
6. Correct error propagation.
7. Minimal handwritten interop.
8. Compatibility with trimming and NativeAOT when required.
9. Separation of native mechanics from application/domain logic.
10. Preservation of Windows security and deployment semantics.

Interop errors can compile cleanly and still cause:

* memory corruption;
* invalid frees;
* use-after-free;
* leaks;
* stack corruption;
* deadlocks;
* silent truncation;
* architecture-specific failures;
* UI ownership bugs;
* native crashes.

Treat declarations and lifetime rules as part of the executable ABI contract.

## Start by choosing the correct API layer

Do not reach for P/Invoke immediately.

Use this decision order:

```text
Existing managed .NET API?
        ↓ no
Windows Runtime API?
        ↓ no
Existing framework interop helper?
        ↓ no
Win32 API represented by Windows SDK metadata?
        ↓ no
Custom/native DLL or unsupported native export?
        ↓
manual/source-generated native declaration
```

For C# Windows applications:

```text
.NET/BCL API
    → prefer the managed API

Windows.* / WinRT
    → use the WinRT projection / C#/WinRT

WinUI/WinRT desktop bridge operation
    → use WinRT.Interop helpers when available

Win32
    → prefer CsWin32

custom C-compatible DLL
    → prefer LibraryImport on modern .NET

special COM ABI
    → CsWin32-generated COM or GeneratedComInterface /
      ComWrappers depending requirements

manual DllImport
    → existing/legacy code or when source-generated
      alternatives cannot represent the scenario
```

Microsoft currently recommends **CsWin32 as the default way to call Win32 from C#**. It generates type-safe declarations, structures, constants, and COM interfaces from Windows SDK metadata. For APIs in `Windows.*` namespaces, Microsoft recommends using their WinRT projection rather than P/Invoke.

Do not recreate an API with handwritten declarations when an authoritative generated projection already exists.

## Inspect the project before changing interop

Determine:

```text
TargetFramework
TargetPlatformVersion
SupportedOSPlatformVersion
RuntimeIdentifier(s)
PlatformTarget / architecture
Windows App SDK version
packaged vs unpackaged
self-contained vs framework-dependent
NativeAOT enabled?
trimming enabled?
runtime marshalling disabled?
existing CsWin32 usage?
existing WinRT.Interop usage?
existing SafeHandle types?
existing COM strategy?
existing native libraries?
```

Then inspect:

* `NativeMethods.txt`;
* `NativeMethods.json`;
* existing `[LibraryImport]`;
* existing `[DllImport]`;
* `[GeneratedComInterface]`;
* `[ComImport]`;
* `SafeHandle` subclasses;
* unsafe blocks;
* native DLL loading;
* HWND acquisition;
* native callbacks;
* native memory allocators;
* native error handling.

Do not introduce a second interop strategy for the same subsystem without a concrete reason.
