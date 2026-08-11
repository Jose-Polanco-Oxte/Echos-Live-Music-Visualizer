# WASAPI — Modes, Latency, and Scheduling

## Prefer shared mode by default

Use **shared mode** unless the requirements justify exclusive access.

Shared mode should normally be preferred because it:

* coexists with other applications;
* uses the Windows audio engine;
* participates naturally in system audio behavior;
* supports endpoint loopback;
* can achieve low periods through `IAudioClient3` on modern Windows.

Do not choose exclusive mode merely because the application is performance-sensitive. `IAudioClient3` allows shared-mode clients on Windows 10+ to query supported engine periods and request low-period shared streams, which can provide low latency without monopolizing the endpoint.

Use exclusive mode only when requirements such as these actually demand it:

* bit-exact or engine-bypassing output;
* a hardware format not suitable for shared mode;
* a verified latency requirement that shared low-period operation cannot satisfy;
* a pro-audio workflow that explicitly expects endpoint exclusivity.

Account for:

* `AUDCLNT_E_DEVICE_IN_USE`;
* `AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED`;
* unsupported formats;
* device-period constraints;
* the fact that other applications can lose access to the endpoint while the exclusive stream is active.

Never silently fall back from exclusive to shared mode, or vice versa, if that changes an explicit semantic requirement such as bit-perfect output. Surface the difference.

## Prefer IAudioClient3 for modern low-latency shared streams

When the supported OS baseline permits it, prefer `IAudioClient3` for new low-latency shared-mode implementations.

Its relevant capabilities are:

* `GetCurrentSharedModeEnginePeriod`
* `GetSharedModeEnginePeriod`
* `InitializeSharedAudioStream`

`IAudioClient3` is available starting with Windows 10.

For a requested stream format:

1. Determine the intended format.
2. Query legal periods using `GetSharedModeEnginePeriod`.
3. Select an actual supported period.
4. Initialize with `InitializeSharedAudioStream`.
5. Treat period negotiation as dynamic runtime behavior.

Legal periods are not arbitrary: supported periods are derived from the minimum, maximum, fundamental, and default values reported by the engine. Do not hardcode assumptions such as "10 ms", "5 ms", or "128 frames".

Handle at least:

* `AUDCLNT_E_ENGINE_PERIODICITY_LOCKED`
* `AUDCLNT_E_ENGINE_FORMAT_LOCKED`

These conditions may occur because another client has already established engine conditions. Query the current state and decide whether the existing period/format is acceptable instead of treating the condition as a generic unexplained failure.

## Treat latency as a negotiated property

Never promise or infer latency solely from a requested buffer size.

Actual latency depends on:

* engine period;
* endpoint/device period;
* driver capabilities;
* hardware buffering;
* audio processing objects;
* application scheduling;
* any resampling or DSP in the path.

Drivers can expose different supported buffer periods. Query capabilities instead of assuming identical behavior across machines.

If latency matters:

* measure it;
* log the negotiated period;
* log the buffer frame count;
* inspect `GetStreamLatency` where relevant;
* distinguish API/engine latency from end-to-end hardware latency.

Do not optimize latency before the stream is functionally correct and stable.

## Prefer event-driven streaming

For interactive or low-latency WASAPI streams, normally use event-driven buffering with:

`AUDCLNT_STREAMFLAGS_EVENTCALLBACK`

Then:

1. Create an appropriate event.
2. Register it with `IAudioClient::SetEventHandle`.
3. Start the stream.
4. Have the audio worker wait for the event.
5. Process the available frames or packets.
6. Return to waiting.

Do not implement a busy-spin polling loop.

Do not perform UI work from the real-time audio callback/worker.

Do not hold application-wide locks while waiting for or processing an audio period.

Use timer-driven buffering only when the architecture or compatibility requirements specifically justify it.

## Keep real-time paths bounded

Treat render and capture processing paths as latency-sensitive.

Inside the hot audio path, avoid whenever practical:

* blocking filesystem I/O;
* synchronous network I/O;
* UI dispatch;
* logging that performs synchronous I/O;
* unbounded locks;
* waiting on unrelated worker threads;
* allocating large objects repeatedly;
* expensive object creation;
* uncontrolled garbage generation;
* device enumeration;
* COM activation;
* format negotiation;
* reparsing configuration;
* arbitrary callbacks supplied by unknown consumers.

Prepare resources before `Start` where practical.

Use preallocated buffers, bounded queues, ring buffers, or other predictable handoff mechanisms between audio processing and slower application subsystems.

A visualization renderer, encoder, recorder, UI, or network sender must not be allowed to stall the WASAPI buffer-processing path.

If work cannot safely complete within the audio period, move it off the real-time path.

## Use MMCSS deliberately

For time-sensitive audio workers, use the Windows multimedia scheduling facilities appropriate to the architecture rather than arbitrary thread-priority hacks.

MMCSS exists specifically to prioritize multimedia work while preserving CPU availability for other work. Windows defines task categories including `Audio`, `Capture`, `Playback`, and `Pro Audio`.

For very-low-latency WASAPI work, also consider the Windows guidance recommending Real-Time Work Queue / properly categorized work items instead of uncontrolled custom real-time threads.

Do not:

* set process priority to realtime as a substitute for correct scheduling;
* blindly assign every worker to `Pro Audio`;
* modify MMCSS registry policy as an application optimization;
* increase priority to conceal excessive work in the callback.

Thread priority cannot compensate for an audio callback that regularly exceeds its processing budget.
