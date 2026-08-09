# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Shell MVVM, fuentes de audio, autorrotación, inmersión y tema
- **Fecha:** 2026-07-29
- **Responsable:** Agente Shell/UI
- **Estado:** histórica; audio y tema sustituidos por la implementación del 2026-08-08

> Los símbolos originales de audio/tema y el tema Noche predeterminado ya no
> describen la aplicación. La evidencia vigente se encuentra en
> `traceability-report-20260808-distribution-runtime-parity.md`.

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.2.1–3 | Módulo 6, Gestión y Captura de Fuentes de Audio | Loopback del sistema por defecto; selector con tipo de dispositivo; cambio transaccional sin reinicio ni detener render. | Sólo una selección nativa iniciada correctamente se persiste; una fuente obsoleta vuelve al loopback predeterminado. |
| RF6.4.1–5 | Módulo 6, Secuenciador y Presets | Rotación configurable, orden explícito, aleatorio, sólo favoritos y presets persistentes. | `AutoRotationConfig` y catálogo se guardan/cargan de JSON. |
| RF6.4.6–7 | Módulo 6 y Plan §4 | `T_fade ∈ [0.5 s, 2.0 s]`; cambio en onset o salvaguarda de `1.5 s`; el estado del frame disparador inicializa el entrante. | Shell entrega a `VisualizerHostViewModel` la duración y el frame de disparo; el compositor render lo consume. |
| RF6.5.1–3 | Módulo 6, Pantalla Completa | Acción global; ocultar overlays/ajustes/cursor; restaurar por puntero o Escape. | F11/botón alternan modo; cursor y controles recuperan visibilidad por interacción. |
| RF6.6.1–3 | Módulo 6, Tema | Selector Sistema/Claro/Noche y sincronización dinámica del tema resuelto. | Sistema es predeterminado; se persiste y actualiza XAML, barra de título y Win2D al cambiar Windows. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la regla |
|---|---|---|---|
| RF6.2 | `AudioCoreService.SelectAudioDevice`, `AppVisualizerState.RestoreAudioSelection`, `SettingsPage` | id, tipo de fuente, resultado y actividad <= 3 s | La ruta vigente distingue loopback/captura directa, conserva el worker funcional ante error y expone recuperación. |
| RF6.4 | `MainViewModel.AdvanceFrame`, `SettingsViewModel` | intervalo 5–300 s; fundido 0.5–2 s, default 1 s; timeout 1.5 s | Reutiliza selector y scheduler, sin temporizador duplicado en la ventana. |
| RF6.5 | `MainWindow.ToggleFullscreen` | `InputSystemCursorShape.None` | Oculta cursor y overlays; puntero/Escape restauran los controles. |
| RF6.6 | `ThemePreference`, `ThemeService`, `ColorPalette.xaml` | Sistema, Claro, Noche y tema resuelto | La preferencia global se guarda con compatibilidad `ThemeIndex`; `ActualThemeChanged` sincroniza superficies y contraste alto. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.2 | Pruebas Rust/FFI/.NET del incremento 2026-08-08 | fuente válida, inválida, obsoleta y sin datos | automatización aprobada; runtime de ambas identidades pendiente |
| RF6.4 | `ViewModelsTests`, `AutoRotationServiceTests` | límites de fundido, onset y 1.5 s | pendiente de ejecutar |
| RF6.5–6 | pruebas de configuración/tema y procedimiento VA2 | cambio de tema y restauración de cursor requieren ejecución WinUI | tema automatizado aprobado; runtime manual pendiente |

## Desviaciones o decisiones

Ninguna. La composición de doble superficie de RF6.4.6 pertenece al host de render; este incremento sólo entrega su duración, estado y transición al contrato MVVM.
