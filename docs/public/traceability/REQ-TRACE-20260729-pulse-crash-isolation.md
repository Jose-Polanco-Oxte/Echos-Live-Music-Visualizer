# REQ-TRACE-20260729-PULSE-CRASH-ISOLATION

- **Feature**: aislamiento del fallo al seleccionar Pulso espectral.
- **Requisitos**: RF-EQ.5, RF-EQ.7, RF6.3.2, RF6.4.6–7.
- **Estado**: `[OBSOLETO / RETIRADO DE ALCANCE - SECCIÓN IV]` (Pulso Espectral fue retirado del catálogo ejecutable según la Sección IV de `Especificacion-de-requerimientos.md`).

## Regla normativa transcrita

RF-EQ.7: el descriptor `Onset` incrementa temporalmente el brillo u opacidad de la zona superior de las barras o sus marcadores de pico. RF6.3.2 exige iniciar y desplegar inmediatamente el visualizador seleccionado. RF6.4.6–7 exige que el cambio conserve ambos visualizadores durante el fundido y que el entrante parta de RMS, `fC` y bandas del frame de cambio.

## Evidencia y oráculo

En el paquete 1.0.0.19, con Windhawk detenido, seleccionar el texto visible **Pulso espectral** finaliza `EchoVisualizer.exe` con `0xc0000005` en `coreclr.dll`. El oráculo inmediato compara la misma transición con la variante Pulse desactivada temporalmente: si sobrevive, el impulso Pulse es la causa; si falla, lo es la composición de transición.

## Límites de la intervención

No se modificarán las fórmulas de envolvente ni de onset. La variante temporalmente desactivada sólo se utilizará para localizar el fallo; no se declarará conforme con RF-EQ.7 hasta reintroducir un impulso seguro y verificable.
