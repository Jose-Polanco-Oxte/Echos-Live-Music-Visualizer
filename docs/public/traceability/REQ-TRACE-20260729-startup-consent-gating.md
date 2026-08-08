# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Arranque seguro y consentimiento previo a audio/renderizado
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** implementada; cierre nativo externo pendiente de aislar

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.1.1–RF6.1.3 | `Especificacion-de-requerimientos.md` §RF6.1 | Splash y advertencia de fotosensibilidad deben preceder al inicio de audio. | No se procesa ni presenta audio antes de interacción explícita. |
| RF6.2 | `Especificacion-de-requerimientos.md` §RF6.2 | La fuente de audio se presenta y conmuta desde el shell. | La enumeración se hace al iniciar la señal autorizada. |
| RF6.4.6 | `Especificacion-de-requerimientos.md` §RF6.4 | Fundido configurable entre 0.5 y 2.0 s; default 1.0 s. | Ningún valor no finito alcanza el compositor. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.1 | `src/ui/MainWindow.xaml` :: `VisualizerHost` | `Visibility=Collapsed` hasta consentimiento. | No se activa el lienzo GPU bajo splash/disclaimer. |
| RF6.1/RF6.2 | `src/ui/MainWindow.xaml.cs` :: `StartAudioAfterConsent` | `AudioCoreService` se crea tras la acción del usuario. | No inicia WASAPI ni enumera dispositivos antes del aviso. |
| RF6.4.6 | `SettingsViewModel.NormalizeFadeDuration` | rango `[0.5, 2.0]` s; default `1.0` s. | `NaN`, infinito y valores fuera de rango se normalizan a 1 s. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.4.6 | `ViewModelsTests.Settings_NormalizesInvalidTransientFadeDuration` | `NaN`, infinito, `0.49`, `2.01`. | aprobado: 31/31 pruebas .NET Release. |
| RF6.1 | MSIX 1.0.0.8, 40 s antes de consentimiento. | Proceso vivo y cero eventos `Application Error`. | aprobado una ejecución; requiere repetir sin inyección de terceros. |
| RF6.1/RF6.2 | Aceptar aviso y observar primer frame/captura. | Audio real y GPU. | pendiente por cierre nativo `coreclr.dll` externo a aislar. |

## Desviaciones o decisiones

Ninguna fórmula fue modificada. El retraso de WASAPI y GPU es una aplicación
directa del orden de consentimiento de RF6.1. Ver
`.agents/qa/logs/incident-QA-INC-20260729-installed-winui-crash.md`.
