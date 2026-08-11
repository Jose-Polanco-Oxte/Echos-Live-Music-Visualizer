# WASAPI — Loopback Capture

## Endpoint loopback capture

Use endpoint loopback when the requirement is:

> capture the system mix currently rendered through an audio output endpoint.

The correct endpoint is a **render endpoint**, but the service obtained from the initialized loopback stream is `IAudioCaptureClient`.

Endpoint loopback requires:

```text
AUDCLNT_SHAREMODE_SHARED
AUDCLNT_STREAMFLAGS_LOOPBACK
```

Loopback is not supported for exclusive-mode streams.

Do not search for or depend on vendor-specific devices such as "Stereo Mix" when WASAPI loopback satisfies the requirement. Such hardware loopback devices are optional and inconsistently named.

For supported Windows 10/11 targets, event-driven loopback is valid. Native event-driven loopback support exists starting with Windows 10 version 1703; older Windows versions required a workaround.

Do not carry the pre-1703 workaround into a modern Windows-only application unless its compatibility baseline actually requires it.

## Process loopback capture

Use process loopback when the requirement is:

* capture audio rendered by a specific process and its descendants; or
* capture system audio while excluding a specific process tree.

Use the process-loopback activation model built around:

```text
ActivateAudioInterfaceAsync
AUDIOCLIENT_ACTIVATION_PARAMS
PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE
PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE
```

This facility requires **Windows 10 build 20348 or later**.

Unlike endpoint loopback, process loopback is not tied to one physical audio endpoint.

If the target process tree is not currently producing audio, expect valid silence rather than treating the absence of samples as device failure.

Always check the application's minimum supported Windows build before choosing process loopback.

Do not emulate process exclusion by capturing the whole endpoint and attempting to subtract waveforms.

## RAW mode

`AUDCLNT_STREAMOPTIONS_RAW` requests an audio path without the normal signal processing where the endpoint supports raw processing.

Use RAW only if:

* the scenario explicitly benefits from bypassing processing;
* the device reports support;
* the application's semantics expect unprocessed audio.

Do not assume RAW means:

* exclusive mode;
* bit-perfect output;
* lower latency in all cases;
* identical signal characteristics across hardware.

Query capability and handle unsupported devices.

For normal consumer/media behavior, preserve the standard processing path unless requirements say otherwise. Microsoft documents RAW as an optional client property in low-latency WASAPI scenarios where the device supports it.

## MATCH_FORMAT

Use `AUDCLNT_STREAMOPTIONS_MATCH_FORMAT` only when avoiding engine resampling is an actual requirement and the selected format is supported.

Do not enable it as a generic performance optimization.

Expect initialization to fail or encounter format-locking behavior when current engine conditions cannot satisfy the requested format.
