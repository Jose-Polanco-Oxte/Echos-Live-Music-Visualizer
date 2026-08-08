# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Densidad espectral real para ecualizador de barras
- **Fecha:** 2026-07-29
- **Responsable:** agente de desarrollo
- **Estado:** implementada; smoke de apariencia con audio real pendiente

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.3 | `Especificacion-de-requerimientos.md` §Módulo 1 | Para `N > 3`, generar `E = [E_1, ..., E_N]`, con `E_i in [0.0, 1.0]`, en escala logarítmica/Mel/lineal. | El Core publica el mismo número de bandas solicitado por el visualizador. |
| RF-EQ.1 | `Especificacion-de-requerimientos.md` §RS-EB | Seleccionar `N in [12, 128]`; agrupar FFT en escala logarítmica/Mel. | El selector de barras reconfigura también el Core, no sólo las figuras XAML. |
| RF-EQ.2 | `Especificacion-de-requerimientos.md` §RS-EB | `v_i[t] = E_i[t]` en ataque; en caída `alpha_decay*v_i[t-1] + (1-alpha_decay)*E_i[t]`, `alpha_decay in [0.85,0.95]`. | Se conserva ataque instantáneo y decay 0.90; no se interpola entre bandas reales de igual cardinalidad. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF1.3 / RF-EQ.1 | `AudioCoreService` y `MainWindow` :: configuración de bandas | `N = 12..128`, `scale_type = 0..2`. | Invoca `set_band_configuration` del FFI al iniciar y cambiar el selector. |
| RF-EQ.2 | `SpectralBarMath` :: muestreo de barra | `source.Length == targetCount`. | `E_i` se entrega directamente a `v_i`; el remapeo logarítmico sólo se usa si hay cardinalidades distintas. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF1.3 / RF-EQ.1 | Prueba FFI que solicita 48 bandas y verifica longitud publicada. | Rechazar `N < 12` para el perfil RS-EB y escala fuera de 0..2. | **Aprobado**: `AudioCoreService_ConfiguresTheNormativeSpectralBarsProfile`. |
| RF-EQ.2 | Prueba de muestreo directo y de ecuación de decay existente. | Vector heterogéneo; preservar cada valor cuando `N` coincide. | **Aprobado**: `LogarithmicSampling_PreservesEveryNativeBandWhenCountsMatch`; 0.90 continúa cubierto por la ecuación existente. |

El MSIX `1.0.0.24` instalado publicó `80 bandas` y RMS real en la interfaz;
la densidad observada procede de Core, no de interpolar el vector de tres
bandas de respaldo.

## Desviaciones o decisiones

Ninguna. El fallback de tres bandas continúa válido sólo para consumidores que
lo soliciten explícitamente; RS-EB solicita siempre densidad `N >= 12`.
