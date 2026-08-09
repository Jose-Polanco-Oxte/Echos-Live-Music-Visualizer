# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Verificación V2–V6, validación VA y empaquetado MSIX
- **Fecha:** 2026-07-29
- **Responsable:** agente de verificación y empaquetado
- **Estado:** ejecutada parcialmente; las aprobaciones dependientes de audio,
  instrumentación de presentación, monitor 4K o duración real permanecen
  pendientes.

> Historical evidence note (2026-08-08): the original packaging command and
> startup-permission assumptions have been superseded. Current work uses
> `scripts/Build-Distributions.ps1`; permission and theme behavior is governed
> by RF6.1.3--RF6.1.5, RF6.2.5, and RF6.6.3. Historical results below are not
> evidence for the current runtime-parity increment.

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| V2 | Plan §7.1 y Especificación §8/Fase VI | `1,000,000` consultas FFI; cero fugas de memoria. | El test de un millón de invocaciones ABI y consultas repetidas de lista termina sin retención anómala. |
| V3 | Plan §7.1 y Especificación §RF5 | Latencia de procesamiento Core `<= 30 ms` (ideal `23 ms`). | Medición end-to-end documentada con WASAPI real y percentiles. |
| V4 | Plan §7.1 y Especificación §RF5 | Tasa de refresco `>= 60 Hz`; 1080p y 4K. | Telemetría de presentación continua durante sesión real. |
| V5 | Plan §7.1 | Resistencia continua de `24 h`. | Registro de salud, memoria y errores durante 24 horas. |
| V6 | Plan §7.1 | Intercambio caliente `<= 16.6 ms`. | Cada cambio se mide entre solicitud y primer frame presentado. |
| VA1–VA5 | Plan §7.2 y Especificación §8/Fase VI | Validaciones perceptuales, UX, onset, hot-plug y JSON. | Procedimientos reproducibles con evidencia adjunta. |
| MSIX | Plan §8/Fase VI | Generar paquete ejecutable en formato MSIX. | El proyecto WinUI crea un `.msix`/`.msixbundle` x64, firmado para distribución. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| V2 | `tests/EchoVisualizer.Tests/FfiStressTests.cs` | `OneMillion = 1_000_000`; límite de heap `1 MiB`; 100 consultas de lista. | La llamada ABI no reserva en el wrapper; la lista se materializa y libera en cada iteración. |
| V2 | `scripts/Invoke-FfiStress.ps1` | configuración `Release`; resultado `.trx`. | Ejecuta sólo la batería V2 y conserva evidencia de la ejecución. |
| V3–V6, VA1–VA5 | `docs/verification/real-time-validation.md` | umbrales en ms, Hz, horas y resoluciones normativas. | Define instrumentos, cálculo, evidencia y regla de aprobación sin sustituir una medición por estimación. |
| MSIX | `src/ui/Package.appxmanifest`, `scripts/Build-Distributions.ps1` | x64/ARM64; `AppxBundle=Always`; certificado del usuario actual opcional. | El punto de entrada común valida metadata, manifiesto, arquitectura, capacidades, payload y firma; una versión temporal se aplica mediante un manifiesto generado sin modificar fuentes. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| V2 | `scripts/Invoke-FfiStress.ps1` | DLL ausente, ABI incorrecto, retención de heap > 1 MiB, crecimiento privado > 64 MiB. | **Aprobado automáticamente el 2026-07-29**: 5/5 pruebas Release, incluido 1,000,000 de consultas ABI y de lecturas de frame; evidencia `artifacts/verification/ffi-stress-20260729-200605.trx`, duración total 17.76 s. La ejecución de cinco corridas consecutivas con Private Bytes sigue pendiente. |
| V3 | Procedimiento V3 de `real-time-validation.md`. | Ningún promedio sustituye p95/p99 ni el peor caso solicitado. | **Pendiente**: falta una fuente WASAPI activa y telemetría por frame de `t_pcm_capturado`, publicación y consumo por render. No se declararon percentiles ni el límite de 30 ms sin CSV/ETW o PIX. |
| V4 | Procedimiento V4 de `real-time-validation.md`. | 10 min por combinación 2D/3D, 1920x1080 y 3840x2160, con >= 60 Hz. | **Pendiente**: el entorno detectó 1920x1080, pero no un monitor 4K ni PresentMon/PIX. No se sustituyó el requisito de 4K por una estimación. |
| V5 | Procedimiento V5 de `real-time-validation.md`. | 24 h, loopback real, muestreo por minuto y cambio cada 5 min. | **Pendiente**: todavía no hay una sesión continua de 24 h ni su CSV de salud. |
| V6 | 100 cambios UI entre barras, espejo, pulso y malla, con el paquete MSIX `1.0.0.21`. | Cambios 2D/3D y cambios en onset; máximo <= 16.6 ms. | **Smoke de estabilidad ejecutado el 2026-07-29**: 100 cambios en 39.61 s sin cierre del proceso ni evento `Application Error`. **No aprobado**: la duración incluye automatización de UI y no mide solicitud a primer frame presentado; falta instrumentación de presentación y casos `Onset == true`. |
| VA1 | Procedimiento VA1 de `real-time-validation.md`. | EDM, clásica, rock/metal y podcast/voz. | **Pendiente**: requiere evaluación humana, las cuatro fuentes de audio y vídeo/anotaciones perceptuales. |
| VA2 | Smoke histórico de fullscreen/Escape del paquete MSIX `1.0.0.21`. | Tema Sistema/Claro/Noche; fullscreen, Escape, cursor y restauración. | **Obsoleto para aceptación actual**: la antigua aceptación explícita del disclaimer ya no es normativa. La sincronización dinámica de tema debe verificarse según RF6.6.3 y el informe de paridad del 2026-08-08. |
| VA3 | Procedimiento VA3 de `real-time-validation.md`. | 20 transiciones; onset, frame inicial y fundido 0.5–2 s. | **Pendiente**: faltan reproducción real, traza de onset y las 20 mediciones de transición. |
| VA4 | Procedimiento VA4 de `real-time-validation.md`. | Dos endpoints y refresco de selector cada 2 s. | **Pendiente**: se detectaron endpoints de audio del sistema, pero no se conectaron/desconectaron físicamente dos dispositivos durante reproducción. |
| VA5 | Suite .NET y procedimiento VA5 de `real-time-validation.md`. | CRUD, reinicio y JSON corrupto con respaldo. | **Automatización aprobada el 2026-07-29**: la suite .NET completa (31/31) incluye comportamiento de presets y fallback de JSON. **Pendiente manual**: CRUD visible, reinicio y comprobación del respaldo desde la UI instalada. |
| MSIX | Evidencia histórica; el comando vigente es `scripts/Build-Distributions.ps1 -Profile Store`. | Certificado con clave privada cuyo Subject coincide con el Publisher del manifiesto. | **Histórico, 2026-07-29**: MSIX x64 `1.0.0.21` fue generado, firmado e instalado. No sustituye la validación estructural y de runtime del incremento actual. |

## Desviaciones o decisiones

Ninguna fórmula fue aproximada. La corrección de estabilidad se verificó con
Windhawk detenido y posteriormente restaurado, por lo que la inyección no fue
la causa del acceso inválido de malla. Las validaciones de hardware no se
declaran aprobadas hasta adjuntar la telemetría y la evidencia indicada. Los
gráficos de marca entregados por la plantilla de Visual Studio son sólo
marcadores y deben reemplazarse antes de la publicación.
