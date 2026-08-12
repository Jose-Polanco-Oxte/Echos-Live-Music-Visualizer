# WASAPI — Diagnostics and Performance

## Diagnostics

For difficult WASAPI issues, record structured diagnostics at lifecycle boundaries, not inside every sample-processing iteration.

Useful fields include:

```text
endpoint ID
friendly endpoint name
render/capture direction
endpoint role
shared/exclusive
loopback mode
process-loopback PID/mode
audio category
stream flags
sample rate
channels
bits / valid bits
subformat
channel mask
block alignment
buffer frame count
engine period frames
period milliseconds
requested vs negotiated format
requested vs negotiated period
HRESULT symbolic name
stream state
device invalidation reason
discontinuity count
underrun/overrun count
```

Do not log every callback or packet under normal operation.

Use counters and periodic summaries.

Always preserve the raw HRESULT and a symbolic interpretation when reporting native failures.

## Performance investigation

When audio glitches:

1. Establish whether the failure is render underrun, capture loss, device invalidation, scheduling delay, or downstream backpressure.
2. Measure audio callback/worker execution time.
3. Compare the worst-case processing duration against the negotiated audio period.
4. Inspect lock contention.
5. Inspect allocations/GC for managed implementations.
6. Inspect device and format changes.
7. Inspect queue saturation.
8. Inspect system/driver behavior.
9. Reduce work on the real-time path before blindly increasing thread priority.
10. Increase buffering only when the resulting latency remains acceptable.

Do not optimize from average callback duration alone; rare worst-case stalls cause glitches.
