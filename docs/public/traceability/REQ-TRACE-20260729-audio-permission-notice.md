# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Declaración y aviso de permisos de audio del paquete MSIX
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** implementada; validación visual VA2 pendiente de aceptación manual

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.2.2 | `Especificacion-de-requerimientos.md` §RF6.2 | El selector detecta entradas, micrófonos, líneas y bucles virtuales. | El manifiesto declara acceso de micrófono y el usuario recibe un aviso antes de iniciar la captura. |
| RF6.1.3 | `Especificacion-de-requerimientos.md` §RF6.1 | El disclaimer debe ser legible y requerir espera/aceptación. | El aviso de permisos forma parte del disclaimer y no inicia render/captura hasta aceptarse. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.2.2 | `src/ui/Package.appxmanifest` :: `DeviceCapability` | `microphone` y `runFullTrust`. | Windows conoce el permiso usado por captura directa; no se declara red, cámara ni ubicación. |
| RF6.1.3 | `src/ui/MainWindow.xaml` :: `DisclaimerPanel` | Texto visible y botón bloqueado 3 s. | Explica captura local y solicita aceptación previa. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.2.2 | Inspeccionar manifiesto dentro del MSIX e instalar paquete firmado de desarrollo. | La aplicación sólo solicita acceso al seleccionar una entrada directa. | Paquete firmado, verificado e instalado como `EchoVisualizer_1.0.0.0_x64__htdmg3bkztkej`. |
| RF6.1.3 | VA2: abrir paquete recién instalado y comprobar aviso antes de aceptar. | El botón permanece deshabilitado durante la cuenta regresiva. | Aplicación instalada y lanzada; pendiente de confirmación visual manual del aviso y cuenta regresiva. |

## Desviaciones o decisiones

El instalador Windows decide la presentación exacta de permisos. Echo declara el
permiso de micrófono en el manifiesto y además ofrece aviso propio claro; no
puede forzar el texto ni la pantalla del instalador del sistema operativo.
