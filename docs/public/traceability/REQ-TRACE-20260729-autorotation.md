# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Autorrotación, Visual Match y fundido 2D
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** propuesta

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.4.1–4 | §RF6.4 | Rotación configurable (5–300 s), orden o aleatoria y sólo favoritos opcional. | Se persiste en `AutoRotation`; el siguiente catálogo se selecciona con esas reglas. |
| RF6.4.6 | §4.1 y RF6.4.6 | Fundido: alpha saliente = 1 - t/T; entrante = t/T; T en [0.5,2] s. | El host aplica opacidad de transición sin corte de un frame. |
| RF6.4.7 | §4.2 y RF6.4.7 | Esperar `Onset == true` o salvaguarda de 1.5 s antes del cambio. | El cambio se inicia en onset o al límite y conserva frame RMS/centroide/bandas. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.4 | `MainWindow` | `IntervalSeconds`, `pendingSince`, `fadeStarted`, 1.0 s de fade. | El temporizador de 60 Hz usa el frame actual para resolver la espera y progreso. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.4.1–7 | Pruebas de ViewModel existentes y procedimiento manual. | Lista vacía/favoritos vacíos, onset ausente, intervalo mínimo. | pendiente |

## Desviaciones o decisiones

El actual catálogo 2D no mantiene dos renderizadores independientes; el fundido
aplica una opacidad del host mientras cambia el estado. La composición 2D/3D
dual queda a cargo de la integración del renderer 3D.
