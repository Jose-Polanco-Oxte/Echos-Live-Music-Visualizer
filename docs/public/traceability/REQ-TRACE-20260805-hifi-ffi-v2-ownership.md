# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** ABI FFI v2, triple buffer y leases
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** propuesta

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF5.1–RF5.2 | Módulo 5 | El cálculo acústico está desacoplado del render y la entrega no bloquea el flujo de audio. | Leer FFI nunca ejecuta DSP. |
| RNF-REL.2 | Fiabilidad | Transferencia lock-free SPSC y memoria compartida sin mutex. | Publicación/adquisición con orden Release/Acquire. |
| RNF-REU.1 | Reusabilidad | Un contrato `AudioFrameData` común entrega el pipeline a los consumidores. | v1 sigue operativo mientras v2 incorpora energías crudas/acondicionadas. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF5.1–2 | `frame_store.rs`, `ffi.rs` | tres slots, `sequence`, timestamps, lease | Worker publica, cliente adquiere y libera sin disparar análisis. |
| RNF-REL.2 | `frame_store.rs` | lectores por slot, Release/Acquire | El escritor no pisa un slot arrendado; el overflow se telemetra. |
| RNF-REU.1 | `ffi.rs`, `AudioCoreService.cs` | ABI v1/v2, `AudioFrameLease` | v2 expone punteros válidos hasta `release`. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF5.1–2 | millón de acquire/release sin audio nuevo | no ejecuta FFT ni asigna | pendiente |
| RNF-REL.2 | stress productor/lector y reconfiguración con leases | slots ocupados, punteros inválidos | pendiente |
| RNF-REU.1 | layout Rust/C#, compatibilidad v1 y DLL sin v2 | fallo limpio | pendiente |

## Desviaciones o decisiones

La ABI v1 no se modifica in situ. El ownership y la política de slots se
documentarán antes de codificar mediante la decisión QA correspondiente.
