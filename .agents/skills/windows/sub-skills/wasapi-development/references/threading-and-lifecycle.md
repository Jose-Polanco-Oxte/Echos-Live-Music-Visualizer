# WASAPI — Threading, Lifecycle, and Concurrency

## COM and threading

WASAPI and MMDevice are COM-based APIs.

Respect the existing application's apartment model.

Do not scatter `CoInitializeEx` / `CoUninitialize` arbitrarily through helper methods.

The thread that owns COM interfaces and the thread performing buffer operations must follow the interface-specific threading/lifetime contracts.

Pay particular attention to service interfaces returned by `IAudioClient::GetService`.

`IAudioCaptureClient` documentation requires releasing the interface from the same thread associated with its creation through `GetService`; buffer acquisition/release ordering is also thread-sensitive.

In managed applications, do not assume the runtime's COM wrappers eliminate native threading rules.

## Async activation

Use `ActivateAudioInterfaceAsync` where the chosen API path requires it, including process loopback and automatic default routing scenarios.

Treat activation as genuinely asynchronous.

The completion handler must:

* correctly represent success/failure;
* obtain the activated interface only after completion;
* avoid assuming that the initiating UI object is still alive;
* participate in the application's cancellation/lifetime strategy.

Do not block the UI thread waiting synchronously for async activation completion.

## Lifecycle and state machine

Represent stream lifecycle explicitly.

A useful conceptual model is:

```text
Uninitialized
    ↓
Activating
    ↓
Initialized
    ↓
Starting
    ↓
Running
    ↓
Stopping
    ↓
Stopped
```

Exceptional transitions can include:

```text
Running → Invalidated
Running → Failed
Activating → Failed
Initialized → Disposed
Invalidated → Reinitializing
Reinitializing → Running
```

Do not use a loose collection of booleans such as:

```text
isRunning
isStarting
isStopping
deviceLost
isDisposed
```

when invalid combinations can occur.

Transitions should be serialized by one clear owner.

## Start/Stop/Reset behavior

Treat these as stateful operations.

`Start` begins audio flow.

`Stop` stops stream progression without creating a new client.

`Reset` resets a stopped stream's audio position/buffering state where supported by the current lifecycle.

Do not call `Reset` as a generic recovery mechanism while worker code may still be inside buffer operations.

Coordinate shutdown so the processing loop cannot race with teardown.

A robust shutdown normally follows the conceptual order:

```text
request stop
↓
wake audio worker if needed
↓
worker exits buffer loop
↓
IAudioClient::Stop
↓
release render/capture/session services
↓
release audio client
↓
release endpoint-specific resources
```

Adapt to the project's ownership model.

## Cancellation

Audio worker cancellation must not depend on a long polling timeout.

When using an event-driven stream, arrange for shutdown to wake the waiting worker promptly, for example through a separate cancellation event or equivalent synchronization primitive.

A worker should be able to wait conceptually on:

```text
audio-ready
OR
shutdown
```

Do not terminate the worker asynchronously.

## Locking

Use one clearly documented synchronization strategy.

Never hold a UI state lock while waiting for audio I/O.

Never call user-extensible callbacks while holding an internal audio lifecycle lock unless the architecture proves this safe.

Avoid callbacks reentering:

```text
Start
Stop
Dispose
ChangeDevice
Reinitialize
```

while a lifecycle transition is in progress.

Prefer immutable configuration snapshots passed into stream creation.
