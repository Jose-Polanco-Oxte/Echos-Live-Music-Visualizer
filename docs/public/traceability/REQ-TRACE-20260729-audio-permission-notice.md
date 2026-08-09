# Audio Permission Notice Traceability Correction

- **Feature / Increment:** Audio permission disclosure and recovery guidance
- **Date:** 2026-08-08
- **Responsible:** Codex
- **Status:** SUPERSEDED; replacement implementation completed, runtime validation pending

## Normative Source

| Requirement ID | Exact Section | Transcribed Rule | Acceptance Criteria |
|---|---|---|---|
| RF6.1.3 | `docs/public/spec/requirements-spec.md` §RF6.1 | The startup notice covers photosensitive content only and is not a system-permission request. | Startup contains no custom acceptance gate for microphone capability. |
| RF6.1.4 | `docs/public/spec/requirements-spec.md` §RF6.1 | MSIX capabilities are declared by the package and disclosed through Windows installation mechanisms. | The package manifest declares `microphone`; the application does not duplicate the installer capability list. |
| RF6.2.5 | `docs/public/spec/requirements-spec.md` §RF6.2 | Access failures receive identity-appropriate, non-blocking recovery guidance. | MSIX uses supported access status; unpackaged desktop guidance opens the global Windows microphone setting and does not promise a per-app prompt. |

## Correction to the 2026-07-29 Record

The original record referenced a nonexistent `DisclaimerPanel`, a three-second
button gate, and a custom permission notice. Those statements do not describe
the current normative specification or application. They must not be used as
implementation evidence.

## Implementation Mapping

| Requirement | File and Symbol | Relationship |
|---|---|---|
| RF6.1.4 | `src/ui/Package.appxmanifest` :: `DeviceCapability Name="microphone"` | Declares packaged microphone capability. |
| RF6.2.5 | `MicrophonePrivacyService`, `SettingsPage.ShowAudioStatus`, `AudioCoreService.ConfirmCaptureActivityAsync` | Identity-aware privacy recovery and bounded activity confirmation are mapped in the 2026-08-08 distribution runtime parity report. |

## Verification

| Requirement | Procedure | Result |
|---|---|---|
| RF6.1.3 | Inspect startup XAML and run both x64 identities. | PENDING FINAL VALIDATION |
| RF6.1.4 | Inspect the built MSIX manifest and installation capability declaration. | PENDING FINAL VALIDATION |
| RF6.2.5 | Deny/unavailable/no-data scenarios for packaged and unpackaged selection. | IMPLEMENTED; MANUAL RUNTIME VALIDATION PENDING |

## Deviations or Decisions

Windows does not provide the same per-application consent prompt to an
unpackaged desktop process that it can expose for packaged identities. The
application therefore reports the actual failure and links to the applicable
desktop-app privacy control instead of emulating a consent prompt.
