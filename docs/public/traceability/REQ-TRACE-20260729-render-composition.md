# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Corrección RS-EB, variantes 2D y composición de transición
- **Fecha:** 2026-07-29
- **Responsable:** agente render_composition
- **Estado:** implementada (composición híbrida: aproximación temporal documentada)

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF-EQ.1 | Especificación §IV RS-EB | `N in [12,128]`, agrupación logarítmica/Mel | El control limita N y el muestreo usa posición logarítmica. |
| RF-EQ.2 | Especificación §IV RS-EB | Si `E >= v_prev`, `v=E`; si no, `v=alpha_decay*v_prev+(1-alpha_decay)*E`, `alpha_decay in [0.85,0.95]` | Ataque inmediato y prueba exacta con alpha=0.90. |
| RF-EQ.3 | Especificación §IV RS-EB | Hue según frecuencia central relativa `fi`, fase global según centroide `fC` | Prueba comprueba cambio de color por frecuencia y centroide. |
| RF-EQ.4 | Especificación §IV RS-EB | Bottom-Up, Top-Down y Center-Out | Las tres geometrías quedan disponibles; mirror usa Center-Out. |
| RF-EQ.5.1-.3 | Especificación §IV RS-EB | Gap desde `0`; radio configurable; peak hold opcional con descenso independiente | Pruebas de clamp y de descenso de pico. |
| RF-EQ.6.1-.2 | Especificación §IV RS-EB | Bloom configurable por RMS; reflejo con opacidad decreciente y desenfoque progresivo | Capas paramétricas sin elementos XAML por barra. |
| RF-EQ.7 | Especificación §IV RS-EB | Onset aumenta brillo/opacidad superior | El modo Pulse añade impulso temporal al onset. |
| RF6.4.6-.7 | Especificación §I Módulo 6 | Cross-fade configurable; receptor toma RMS, fC y bandas del instante de cambio; onset preferente | Estado de transición mantiene ambos extremos, snapshot y pesos complementarios. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF-EQ.1-.7 | `Win2DSpectralBarVisualizer`, `SpectralBarMath` | `Decay=0.90`, `Gap>=0`, `CornerRadius`, `PeakHoldEnabled`, bloom/reflection | Fórmulas puras ejercitadas por pruebas; renderer sólo dibuja su resultado. |
| RF6.4.6-.7 | `VisualizerTransitionState` | duración 0.5-2.0 s, snapshot de frame | Pesos `out=1-progress`, `in=progress`; snapshot inmutable inicial. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF-EQ.1-.7 | `SpectralBarMathTests` | N=12/128, Gap=0, ataque/decay, pico, color, onset | 5/5 aprobadas el 2026-07-29 |
| RF6.4.6-.7 | `VisualizerTransitionStateTests` | inicio, mitad, final, snapshot independiente | 2/2 aprobadas el 2026-07-29 |
| RF-EQ.6 | Inspección Win2D en GPU | blur/reflejo visible con RMS 0/1 | pendiente de GPU real |

## Desviaciones o decisiones

La superficie D3D11 de composición actual no se puede importar de forma segura desde Win2D sin que el host proporcione un `CanvasDevice` interoperable y gestione handles compartidos. Se entrega el estado de transición puro para que ambas instancias reciban el snapshot exacto y se registra la interop híbrida como aproximación temporal en `decision-QA-DEC-20260729-hybrid-render-interop.md`.
