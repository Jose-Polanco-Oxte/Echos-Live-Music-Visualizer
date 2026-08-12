# WASAPI — Testing and Review

## Testing

Separate deterministic audio logic from hardware-dependent integration tests.

Unit-test without an actual device:

* format calculations;
* frame/byte conversions;
* channel transforms;
* ring-buffer behavior;
* state transitions;
* retry policy;
* error mapping;
* discontinuity handling;
* sample conversion;
* timing calculations;
* backpressure behavior.

Use integration tests for:

* endpoint enumeration;
* default-device resolution;
* render initialization;
* capture initialization;
* loopback;
* process loopback;
* event signaling;
* device switching;
* invalidation and recovery;
* exclusive-mode behavior where hardware permits;
* low-period negotiation.

Do not make ordinary CI depend on the presence of one specific consumer audio device.

Hardware-sensitive tests should detect capability and report **unsupported/skipped**, not produce false failures.

## Review checklist

Before considering WASAPI work complete, verify:

```text
[ ] Correct render/capture/loopback scenario selected.
[ ] Windows minimum version/build supports every selected API.
[ ] Shared vs exclusive mode is intentional.
[ ] Requested format is verified or negotiated correctly.
[ ] No hardcoded device format assumptions remain unintentionally.
[ ] Buffer sizes are handled in frames.
[ ] Event-driven loop executes within its timing budget.
[ ] GetBuffer/ReleaseBuffer calls are paired correctly.
[ ] Capture drains all available packets.
[ ] Silent capture packets are handled safely.
[ ] Discontinuity and timestamp flags are handled where relevant.
[ ] Native buffer pointers never escape their valid lifetime.
[ ] Device invalidation has a recovery path.
[ ] Default-device changes follow explicit routing semantics.
[ ] Audio workers do not perform UI work.
[ ] Slow consumers cannot block the WASAPI path indefinitely.
[ ] Native/COM resources have deterministic ownership.
[ ] Stream shutdown cannot race buffer processing.
[ ] Errors preserve meaningful HRESULT information.
[ ] Logging is not performed per audio frame/packet in production.
[ ] Endpoint volume is not modified when session volume is intended.
[ ] Latency claims are measured or based on negotiated runtime values.
[ ] Hardware-dependent behavior is tested on representative devices.
```

## Anti-patterns

Reject or refactor code that does any of the following without a very strong documented reason:

```text
Sleep(10) as the primary low-latency audio scheduler
busy-looping GetCurrentPadding/GetNextPacketSize
hardcoding 48 kHz stereo float because "Windows uses it"
assuming GetMixFormat is valid for exclusive mode
holding a WASAPI buffer while another thread processes it
performing FFT/rendering/database/network work before ReleaseBuffer
allocating large buffers on every callback
using unbounded queues after capture
changing system endpoint volume for application-only volume
ignoring AUDCLNT_BUFFERFLAGS_SILENT
ignoring device invalidation
reusing an invalidated IAudioClient
reinitializing inside IMMNotificationClient callbacks
assuming default audio devices never change
using display names as persistent endpoint identity
enabling exclusive mode solely for "better performance"
enabling RAW without checking support
assuming one requested period works on every driver
silently converting process-loopback failure to system loopback
catching all HRESULTs and retrying forever
disposing COM resources concurrently with active packet processing
mixing XAML/UI state directly into the audio callback
raising process/thread priority before profiling the callback workload
```
