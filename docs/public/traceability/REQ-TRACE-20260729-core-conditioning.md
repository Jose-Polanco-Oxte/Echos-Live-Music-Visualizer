# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Ingesta PCM normalizada y acondicionamiento LUFS en la ruta FFI.
- **Fecha:** 2026-07-29
- **Responsable:** Core agent
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.1 | `Especificacion-de-requerimientos.md` §Módulo 1 / RF1.1; plan Fase II Módulo 0 | PCM a 44.1 kHz o 48 kHz, bloques N de 512 a 1024 muestras; el plan exige downmix multicanal y `rubato` para normalizar a 48 kHz. | Cada callback produce audio mono continuo a 48 kHz y sólo se publican bloques completos N. |
| RF4.1 | `Especificacion-de-requerimientos.md` §Módulo 4 / RF4.1 | Aplicar K-weighting: high-shelf +4 dB sobre 1.5 kHz seguido de RLB high-pass bajo 100 Hz. | La ruta que entrega FFI procesa muestras por los dos biquads antes de medir sonoridad. |
| RF4.3 | `Especificacion-de-requerimientos.md` §Módulo 4 / RF4.3 | `Lshort=-0.691+10log10(sum(Gi zi))`, `DeltaL=Lshort-Ltarget`, `Graw=10^(-DeltaL/20)`, `gamma=1+(2.2-1)tanh(DeltaL/6)`, IIR alpha=0.03 y `Efinal=clamp((E*G)^gamma,0,1)`; Ltarget=-14 LUFS. | Las bandas publicadas por FFI se acondicionan con esos defaults; modo manual usa gain/gamma del cliente. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF1.1 | `src/core/src/preprocess.rs` :: `AudioPreprocessor`; `capture.rs` :: `capture_loop_inner` | 44_100 / 48_000 / 96_000 Hz; N=512..=1024 | Downmix `sum(C)/C`, `SincFixedIn` de rubato y acumulador de salida que emite N muestras consecutivas. |
| RF4.1 / RF4.3 | `src/core/src/loudness.rs` :: `LoudnessProcessor`; `ffi.rs` :: `AudioEngine::process_*` | -14 LUFS, 1.0, 2.2, 6 dB, 0.03 | `process_samples` calcula el ajuste y `condition_band_energies` transforma exactamente el vector que se expone por `AudioFrameData`. |
| RF4.3 | `src/core/src/ffi.rs` :: `set_lufs_mode` | mode=0 automático; mode=1 manual; gain/gamma f32 | El ABI conserva el modo en el motor y lo aplica al siguiente frame sin reasignar el vector de bandas. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF1.1 | Pruebas de downmix, 44.1→48, 96→48, continuidad entre callbacks y tamaño de bloque | Muestras no finitas, callback parcial y N=512/1024 | aprobado: `cargo test` (2026-07-29) |
| RF4.1 / RF4.3 | Pruebas K-weighting, defaults, manual/automático, clamp y publicación FFI | Silencio, energía no finita, valores fuera de rango | aprobado: `cargo test` y `cargo clippy -- -D warnings` (2026-07-29) |

## Desviaciones o decisiones

Ninguna. `rubato::SincFixedIn` usa interpolación sinc de longitud fija (FIR polifásico) y un acumulador hace que paquetes WASAPI de longitud variable no alteren la continuidad ni el tamaño de bloque publicado.
