# Requirements and Formula Traceability Report

- **Feature / Increment:** Distribution runtime parity and configuration hardening
- **Date:** 2026-08-08
- **Responsible:** Codex
- **Status:** IMPLEMENTED AND VERIFIED

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.5 | `docs/public/spec/requirements-spec.md` §RF6.1 | MSIX and unpackaged self-contained distributions must start with complete WinUI resources. | Both x64 identities remain running through a ten-second smoke window; ARM64 payloads pass structural validation. |
| RF6.1.6 | `docs/public/spec/requirements-spec.md` §RF6.1 | Both distributions project one visual identity and include valid Win32/package icon assets. | EXE has a multi-resolution embedded icon and loose runtime asset; MSIX contains all manifest assets and required variants without generic shell fallback. |
| RF6.2.2 | `docs/public/spec/requirements-spec.md` §RF6.2 | The selector distinguishes direct-capture inputs from render-loopback outputs. | Native, FFI, managed model, and UI retain a stable device-kind value. |
| RF6.2.3 | `docs/public/spec/requirements-spec.md` §RF6.2 | Runtime source replacement is transactional and only successful selection is persisted. | Failed replacement retains the current worker and setting; stale startup selection falls back to default loopback. |
| RF6.2.5 | `docs/public/spec/requirements-spec.md` §RF6.2 | Capture timestamps must advance within at most 3 seconds, with identity-appropriate privacy recovery. | Success, native error, access denial, stale fallback, and no-data outcomes are visible and actionable. |
| RF6.6.3 | `docs/public/spec/requirements-spec.md` §RF6.6 | System theme follows Windows at startup and runtime across XAML, title bar, and Win2D while respecting high contrast. | Both x64 identities react consistently to live application-theme changes; explicit Light/Dark remain stable. |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship with Formula |
|---|---|---|---|
| RF6.1.5 | `scripts/Build-Distributions.ps1` | Profile, RID, PRI and payload checks | Existing common build entry point verifies both distribution models. |
| RF6.1.6 | `build/branding.json`, `scripts/Generate-BrandAssets.ps1`, `src/ui/EchoVisualizer.csproj`, `BrandingService.ApplyWindowIcon`, distribution validators | 61 generated assets; ICO frames 16/20/24/32/40/48/64/128/256 px | One recipe generates the Win32 ICO and package variants; the project embeds/copies them and the validator checks canonical, published, packaged, and PE resource projections. |
| RF6.2.2 | `capture::AudioDeviceKind`, `ffi::AudioDevicePropertiesV2`, `get_audio_devices_v2`, `AudioCoreService.GetAudioDevicesV2` | ABI version 2; struct size 32 bytes on 64-bit; kind 1/2 | v1 remains available while v2 carries a self-describing render-loopback/direct-capture kind through the managed selector. |
| RF6.2.3 | `LoopbackCapture::start`, `replace_worker_transactionally`, `AudioEngine::set_audio_device`, `AudioCoreService.SelectAudioDevice`, `AppVisualizerState.RestoreAudioSelection` | Endpoint ID and structured selection outcome | Capture startup is acknowledged before the worker is replaced; failure retains the active worker, and stale settings fall back to default loopback before persistence. |
| RF6.2.5 | `AudioCoreService.ConfirmCaptureActivityAsync`, `MicrophonePrivacyService`, `SettingsPage.ShowAudioStatus` | Maximum confirmation interval: 3 seconds | Advancing capture timestamps confirm activity; packaged/unpackaged access and no-data failures map to an accessible InfoBar and recovery action. |
| RF6.6.3 | `ThemePreference`, `ThemeService`, `ColorPalette.xaml`, `VisualizerPage.ThemeService_ResolvedThemeChanged`, `UserSettingsService.LoadFromPath` / `SaveToPath` | System/Light/Dark preference and resolved theme | Root `ActualThemeChanged` and system color events re-resolve XAML resources, title-bar colors, and Win2D clear color; high contrast uses Windows system colors. Tests use an isolated settings path and cannot overwrite the real persisted preference. |

## Distribution Acceptance Matrix

| Distribution | Architecture | Build / Structural Checks | Runtime Checks |
|---|---|---|---|
| Unpackaged self-contained | x64 | Metadata, PE, runtime payload, PRI, loose assets, ICO frames and embedded icon | Ten-second startup, window/taskbar branding, loopback, microphone, failure feedback, and live theme switching |
| Unpackaged self-contained | ARM64 | Metadata, PE, runtime payload, PRI, loose assets, ICO frames and embedded icon | Not executed on the x64 validation host |
| Signed MSIX | x64 | Signature, identity, version, architecture, entry point, capabilities, dependencies, assets and payload | Install/update, ten-second startup, installed branding, loopback, microphone/access feedback, and live theme switching |
| Signed MSIX | ARM64 | Signature, identity, version, architecture, entry point, capabilities, dependencies, assets and payload | Not installed or executed on the x64 validation host |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| RF6.1.5 | Shared-script builds and x64 smoke tests | ARM64 is structural-only on x64 | PASS: final EXE/MSIX x64 processes remained active for ten seconds and closed normally; both ARM64 outputs passed structural validation. |
| RF6.1.6 | Product/asset drift checks plus EXE/MSIX resource inspection | All planned ICO frames and shell variants | PASS: 61 canonical assets, nine ICO frames, PE group icon, loose assets, bundle resource packages, signatures, and visible x64 window branding validated. |
| RF6.2.2 | Rust, FFI, and managed mapping tests | Render and capture endpoints | PASS: ABI layout/kind and live enumeration tests included in 74 Rust and 40 .NET tests |
| RF6.2.3 | Worker replacement and persistence tests | Invalid/stale endpoint and native startup failure | PASS: transactional replacement, invalid-device recovery, and stale/default fallback checks passed. |
| RF6.2.5 | Activity timeout, live direct-capture probe, and identity-specific recovery mapping | Access denied and opened-without-frames | PASS: the default Realtek direct-capture endpoint selected successfully and produced advancing timestamps within three seconds; packaged/unpackaged recovery branches compile and are covered by focused tests. |
| RF6.6.3 | Preference migration/isolation tests and live Windows theme switch in both x64 identities | System, explicit themes, optional WinRT accessibility event, and high contrast | PASS: both running identities changed from dark to light without restart and Windows was restored to dark; unpackaged absence of `HighContrastChanged` registration no longer prevents startup. |

## Deviations or Decisions

- The official version remains `0.1.0.6`. A higher package identity may be
  supplied only as a temporary generated build override for local installation.
- The existing audio-device ABI remains available; device kind is introduced
  through a versioned extension instead of changing the old structure layout.
- Unpackaged desktop microphone access uses the global Windows desktop-app
  privacy control and must not be represented as an MSIX-style per-app prompt.
- Runtime validation is limited to x64 on the current host; ARM64 acceptance is
  structural until executed on compatible hardware.
- On the validation Windows build, registering
  `AccessibilitySettings.HighContrastChanged` from the unpackaged identity can
  return `ERROR_NOT_FOUND`. The optional event is tolerated and
  `UISettings.ColorValuesChanged` remains the cross-identity notification that
  re-reads the current high-contrast state.
- The test suite previously wrote its fixture into the real LocalAppData
  settings file, forcing `ThemeIndex=Light`. Tests now use a unique temporary
  path; a before/after SHA-256 check confirmed that the real settings file is
  unchanged by the full .NET suite.
