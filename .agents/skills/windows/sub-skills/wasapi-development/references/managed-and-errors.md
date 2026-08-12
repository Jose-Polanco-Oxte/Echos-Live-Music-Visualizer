# WASAPI — Managed-Code Guidance and Error Handling

## Managed-code guidance

For C#/.NET implementations:

* Keep native resource ownership explicit.
* Dispose COM/native resources deterministically.
* Keep buffer-processing code allocation-conscious.
* Avoid LINQ, reflection, heavy logging, and closure-heavy code in the hot path when they create avoidable work.
* Do not expose raw native pointers beyond the smallest necessary scope.
* Use `Span<T>`, `ReadOnlySpan<T>`, unsafe blocks, or pinned/native buffers only where they materially improve correctness/performance and fit project conventions.
* Avoid pinning managed objects for long periods.
* Keep the UI thread independent from the audio processing thread.
* Marshal UI updates asynchronously and at a lower rate than the audio callback when appropriate.
* Do not assume `async`/`await` is appropriate for the real-time processing loop itself.

If the project uses WinUI 3, audio capture/render services should normally remain UI-framework-independent. The UI may control lifecycle and display state, but XAML/ViewModels should not own WASAPI buffer processing.

## Error handling

Categorize errors instead of wrapping every HRESULT in one generic exception.

Useful categories:

```text
UnsupportedConfiguration
EndpointUnavailable
EndpointBusy
ExclusiveModeDenied
DeviceInvalidated
ResourcesInvalidated
ServiceUnavailable
ActivationFailed
FormatNegotiationFailed
BufferProtocolViolation
UnexpectedNativeFailure
```

Preserve the original HRESULT.

Recover only when the error semantics make recovery meaningful.

Do not retry programming errors such as buffer-protocol violations indefinitely.

## Fallback policy

Fallbacks must preserve product semantics.

Examples:

**Acceptable when requirements permit**

```text
preferred low period unavailable
→ use supported higher period
```

```text
requested shared format unavailable
→ use explicitly accepted closest format
```

**Not automatically acceptable**

```text
exclusive bit-perfect unavailable
→ silently use shared mode
```

```text
process loopback unsupported on OS
→ silently capture all system audio
```

```text
RAW unsupported
→ claim capture is unprocessed
```

Expose material behavior changes to the caller or user.
