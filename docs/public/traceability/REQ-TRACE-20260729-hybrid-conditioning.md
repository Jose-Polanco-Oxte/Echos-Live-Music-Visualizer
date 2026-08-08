# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** modo experimental híbrido: normalización macro LUFS y Pico Maestro micro
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** implementada; pendiente de comparación con audio real

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF4.3 | Módulo 4, acondicionamiento antes de FFI | El vector de energías se adapta antes de publicarse y queda en `[0,1]`. | El buffer preasignado se modifica in situ y todos los resultados son finitos. |
| RF4.3.3 | Módulo 4, comparativa híbrida | Tilt estático, ganancia LUFS macro, divisor de Pico Maestro y `tanh` en ese orden. | Un selector permite elegir las tres rutas experimentales sin reiniciar captura. |

## Fórmula transcrita e implementación aprobada

- `W_i = E_i * (f_c,i / 1000 Hz)^0.35`; la referencia de 1 kHz hace adimensional el tilt.
- `DeltaL = Lshort - (-14 LUFS)`. Si `Lshort < -50 LUFS` o `abs(DeltaL) <= 2 LU`, `Graw=1`; de otro modo `Graw=clamp(10^(-DeltaL/20), 0.5, 2.0)`.
- `G[t] = G[t-1] + 0.01 * (Graw - G[t-1])`; `E_lufs,i = W_i * G[t]`.
- `Mframe = max(E_lufs,i)`. En subida: `M[t]=M[t-1]+0.20*(Mframe-M[t-1])`; en bajada: `M[t]=M[t-1]*(1-0.003)`; finalmente `M=max(M,0.05)`.
- `S_i=(E_lufs,i/M)*0.75`, `C_i=S_i` y `Y_i=tanh(C_i)`.
- Tras silencio prolongado, el siguiente frame activo usa `G=1` y `M=max(Mframe,0.05)`.

La corrección gamma pivotada es opcional en la propuesta. Para esta primera
comparativa se fija implícitamente `gamma=1`, por lo cual `C_i=S_i`; esto
preserva las proporciones de bandas después del tilt. La decisión está en
`decision-QA-DEC-20260729-hybrid-conditioning.md`.

> **Sustituido para el modo híbrido:** RF4.3.4 y
> `REQ-TRACE-20260805-hybrid-natural-band-gain.md` eliminan el tilt de esta
> ruta. El modo Pico Maestro independiente de RF4.3.2 conserva su fórmula
> experimental original.

## Mapeo de implementación

| Requisito | Archivo y símbolo | Parámetros | Relación con la fórmula |
|---|---|---|---|
| RF4.3.3 macro | `src/core/src/loudness.rs`, `process_hybrid_samples` | −14 LUFS, −50 LUFS, ±2 LU, `[0.5,2]`, `alpha=0.01` | Calcula y suaviza el único `G` macro. |
| RF4.3.3 micro | `src/core/src/master_peak.rs`, `condition_hybrid_band_energies` | tilt .35, attack .20, decay .003, floor .05, target .75 | Aplica el divisor común y `tanh` in situ. |
| RF4.3.3 FFI/UI | `src/core/src/ffi.rs`, `src/ui/Audio/*`, `src/ui/MainWindow.*` | modo ABI `3`, selector de tres opciones | Cambia ruta antes de `AudioFrameData`; telemetría ya registra modo y `M`. |

## Oráculos de verificación

| Prueba | Oráculo determinista |
|---|---|
| `rf4_3_3_hybrid_lufs_uses_deadband_limits_and_slow_iir` | ±2 LU produce `G=1`; fuera de zona muerta se limita a `[0.5,2]` y el primer paso es 1% del objetivo. |
| `rf4_3_3_hybrid_master_resets_after_silence_and_keeps_common_divisor` | El retorno a actividad fija `M=max(Mframe,.05)` y el cociente previo a `tanh` conserva las proporciones ponderadas. |
| ABI y .NET | El modo `3` se acepta, la lectura FFI permanece válida y `master_peak >= .05`. |

## Procedimiento manual pendiente

1. Elegir **Híbrido LUFS + Pico maestro** y mantener fija la misma fuente,
   volumen, pista y número de bandas empleados para los otros dos modos.
2. Reproducir al menos 180 s incluyendo inicio después de silencio, sección
   tranquila y transitorio fuerte.
3. Confirmar que el CSV aumenta, contiene el modo y `master_peak`, y comparar
   altura inicial, altura sostenida y respuesta al transitorio contra los dos
   modos existentes. No promoverlo a producción sin esta prueba real.
