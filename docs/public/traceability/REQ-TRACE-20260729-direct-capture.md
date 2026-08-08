# Trazabilidad — captura directa WASAPI

## Alcance verificable

La selección de una fuente de entrada activa (micrófono, línea o bucle virtual)
usa WASAPI en modo de captura directa; la captura global predeterminada conserva
WASAPI loopback sobre el endpoint de salida predeterminado. El cambio sustituye
únicamente el worker de captura, sin cambiar el ABI `AudioFrameData` ni detener
el hilo que consulta frames.

## Requisitos fuente

| ID | Encabezado fuente | Obligación aplicable |
| --- | --- | --- |
| RF1.1 | Ingesta y Buferización | Ingerir PCM a 44.1 o 48 kHz en bloques de 512 a 1024 muestras. |
| RF6.2.1 | Captura Predeterminada del Sistema Operativo | Mantener System Loopback como ruta predeterminada. |
| RF6.2.2 | Selector de Dispositivo de Entrada | Enumerar dinámicamente endpoints de salida y de entrada disponibles. |
| RF6.2.3 | Re-conmutación en Tiempo Real | Sustituir el worker de captura sin reiniciar la aplicación ni el render. |

## Fórmulas, unidades y límites

RF1.1 no define una fórmula. El contrato de la señal es PCM, frecuencia de
muestreo `f_s ∈ {44.1 kHz, 48 kHz}` y tamaño de bloque `N ∈ [512, 1024]`.
WASAPI puede proporcionar otra tasa; la ruta existente solicita PCM float a
48,000 Hz compartido con autoconversión del sistema. Para cada frame se publica
exactamente `N` muestras mono. El downmix conserva la ecuación normativa del
plan: `S_mono[n] = (1/C) * sum(S_c[n])`; la implementación suma todos los
canales intercalados y divide entre `C`.

## Mapeo de implementación

- `AudioDeviceKind::{LoopbackRender, DirectCapture}` identifica la semántica
  del endpoint sin alterar las estructuras FFI existentes.
- `enumerate_audio_devices` recorre `Direction::Render` y `Direction::Capture`;
  cada ID se etiqueta internamente y se expone con el mismo `AudioDeviceProperties`.
- `CaptureSource::from_device_id` verifica el ID contra la enumeración MTA y
  selecciona el modo correcto. Un endpoint Capture inicializa IAudioClient con
  `Direction::Capture` directo; un endpoint Render usa el mismo cliente en
  loopback, preservando RF6.2.1.
- `drain_float_blocks` parametriza `C`; los buffers intercalados se convierten
  en frames mono exactamente de `N` muestras.

## Oráculos de prueba

- Prueba determinista de clasificación: un ID Capture selecciona captura
  directa; un ID Render selecciona loopback; un ID desconocido falla.
- Prueba determinista de PCM multicanal: cuatro canales `[1, -1, 0.5, 0.5]`
  producen `(1 - 1 + .5 + .5) / 4 = 0.25`, y un bloque se publica sólo al
  alcanzar `N` muestras.
- Prueba de límites RF1.1: `512` y `1024` son válidos; `511` y `1025` son
  rechazados antes de crear el worker.

## Verificación posterior

Se compara el modo elegido con el endpoint enumerado antes de iniciar el
cliente. La verificación con un micrófono físico queda para la integración de
hardware: se debe comprobar que el selector continúe refrescando frames sin
interrumpir el render y que el dispositivo se pueda cambiar en caliente.
