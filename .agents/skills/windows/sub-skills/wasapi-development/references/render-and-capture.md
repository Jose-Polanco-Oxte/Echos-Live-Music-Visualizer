# WASAPI — Render and Capture

## Rendering

A render stream writes audio frames through `IAudioRenderClient`.

For shared-mode rendering, the normal capacity calculation is conceptually:

```text
bufferFrames = IAudioClient::GetBufferSize()
padding      = IAudioClient::GetCurrentPadding()
available    = bufferFrames - padding
```

Request no more frames than are actually writable.

For each packet:

```text
IAudioRenderClient::GetBuffer(frames)
write exactly the intended audio data
IAudioRenderClient::ReleaseBuffer(frames, flags)
```

Keep `GetBuffer` and its corresponding `ReleaseBuffer` correctly paired and ordered.

Never:

* retain the returned buffer after `ReleaseBuffer`;
* call `GetBuffer` repeatedly without releasing the prior buffer;
* release more frames than acquired;
* request more frames than the current writable capacity.

If output should be silence, use the appropriate WASAPI silent-buffer semantics instead of performing unnecessary sample filling when the implementation permits it.

For event-driven exclusive streams, follow the stricter buffer-size contract; releasing an incorrect packet size can produce `AUDCLNT_E_BUFFER_SIZE_ERROR`.

## Prime render streams intentionally

When a renderer needs immediate non-silent output, consider priming the endpoint buffer before starting the stream.

If startup silence is intentional, mark it explicitly.

Do not let the first callback perform expensive lazy initialization before producing the first buffer.

## Capture

A capture stream reads packets through `IAudioCaptureClient`.

The processing model is packet-oriented, not "read an arbitrary number of bytes."

On each wakeup, drain all currently available packets:

```text
while GetNextPacketSize() > 0:
    GetBuffer(...)
    consume/copy the complete packet
    ReleaseBuffer(...)
```

Microsoft recommends reading all available packets each time the capture processing thread runs.

`GetBuffer` and `ReleaseBuffer` must remain correctly paired and ordered on the same processing thread. Consecutive unmatched calls can fail with `AUDCLNT_E_OUT_OF_ORDER`.

Capture packets must be consumed as entire packets or not consumed:

```text
ReleaseBuffer(packetFrames)
```

or:

```text
ReleaseBuffer(0)
```

Do not partially consume an acquired packet.

## Capture buffer flags

Always inspect the capture flags.

Handle at least the semantic cases represented by:

```text
AUDCLNT_BUFFERFLAGS_SILENT
AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY
AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR
```

For silent packets, do not dereference sample data as though valid audio bytes must be present. Treat the packet as the specified number of zero-valued frames.

A discontinuity is not merely a logging curiosity. Propagate it to any component that relies on a continuous signal, timestamp sequence, FFT history, recorder timeline, encoder state, or synchronization.

A timestamp error means the associated position/timing metadata cannot be trusted for that packet.

## Timing and positions

When synchronization matters, distinguish:

* number of frames transferred;
* device position;
* QPC-derived timing;
* stream position;
* wall-clock time.

Do not derive precise media timestamps solely from callback arrival time.

Capture `GetBuffer` can return the device position and a QPC-based timestamp associated with the first frame in the packet.

Use `IAudioClock` / documented WASAPI timing facilities when a stable audio clock is required.

For A/V synchronization, visualization timing, or cross-stream correlation, document which clock is authoritative.
