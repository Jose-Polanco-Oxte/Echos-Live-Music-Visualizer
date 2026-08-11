# WASAPI — Implementation Workflow and Source of Truth

## Implementation workflow

When asked to add or modify WASAPI behavior:

### 1. Discover

Inspect:

```text
audio architecture
existing interop layer
OS baseline
current device-selection semantics
current stream lifecycle
threading model
internal sample format
downstream consumers
tests
```

### 2. Specify

Write down internally:

```text
direction
endpoint semantics
shared/exclusive
normal/loopback/process-loopback
format
latency target
processing mode
routing behavior
recovery policy
```

### 3. Validate capability

Before initialization:

```text
resolve endpoint/interface
query format
query supported format if custom
query period if low latency
verify OS-gated APIs
verify optional RAW/format-match support
```

### 4. Initialize

Create the smallest valid configuration.

Do not add advanced flags until their requirement is clear.

### 5. Start processing

Keep the audio loop:

```text
bounded
allocation-conscious
lock-light
UI-independent
prompt about releasing WASAPI buffers
```

### 6. Handle lifecycle failures

Treat device loss and route changes as explicit state transitions.

### 7. Validate

Build and run relevant tests.

Test actual stream start/stop repeatedly.

When applicable, test:

```text
device unplug/replug
default-device switch
no target process audio
target process termination
silence
format mismatch
low-period rejection
exclusive-mode denial
application shutdown while streaming
```

### 8. Measure

For latency/performance changes, collect evidence before claiming improvement.

## Source-of-truth policy

When repository assumptions conflict with current Windows behavior, verify against **current Microsoft Learn / Windows SDK documentation** before modifying low-level semantics.

Prefer these source families:

```text
Windows Audio Session API (WASAPI)
Core Audio APIs
MMDevice API
IAudioClient / IAudioClient2 / IAudioClient3
IAudioRenderClient
IAudioCaptureClient
Loopback Recording
Application Loopback Audio Capture
Low Latency Audio
Audio Sessions
EndpointVolume API
Multimedia Class Scheduler Service
Windows Classic Samples
```

Do not treat:

```text
old Stack Overflow answers
random P/Invoke snippets
legacy Vista-era samples
third-party wrappers
blog posts
AI-generated COM declarations
```

as authoritative when they conflict with the Windows SDK or current Microsoft documentation.

When using old WASAPI documentation, distinguish **API invariants that remain valid** from **historical workarounds that modern Windows no longer needs**.

In particular:

* modern shared low-latency design should consider `IAudioClient3`;
* endpoint loopback is shared-mode only;
* event-driven loopback no longer requires the pre-Windows-10-1703 workaround on supported modern systems;
* process loopback requires Windows 10 build 20348+;
* direct WASAPI device-routing behavior must be selected deliberately rather than assumed.
