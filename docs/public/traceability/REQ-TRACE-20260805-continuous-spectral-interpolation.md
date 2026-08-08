# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Interpolación espectral continua para bandas dinámicas
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.2 | Módulo 1, Descomposición Frecuencial | `X[k] = sum(x[n] * w[n] * exp(-j 2*pi*k*n/N))` con ventana Hamming/Hanning. | Las magnitudes FFT siguen siendo la fuente de energía. |
| RF1.3 | Módulo 1, Agrupación Espectral | N bandas configurables Log/Mel/Lineal y un vector continuo de energía de tamaño variable. | Ninguna banda configurada queda estructuralmente sin muestra FFT. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF1.3 | `src/core/src/analysis.rs` :: `aggregate_bands` | `f = start + (j + 0.5)/M * (end-start)`, `M=max(1, ceil((end-start)/bin_width))`. | Para cada punto se interpola `abs(X[f])` linealmente entre bins contiguos y se calcula RMS de las muestras. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF1.3 | `analysis::tests::{interpolates_magnitude_between_adjacent_fft_bins, continuous_aggregation_covers_every_logarithmic_low_band, logarithmic_band_centres_react_to_low_frequency_tones}`. | Bandas 20–28.3, 28.3–39.9 y 56.4–79.6 Hz no pueden ser cero estructural. | aprobado en `cargo test` (2026-08-05) |

## Desviaciones o decisiones

Ver [QA-DEC-20260805-CONTINUOUS-SPECTRAL-INTERPOLATION](../../.agents/qa/logs/decision-QA-DEC-20260805-continuous-spectral-interpolation.md). FFT N=2048 se mantiene fuera de este incremento y está registrada como issue local.
