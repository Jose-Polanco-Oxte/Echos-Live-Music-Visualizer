# Win2D — Drawing Sessions and Device Recovery

## Drawing-session ownership

`CanvasDrawingSession` is scoped work.

- Use the drawing session supplied by a Win2D draw event only inside that event.
- Never store it for later use or pass it to another thread.
- Do not manually dispose the event-owned drawing session.
- Dispose drawing sessions that the application explicitly creates, normally with `using`.
- Do not create overlapping drawing sessions for the same render target or surface unless the API explicitly supports the pattern.

Apply the same ownership discipline to disposable Win2D resources. Dispose resources when their owning scope ends instead of waiting for GC to release GPU memory.

## Device lost is normal runtime behavior

Treat device loss as a recoverable lifecycle transition, not an impossible error.

Built-in Win2D controls can recreate their device and raise `CreateResources` again. Application code must make its resource graph reconstructible.

When drawing outside protected Win2D control callbacks or managing `CanvasDevice` directly:

- detect device-lost failures with `CanvasDevice.IsDeviceLost`;
- route recovery through `RaiseDeviceLost` when sharing the device with controls;
- subscribe to `CanvasDevice.DeviceLost` when the application owns the device lifecycle;
- recreate the device and all dependent resources as required.

Never catch and ignore a device-lost exception while continuing to use the invalid device.

Do not retain a bitmap, render target, brush, command list, cached geometry, or effect graph merely because the managed object still exists after device replacement.
