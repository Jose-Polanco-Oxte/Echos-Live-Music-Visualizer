# Win2D Development — Overview

Use this skill for production Win2D work in modern Windows App SDK / WinUI 3 applications.

Treat Win2D as an immediate-mode GPU rendering API layered over Direct2D. Keep rendering architecture, resource ownership, device lifecycle, DPI, and threading explicit.

## Source authority

When documentation or examples disagree, use this order:

1. Current Microsoft Learn Win2D documentation for Windows App SDK.
2. The active `microsoft/Win2D` repository, especially `winappsdk/main`, its changelog, source, tests, and published headers.
3. The installed/current `Microsoft.Graphics.Win2D` NuGet package and its actual projected API surface.
4. The Win2D WinUI 3 generated API reference.
5. Current Direct2D, DirectWrite, DXGI, Windows App SDK, and WinUI documentation for underlying semantics.

Generated Win2D API pages contain historical WinUI 3 text in some areas. Do not treat an old "unsupported", UWP, `Windows.UI.Xaml`, Project Reunion, or experimental note as authoritative when the current Learn documentation, package, changelog, or source disagrees.

Do not copy old UWP snippets into WinUI 3 code without validating namespaces, package assumptions, threading, and lifecycle behavior.

## Establish the project baseline

Before changing rendering code, inspect:

- language: C#/.NET or C++;
- `TargetFramework` and target/minimum Windows versions;
- Windows App SDK version;
- `Microsoft.Graphics.Win2D` version;
- packaged vs unpackaged deployment when relevant;
- target architectures/RIDs;
- existing Win2D control or rendering surface;
- whether Direct2D, Direct3D 11, Windows Composition, ComputeSharp, or other native graphics components share resources with Win2D.

Do not silently upgrade Win2D, Windows App SDK, the target framework, or Windows SDK unless the task requires it.

For WinUI 3, use `Microsoft.Graphics.Win2D`. Do not introduce `Win2D.uwp` as the package baseline.

Do not assume `Any CPU`, architecture support, API availability, or Windows-version support. Verify them against the actual project and package.
