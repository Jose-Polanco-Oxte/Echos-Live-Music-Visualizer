# Domain Knowledge — DSP & Audio Signal Processing

## 1. Audio Processing Domain Terms

### 1.1 WASAPI Loopback Capture
Windows Audio Session API (WASAPI) loopback mode captures raw PCM audio streams directly from the system output endpoint without requiring virtual audio cables or third-party audio drivers.

### 1.2 Multiresolution STFT & ERB Band Splitting
- **Short-Time Fourier Transform (STFT)**: Converts time-domain PCM samples into complex frequency spectrum frames using windowed FFTs (hop size $H=512$, window length up to 4096 bins, Blackman-Harris 4 window).
- **ERB / Logarithmic Bands**: Linear FFT frequency bins ($20\text{ Hz} - 20\text{ kHz}$) are mapped into 3 to 128 discrete perceptual energy bands using Equivalent Rectangular Bandwidth (ERB) logarithmic scales (initial preset: 48 bands).
- **Power Integration**: Band energy $E_i$ represents the average power within each perceptual interval, calculated using power integration and bin interpolation rather than picking a single center bin.

### 1.3 Audio Features & Metrics
- **RMS (Root Mean Square)**: Overall time-domain signal energy.
- **Spectral Centroid**: Center of mass of the spectrum, indicating perceived sound brightness.
- **Spectral Onset**: Rate of spectral flux change, detecting percussive attacks and beat hits.
- **LUFS (Loudness Units relative to Full Scale)**: Perceptual loudness measurement using standard K-weighting pre-filtering.

---

## 2. Normative Hybrid LUFS + Master Peak Scaling (RF4.3.4)

Production UI utilizes the **Hybrid LUFS + Master Peak Scaler** (RF4.3.4). Experimental modes (`NormativeLufs`, `MasterPeak`, `HybridMacroMaster`) exist in ABI solely for backward compatibility.

### 2.1 Fixed Scaling Parameters
- **Target Loudness ($L_{\text{target}}$)**: $-14\text{ LUFS}$
- **Silence Threshold ($L_{\text{silence}}$)**: $-50\text{ LUFS}$
- **Deadband**: $\pm 2\text{ LU}$
- **Macro Gain Limits**: $\text{clamp}(G_{\text{raw}}, 0.5, 2.0)$
- **Temporal Smoothing**: Attack rate $= 0.20$, Decay rate $= 0.003$
- **Headroom Target ($H_{\text{target}}$)**: $0.75$
- **Noise Floor ($P_{\text{floor}}$)**: $0.05$
- **Gamma ($\gamma$)**: $1.0$ (Linear scaling)

### 2.2 Mathematical Formula Pipeline
1. **Raw Macro Gain Calculation**:
   $$G_{\text{raw}} = \text{clamp}\left(10^{-\frac{L_{\text{short}} - L_{\text{target}}}{20}}, 0.5, 2.0\right)$$
2. **Gain Smoothing**:
   $$G_t = G_{t-1} + 0.01 \cdot (G_{\text{raw}} - G_{t-1})$$
3. **Amplitude Conversion & Soft Clipping**:
   - Power $E_i$ arriving from the analyzer is converted once to amplitude:
     $$A_i = \sqrt{E_i} \cdot G_t$$
   - Normalized by Master Peak divisor and limited by $\tanh$ soft clipping to preserve target headroom ($H_{\text{target}} = 0.75$).
4. **Silence Reset**: After prolonged silence ($L_{\text{short}} < L_{\text{silence}}$), macro gain $G_t$ and Master Peak divisors reset to baseline values.

> [!IMPORTANT]
> **K-Weighting Restriction**: K-weighting is applied **exclusively** for LUFS loudness measurement. It MUST NOT be re-applied per visual frequency band. No spectral tilt is applied in the production pipeline.

---

## 3. Visual Spectrum Bars vs. Continuous EQ Spectrum

### 3.1 Discrete Bar Representation
Echo displays discrete visual frequency bars. Each bar represents average perceptual energy across an ERB/log interval normalized dynamically.

### 3.2 Key Differences from DAW/EQ Spectrum Analyzers
- DAW visualizers (e.g., Fruity Parametric EQ 2) render continuous envelope curves over dense FFT bins in dB with temporal decay and visible noise floors.
- Echo's discrete visual bars preserve relative energy ratios within intervals, but obscure narrow spectral spikes and deep internal valleys.
- **Strict Prohibition**: Never add artificial bass multipliers, treble tilt compensations, or gamma tweaks to force bars to mimic a DAW EQ curve without explicit specification approval and traceability documentation.
