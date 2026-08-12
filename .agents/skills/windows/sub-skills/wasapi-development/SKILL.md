---

name: wasapi-development
description: Design, implement, review, debug, and optimize Windows Audio Session API (WASAPI) and Core Audio code on Windows 10/11. Use for audio rendering, microphone capture, system loopback, process loopback, low-latency audio, shared/exclusive streams, IAudioClient/IAudioClient2/IAudioClient3, IAudioRenderClient, IAudioCaptureClient, MMDevice endpoint selection, audio sessions, device switching, stream recovery, format negotiation, buffer processing, MMCSS, and native interop from C++, C#, .NET, WinUI 3, WPF, or other Windows desktop applications.
compatibility: Windows desktop development targeting Windows 10 or Windows 11. Some capabilities require specific Windows builds; verify the project's minimum supported OS before selecting APIs.
metadata: 
  domain: windows-audio
  version: "1.0"
--------------

# WASAPI Development

Use this skill when working directly with **WASAPI, Core Audio, MMDevice, audio sessions, endpoint volume, or low-level Windows audio streams**.

Treat audio streaming code as **real-time, stateful, resource-sensitive systems code**, not ordinary application code.

## Reference documents

This skill is split across modular reference files in `references/`. Load only the document(s) relevant to the current task.

| Reference | Contents | Load when |
| --- | --- | --- |
| [`references/overview.md`](references/overview.md) | Goals, when to use WASAPI, inspect the existing system, core optimization principle. | Starting any WASAPI work; orientation. |
| [`references/scenario-and-architecture.md`](references/scenario-and-architecture.md) | Classify direction/endpoint/mode/latency/processing; Core Audio object chain; recommended class responsibilities. | Selecting the stream scenario; designing structure. |
| [`references/modes-latency-scheduling.md`](references/modes-latency-scheduling.md) | Shared vs exclusive mode; `IAudioClient3`; latency as negotiated; event-driven streaming; real-time bounds; MMCSS. | Choosing mode/latency; scheduling the audio worker. |
| [`references/audio-formats.md`](references/audio-formats.md) | Format negotiation, `GetMixFormat` / `IsFormatSupported`, format ownership, sample conversion, multichannel. | Negotiating or converting audio formats. |
| [`references/render-and-capture.md`](references/render-and-capture.md) | `IAudioRenderClient` / `IAudioCaptureClient` buffer protocol; priming; capture flags; timing/positions. | Implementing render or capture loops. |
| [`references/loopback.md`](references/loopback.md) | Endpoint loopback, process loopback, RAW mode, MATCH_FORMAT. | Capturing system/process audio or bypassing processing. |
| [`references/devices-routing-changes.md`](references/devices-routing-changes.md) | MMDevice endpoint selection, default routing, `IMMNotificationClient`, invalidation/recovery. | Choosing devices; handling device changes. |
| [`references/sessions-and-volume.md`](references/sessions-and-volume.md) | Audio categories, sessions, endpoint vs session volume. | Session/volume control. |
| [`references/threading-and-lifecycle.md`](references/threading-and-lifecycle.md) | COM/threading, async activation, lifecycle state machine, Start/Stop/Reset, cancellation, locking. | Stream lifecycle and concurrency. |
| [`references/data-flow.md`](references/data-flow.md) | Backpressure, buffer ownership across threads, silence, discontinuities. | Connecting a slow consumer; handing off audio data. |
| [`references/diagnostics-and-performance.md`](references/diagnostics-and-performance.md) | Structured diagnostics; investigating glitches/underruns. | Debugging or optimizing audio. |
| [`references/managed-and-errors.md`](references/managed-and-errors.md) | C#/.NET guidance, error categorization, fallback policy. | Managed implementations; error handling. |
| [`references/testing.md`](references/testing.md) | Unit vs integration testing, review checklist, anti-patterns. | Testing and reviewing WASAPI code. |
| [`references/workflow.md`](references/workflow.md) | Step-by-step implementation workflow; source-of-truth policy. | Implementing a new or modified audio feature. |

## How to use

1. Read `references/overview.md` for orientation.
2. Read the specific `references/*.md` documents for the task (format selection, capture loop, device handling, etc.).
3. Apply the guidance to the host project, preserving its existing abstractions and conventions.
