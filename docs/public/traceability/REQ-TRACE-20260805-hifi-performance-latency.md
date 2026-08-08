# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Métricas de rendimiento y latencia HI-FI
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** benchmark offline reproducible agregado; validación integrada pendiente

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RNF-PERF.1 | Rendimiento | `L_c`: hop de entrada a frame publicado, objetivo p99 < 1.5 ms en hardware de referencia. `L_g` se reporta por ventana; no es latencia de cómputo. | Medición Release reproducible, no inferida. |
| RNF-PERF.2 | Rendimiento | Render >=60 FPS, objetivo 120 FPS. | Medición a 60/120 FPS. |
| RNF-PERF.3 | Rendimiento | Worker DSP separado del render. | El render sólo consume el último frame. |
| RF5.1 | Módulo 5 | Desacoplar cálculo acústico del proceso gráfico. | Polling FFI no incrementa el contador FFT. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RNF-PERF.1 | scheduler DSP, telemetría FFI | `compute_latency_us`, `L_g`, timestamps | Registra p50/p95/p99 por hop. |
| RNF-PERF.2–3 | UI y benchmark | FPS, asignaciones, working set | Render a cadencia propia y sin DSP. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RNF-PERF.1 | `scripts/Run-DspBenchmark.ps1` en Release con fixtures deterministas | p50/p95/p99; el harness no representa hardware/audio real | parcial: CSV `artifacts/benchmarks/dsp-offline-20260805-132556.csv`; p99 7–17 us en ejecución local |
| RNF-PERF.2–3 | perfil 60/120/144 Hz y contador FFT | no confundir `L_g` con `L_c` | pendiente |

## Desviaciones o decisiones

Los valores de rendimiento no se declararán aprobados sin audio, GPU y hardware
de referencia. La política de medición y overflow se vincula a QA. El primer
wrapper falló al observar el código de salida del proceso; quedó registrado en
`incident-QA-INC-20260805-benchmark-wrapper-exitcode.md` y corregido antes de
la ejecución válida.
