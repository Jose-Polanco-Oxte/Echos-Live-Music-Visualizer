# Windows Native Interop — HWND and WinUI 3 Interop

## WinUI 3 HWND interop

Many native desktop APIs require an `HWND`.

In WinUI 3 C# use the supported helper:

```csharp
nint hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
```

rather than attempting to discover the HWND using window titles, enumeration, process IDs, or assumptions about XAML internals. Microsoft documents `WindowNative.GetWindowHandle` as the supported C# route for retrieving a WinUI 3 window handle.

Treat the HWND as:

```text
borrowed window identity
```

not as a resource that your helper owns.

Never call `DestroyWindow` on a framework-owned WinUI HWND unless the framework/API contract explicitly delegates that ownership.

## WinRT UI requiring an owner HWND

Desktop use of some WinRT UI requires an owning desktop window.

When the corresponding helper exists, use patterns such as:

```csharp
var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
WinRT.Interop.InitializeWithWindow.Initialize(winrtObject, hwnd);
```

instead of manually re-declaring `IInitializeWithWindow`. Microsoft provides this interop pattern for modern .NET desktop applications.

Always initialize owner-dependent UI before displaying it.

Use the actual logical owner window, not necessarily the application's first window.

This matters in multi-window applications.

## DPI-sensitive interop

Win32 coordinates may represent:

```text
physical pixels
logical units
client coordinates
screen coordinates
device-independent units
```

Do not pass XAML DIPs directly to a pixel-based native API without verifying the contract.

When crossing WinUI ↔ Win32 boundaries, explicitly identify the coordinate space.

## Window messages

For Win32 message interop, preserve pointer-width semantics:

```text
WPARAM → unsigned pointer-sized
LPARAM → signed pointer-sized
LRESULT → signed pointer-sized
```

Do not represent all message values as `int`.

For messages that pack multiple fields into `WPARAM` or `LPARAM`, use documented extraction semantics.

Be careful with signed coordinates.

Do not assume every message's `LPARAM` is a pointer.

## Subclassing

Window subclass procedures are native callbacks and have all callback-lifetime constraints.

When subclassing framework-owned windows:

* retain the callback;
* preserve the original/default processing path;
* unregister before callback state is destroyed;
* handle window destruction;
* avoid blocking;
* avoid throwing across the callback.

Prefer supported subclass APIs rather than replacing a framework window procedure directly when possible.
