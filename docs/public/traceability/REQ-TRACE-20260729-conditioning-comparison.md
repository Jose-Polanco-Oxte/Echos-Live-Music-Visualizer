# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** comparativa de acondicionamiento estabilizado LUFS y Pico Maestro
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** implementada; pendiente de comparación con audio real

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF4.3 | Módulo 4, ecuación final | La salida vigente es `clamp((E_i * G)^gamma, 0, 1)` con objetivo −14 LUFS. | Se conserva como referencia y no se modifica silenciosamente. |
| RF4.3.1 | Módulo 4, calibración contra colapso | Instrumentar antes de alterar parámetros; separar DSP de render. | Comparativa A/B registrada con valores pre/post y bloques nuevos. |
| RF4.3.2 | Módulo 4, comparativa experimental | Dos modos de prueba seleccionables: LUFS estabilizado con pivote y Pico Maestro con headroom. | Cada modo mantiene salida finita `[0,1]`, sin asignaciones por frame y con pruebas matemáticas. |

## Fórmulas aprobadas para la comparativa

### Modo A: LUFS estabilizado con pivote

- Puerta de silencio: RMS `<= −50 dBFS` restablece `G=1`, `gamma=1` y no adapta con silencio.
- Zona neutra de contraste: `d = max(DeltaL − 1.5 LU, 0)`.
- `Graw = clamp(10^(−DeltaL/20), 0, 8)` y `G[t] = 0.03*Graw + 0.97*G[t−1]` fuera de silencio.
- `gammaRaw = 1 + 1.2*tanh(d/6)` y `gamma[t] = 0.03*gammaRaw + 0.97*gamma[t−1]`.
- Con `P=0.02`, `x=clamp(E_i*G,0,1)` y `Efinal=clamp(P*(x/P)^gamma,0,1)`.

El pivote queda invariante; sobre `P` gamma aumenta contraste y por debajo de
`P` lo reduce. La zona neutra evita activar contraste por variaciones pequeñas
alrededor de −14 LUFS.

### Modo B: Pico Maestro con headroom

- Inclinación estática dimensionalmente normalizada: `W_i=E_i*(f_c,i/1000 Hz)^0.35`.
- `Mframe=max_i(W_i)`.
- Si `Mframe>Mprev`, `M=Mprev+0.20*(Mframe−Mprev)`; en otro caso, `M=Mprev*(1−0.003)`.
- `M=max(M,0.05)`. Con RMS `<=−50 dBFS`, se congela `M`.
- `S_i=(W_i/M)*0.75`; `Y_i=tanh(S_i)`.

La formulación respeta exactamente el limitador suave propuesto. Por ello, un
valor de entrada `S=0.75` produce `tanh(0.75)≈0.635`; la interpretación de
"75%" se validará visualmente y no se normaliza sin una decisión posterior.

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF4.3.2 A | `src/core/src/loudness.rs` | −50 dBFS, 1.5 LU, `P=0.02`, `alpha=0.03`. | Acondicionamiento pivotado sin alterar el vector publicado. |
| RF4.3.2 B | `src/core/src/master_peak.rs` | tilt 0.35 relativo a 1 kHz; ataque 0.20; decay 0.003; piso 0.05; target 0.75. | Un divisor maestro común tras ponderación estática. |
| RF4.3.2 | `src/core/src/ffi.rs`, `src/ui/Audio/*`, `src/ui/MainWindow.*` | `set_conditioning_mode` y `ToggleSwitch` de prueba. | Conmuta ruta antes de publicar `AudioFrameData`; CSV añade modo y `master_peak`. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF4.3.2 A | `rf4_3_2_stabilized_mode_resets_after_silence_and_has_a_gamma_deadband`; `rf4_3_2_pivot_preserves_reference_and_increases_only_upper_contrast`. | Cero, no finitos, `E=P`, `E<P`, `E>P`. | Correctas. |
| RF4.3.2 B | `rf4_3_2_master_peak_uses_the_asymmetric_equation_and_floor`; `rf4_3_2_master_peak_freezes_during_silence_and_uses_a_common_divisor`. | Silencio, primer pico, valores por encima de 1. | Correctas. |
| RF4.3.2 FFI | Rust `rf4_3_2_exposes_both_comparison_modes_through_the_abi` y .NET `AudioCoreService_SwitchesBothRf4_3_2ConditioningModes`. | Selector válido e invalido; diagnóstico de Pico Maestro. | Correctas. |
| RF4.3.1 | Sesiones A/B con las cuatro pistas del protocolo existente. | 100% bloques nuevos; registrar métricas pre/post. | pendiente de audio real. |

## Desviaciones o decisiones

La ecuación normativa RF4.3 permanece disponible como referencia. La frecuencia
del tilt se expresa relativa a 1 kHz para que el exponente 0.35 sea adimensional;
véase la decisión QA `QA-DEC-20260729-conditioning-comparison`.

## Procedimiento manual de comparación

1. Mantener fija fuente, volumen de Windows, número de bandas y pista.
2. Elegir **LUFS estabilizado (pivote)**, esperar cinco segundos y reproducir
   al menos 180 s; confirmar que el contador de muestras aumenta.
3. Elegir **Pico maestro (75%)**, esperar cinco segundos y repetir el mismo
   fragmento. El CSV debe registrar `conditioning_mode` y `master_peak`.
4. Comparar altura inicial, mediana de energía posterior, picos y evolución del
   divisor. No aprobar defaults de producción hasta completar los cuatro géneros
   definidos por VA1.
