# System Architecture — Echo Live Music Visualizer

## 1. High-Level Pipeline Architecture
Echo uses a decoupled, multi-threaded pipeline designed for low latency, zero allocations per render tick, and real-time audio visual responsiveness.

```
[WASAPI Audio Input] 
        │ (Continuous PCM Audio Buffer)
        ▼
[Rust DSP Engine: src/core]
   ├── Downmix / Resample (48 kHz)
   ├── Multiresolution STFT (H=512, FFT 4096/2048/1024, Blackman-Harris 4)
   ├── Perceptual Filterbank (ERB / Logarithmic 3–128 Bands)
   ├── Feature Extractor (RMS, Centroid, Onset, K-Weighted LUFS)
   └── Scaler (Master Peak + Hybrid LUFS Macro-Gain RF4.3.4)
        │
        ▼ (SPSC Lock-Free Queue / Triple-Buffer Frame Store)
[Zero-Copy ABI v2 Interop Layer]
        │
        ▼ (Ephemeral Lease: AudioFrameView)
[C# WinUI 3 UI Layer: src/ui]
   ├── AudioCoreService (FFI Lifetime & Session Manager)
   └── Win2D CanvasControl renderer (CanvasControl.Draw; UI timer requests redraws)
```

## 2. Core Subsystems

### 2.1 WASAPI Audio Capture & Downmixing (`src/core/wasapi/`)
- Captures loopback system audio continuously via Windows Audio Session API (WASAPI).
- Handles format negotiation, downmixing multi-channel audio to mono/stereo, and resampling to standard 48 kHz.

### 2.2 Rust DSP Processing Core (`src/core/dsp/`)
- **Multiresolution STFT**: Uses hop size $H=512$, windowed by Blackman-Harris 4 across STFT resolutions (4096, 2048, 1024 bins).
- **Logarithmic ERB Filterbank**: Maps linear FFT bins into 3 to 128 discrete perceptual frequency bands (default 48 bands). Integration procreates power averages across intervals rather than center-bin sampling.
- **Metrics Extractor**: Calculates RMS energy, spectral centroid (brightness), spectral onset (percussive flux), and short-term / integrated LUFS.
- **Dynamic Scaler**: Combines short-term LUFS macro gain adjustment with single Master Peak amplitude division and `tanh` soft clipping.

### 2.3 Decoupling & FFI ABI v2 (`src/core/ffi/`)
- **Memory Ownership**: Rust owns all frame buffers. C# receives non-owning, ephemeral leases (`AudioFrameView`).
- **Concurrency**: Lock-free Single-Producer Single-Consumer (SPSC) queue and triple-buffered frame store decouple Rust audio processing threads from C# UI render ticks.
- **ABI Compatibility**: ABI v1 retained for backward test compatibility; ABI v2 (`acquire_latest_analysis_frame_v2`) used for zero-copy production flow.

### 2.4 WinUI 3 UI & Direct3D Rendering (`src/ui/`)
- **`AudioCoreService`**: Manages FFI handle lifecycle, background WASAPI polling, and event notifications.
- **`Win2DGpuSpectralBarVisualizer`**: Renders the active spectral bars through a Win2D
  `CanvasControl` and its `Draw` callback.
- **Render scheduling**: `VisualizerPage` uses a `DispatcherTimer` with a 16 ms
  interval to request updates while the page is active; the renderer itself draws
  from the latest available analysis frame.
- **Allocation invariant**: The draw path must avoid per-frame managed allocations;
  verify this against the current renderer implementation when changing it rather
  than relying on historical renderer type names.

## 3. Threading & Concurrency Model
1. **Audio Thread (Real-Time)**: Executes WASAPI callbacks, writes raw PCM buffers into DSP worker queue.
2. **DSP Worker Thread**: Performs windowing, STFT, filterbank mapping, LUFS scaling, and updates the triple-buffered Frame Store.
3. **UI Thread (Win2D draw cycle)**: The page timer requests canvas invalidation while
   active; `CanvasControl.Draw` acquires the latest FFI frame lease and draws without
   blocking audio execution.
