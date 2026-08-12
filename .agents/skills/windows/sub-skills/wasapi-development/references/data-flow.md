# WASAPI — Data Flow and Backpressure

## Backpressure

If captured audio feeds another subsystem, define what happens when the consumer cannot keep up.

Possible policies include:

```text
drop oldest
drop newest
bounded blocking outside the audio path
disconnect slow consumer
record discontinuity
increase downstream buffering
```

Choose deliberately.

Do not allow an unbounded queue to hide a permanently slow consumer.

For real-time visualization, dropping stale frames is often preferable to making the audio capture path wait.

For recording, loss policy may need to favor continuity and explicitly report overruns.

## Buffer ownership across threads

Never pass a pointer returned directly by:

```text
IAudioCaptureClient::GetBuffer
IAudioRenderClient::GetBuffer
```

to another thread for later use.

The pointer's validity is bounded by the corresponding `ReleaseBuffer`.

If another subsystem needs the samples:

1. copy or transform them while the packet is valid;
2. place owned data into the handoff mechanism;
3. release the WASAPI packet promptly.

## Silence

Treat silence as normal data.

Examples include:

* capture packet marked silent;
* process loopback target producing no audio;
* initial stream state;
* intentionally silent render buffers.

Do not interpret silence as:

* disconnected device;
* stalled stream;
* failed capture;
* zero-length packet.

Differentiate these states explicitly.

## Discontinuities

Track discontinuities when downstream semantics care about continuity.

Sources can include:

* missed capture packets;
* device invalidation;
* stream restart;
* queue overflow;
* consumer overrun;
* format change;
* endpoint switch.

A recorder may need to preserve timing despite a discontinuity.

A visualizer may simply reset temporal smoothing state.

A DSP pipeline may need to clear history.

Do not conceal discontinuities merely to make telemetry appear clean.
