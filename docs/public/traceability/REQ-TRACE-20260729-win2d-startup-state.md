# Trazabilidad de corrección de arranque Win2D

- **Feature / incremento:** Corrección del crash de primer dibujo Win2D
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** implementada como endurecimiento; no fue la causa primaria del cierre nativo posterior

## Fuente normativa

| ID de requisito | Sección exacta | Regla | Criterio de aceptación |
|---|---|---|---|
| RF5.2 | `Especificacion-de-requerimientos.md` §Módulo 5 | La entrega al renderizador no debe interrumpir el flujo en tiempo real. | La interfaz permanece viva antes y después del primer frame. |
| RF6.1.1–RF6.1.3 | `Especificacion-de-requerimientos.md` §RF6.1 | Splash y disclaimer anteceden al renderizado activo. | Ningún callback de dibujo falla durante splash o disclaimer. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Regla aplicada |
|---|---|---|
| RF5.2 / RF6.1 | `Win2DSpectralBarVisualizer` constructor | `EnsureBufferSize()` se ejecuta antes de suscribir `Canvas_Draw`; el primer callback dispone de `BarCount` entradas aunque todavía no exista `AudioFrameData`. |

## Verificación

| Prueba | Resultado esperado |
|---|---|
| Smoke MSIX instalado, 30 s sin aceptar disclaimer | El proceso sigue vivo y no aparecen eventos Application Error para EchoVisualizer. La investigación posterior aisló que el cierre nativo persiste incluso con este host oculto, por lo que esta protección no se presenta como causa raíz. |
| Smoke posterior a aceptación y lectura de frame | El proceso permanece vivo y el renderizador consume el buffer preasignado. |
