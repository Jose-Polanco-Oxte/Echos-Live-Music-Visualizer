# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Refactorización DSP HI-FI: captura, STFT y bandas
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** propuesta

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.1 | Módulo 1, ingesta | `f_a=48,000 Hz`, `H=512 frames/canal`, PCM de 1–8 canales y SPSC mínimo de 16,384 frames/canal. | Muestras por canal continuas, ordenadas y sin bloqueo. |
| RF1.2 | Módulo 1, STFT | STFT deslizante con `Nfft=4096/2048/1024` y ventana Blackman-Harris de cuatro términos. | Cada hop analiza las tres ventanas preasignadas. |
| RF1.3–RF1.4 | Módulo 1, bandas/fusión | ERB por defecto; cruces coseno al cuadrado 200–300 Hz y 3800–4200 Hz. `P_fused=W_A P_A+W_B P_B`. | Cobertura 20 Hz–20 kHz, sin bandas estructuralmente vacías ni discontinuidad en cruces. |
| RNF-REL.1–2 | Fiabilidad | SPSC sin locks; callback no bloqueante, con telemetría de underflow/overflow/drops. | No hay pérdida/reordenamiento en fixtures ni `NaN`/`Infinity`. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF1.1 | `capture.rs`, `preprocess.rs`, `spsc.rs` | `H`, `f_a`, carriles por canal | Captura continua y resampling por canal al ring. |
| RF1.2 | `stft.rs`, `multiresolution.rs` | `Nfft`, ventana BH4, hop 512 | Tres STFT sobre historial común de 4096 frames/canal. |
| RF1.3–1.4 | `bands.rs`, `multiresolution.rs` | ERB, perfiles log-octava, `W_A/W_B` | Integración continua de potencia fusionada. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF1.1 | Fixtures de paquetes irregulares y resampling 44.1/48/96 kHz por canal | antifase, underflow, overflow | pendiente |
| RF1.2 | Tonos en 20–250 Hz y tests de fuga contra rectangular/Hamming | tonos entre bins | pendiente |
| RF1.3–1.4 | Monotonía ERB/log-octava, cobertura y continuidad de cruces | silencio y bandas estrechas | pendiente |
| RNF-REL | Stress productor/consumidor | sin esperas ni no-finitos | pendiente |

## Desviaciones o decisiones

Decisiones QA pendientes vinculadas: normalización multicanal, Blackman-Harris,
ERB frente a log-octava y política SPSC. La interpolación continua actual se
conservará durante la migración, pero no sustituye la integración HI-FI.
