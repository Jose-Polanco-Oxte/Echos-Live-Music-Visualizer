# Win2D — Animation and Threading

## Animation and threading

`CanvasAnimatedControl` has a dedicated game-loop model. Treat its `Update` and `Draw` work as render-thread work, not UI-thread work.

Within `Update` / `Draw`:

- do not block on tasks, events, locks, file I/O, networking, or UI dispatch;
- do not access XAML objects unless the API explicitly permits it from that thread;
- do not mark handlers `async` as a substitute for designing correct synchronization;
- keep state transfer bounded and cheap;
- separate simulation/update from rendering when practical.

If UI state must affect animation, publish a snapshot or small synchronized state change rather than reading a complex UI object graph from the game-loop thread.

If work must execute on the game-loop thread, use the control's game-loop scheduling mechanisms. Be careful with `await`: continuations are not automatically guaranteed to remain on the game-loop thread unless the synchronization strategy explicitly ensures it.

Choose fixed vs variable timestep intentionally. Do not assume a stable 60 FPS. Use timing information supplied by the control rather than hardcoding frame duration into simulation logic.

Pause continuous animation when it is not needed.

## CanvasVirtualControl

For a virtual control:

- draw only the rectangles reported as invalid;
- create a drawing session for each required region;
- invalidate only regions that changed when possible;
- account for resize behavior explicitly;
- avoid rendering the entire logical surface just because its dimensions are large.

Use its cross-thread drawing capabilities only when there is a concrete reason and ownership is well defined. Do not add threading complexity merely because the API allows it.
