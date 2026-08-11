# WASAPI — Scenario and Architecture

## Establish the exact audio scenario

Before implementing anything, classify the stream along these dimensions:

**Direction**

* Render: application → audio output.
* Capture: audio input → application.
* Endpoint loopback: system mix rendered to a selected output endpoint → application.
* Process loopback: audio rendered by a particular process tree, or everything except that process tree → application.

**Endpoint selection**

* Explicit endpoint selected by the user.
* Current default endpoint.
* Default endpoint for a specific role.
* Automatically routed default interface.

**Mode**

* Shared mode.
* Exclusive mode.

**Latency**

* Normal interactive/media latency.
* Low latency.
* Pro-audio / latency-critical.

**Processing**

* Normal Windows signal-processing path.
* Raw processing where supported and explicitly required.
* Format matching / avoidance of engine resampling where supported and required.

Never choose these accidentally through copied constants.

## Understand the Core Audio object chain

A conventional endpoint-specific stream normally follows this conceptual path:

```text
IMMDeviceEnumerator
        ↓
IMMDevice
        ↓
IAudioClient / IAudioClient2 / IAudioClient3
        ↓
Initialize / InitializeSharedAudioStream
        ↓
IAudioRenderClient or IAudioCaptureClient
        ↓
Start
        ↓
buffer-processing loop
        ↓
Stop
        ↓
release services and client resources
```

`IAudioClient` represents the stream relationship between the application and either the Windows audio engine in shared mode or the hardware endpoint path in exclusive mode.

Do not merge endpoint enumeration, client activation, stream lifetime, and packet processing into one giant class unless the existing architecture explicitly calls for it.

Prefer clear responsibilities such as:

```text
AudioDeviceEnumerator
AudioEndpoint
WasapiStream
WasapiRenderStream
WasapiCaptureStream
WasapiLoopbackStream
AudioFormat
AudioBufferProcessor
AudioDeviceWatcher
AudioSessionController
```

Names should follow the host project's conventions.
