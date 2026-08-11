---

name: windows-native-interop
description: Design, implement, review, debug, and modernize Windows native interoperability for C#/.NET desktop applications. Use for Win32, HWND, HANDLE, COM, WinRT interop, CsWin32, P/Invoke, LibraryImport, GeneratedComInterface, callbacks, native DLLs, Windows SDK types, unmanaged memory, native resource ownership, error propagation, architecture-sensitive code, WinUI 3 interop, and low-level Windows API access.
compatibility: Primarily C#/.NET desktop applications targeting Windows 10/11, including WinUI 3, WPF, WinForms, console applications, services, and class libraries. Verify minimum Windows version, target architecture, packaging model, and NativeAOT/trimming requirements before selecting an interop mechanism.
metadata:
  domain: windows-native
  version: "1.0"
--------------

# Windows Native Interop

Use this skill when managed Windows code must cross into **Win32, COM, Windows Runtime interop, native DLLs, C ABI functions, native callbacks, Windows handles, HWND-based desktop APIs, or unmanaged memory**.

Treat declarations and lifetime rules as part of the executable ABI contract.

## Reference documents

This skill is split across modular reference files in `resources/`. Load only the document(s) relevant to the current task.

| Reference | Contents | Load when |
| --- | --- | --- |
| [`resources/overview.md`](resources/overview.md) | Goals; choosing the correct API layer; inspecting the project before changing interop. | Starting any interop work; orientation. |
| [`resources/declarations.md`](resources/declarations.md) | CsWin32 and minimal `NativeMethods.txt`; `LibraryImport`; `DllImport`; WinRT is not Win32. | Selecting how to declare a native call. |
| [`resources/hwnd-winui.md`](resources/hwnd-winui.md) | WinUI 3 HWND interop; owner-HWND WinRT UI; DPI-sensitive interop; window messages; subclassing. | HWND-based and WinUI 3 interop. |
| [`resources/types-and-handles.md`](resources/types-and-handles.md) | ABI-correct types; typed handles; `SafeHandle`; owned vs borrowed; invalid values; structures; generated types. | Handles, structures, and type mapping. |
| [`resources/strings-errors-com.md`](resources/strings-errors-com.md) | Unicode strings; A/W variants; HRESULT vs Win32 errors; COM lifetime/apartments/identity. | Strings, error handling, COM. |
| [`resources/callbacks-memory-dlls.md`](resources/callbacks-memory-dlls.md) | Native callbacks; calling conventions; unsafe code; pointer lifetimes; allocators; DLL loading/security. | Callbacks, memory, native DLLs. |
| [`resources/architecture-and-deployment.md`](resources/architecture-and-deployment.md) | x64/ARM64/x86; AnyCPU; version gating; packaging; NativeAOT/trimming; abstraction layering; reentrancy; errors. | Architecture, deployment, layering. |
| [`resources/workflow-testing-review.md`](resources/workflow-testing-review.md) | Implementation workflow; testing; leak validation; anti-patterns; review checklist; source-of-truth; core principle. | Implementing, testing, and reviewing. |

## How to use

1. Read `resources/overview.md` for API-layer selection and the 10 goals.
2. Read the specific `resources/*.md` documents for the task (declarations, handles, strings/errors/COM, callbacks/memory/DLLs, architecture/deployment, etc.).
3. Apply the guidance to the host project, preserving its existing abstractions and conventions.
