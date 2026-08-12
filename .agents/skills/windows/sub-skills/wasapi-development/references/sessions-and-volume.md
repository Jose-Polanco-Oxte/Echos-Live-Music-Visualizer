# WASAPI — Sessions and Volume

## Audio categories

When setting `AudioClientProperties`, select an `AUDIO_STREAM_CATEGORY` that accurately represents the application scenario.

Do not copy `AudioCategory_Media`, `AudioCategory_Communications`, or another category without examining the application.

The category can affect Windows audio policy and processing behavior.

Keep the selected category close to stream initialization code and document non-obvious choices.

## Audio sessions

Distinguish:

```text
stream
session
endpoint
```

They are not interchangeable.

Use audio-session interfaces when the application needs session-level behavior such as:

* session identity;
* session volume;
* mute;
* session lifecycle;
* ducking-related behavior;
* observing other audio sessions.

Relevant interfaces include:

```text
IAudioSessionControl
IAudioSessionControl2
IAudioSessionEvents
IAudioSessionManager2
ISimpleAudioVolume
IChannelAudioVolume
IAudioStreamVolume
```

Core Audio exposes separate interfaces for stream, session, and endpoint volume control.

Do not change endpoint master volume when the requirement is only to modify the application's session volume.

## Endpoint volume

`IAudioEndpointVolume` controls the endpoint/device volume, not merely one application's stream.

Use it only when the product intentionally manages device-level volume or an exclusive-mode workflow genuinely requires it.

Microsoft warns that inappropriate endpoint-volume manipulation can interfere with Windows audio policy and the user's system volume settings.

For normal shared-mode application volume, prefer session-level controls such as `ISimpleAudioVolume`.

Never restore endpoint volume to a stale cached value after another application or the user has legitimately changed it unless the product contract explicitly requires ownership of that setting.
