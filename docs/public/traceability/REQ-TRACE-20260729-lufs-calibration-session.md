# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** registro histórico de sesiones de calibración LUFS/Gamma
- **Fecha:** 2026-07-29
- **Responsable:** Codex
- **Estado:** archivada; los controles de prueba fueron retirados de producción el 2026-08-05

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF4.3 | Módulo 4, Acondicionamiento dinámico | $E_{final,i}=clamp((E_iG)^{\gamma},0,1)$; automático: $L_{target}=-14$, $\gamma_{base}=1$, $\gamma_{max}=2.2$, $\sigma=6$, $\alpha=0.03$. | El modo automático conserva esos valores; manual permite $G\ge0$, $\gamma>0$. |
| RF4.3.1 | Módulo 4, calibración contra colapso | Instrumentar $L_{short}$, $\Delta L$, $G$, $\gamma$, $E_i$, $E_{final,i}$; separar DSP de render. | CSV por sesión y comparación A/B antes de cambiar fórmula. |

## Mapeo de implementación propuesto

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RF4.3 | `src/core/src/ffi.rs` y `src/ui/Audio/AudioCoreService.cs` | Modos automático y manual. | Reutiliza `set_lufs_mode`; no cambia la ecuación. |
| RF4.3.1 | `src/core/src/ffi.rs`, `src/ui/Audio/SpectralTelemetryRecorder.cs` y `src/ui/MainWindow.*` | $L_{short}$ (LUFS), potencia cruda, amplitud, pico maestro y salida acondicionada. | Expone observabilidad temporal sin controles de prueba ni copia de vectores. |

## Modos de prueba (histórico, no disponibles en producción)

| Selector | Configuración | Qué aísla |
|---|---|---|
| Automático normativo | modo automático RF4.3 | Comportamiento actual completo. |
| Referencia neutra | manual $G=1$, $\gamma=1$ | Audio/FFT/render sin acondicionamiento de salida. |
| Control de ganancia | manual $G=10^{-6/20}\approx0.50$, $\gamma=1$ | Efecto de atenuar $G$ sin gamma. |
| Control de gamma | manual $G=1$, $\gamma=1+1.2tanh(1)\approx1.91$ | Efecto del gamma típico de $\Delta L=+6$ LU sin ganancia. |

## Procedimiento manual

Este procedimiento queda conservado únicamente como evidencia histórica. Los
selectores LUFS/Gamma y escalado de prueba ya no existen en la aplicación.
Para nuevas sesiones se usa Híbrido como ruta única.

1. Mantener fija la fuente seleccionada, volumen de Windows y número de bandas.
2. Elegir un modo; el registro inicia una sesión nueva. Esperar cinco segundos
   antes de iniciar la reproducción para separar el silencio inicial.
3. Reproducir el fragmento indicado hasta el final y responder en este chat
   `fin: <pista> / <modo>`; no cambiar controles durante la muestra.
4. Repetir el mismo fragmento primero con **Referencia neutra** y después con
   **Automático normativo**. Los controles aislados se ejecutan una vez para
   interpretar los dos términos.
5. Comparar tendencias de 30 s: $L_{short}$, $G$, $\gamma$ y energía media
   posterior. Si la referencia neutra no cae y automático sí, se investiga
   RF4.3; si ambos caen o predominan bloques repetidos, se investiga captura o
   render antes de alterar los coeficientes.

## Pistas propuestas

| Orden | Pista y fragmento | Propósito |
|---|---|---|
| 1 | Daft Punk — *Get Lucky*, 00:45–03:45 | Electrónica estable y comprimida; detecta caída sostenida. |
| 2 | Billie Eilish — *bad guy*, 00:00–02:30 | Graves, silencios y transitorios secos. |
| 3 | Metallica — *Enter Sandman*, 00:35–03:35 | Rock comprimido con batería y guitarras densas. |
| 4 | Claude Debussy — *Clair de Lune*, 00:00–03:00 | Dinámica amplia y pasajes suaves. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RF4.3 | `cargo test` y `cargo clippy -- -D warnings`. | $G=0$, $\gamma=1$, valores no finitos. | 32 pruebas Rust correctas; clippy correcto. |
| RF4.3.1 | Prueba aislada .NET `AudioCoreService_ReportsLufsDiagnosticsWithoutReadingAnotherFrame`; cuatro pares A/B de las pistas propuestas. | Cinco segundos de silencio inicial; distinguir bloque nuevo/repetido. | Contrato FFI correcto; validación con hardware/audio real pendiente. |

## Registro de ejecuciones manuales

| Sesión | Pista / modo | Duración | Observación registrada | Resultado |
|---|---|---:|---|---|
| 1 | Daft Punk — *Get Lucky* / Referencia neutra ($G=1$, $\gamma=1$) | 291.4 s | 1,087 muestras; 100% de bloques nuevos; media de energía posterior 0.00665 en primera mitad y 0.01390 en segunda. | No se observa caída sostenida sin acondicionamiento. Pendiente comparar el mismo material en automático. |
| 2 | Daft Punk — *Get Lucky* / Automático normativo | 228.9 s | 857 muestras; 100% de bloques nuevos; $G$ medio 2.49; $\gamma$ medio 1.001 y máximo 1.069; energía posterior/media previa = 1.303. | Muestra exploratoria sustituida por 2b, porque el inicio de reproducción no quedó marcado con precisión. |
| 2b | Daft Punk — *Get Lucky* / Automático normativo (repetición limpia) | 229.6 s | 859 muestras; 100% de bloques nuevos; $G$ medio 2.23; $\gamma$ medio 1.001 y máximo 1.065; energía posterior/media previa = 1.298; segunda mitad 0.01746 frente a 0.01820. En el audio activo, los primeros 10 s tuvieron $G=2.399$ y salida media 0.03858; los últimos 10 s, con energía previa prácticamente igual (0.01741 vs 0.01760), tuvieron $G=1.187$ y salida 0.02090. | **Confirmado el transitorio de inicio:** la ventana corta incorpora el silencio de preinicio y el IIR tarda en asentarse; la ganancia inicial es alta y decae gradualmente. En esta sesión $\gamma=1.0$, por lo que el efecto no procede del gamma. No hay colapso sostenido posterior. |
| 3 | Daft Punk — *Get Lucky* / Control de gamma ($G=1$, $\gamma=1.91391$) | 224.0 s | 841 muestras; 99.9% de bloques nuevos; energía media previa 0.01313 y posterior 0.00109; razón posterior/previa = 0.083. | **Confirmado:** el gamma alto, aplicado a energías normalizadas, reduce 91.7% la energía media. Es una causa suficiente de barras diminutas cuando el automático alcance valores de gamma elevados. |
| 5 | Metallica — *Enter Sandman* / Automático normativo | No evaluable | El CSV iniciado para la sesión quedó en 0 bytes y no contiene muestras; la aplicación permaneció activa. | **Inválida:** incidente de telemetría. No se extrae conclusión de LUFS, gamma ni del visualizador. Véase `QA-INC-20260729-LUFS-SESSION-NO-SAMPLES`. |
| 5r | Metallica — *Enter Sandman* / Automático normativo (repetición) | 87.0 s activos | 326 muestras y 100% bloques nuevos. 0–20 s: $L_{short}=-15.59$, $G=1.61$, $\gamma=1.02$, salida/previa=1.61. 40–60 s: $L_{short}=-13.69$, $G=0.97$, $\gamma=1.06$ (máx. 1.205), salida/previa=0.82. 80–100 s: $L_{short}=-13.64$, $G=0.96$, $\gamma=1.08$, salida/previa=0.76. | **Confirmado con música fuerte:** al asentarse la ventana LUFS disminuye la ganancia inicial y, al superar el objetivo, el exponente $\gamma>1$ reduce energías normalizadas menores que uno. La toma es suficiente para verificar el transitorio y la contribución de gamma, pero no sustituye una reproducción completa de 180 s ni una prueba de duración. |

## Desviaciones o decisiones

No se cambia ningún default ni término de RF4.3. Los controles manuales son
instrumentos de diagnóstico temporales. Véase
`.agents/qa/logs/decision-QA-DEC-20260729-lufs-diagnostic-modes.md`.

Tras la sesión 5 inválida, el registro se sondea antes de devolver temprano por
ausencia de `AudioFrameView` y muestra su contador de muestras. Esta mejora de
observabilidad no altera la fórmula ni los parámetros RF4.3; deberá verificarse
con una sesión nueva antes de repetir la prueba 5.
