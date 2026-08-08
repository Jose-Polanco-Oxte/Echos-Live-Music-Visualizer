# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Escalado espectral visual logarítmico en decibelios (dB) con compensación perceptual de sonoridad por octava (+3 dB/octava)
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.3 | `Especificacion-de-requerimientos.md` §RF1.3 | `E_i in [0,1]`, bandas dinámicas e integración continua | Ninguna banda aguda estructuralmente inactiva o vacía ante señal audible |
| RF4.3.4 | §RF4.3 / addendum HI-FI | Pico Maestro común, `Htarget=0.75`, `Pfloor=0.05`, acondicionamiento de magnitud visual | `Y_final` se mantiene acotado en `[0.0, 1.0]` con dynamic range en dB y dinamismo balanceado en altas frecuencias |
| RF5.1 | §FFI/ABI v2 | Los buffers se leen bajo lease y no se asignan por tick | La transformación logarítmica dB se ejecuta en Rust sin GC ni asignaciones en C# |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF4.3.4 | `src/core/src/master_peak.rs` :: `MasterPeakScaler` | `MASTER_VISUAL_DB_FLOOR = -50.0`, `MASTER_PINK_NOISE_EXPONENT = 0.15` | Aplica $L_i = 20 \log_{10}(S_i)$ y $T_i = (f_c/1000)^{0.15}$ acotando en $[0.0, 1.0]$ |
| RF5.1 | `src/core/src/ffi.rs` :: `echo_core_set_spectral_scaling_mode` | `SpectralScalingMode` (Linear, Decibels, PerceptualPinkNoise) | Permite configurar el modo de escalado FFI |
| RF5.1 | `src/ui/Audio/EchoCoreNative.cs` | `LibraryImport` | Declara la entrada nativa C# sin copias de arreglos |
| RF5.1 | `src/ui/Audio/AudioCoreService.cs` | `SetSpectralScalingMode` | Expone la llamada al motor de audio C# |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF4.3.4 | `rf4_3_4_hybrid_decibel_scaling_bounds` en `master_peak.rs` | $E_i \to 0 \implies 0.05$; $E_i \to 1.0 \implies \le 1.0$ | PASS: `cargo test` |
| RF4.3.4 | `rf4_3_4_high_frequency_reactivity` en `master_peak.rs` | Señal $0.01$ en $10\text{ kHz}$ pasa de $0.037$ a $\ge 0.30$ | PASS: `cargo test` |
| RF5.1 | `dotnet test tests/EchoVisualizer.Tests/` | 100% de la suite de pruebas .NET FFI | PASS: `dotnet test` |
| UX | Ejecución y prueba visual en Debug x64 con música real | Las barras de agudos ($>6\text{ kHz}$) se mueven vivamente | PASS: Manual |
