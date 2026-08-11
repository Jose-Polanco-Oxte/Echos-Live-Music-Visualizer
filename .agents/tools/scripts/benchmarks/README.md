# Benchmarks y procedimiento V&V

## Benchmark offline reproducible

Desde la raíz del repositorio, con Rust estable instalado:

```powershell
pwsh -File .\.agents\tools\scripts\Run-DspBenchmark.ps1 -Iterations 2000
```

El script compila el harness en `Release`, genera fixtures deterministas y
guarda CSV/JSON en `artifacts/benchmarks/` (esa salida local no es evidencia de
hardware). `L_c` es el tiempo de `DspProcessor::process_into` medido con
`Instant` y se reporta por fixture en p50/p95/p99 (microsegundos). También se
capturan working set y CPU del proceso del harness. `drops`, `overflows`,
`underflows` y `sequence_ok` describen el recorrido offline; no sustituyen la
telemetría de captura WASAPI.

Fixtures: tono 1 kHz, sweep 20–500 Hz, ruido determinista, subgrave 32 Hz y
rock/electrónica/percusión sintéticos. También se incluye un marcador de
contrafase mono (`antiphase_mono_surrogate`) para mantener la matriz de casos;
la cancelación estéreo real requiere el analizador multicanal/captura y no se
declara cubierta por este harness mono. Las pistas musicales, entradas
44.1/48/96 kHz, WASAPI loopback/entrada directa y GPU requieren validación
adicional en el entorno real.

## Estado V3–V6 y VA1–VA5

Este procedimiento prepara, pero no aprueba, la aceptación completa:

| ID | Procedimiento | Estado actual |
|---|---|---|
| V3 | Ejecutar Release con audio real y comparar `L_c` p99, `L_g` por ventana y extremo a extremo contra RNF-PERF.1/RNF-PERF.2 | Pendiente: audio/hardware real |
| V4 | Medir FPS sostenido 1080p y 4K en GPU de referencia, incluido working set y drops | Pendiente: GPU real |
| V5 | Mantener captura/render 24 h y revisar secuencias, memoria, drops y recuperación | Pendiente: endurance real |
| V6 | Cambiar visualizadores durante reproducción y verificar handoff/cross-fade ≤16.6 ms | Pendiente: aplicación/GPU real |
| VA1 | Reproducir EDM, clásica, rock/metal y voz; registrar percepción, pumping y pasajes suaves | Pendiente: audio real y evaluación humana |
| VA2 | Ejecutar splash, disclaimer, fullscreen, cursor y cambio de fuente | Pendiente: UX manual |
| VA3 | Verificar que el inicio del cross-fade coincide con `Onset` | Pendiente: audio/GPU real |
| VA4 | Conectar/desconectar dispositivos y verificar hot-plug/conmutación | Pendiente: hardware WASAPI |
| VA5 | Crear, editar, recargar y recuperar presets JSON corruptos | Pendiente: ejecución manual integrada |

No se deben marcar estos casos como aprobados usando únicamente el benchmark
offline. La evidencia debe incluir fecha, hardware, fuente de audio, duración,
configuración y artefactos generados.
