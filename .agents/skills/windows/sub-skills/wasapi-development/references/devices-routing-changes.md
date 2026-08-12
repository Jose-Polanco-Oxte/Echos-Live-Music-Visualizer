# WASAPI — Devices, Routing, and Change Handling

## Device selection and endpoint identity

Use MMDevice APIs for endpoint discovery and explicit endpoint selection.

For the default endpoint, choose both:

* data flow: render or capture;
* role: console, multimedia, or communications.

`IMMDeviceEnumerator::GetDefaultAudioEndpoint` resolves the default endpoint for a specified direction and role.

Do not assume that all roles map to the same endpoint.

Treat endpoint IDs as opaque stable identifiers. Do not parse their internal string representation or derive meaning from it.

Store an endpoint ID when persistent explicit-device selection is required, not a display name.

## Default-device routing

Decide explicitly whether a stream is bound to:

* a particular physical/logical endpoint; or
* the system's evolving default route.

These are different semantics.

For modern Windows, automatic stream routing is available when a WASAPI interface is activated using the default render/capture device-interface identifiers through `ActivateAudioInterfaceAsync`; this capability exists starting with Windows 10 version 1607.

If the project instead binds directly to `IMMDevice`, implement device-change behavior appropriate to the application.

Do not assume direct WASAPI streams will always move seamlessly between devices unless the selected activation/routing mechanism provides that behavior.

## React to endpoint changes

Long-lived audio applications must assume that endpoints can:

* appear;
* disappear;
* be disabled;
* be unplugged;
* change properties;
* become or cease to be the default device.

Use `IMMNotificationClient` when the application needs endpoint lifecycle/default-device notifications. The interface reports device addition/removal/state/property/default-role changes.

Callbacks must be lightweight.

Do not rebuild the complete audio graph while holding callback-owned locks.

A useful pattern is:

```text
notification callback
       ↓
record immutable change
       ↓
signal coordinator
       ↓
stop/rebuild stream outside callback
```

Device and session notifications can arrive asynchronously and in different orders. Recovery logic must not depend on one exact notification ordering.

## Treat invalidation as normal runtime behavior

A WASAPI stream can become invalid when:

* hardware is unplugged;
* the device is disabled or reconfigured;
* resources are invalidated;
* the audio service stops;
* exclusive/offload conditions change.

Handle HRESULTs such as:

```text
AUDCLNT_E_DEVICE_INVALIDATED
AUDCLNT_E_RESOURCES_INVALIDATED
AUDCLNT_E_SERVICE_NOT_RUNNING
AUDCLNT_E_ENDPOINT_CREATE_FAILED
```

as categorized runtime states, not generic exceptions. Microsoft documents device/resource invalidation on core client operations.

For recoverable scenarios:

1. Stop using the invalid client.
2. Terminate the old processing loop.
3. Release stream service objects.
4. Re-resolve the endpoint if necessary.
5. Re-query the format and periods.
6. Create and initialize a new audio client.
7. Restore application state that is still meaningful.
8. Restart streaming.

Do not continue invoking methods on a client known to be invalid.

Use bounded retries with state transitions; never spin indefinitely recreating a failing device.
