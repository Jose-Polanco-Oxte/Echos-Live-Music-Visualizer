# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** calibración natural de ganancia por banda del modo híbrido
- **Fecha:** 2026-08-05
- **Responsable:** Codex con dirección del usuario
- **Estado:** implementada; pendiente de comparación con audio real

## Fuente normativa

| ID | Sección | Regla | Aceptación |
|---|---|---|---|
| RF4.3 | Acondicionamiento dinámico LUFS | La ganancia de sonoridad se calcula antes de publicar el vector. | `G_LUFS` sigue siendo global y no se duplica por banda. |
| RF4.3.3 | Comparativa híbrida | Pico Maestro conserva un divisor común entre bandas. | El modo conserva la dinámica macro LUFS y la relación espectral medida. |
| RF4.3.4 | Calibración de ganancia natural | No aplicar ganancia dependiente de frecuencia adicional al vector FFT. | Una entrada de igual energía en dos bandas conserva la misma proporción antes de `tanh`. |

## Fórmula aprobada

Para el modo híbrido, después de obtener la energía FFT normalizada `E_i` y la
ganancia macro LUFS común `G[t]`:

```text
W_i = E_i                         (ganancia espectral H_i = 1.0)
E_LUFS,i = W_i * G[t]
M_frame = max_i(E_LUFS,i)
S_i = (E_LUFS,i / max(M_t, 0.05)) * 0.75
Y_i = tanh(S_i)
```

Se elimina exclusivamente del híbrido el tilt experimental
`(f_c/1000 Hz)^0.35`. La K-weighting ITU-R BS.1770-4 permanece en la medición
de `Lshort` que produce `G[t]`; no se reaplica por banda porque sería una
segunda ponderación espectral y reduciría adicionalmente el contenido grave.

## Mapeo y oráculo

| Archivo | Cambio | Oráculo determinista |
|---|---|---|
| `src/core/src/master_peak.rs` | `condition_hybrid_band_energies` usa sólo `E_i * G[t]`. | Con `E=[0.2,0.1]` y `G=1`, `atanh(Y_0)/atanh(Y_1)=2`. |
| `src/core/src/ffi.rs` | Sin cambio de ABI: modo `3` sigue publicando el mismo buffer. | La prueba FFI de modos sigue aceptando el modo híbrido. |

## Procedimiento manual

Con la misma fuente, volumen, bandas y pista, elegir Híbrido y comparar graves,
medios y agudos durante una sección sostenida. Confirmar que el CSV mantiene
`G` y `master_peak`, que no aparecen picos iniciales tras silencio y que la
altura global sigue adaptándose al programa. No declarar aprobado sin prueba de
audio real.
