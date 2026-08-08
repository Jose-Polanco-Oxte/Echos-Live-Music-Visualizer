# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Reparación de captura nativa empaquetada y fundido de selección
- **Fecha:** 2026-07-29
- **Responsable:** agente de desarrollo
- **Estado:** implementada parcialmente; verificación perceptual de transición pendiente

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF1.1 | `Especificacion-de-requerimientos.md` §RF1.1; Plan §1.1 | Capturar PCM a 44.1/48 kHz en bloques `N in [512, 1024]`; normalizar a 48 kHz con `rubato` cuando corresponda. | La UI recibe frames del Core WASAPI publicado, no una señal de demostración. |
| RF4.3 | `Especificacion-de-requerimientos.md` §RF4.3 | `E_final,i[t] = clamp((E_i[t] * G[t])^gamma[t], 0.0, 1.0)` antes de transferir al visualizador. | El frame nativo acondicionado se consume directamente por el visualizador. |
| RF6.2.1–RF6.2.3 | `Especificacion-de-requerimientos.md` §RF6.2 | Loopback del sistema predeterminado; selector dinámico y reconmutación sin reiniciar render. | El MSIX incluye `EchoCore.dll`, inicia la captura y enumera fuentes reales. |
| RF6.4.6 | `Especificacion-de-requerimientos.md` §RF6.4.6; Plan §4.1 | Ambas instancias viven durante `T_fade in [0.5 s, 2.0 s]`; `alpha_A = 1 - t/T_fade`, `alpha_B = t/T_fade`. | Un solo temporizador produce opacidades complementarias y ningún fotograma de corte/parpadeo. |
| RF6.4.7 | `Especificacion-de-requerimientos.md` §RF6.4.7; Plan §4.2 | El entrante usa el frame de disparo (`RMS`, `fC`, bandas); onset o salvaguarda de 1.5 s para autorrotación. | El compositor conserva el snapshot de disparo y no reinicia una transición activa. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.2 | `src/ui/EchoVisualizer.csproj` :: contenido MSIX de `EchoCore.dll` | DLL nativa x64 junto al ejecutable empaquetado. | Permite a `AudioCoreService` invocar el FFI WASAPI. |
| RF6.2 | `src/ui/MainWindow.xaml.cs` :: `StartAudioAfterConsent` | Servicio nativo disponible o estado explícito de fallo/silencio. | No sustituye el flujo de captura por `DemoAudioFrameSource`. |
| RF6.4.6–7 | `MainViewModel`, `VisualizerHostViewModel`, `MainWindow` :: compositor 2D | Un reloj de `VisualizerTransitionState`; opacidades complementarias. | El host finaliza sólo cuando el compositor informa progreso 1.0. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF6.2 | MSIX `1.0.0.22` inspeccionado como ZIP, arranque instalado y loopback mediante 12 tonos del sistema. | DLL ausente debe informar error, no simular audio. | **Aprobado en smoke**: el paquete contiene `EchoCore.dll` (1,204,224 bytes); la UI informó captura nativa y RMS pasó de `0.00` a `0.19–0.21` con onset. |
| RF6.4.6–7 | 32 pruebas .NET, incluido encolado de selección durante un fundido; smoke de seis selecciones 2D. | Inicio, mitad y final; duración 0.5–2.0 s. | **Automatizado aprobado**: el host no puede iniciar una segunda transición mientras existe superficie saliente, y el proceso permaneció vivo sin `Application Error`. **Pendiente manual**: observar la continuidad visual del fundido en una sesión de audio real. |

## Desviaciones o decisiones

La ruta 2D temporal basada en XAML no sustituye la composición Win2D/3D final
del plan. Esta corrección sólo elimina el doble reloj y el fallback engañoso;
las transiciones híbridas continúan pendientes de su compositor nativo.
