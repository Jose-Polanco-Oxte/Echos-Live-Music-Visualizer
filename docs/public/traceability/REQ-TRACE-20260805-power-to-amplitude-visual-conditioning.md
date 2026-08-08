# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** conversión de potencia espectral a amplitud visual,
  eliminación de controles LUFS/Gamma de prueba y telemetría temporal
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.2 | `Especificacion-de-requerimientos.md` §RF1.2 | `P[k] = (1/C) * sum_c |X_c[k]|^2`; conservar potencia por canal hasta la integración | Las proporciones de potencia entre bandas no se alteran en Core |
| RF1.3 | §RF1.3 | `E_i in [0,1]`, bandas dinámicas e integración continua | Ninguna banda estructuralmente vacía; salida finita |
| RF4.3 | §RF4.3 | `Efinal_i = clamp((E_i * G)^gamma, 0, 1)`; `G = 10^(-DeltaL/20)` | La ganancia LUFS se aplica en amplitud visual y queda acotada |
| RF4.3.4 | §RF4.3 / addendum HI-FI | Pico Maestro común, `Htarget=0.75`, `Pfloor=0.05`, `Y=tanh((A_i/Pmaster)*Htarget)` | Un divisor común conserva relaciones; RMS 0.01/0.1/0.5 produce salida finita y visible proporcional |
| RF5.1 | §FFI/ABI v2 | Los buffers se leen bajo lease y no se asignan por tick | Telemetría no copia el vector ni cruza la vida del lease |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF1.2 | `src/core/src/stft.rs` :: `StftAnalyzer::analyze_windows` | `power_scale`, `power[k]` | Produce potencia normalizada `|X|^2`; no se modifica como fuente analítica |
| RF4.3.4 | `src/core/src/master_peak.rs` :: `condition_hybrid_band_energies` | `amplitude_i=sqrt(power_i)`, `master_peak`, `MASTER_HEADROOM_TARGET` | Convierte a amplitud antes de aplicar `G`, divisor común y `tanh` |
| RF5.1 | `src/ui/Audio/AudioFrame.cs` :: `AudioFrameLease` | `RawBandEnergies`, `ConditionedBandEnergies` | Telemetría agrega spans dentro de la vida del lease |
| RF5.1 | `src/ui/Audio/SpectralTelemetryRecorder.cs` | `raw_power`, `amplitude`, `master_peak`, `conditioned` | CSV temporal a 250 ms, medias y máximos, sin almacenar vectores |
| UX | `src/ui/MainWindow.xaml` / `MainWindow.xaml.cs` | Híbrido fijo | Se eliminan los combos de prueba LUFS/Gamma y escalado |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF1.2/RF4.3.4 | `master_peak` tests de proporción común y conversión de potencia | Potencias 0, subnormales y no finitas | PASS: `cargo test --lib` 70/70 |
| RF4.3.4 | `hybrid_power_to_amplitude_is_monotonic_for_representative_rms_levels` | RMS 0.01, 0.1 y 0.5; `0 <= output <= 1` | PASS: `cargo test --lib` 70/70 |
| RF5.1 | `SpectralTelemetryRecorder` agrega spans durante el lease | CSV a 250 ms, sin almacenar vectores | PASS: compilación Debug x64 |
| UX | Build y prueba de referencias XAML/C# | No deben existir controles ni textos de prueba | PASS: .NET 39/39, 0 advertencias |

## Desviaciones o decisiones

La potencia se conserva para el análisis normativo. La conversión `sqrt(P)` se
realiza sólo en la frontera de acondicionamiento visual para que el piso y el
headroom del Pico Maestro permanezcan en unidades de amplitud. Los modos de
prueba LUFS/Gamma y el selector de escalado fueron retirados de la UI; el Core
inicia Híbrido por defecto y conserva los símbolos ABI antiguos sólo para
compatibilidad.
