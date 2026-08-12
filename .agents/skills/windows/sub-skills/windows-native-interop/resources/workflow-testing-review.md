# Windows Native Interop — Implementation Workflow, Testing, and Review

## Implementation workflow

When adding native Windows integration:

### 1. Classify

Determine:

```text
managed API?
WinRT?
Win32?
COM?
custom C DLL?
callback?
raw memory?
HWND interop?
```

### 2. Select the projection

Prefer:

```text
managed API
→ WinRT projection
→ WinRT.Interop helper
→ CsWin32
→ LibraryImport
→ GeneratedComInterface / ComWrappers
→ manual declaration as last resort
```

### 3. Verify the native contract

Confirm from authoritative documentation/metadata:

```text
native signature
types
calling convention
string representation
error model
ownership
threading
minimum Windows version
release function
callback lifetime
```

### 4. Define ownership

For every returned:

```text
handle
pointer
buffer
COM interface
callback registration
```

write down internally who releases it and how.

### 5. Isolate

Place low-level code behind the narrowest reasonable wrapper.

### 6. Implement

Prefer generated declarations and strong native types.

Avoid conversions until crossing into application code.

### 7. Handle errors

Preserve native error semantics.

Translate only at the abstraction boundary.

### 8. Validate lifetime

Exercise:

```text
success
failure
early return
exception
cancellation
repeated operation
shutdown
```

All owned native resources must still be released exactly once.

### 9. Validate architecture

Build/test all supported native architectures.

### 10. Validate deployment

For custom DLLs verify:

```text
binary present
correct architecture
dependencies present
secure loading path
packaged/unpackaged behavior
```

## Testing

Separate pure conversion logic from real OS calls.

Unit test:

```text
flag composition
structure conversion
coordinate conversion
size calculations
error mapping
fallback rules
state machines
ownership wrappers where possible
```

Integration test:

```text
actual native invocation
handle acquisition/release
HWND interop
COM activation
DLL loading
callback registration/unregistration
Windows-version-gated paths
architecture-specific behavior
```

Tests must not depend unnecessarily on one machine's:

* window placement;
* monitor count;
* username;
* installation directory;
* localized error text.

Compare error codes, not localized message strings.

## Resource-leak validation

For repeated native operations, test lifecycle loops:

```text
create
use
release
repeat
```

Watch for growth in:

* handles;
* GDI objects;
* USER objects;
* COM references;
* unmanaged allocations.

A native wrapper that succeeds once but leaks on every call is incorrect.

## Review generated code when behavior is surprising

Source generation reduces signature errors but does not eliminate the need to understand the contract.

Inspect generated CsWin32/LibraryImport code when:

* overload selection is unclear;
* ownership is unclear;
* a COM signature behaves unexpectedly;
* marshalling introduces allocation;
* NativeAOT fails;
* unsafe pointers appear unexpectedly;
* generated types conflict with existing definitions.

Do not replace generated code immediately because its shape differs from an old handwritten declaration.

First verify which declaration is actually ABI-correct.

## Anti-patterns

Reject or refactor these patterns unless a verified requirement justifies them:

```text
handwritten DllImport for ordinary Win32 when CsWin32 can generate it

copying declarations from PInvoke.net without checking current metadata

using int for HWND/HANDLE/WPARAM/LPARAM on 64-bit systems

treating every native handle as IntPtr with no ownership semantics

calling CloseHandle on arbitrary Windows handle types

closing borrowed or pseudo-handles

assuming every failed handle equals NULL

using GetLastError after APIs that don't define errors that way

reading last-error long after the failing P/Invoke call

using ANSI Win32 APIs in new Windows-only code without a reason

using CharSet.Auto in new native Windows declarations

using [Out] string as a mutable native buffer

hardcoding struct size/alignment from an x86 example

adding Pack=1 to silence layout bugs

passing a native pointer to another thread beyond its documented lifetime

letting a managed exception escape through a native callback

allowing callback delegates/context to be collected before unregistering

assuming COM objects are free-threaded

manually releasing a COM object already owned by another wrapper

mixing Marshal COM APIs, raw pointers, CsWin32 COM, and ComWrappers casually

calling Win32 to access an API already correctly projected through WinRT

redeclaring IInitializeWithWindow instead of using the modern WinRT.Interop helper

discovering a WinUI HWND by title/process enumeration

loading application DLLs from the current working directory

using SetDllDirectory globally as a convenient dependency fix

assuming AnyCPU solves native binary architecture

checking OS architecture instead of process architecture

spreading PInvoke calls throughout ViewModels

catching native failures and replacing them with generic Exception

retrying all native failures indefinitely
```

## Review checklist

Before native interop work is considered complete:

```text
[ ] The chosen API layer is the highest appropriate abstraction.
[ ] Win32 APIs use CsWin32 where practical.
[ ] WinRT APIs use WinRT projection instead of P/Invoke.
[ ] WinUI HWND comes from supported framework interop.
[ ] Handwritten declarations have verified native signatures.
[ ] Pointer-sized native values use pointer-sized managed types.
[ ] BOOL/native bool semantics are correct.
[ ] Strings use the correct encoding/ownership.
[ ] Structure layout and indirection are verified.
[ ] No unexplained Pack override exists.
[ ] Native calling convention is correct.
[ ] Every native resource has explicit ownership.
[ ] The correct resource-specific release API is used.
[ ] Borrowed/pseudo-handles are not released.
[ ] SafeHandle is used for owned handles where appropriate.
[ ] HRESULT and Win32 error semantics are not confused.
[ ] Last-error is captured immediately when required.
[ ] COM lifetime/apartment requirements are respected.
[ ] Callback lifetime exceeds every possible native invocation.
[ ] Callback exceptions cannot escape into native code.
[ ] Pointer lifetime does not exceed the native contract.
[ ] Allocation/free APIs match.
[ ] Native DLL resolution is controlled and secure.
[ ] Architecture-specific behavior is validated.
[ ] Minimum Windows version is respected.
[ ] NativeAOT/trimming requirements are accounted for.
[ ] Interop calls are isolated from UI/domain logic.
[ ] Failure and cleanup paths are tested.
[ ] Repeated operations do not leak native resources.
```

## Source-of-truth policy

When native declarations, old examples, generated code, and online snippets disagree, use this authority order:

```text
current Windows SDK metadata / headers
        ↓
current Microsoft Learn Win32 / Windows App SDK documentation
        ↓
official Microsoft source generators and samples
        ↓
.NET native interop documentation
        ↓
maintained first-party repositories
        ↓
third-party wrappers
        ↓
community snippets / old Stack Overflow answers
```

For C# Win32 declarations specifically, prefer **CsWin32 and the Windows SDK metadata it consumes** over manually reproducing the C declaration.

For handwritten .NET interop, follow current .NET native-interoperability guidance for `LibraryImport`, `SafeHandle`, callbacks, marshalling, and native type matching.

For WinUI/WinRT desktop interop, prefer current Windows App SDK and C#/WinRT guidance rather than UWP-era recipes.

## Core principle

Optimize Windows native interop in this order:

```text
correct API layer
→ correct ABI
→ correct ownership
→ correct threading
→ correct error semantics
→ compatibility
→ safety
→ maintainability
→ performance
```

Never trade ABI correctness or ownership correctness for a shorter interop declaration.
