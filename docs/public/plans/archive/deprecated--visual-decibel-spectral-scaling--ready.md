# Escalado Espectral Visual en Decibelios (dB) — READY

## Registro de avance

### 2026-08-05 — Implementación, Trazabilidad y Verificación Completadas

- **Trazabilidad de Requisitos:** Creado `docs/traceability/REQ-TRACE-20260805-visual-db-scaling.md` mapeando RF4.3.4, RF-EQ.1, RF-EQ.2 y RF5.1.
- **Decisión de Ingeniería QA:** Creada `.agents/qa/logs/decision-QA-DEC-20260805-visual-db-scaling.md`.
- **Core DSP en Rust:**
  - Implementado `SpectralScalingMode` (`Linear = 0`, `Decibels = 1`, `PerceptualPinkNoise = 2`) en `src/core/src/master_peak.rs`.
  - Incorporada la conversión a Decibelios ($D_{\text{floor\_db}} = -50.0\text{ dB}$) con inclinación perceptual de sonoridad por octava (+3 dB/octava, $T_i = (f_{c,i}/1000)^{0.15}$).
  - Expueta la entrada nativa FFI `echo_core_set_spectral_scaling_mode` en `src/core/src/ffi.rs`.
  - Agregadas pruebas deterministas unitarias en Rust (71/71 pruebas de Rust pasaron al 100%).
- **Capa C# UI:**
  - Importada `echo_core_set_spectral_scaling_mode` en `src/ui/Audio/EchoCoreNative.cs`.
  - Expuesto `TrySetSpectralScalingMode(SpectralScalingMode mode)` en `src/ui/Audio/AudioCoreService.cs`.
- **Verificación:**
  - `cargo test`: 71/71 pasaron.
  - `dotnet test`: 38/38 pasaron.
  - `dotnet build EchoVisualizer.sln -c Debug -p:Platform=x64`: 0 errores.

## Siguiente actividad autorizada

Completar la validación visual en vivo abriendo la aplicación desde el menú Inicio o mediante Debug en Visual Studio con archivos de audio reales en reproductor local o streaming.
