# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Shell MVVM, fuentes de audio, autorrotación, inmersión y tema
- **Fecha:** 2026-07-29
- **Responsable:** Agente Shell/UI
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.2.1–3 | Módulo 6, Gestión y Captura de Fuentes de Audio | Loopback del sistema por defecto; selector dinámico; cambio sin reinicio ni detener render. | La selección se conserva tras refrescar cada 2 s y la conmutación sólo reinicia la captura nativa. |
| RF6.4.1–5 | Módulo 6, Secuenciador y Presets | Rotación configurable, orden explícito, aleatorio, sólo favoritos y presets persistentes. | `AutoRotationConfig` y catálogo se guardan/cargan de JSON. |
| RF6.4.6–7 | Módulo 6 y Plan §4 | `T_fade ∈ [0.5 s, 2.0 s]`; cambio en onset o salvaguarda de `1.5 s`; el estado del frame disparador inicializa el entrante. | Shell entrega a `VisualizerHostViewModel` la duración y el frame de disparo; el compositor render lo consume. |
| RF6.5.1–3 | Módulo 6, Pantalla Completa | Acción global; ocultar overlays/ajustes/cursor; restaurar por puntero o Escape. | F11/botón alternan modo; cursor y controles recuperan visibilidad por interacción. |
| RF6.6.1–2 | Módulo 6, Tema | Selector de modos y modo noche de baja luminancia. | Preferencia Sistema/Claro/Noche se persiste; Noche es predeterminado. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la regla |
|---|---|---|---|
| RF6.2 | `MainWindow.RefreshAudioSources` y `DeviceRefreshCoordinator` | periodo 2 s, id de fuente seleccionado | Sustituye la lista sólo conservando el id seleccionado si aún existe. |
| RF6.4 | `MainViewModel.AdvanceFrame`, `SettingsViewModel` | intervalo 5–300 s; fundido 0.5–2 s, default 1 s; timeout 1.5 s | Reutiliza selector y scheduler, sin temporizador duplicado en la ventana. |
| RF6.5 | `MainWindow.ToggleFullscreen` | `InputSystemCursorShape.None` | Oculta cursor y overlays; puntero/Escape restauran los controles. |
| RF6.6 | `EchoPresetsConfig.Theme`, `MainWindow.ApplyTheme` | Sistema, Claro, Noche | La preferencia se guarda junto al preset y se aplica al root XAML. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.2 | `DeviceRefreshCoordinatorTests` | fuente seleccionada presente, retirada y lista vacía | pendiente de ejecutar |
| RF6.4 | `ViewModelsTests`, `AutoRotationServiceTests` | límites de fundido, onset y 1.5 s | pendiente de ejecutar |
| RF6.5–6 | pruebas de configuración y procedimiento VA2 | restauración de cursor requiere ejecución WinUI | pendiente manual |

## Desviaciones o decisiones

Ninguna. La composición de doble superficie de RF6.4.6 pertenece al host de render; este incremento sólo entrega su duración, estado y transición al contrato MVVM.
