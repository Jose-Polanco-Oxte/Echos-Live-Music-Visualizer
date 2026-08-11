# WASAPI — Audio Formats

## Audio format rules

Treat the negotiated `WAVEFORMATEX` / `WAVEFORMATEXTENSIBLE` as authoritative.

Never assume:

```text
44.1 kHz
48 kHz
16-bit PCM
32-bit float
stereo
2 channels
```

unless the application's contract explicitly fixes that format and support has been verified.

For shared-mode streams, `GetMixFormat` is the natural baseline when the application can operate in the engine's format. The mix format represents the audio engine's shared-mode processing format and is not evidence that the same format is supported in exclusive mode.

When requesting a specific format, use `IsFormatSupported`.

Interpret it correctly:

```text
S_OK      → requested format supported
S_FALSE   → shared mode found a closest supported format
failure /
AUDCLNT_E_UNSUPPORTED_FORMAT
          → requested format not supported
```

The shared-mode closest-match result is meaningful and must be managed correctly. Exclusive-mode format probing behaves differently and does not provide the same closest-match behavior.

Do not reinterpret sample payloads without checking:

* format tag/subformat;
* sample rate;
* channel count;
* valid bits;
* container bits;
* channel mask;
* `nBlockAlign`.

Use `nBlockAlign` to translate frames to byte counts:

```text
bytes = frames * nBlockAlign
```

Prefer reasoning in **audio frames** at the WASAPI boundary. Convert to bytes only where required.

## Respect format ownership

Several Core Audio APIs return allocated format structures.

Follow the API's documented allocator/deallocator contract exactly.

In native code, do not substitute `delete`, `free`, or an unrelated allocator for memory that must be released using `CoTaskMemFree`.

In managed code, ensure native buffers have a single explicit owner and are released exactly once.

Do not retain pointers to native format memory beyond their valid ownership lifetime.

## Sample processing

Keep the native device format separate from the application's internal DSP format.

If the DSP operates on float samples but WASAPI provides another representation:

```text
WASAPI device format
      ↓
explicit conversion
      ↓
canonical internal format
      ↓
DSP / visualization / analysis
```

Do not reinterpret integer PCM bytes as float samples.

If conversion is necessary, centralize and test it.

Verify:

* signedness;
* bits per sample;
* valid bits;
* endianness assumptions;
* channel order;
* clipping;
* scaling;
* NaN/Infinity behavior for floating-point processing.

Avoid unnecessary format conversion in the real-time loop.

## Multichannel audio

Do not assume channel count equals two.

When supporting multichannel streams:

* preserve the channel count;
* honor the channel mask when available;
* distinguish channel index from speaker identity;
* design transforms that either support arbitrary channel counts or reject unsupported layouts explicitly.

Do not silently truncate channels.
