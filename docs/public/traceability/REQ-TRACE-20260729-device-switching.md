# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** Enumeración y reconmutación de fuentes de audio
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** aproximación temporal

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF6.2.1 | §RF6.2, `Especificacion-de-requerimientos.md` | La fuente predeterminada es *System Loopback*. | La instancia inicial captura el endpoint de reproducción predeterminado. |
| RF6.2.2 | §RF6.2 | La sección de ajustes contiene una lista desplegable que detecta y enumera dispositivos disponibles. | El selector muestra los endpoints de reproducción activos, con identificador estable y nombre legible. |
| RF6.2.3 | §RF6.2 | El dispositivo puede cambiarse en ejecución sin reiniciar la aplicación ni interrumpir el hilo gráfico. | El cambio reemplaza sólo el hilo de captura; el `AudioEngine` y el temporizador WinUI permanecen activos. |
| ABI dispositivos | §2.1–2.3, `Echo-Development-Plan.md` | `get_audio_devices` asigna la lista en Rust y C# debe invocar `free_device_list`. `set_audio_device` recibe un ID UTF-8. | Cada lista enumerada se libera en `finally`; los punteros no sobreviven a la conversión a objetos administrados. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF6.2.1 / RF6.2.3 | `src/core/src/capture.rs` :: `LoopbackCapture::start` | `device_id: Option<String>`; `None` representa el endpoint Render predeterminado. | El nuevo hilo MTA abre el endpoint seleccionado en loopback; al sustituirlo, el motor conserva su DSP y FFI. |
| ABI dispositivos | `src/core/src/ffi.rs`, `src/ui/Audio/EchoCoreNative.cs`, `AudioCoreService.cs` | `AudioDeviceProperties` es `repr(C)`/blittable; ID y nombre son UTF-8 NUL terminados. | La propiedad de memoria permanece en Rust hasta `free_device_list`; C# materializa y libera en el mismo método. |
| RF6.2.2 | `src/ui/MainWindow.xaml(.cs)` | `ComboBox` ligado a una lista de `AudioDevice`. | La selección llama al servicio sin bloquear el temporizador de renderizado. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| ABI dispositivos | Compilación ABI Rust/C# y Clippy. | Lista vacía, ID UTF-8, puntero nulo, error de dispositivo. | Compila; falta prueba de integración con endpoint real. |
| RF6.2.3 | Revisión de que el selector usa `TrySelectLoopbackDevice` sin detener el temporizador. | El fallo conserva la captura previa; la UI informa el error. | Compila; requiere prueba manual con dos endpoints. |
| RF6.2.1 / RF6.2.2 | Prueba manual en Windows con dispositivo predeterminado. | Requiere hardware/endpoints disponibles en la máquina. | Pendiente de hardware. |

## Desviaciones o decisiones

Los endpoints de reproducción se enumeran porque WASAPI loopback se asocia a un
endpoint Render. Micrófonos y entradas de línea requieren una ruta de captura
directa distinta y no se anunciarán como compatibles con loopback en este
incremento.
