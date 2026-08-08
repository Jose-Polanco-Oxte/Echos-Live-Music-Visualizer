# REQ-TRACE-20260729-XAML-RENDER-FALLBACK

- **Fecha**: 2026-07-29
- **Área**: RF5.2, RF6.3, RF6.4.6–7
- **Cambio**: sustituir la superficie `CanvasControl` de Win2D por un lienzo XAML administrado para las variantes 2D.

## Evidencia del incidente

Con Windhawk detenido, fuente demo, `Canvas_Draw` vacío y sin solicitudes de invalidación, la aplicación instalada siguió finalizando con `coreclr.dll` y `0xc0000005` al hacer visible `CanvasControl`. La aceptación del aviso, temporizador, lectura demo y actualización del view model fueron estables en variantes aisladas.

## Invariantes funcionales

- La envolvente mantiene ataque instantáneo y decay `0.90 * previo + 0.10 * energía`.
- `Gap=0`, peak-hold, glow, reflexión, color por frecuencia/centroide y las variantes barras/espejo/pulso se conservan en el renderizador administrado.
- El cross-fade 2D conserva dos lienzos XAML activos y opacidades complementarias.

## Verificación prevista

1. Ejecutar la aplicación instalada con Windhawk detenido durante 60 s y alternar todas las variantes 2D.
2. Confirmar que no hay `Application Error` para `EchoVisualizer` desde el inicio de la prueba.
3. Ejecutar pruebas unitarias de geometría, decay, colores y transición.

La ruta D3D11 queda fuera de la prueba de esta corrección y no se activa desde la selección 2D.
