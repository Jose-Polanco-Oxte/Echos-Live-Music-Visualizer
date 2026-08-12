# WASAPI Development — Overview

Use this skill when working directly with **WASAPI, Core Audio, MMDevice, audio sessions, endpoint volume, or low-level Windows audio streams**.

Treat audio streaming code as **real-time, stateful, resource-sensitive systems code**, not ordinary application code.

The goals are:

1. Correctness under normal operation and device changes.
2. Glitch-resistant real-time behavior.
3. Predictable ownership and lifecycle.
4. Correct format and buffer handling.
5. Graceful recovery from audio-device failures.
6. Lowest necessary latency without unnecessarily disrupting the rest of the system.
7. Compatibility with the project's declared Windows baseline.

WASAPI is appropriate when the application requires finer control or lower latency than higher-level Windows audio APIs provide. Do not introduce direct WASAPI merely because it is lower level; preserve higher-level APIs when they already satisfy the requirements. Microsoft specifically recommends considering AudioGraph for new applications and using WASAPI when greater control or lower latency is required.

## First inspect the existing system

Before changing audio code:

* Read the project's architecture, conventions, requirements, and existing audio abstractions.
* Identify the implementation language and interop mechanism.
* Find all code responsible for device enumeration, stream creation, capture/render loops, format conversion, synchronization, disposal, and device-change handling.
* Determine the application's minimum Windows version/build.
* Determine whether audio processing shares timing or state with rendering, visualization, networking, recording, or another subsystem.
* Preserve established abstractions unless there is a concrete reason to change them.
* Do not replace a working interop library, COM abstraction, or resource-management strategy casually.

When the project uses C#/.NET, prefer extending its existing native interop strategy rather than adding a second unrelated wrapper around WASAPI.

## Core principle

Optimize WASAPI code in this order:

```text
correct lifecycle
→ correct buffer protocol
→ correct format handling
→ robust device recovery
→ bounded real-time processing
→ measured latency
→ targeted optimization
```

Never sacrifice the first four to make a nominal buffer-period number smaller.
