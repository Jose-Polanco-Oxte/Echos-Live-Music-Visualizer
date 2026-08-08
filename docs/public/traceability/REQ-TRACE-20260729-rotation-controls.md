# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Controles y estado persistente de autorrotación/presets
- **Fecha:** 2026-07-29
- **Responsable:** agente `rotation_controls`
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.4.1 | `Especificacion-de-requerimientos.md` §RF6.4 | Alternar automáticamente el visualizador activo tras un intervalo de tiempo configurable. | La configuración persistida permite habilitar/deshabilitar y usar un intervalo entero de 5 a 300 segundos. |
| RF6.4.2 | `Especificacion-de-requerimientos.md` §RF6.4 | El usuario selecciona los visualizadores del ciclo y especifica el orden exacto. | El orden del catálogo habilitado se conserva como secuencia; el siguiente secuencial es el elemento posterior con retorno al inicio. |
| RF6.4.3 | `Especificacion-de-requerimientos.md` §RF6.4 | Random Mode inhabilita el orden secuencial y selecciona aleatoriamente del grupo habilitado. | La selección aleatoria usa exclusivamente candidatos habilitados y evita repetir el activo si hay otra opción. |
| RF6.4.4 | `Especificacion-de-requerimientos.md` §RF6.4 | Perfil de fábrica: rotación continua usando únicamente Favoritos. | `CreateDefault` inicializa `OnlyFavorites = true`. |
| RF6.4.5 | `Especificacion-de-requerimientos.md` §RF6.4; `Echo-Development-Plan.md` §3.1 | `enabled: boolean`, `intervalSeconds: integer [5,300]`, `isRandom: boolean`, `onlyFavorites: boolean`. | `presets.json` carga y guarda los cuatro campos y rechaza fuera de rango. |
| RF6.4.7 | `Echo-Development-Plan.md` §4.2 | Esperar `OnsetDetectado == true` o salvaguarda de 1.5 s antes del cambio. | El planificador expone el estado pending y dispara en onset o a los 1.5 s exactos. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.4.1–4 | `src/ui/Services/AutoRotationService.cs` :: `AutoRotationScheduler`, `AutoRotationSelector` | `intervalSeconds` (s), `pendingElapsed` (s), orden de `RotationCandidate`. | La planificación usa intervalo en segundos; selector secuencial usa `(índice + 1) mod N`; random selecciona el grupo elegible. |
| RF6.4.5 | `src/ui/Services/PresetManagerService.cs` :: `EchoPresetsConfig` | enteros de 5–300 s y booleanos. | Validación y serialización del esquema formal. |
| RF6.4.1–5 | `src/ui/ViewModels/SettingsViewModel.cs`, `MainViewModel.cs` | propiedades bindables y configuración serializable. | El ViewModel expone estado para controles y `Save` conserva la configuración actual. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.4.1, 5 | `AutoRotationConfig_RequiresIntervalWithinSchemaBounds` | 5 y 300 válidos; 4 y 301 inválidos. | superada |
| RF6.4.2, 3 | `AutoRotationSelector_*`, `MainViewModel_PersistsManualRotationOrderAndRequestsNextSceneAfterOnset` | vuelta al inicio, filtro de favoritos, grupo vacío y aleatorio sin repetición. | superada |
| RF6.4.7 | `AutoRotationScheduler_WaitsForOnsetOrOnePointFiveSecondSafeguard` | onset inmediato, 1.499 s y 1.500 s. | superada |
| Controles WinUI | Integración: enlazar `Settings` a ToggleSwitch/NumberBox/ToggleSwitch/ToggleSwitch y llamar a `Save`. | Probar mínimo, máximo, reiniciar y recargar. | pendiente de integración por propietario de `MainWindow`. |

## Desviaciones o decisiones

Ninguna. El archivo `MainWindow.xaml` está reservado por el incremento del host D3D; este incremento entrega las propiedades bindables y el contrato de integración sin editar ese archivo concurrente.
