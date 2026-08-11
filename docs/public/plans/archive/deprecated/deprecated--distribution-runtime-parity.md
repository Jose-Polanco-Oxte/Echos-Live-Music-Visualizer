# Distribution Runtime Parity and Configuration Hardening Plan

- **Status:** Ended, implemented and verified 2026-08-08
- **Created:** 2026-08-08
- **Branch:** `dev`
- **Source audit:** `.agents/state/handoffs/distribution-runtime-parity.md`
- **Related build handoff:** `.agents/state/handoffs/publishing.md`

## Objective

Make the GitHub unpackaged EXE and Store MSIX distributions behave like the
same product at runtime, while eliminating fragile duplicated configuration.
The work covers branding, audio-input selection and diagnostics, system-theme
synchronization, package/application manifests, build validation, CI, and
requirements traceability.

## Confirmed Baseline

- The unpackaged self-contained EXE now starts correctly and its WinUI resource
  graph is complete.
- The locally signed x64 MSIX `0.1.0.7` and the x64 unpackaged EXE passed smoke
  tests; ARM64 artifacts passed structural validation.
- The official version in versioned sources remains `0.1.0.6`.
- The unpackaged publish output omits `Assets`, the project has no
  `ApplicationIcon`, and the current ICO contains only a 48-by-48 image.
- Direct native capture from the selected Realtek microphone succeeds in an
  isolated probe, so the current microphone defect is primarily an application
  state, diagnostics, and user-feedback problem rather than a proven native
  capture failure.
- Windows privacy settings permit microphone access for desktop applications,
  and Windows records access by both identities. An unpackaged desktop app is
  not expected to receive the same per-app consent prompt as a packaged app.
- The current machine is configured for dark applications and both builds were
  observed in dark mode. The reported always-light behavior is not yet locally
  reproduced, but the application has confirmed synchronization weaknesses:
  theme-dependent brushes use `StaticResource`, no central
  `ActualThemeChanged` propagation exists, and title-bar/Win2D colors can drift.
- Product version, branding metadata, assets, documentation, and workflow
  assumptions are duplicated without a single consistency gate.

## Scope

### In scope

- Canonical product metadata and automated consistency validation.
- Deterministic generation and validation of Win32 and MSIX branding assets.
- Equivalent product icon behavior for executable, taskbar/window, Start menu,
  installed package, and published unpackaged payload.
- Explicit render-loopback versus direct-capture device metadata across Rust,
  FFI, managed code, settings, and the UI.
- Observable microphone selection results, failure diagnostics, privacy
  guidance, stale-device recovery, and capture-activity confirmation.
- Reliable System/Light/Dark theme behavior, including runtime OS theme changes
  across XAML, title bar, and Win2D.
- Manifest, project, build-script, workflow, documentation, and traceability
  updates required by the above behavior.
- x64 runtime smoke tests and ARM64 structural checks for both distributions.

### Out of scope

- An official version bump, tag, GitHub Release, Store submission, or Partner
  Center identity replacement.
- A general UI redesign or audio engine rewrite.
- Production code that reads Windows privacy registry keys.
- Requiring a per-application microphone prompt for unpackaged Win32, because
  Windows governs it through the global desktop-app privacy control.
- Speculative capability or SDK changes that are not supported by a
  reproducible validation failure.

## Architecture Decisions

### 1. Canonical metadata with validation at format boundaries

Add `build/Product.props` as the canonical source for the official four-part
application version, product/display name, publisher, package identity, and
primary icon path. Import it from the UI project and map it to assembly, file,
informational, and package-related MSBuild properties.

Because `Package.appxmanifest`, Cargo metadata, Markdown, and release tags have
different formats and cannot all safely consume arbitrary MSBuild properties,
they remain explicit files but become validated projections:

- Manifest identity, publisher, display name, and official version must match
  `Product.props`.
- Cargo's semantic version must match the first three components of the
  canonical Windows version.
- README/version badges and the current changelog entry must match the official
  version.
- Official release tags must match the canonical version.
- A temporary `AppxPackageVersion` override remains supported for local signed
  test packages and must not modify versioned source files.

The common validation belongs in the shared distribution script so local builds
and CI cannot diverge.

### 2. One deterministic branding source and generated projections

Use the existing high-resolution Echo logo as the visual source and add a small
versioned branding recipe under `build/`. Add a PowerShell generator/checker
that creates:

- A multi-frame `AppIcon.ico` with 16, 20, 24, 32, 40, 48, 64, 128, and
  256-pixel frames.
- The base MSIX assets declared by the manifest.
- Required scale and target-size variants, including unplated variants where
  appropriate for Windows shell surfaces.

The generated files remain versioned for normal Visual Studio/MSBuild use. CI
runs the generator in check mode and fails when committed projections differ
from the canonical source/recipe.

Set `ApplicationIcon` in the project, publish the required loose assets for the
unpackaged profile, and retain the runtime `AppWindow.SetIcon` path only for the
window/taskbar surface. Runtime icon resolution must be centralized and emit a
diagnostic if the expected asset is unavailable.

### 3. Versioned audio-device ABI and transactional selection

Do not silently change the layout of the existing FFI device structure. Keep
the v1 exports and add a v2 device-list ABI containing a structure size/version
and a device-kind value (`RenderLoopback` or `DirectCapture`). Mirror that enum
in managed code and show the distinction in the selector.

Replace bool-only device selection at the service/UI boundary with a structured
result. A selection is committed to the ViewModel and persisted settings only
after the native worker is running successfully. Read and surface the native
last-error message on failure.

At startup, a stale or unavailable saved endpoint must fall back explicitly to
the default loopback device, synchronize the UI and stored setting, and report
the fallback rather than leaving a misleading selection.

After selecting an input, verify within a bounded interval that capture
timestamps advance. If the endpoint opened but no frames arrive, show a
non-blocking status such as "selected, but no audio data is arriving".

Privacy handling is identity-aware:

- Packaged MSIX retains the microphone capability and uses supported Windows
  access-status APIs where applicable before direct capture.
- Unpackaged Win32 explains that permission is controlled by the Windows
  desktop-app microphone setting and offers a link to
  `ms-settings:privacy-microphone` when access is denied.
- Neither profile claims that permission was granted merely because a device
  appears in the enumeration.

### 4. Central resolved-theme service

Introduce a `ThemeService` and replace magic integer handling with a typed
System/Light/Dark preference while preserving migration from existing integer
settings. System maps to `ElementTheme.Default` on the root element.

Subscribe to root `ActualThemeChanged` and propagate the resolved Light/Dark
theme to every non-XAML surface. Convert custom theme-dependent brush lookups
from `StaticResource` to `ThemeResource`; derive Win2D clear colors from the
same theme resource dictionary; update title-bar colors from the resolved theme.
Dispose event subscriptions with the owning window/page and preserve Windows
high-contrast behavior rather than overriding accessibility colors.

## Execution Phases

### Phase 1 — Requirements and acceptance contract

1. Update `docs/public/spec/requirements-spec.md` before functional code:
   - Add distribution-branding parity and valid icon requirements.
   - Strengthen audio selection requirements to distinguish device kinds,
     retain the previous working input on failure, avoid persisting failure,
     provide identity-appropriate privacy guidance, and confirm live capture.
   - Add runtime system-theme synchronization across XAML, title bar, and
     Win2D, including high-contrast compatibility.
2. Define a distribution acceptance matrix for EXE x64/ARM64 and MSIX
   x64/ARM64, marking runtime versus structural-only checks.
3. Reconcile the obsolete audio-permission traceability record so it no longer
   references nonexistent UI or promises obsolete permission behavior.

**Exit criteria:** normative behavior and measurable acceptance criteria are
reviewable before implementation begins.

### Phase 2 — Canonical metadata and drift gates

1. Add `build/Product.props` and import it from
   `src/ui/EchoVisualizer.csproj`.
2. Add shared validation helpers to `scripts/Build-Distributions.ps1` (or a
   narrowly scoped script invoked by it) for project, manifest, Cargo,
   documentation, and tag-version consistency.
3. Change workflows to obtain the official version through the canonical build
   metadata/validator instead of parsing different files independently.
4. Preserve validated temporary package-version overrides for local smoke
   builds without editing the official version.

**Exit criteria:** deliberate mismatch fixtures/checks fail with actionable
messages; the unchanged `0.1.0.6` repository passes.

### Phase 3 — Branding asset pipeline and distribution integration

1. Add the branding recipe and deterministic generator/check mode.
2. Generate the multi-frame ICO and MSIX base/scale/target-size assets.
3. Configure `ApplicationIcon` and unpackaged publish-copy behavior.
4. Centralize and harden runtime window-icon loading.
5. Extend distribution validation to inspect:
   - ICO frames and dimensions.
   - Embedded executable icon resources.
   - Loose unpackaged assets.
   - MSIX manifest references, package payload, declared base sizes, and shell
     variants.
6. Run the asset drift check in CI before packaging.

**Exit criteria:** Windows surfaces no longer fall back to the generic EXE icon,
and both profiles are generated from the same canonical branding input.

### Phase 4 — Audio identity, selection, and diagnostics

1. Add the compatible v2 FFI device-list API and device-kind mapping.
2. Extend the managed model and settings UI to identify outputs/loopback and
   microphones/direct capture clearly.
3. Make selection transactional and expose native error details.
4. Add stale-device fallback and keep persisted state synchronized.
5. Add a bounded live-frame/activity confirmation and an accessible status
   surface (`InfoBar` or equivalent) for success, fallback, denied access,
   native failure, and no-data conditions.
6. Add packaged/unpackaged privacy guidance as defined above.
7. Ensure diagnostics do not allocate in the render tick or interrupt the
   currently working audio worker until replacement startup succeeds.

**Exit criteria:** selecting a microphone either produces confirmed advancing
capture data or gives a specific recovery action; failure cannot silently alter
the saved selection.

### Phase 5 — Theme synchronization

1. Add the typed theme preference and backward-compatible setting migration.
2. Add the central theme service and root `ActualThemeChanged` subscription.
3. Convert theme-dependent custom brushes to `ThemeResource`.
4. Synchronize title-bar and Win2D colors from the resolved theme.
5. Verify event unsubscription, additional windows/navigation, and high
   contrast.

**Exit criteria:** System follows the current Windows app theme at launch and
while running, while explicit Light/Dark remains stable in both distributions.

### Phase 6 — Documentation, traceability, and workflow consolidation

1. Use the requirements-traceability workflow to produce
   `docs/public/traceability/traceability-report-20260808-distribution-runtime-parity.md`.
2. Update README and CONTRIBUTING instructions to use the shared build entry
   point, canonical version flow, asset check, and accurate microphone privacy
   model.
3. Update `.agents` build guidance, relevant context, and handoffs to match the
   final scripts and behavior.
4. Remove or correct stale version and nonexistent-script references found by
   repository-wide validation.

**Exit criteria:** requirements, implementation, tests, build commands, and
operator documentation point to the same mechanisms.

### Phase 7 — Automated and local distribution acceptance

Run, in order:

1. PowerShell parser validation for changed scripts and YAML parsing for all
   workflows.
2. Metadata and generated-asset drift checks.
3. `cargo fmt --check`.
4. `cargo clippy -- -D warnings`.
5. `cargo test`.
6. `dotnet test` in Release/x64.
7. Shared-script builds for GitHub x64/ARM64 and Store x64/ARM64.
8. PE architecture, dependency, PRI, manifest, capability, signature, icon,
   asset, and payload validation.
9. EXE x64 runtime acceptance:
   - Shell/window/taskbar branding.
   - Default loopback and microphone selection with advancing frames.
   - Failure/recovery messaging.
   - System/Light/Dark launch and live OS-theme switching.
10. Signed MSIX x64 install/update and the same runtime acceptance, including
    packaged microphone access behavior.
11. ARM64 structural validation only on the x64 host.

If the installed local package remains `0.1.0.7`, use temporary test version
`0.1.0.8`; leave the official version `0.1.0.6` unchanged. Close all test
processes normally and do not commit, tag, push, publish, or submit unless the
user separately authorizes it.

## Required Test Additions

- Rust: device-kind mapping, worker replacement failure, stale endpoint
  handling, and preservation of the active worker.
- FFI: v1 compatibility, v2 layout/size/version, kind conversion, allocation
  and free symmetry, and last-error propagation.
- .NET: theme preference migration/mapping, transactional selection,
  persistence only on success, stale-device fallback, activity timeout, and
  user-facing error-state mapping.
- Build validators: canonical metadata mismatches, all ICO frames, PNG
  dimensions/variants, embedded EXE icon, unpackaged assets, MSIX manifest
  references, version override isolation, and architecture.
- Manual/runtime: both audio source classes and live system-theme changes in
  x64 EXE and x64 MSIX.

## Primary Files Expected to Change

- `build/Product.props`
- `build/branding.json`
- `scripts/Build-Distributions.ps1`
- `scripts/Generate-BrandAssets.ps1`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `.github/workflows/store-build.yml`
- `src/ui/EchoVisualizer.csproj`
- `src/ui/Package.appxmanifest`
- `src/ui/Assets/*`
- `src/ui/App.xaml` and theme resource dictionaries
- `src/ui/MainWindow.xaml.cs`
- `src/ui/Views/SettingsPage.*`
- `src/ui/Views/VisualizerPage.xaml`
- UI audio service, interop, model, settings, and test files
- Rust audio-device, engine, FFI, and test modules
- `docs/public/spec/requirements-spec.md`
- `docs/public/traceability/*`
- `README.md`, `CONTRIBUTING.md`, and relevant `.agents` operational state

Exact file names inside the audio and theme layers must follow the current
repository structure discovered at implementation time; no parallel subsystem
should be introduced merely to match this plan's terminology.

## Risks and Mitigations

- **Windows shell icon caching:** validate embedded resources and package
  payload independently of visual cache; refresh/reinstall only within the
  local test package scope.
- **FFI breakage:** retain v1 exports and introduce version/size fields for v2.
- **Audio false positives:** distinguish endpoint open success from advancing
  captured frames and preserve the last working worker until replacement is
  confirmed.
- **Theme event leaks:** centralize subscriptions and bind their lifetime to the
  root window/page.
- **Generated asset noise:** keep one deterministic recipe, document the tool
  prerequisites, and enforce check mode in CI.
- **Dirty working tree:** preserve the already implemented distribution changes
  and avoid overwriting unrelated user work.
- **Version contamination:** validate that local MSIX overrides occur only in
  generated artifact directories.

## Completion Definition

The plan is complete only when all automated checks pass, both x64
distributions pass branding/audio/theme runtime acceptance, both ARM64
distributions pass structural validation, traceability is current, and no
official version/release state changed without explicit authorization.
