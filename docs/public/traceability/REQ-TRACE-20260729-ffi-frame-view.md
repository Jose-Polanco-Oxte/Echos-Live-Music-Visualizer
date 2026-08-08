# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Lectura FFI de `AudioFrameData` sin asignaciones por frame
- **Fecha:** 2026-07-29
- **Responsable:** Integración
- **Estado:** implementada

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| FFI §2.1 | `Echo-Development-Plan.md` §2.1 | `energias_bandas` pertenece al `AudioEngine`; C# lee directamente el puntero sin asignación en heap por frame. | Un frame administrado expone un `ReadOnlySpan<float>` válido sólo hasta la siguiente lectura FFI, sin copia ni asignación. |
| RNF-REU.1 | `Especificacion-de-requerimientos.md` §II.5 | Todas las soluciones consumen el contrato estandarizado `AudioFrameData`. | Visualizadores y secuenciador leen el mismo frame inmutable durante el tick. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| FFI §2.1 | `src/ui/Audio/AudioFrame.cs` :: `AudioFrameView` | `ReadOnlySpan<float>` sobre `float*` nativo; duración: una lectura. | No se materializa un arreglo administrado. |
| FFI §2.1 | `src/ui/Audio/AudioCoreService.cs` :: `TryReadFrame` | puntero, `BandCount`, timestamp en ms. | Construye la vista directamente desde `get_latest_frame`. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| FFI §2.1 | `FfiStressTests.AudioCoreService_OneMillionFrameReads_DoNotAllocateManagedMemory`. | 0 bytes administrados después del calentamiento; banda vacía o `BandCount > 128` rechazada. | aprobado (2026-07-29) |
| RNF-REU.1 | `dotnet test EchoVisualizer.sln -c Release --no-restore`. | La vista no se conserva entre lecturas. | aprobado: 27/27 (2026-07-29) |

## Desviaciones o decisiones

Ninguna.
