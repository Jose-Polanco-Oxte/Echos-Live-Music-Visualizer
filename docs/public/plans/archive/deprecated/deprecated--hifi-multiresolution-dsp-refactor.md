## Plan de refactorización HI‑FI multirresolución

No se modificará código ni requisitos hasta cerrar el Bloque 1. La arquitectura objetivo será:

```text
WASAPI multicanal
→ resampling por canal a 48 kHz
→ ring buffer SPSC continuo
→ hop H=512 frames/canal (10.667 ms)
→ STFT 4096 / 2048 / 1024 con Blackman-Harris 4
→ potencia por canal + fusión por región
→ bandas ERB / log-octava + interpolación continua
→ LUFS / acondicionamiento
→ triple buffer con lease FFI v2
→ WinUI/Win2D a 60–144 FPS
```

La interpolación continua recién implementada se conserva: evita bandas vacías, pero deja de ser la única defensa contra la baja resolución de graves.

### Decisiones base que el plan adopta

| Elemento | Decisión |
|---|---|
| Tasa interna | 48 kHz |
| Hop `H` | 512 frames/canal |
| Cadencia DSP | 93.75 Hz |
| Graves | FFT 4096, 20–250 Hz, 11.71875 Hz/bin |
| Medios | FFT 2048, 250–4000 Hz, 23.4375 Hz/bin |
| Agudos/onset | FFT 1024, 4–20 kHz, 46.875 Hz/bin |
| Ventana | Blackman-Harris de 4 términos |
| Canales | FFT por canal y combinación de potencia; no downmix lineal previo |
| Bandas HI‑FI | ERB por defecto; Log-Octave 1/3 y 1/6 como perfiles alternos |
| Fusión | Cross-fade cosenoidal 200–300 Hz y 3.8–4.2 kHz |
| Render | Consume el último frame publicado; nunca dispara DSP |
| Paralelismo | Un worker DSP dedicado inicialmente; no Rayon hasta medir necesidad |

La combinación estéreo se hará después de FFT:

\[
P[k] = \frac{1}{C}\sum_{c=1}^{C}|X_c[k]|^2
\]

No se aplicará \(\sqrt{L^2 + R^2}\) directamente a PCM: rectificaría la señal y alteraría el análisis.

---

## Bloque 0 — Preparar una base Git recuperable

Responsable: integrador.

El árbol actual contiene trabajo previo sin consolidar. Antes de crear la rama de esta feature:

1. Inventariar y revisar los cambios actuales de LUFS, híbrido, interpolación, UI y empaquetado.
2. Ejecutar las pruebas actuales y crear un commit de integración verificable en `dev`.
3. Crear una única rama desde `dev` limpio:

```text
codex/hifi-multiresolution-pipeline
```

4. No crear ramas por cada archivo o microcambio.
5. Mantener `main` intacta. La promoción sólo ocurrirá después de validación real de audio/GPU.

Resultado verificable: un hash base recuperable, pruebas existentes verdes y una rama única para la refactorización.

---

## Bloque 1 — Actualizar requisitos, roadmap y decisiones QA

Responsable exclusivo: agente de requisitos/QA.
Archivos: `docs/spec/**`, `docs/traceability/**`, `.agents/qa/logs/**`, `AGENT-HANDOFF.md`.

Antes de modificar DSP, crear:

- `REQ-TRACE` para captura/STFT/bandas.
- `REQ-TRACE` para FFI v2 y ownership.
- `REQ-TRACE` para rendimiento/latencia.
- Decisiones QA para:
  - normalización multicanal;
  - ventana Blackman-Harris;
  - ERB frente a Log-Octave;
  - política de overflow SPSC;
  - lifetime de frames/leases;
  - separación entre espectro físico, LUFS y perfil perceptual.

Cambios normativos previstos:

### RF1.1 — Ingesta, normalización y hop

Reemplazar la ambigüedad actual de `N` por tres símbolos distintos:

- `H`: hop o quantum de análisis.
- `Nfft`: tamaño de una ventana STFT.
- `B`: número de bandas de salida.

Nueva regla:

\[
H = 512\ \text{frames/canal}
\]

\[
f_a = 48,000\ \text{Hz}
\]

La captura aceptará PCM de 1 a 8 canales y conservará las muestras por canal hasta después del análisis FFT. El ring buffer SPSC almacenará frames de audio continuos y ordenados, con una capacidad mínima inicial de 16,384 frames/canal.

### RF1.2 — STFT multirresolución

Reemplazar la ventana única de 1024/Hamming por tres analizadores con hop común:

| Región | `Nfft` | Ventana |
|---|---:|---|
| 20–250 Hz | 4096 | Blackman-Harris 4 |
| 250–4000 Hz | 2048 | Blackman-Harris 4 |
| 4000–20000 Hz | 1024 | Blackman-Harris 4 |

\[
w[n] =
0.35875
-0.48829\cos\left(\frac{2\pi n}{Nfft-1}\right)
+0.14128\cos\left(\frac{4\pi n}{Nfft-1}\right)
-0.01168\cos\left(\frac{6\pi n}{Nfft-1}\right)
\]

Las ventanas son deslizantes y preasignadas: no se esperan 4096 muestras nuevas antes de actualizar.

### RF1.3 — Bandas perceptuales continuas

Añadir:

- ERB como perfil HI‑FI por defecto.
- Log-Octave fraccional 1/3 y 1/6.
- Conservación de Lineal, Logarítmica y Mel para compatibilidad de presets.
- Prohibición de bandas estructuralmente vacías.
- Integración de potencia con filtros triangulares/trapezoidales, manteniendo la interpolación de bins para rangos estrechos.

\[
ERBRate(f) = 21.4\log_{10}(1 + 0.00437f)
\]

### Nuevo RF1.4 — Fusión multirresolución

Definir los cruces de resolución:

\[
u = clamp\left(\frac{f-f_{low}}{f_{high}-f_{low}},0,1\right)
\]

\[
W_A(f)=\cos^2\left(\frac{\pi}{2}u\right)
\qquad
W_B(f)=1-W_A(f)
\]

\[
P_{fused}(f)=W_A(f)P_A(f)+W_B(f)P_B(f)
\]

- FFT 4096 → 2048: 200–300 Hz.
- FFT 2048 → 1024: 3800–4200 Hz.

### RF2 — Separar análisis de estética visual

El Core debe publicar energía física cruda y energía acondicionada, sin aplicar una inercia irreversible destinada exclusivamente a barras.

La inercia visual seguirá en RF-EQ.2, dentro del renderizador. Esto preserva la reutilización del mismo análisis por futuros visualizadores.

### RF3 — Features rápidas

- RMS por hop de 512 y por potencia multicanal.
- Centroide desde el espectro fusionado.
- Onset desde la ruta rápida de 1024.
- Añadir `onset_score ∈ [0,1]`, conservando `onset_detected` para compatibilidad.

### RF4 — LUFS y perfiles perceptuales

- LUFS/K-weighting se calcula por canal y sólo controla la ganancia global.
- El híbrido conserva ganancia espectral neutra:

\[
W_i=E_i,\qquad E_{lufs,i}=E_iG_t
\]

- ISO 226/A-weighting será un perfil de presentación opcional, nunca una coloración silenciosa del vector físico ni del híbrido.

### RNF-PERF — Reemplazar “latencia ≤30 ms” por métricas medibles

| Métrica | Definición | Objetivo |
|---|---|---|
| `L_c` | Entrada de hop → frame publicado | p99 < 1.5 ms en hardware de referencia |
| Cadencia | Hops procesados | 93.75 Hz |
| `L_g` | Edad/grupo de ventana | Reportada por cada `Nfft` |
| Render | Frame rate | ≥60 FPS; objetivo 120 |
| `L_e2e` | WASAPI + `L_g` + `L_c` + render | Medida en hardware |

La edad de grupo aproximada será:

- 1024: 10.66 ms.
- 2048: 21.32 ms.
- 4096: 42.66 ms.

No se presentará la edad de una ventana grave como “latencia de cómputo”.

---

## Bloque 2 — Núcleo matemático offline y pruebas de oráculo

Responsable exclusivo: agente Core DSP.
Archivos nuevos sugeridos:

```text
src/core/src/stft.rs
src/core/src/multiresolution.rs
src/core/src/bands.rs
src/core/src/features.rs
```

Objetivo: construir y probar la matemática sin tocar todavía WASAPI ni FFI.

Implementar:

1. `StftAnalyzer` preasignado para una sola resolución.
2. `MultiResolutionAnalyzer` con exactamente tres instancias: 4096, 2048 y 1024.
3. Ventanas Blackman-Harris precalculadas y normalización de ganancia.
4. Espectro por canal y combinación de potencia.
5. Generador ERB y Log-Octave.
6. Fusión cosenoidal entre regiones.
7. Integración continua de energía en bandas.
8. RMS, centroide y onset rápido desacoplados.

Pruebas obligatorias:

- Tono puro en bin de 1024, 2048 y 4096.
- Tono de 20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200 y 250 Hz.
- Separación de tonos graves que N=1024 no distinguía.
- Fuga espectral Blackman-Harris contra ventana rectangular y Hamming.
- Continuidad de energía en cruces 200–300 y 3800–4200 Hz.
- ERB/Log-Octave monótonas, sin huecos y cubriendo 20 Hz–20 kHz.
- Bandas estrechas nunca quedan en cero salvo entrada silenciosa.
- Cero asignaciones después de construir analizadores.

Resultado verificable: matemáticas HI‑FI correctas mediante fixtures deterministas y `cargo test`.

---

## Bloque 3 — Captura multicanal y ring buffer continuo

Responsable exclusivo: agente Core de captura.
Archivos: `src/core/src/capture.rs`, `preprocess.rs`, `spsc.rs`.

Reemplazar el diseño actual:

```text
callback → Vec por bloque → cola de bloques → “quedarse con el último”
```

por:

```text
callback WASAPI
→ buffers preasignados
→ resampling por canal
→ SPSC de frames continuos
→ extracción exacta de hops de 512
```

Trabajo concreto:

1. Cambiar `AudioPreprocessor` para conservar carriles por canal.
2. Ejecutar `rubato` por canal conservando estado entre callbacks.
3. Sustituir `CapturedBlock { Vec<f32> }` por PCM continuo preasignado.
4. Eliminar `samples.to_vec()` de `publish_block`.
5. Eliminar `latest_block()` y el descarte de bloques intermedios.
6. Introducir contadores atómicos:
   - frames capturados;
   - frames consumidos;
   - underflows;
   - overflows;
   - drops;
   - high-water mark;
   - timestamp del último hop.
7. Insertar silencio sólo ante timeout real y con telemetría.
8. No bloquear nunca el callback WASAPI.

Pruebas obligatorias:

- Paquetes WASAPI de tamaño irregular reconstruyen una secuencia exacta.
- No hay pérdida, duplicado ni reordenamiento de muestras.
- Resampling 44.1→48, 48→48 y 96→48 por canal.
- Señal L = seno, R = −seno sigue produciendo energía visual.
- Underflow/overflow no bloquean ni producen `NaN`.
- Cero asignaciones por callback después del warmup.

Resultado verificable: el Core recibe cada hop en orden, sin depender de la velocidad de la UI.

---

## Bloque 4 — Scheduler DSP con historial solapado

Responsable exclusivo: integrador Core.

Implementar un worker DSP dedicado:

```text
SPSC → consume hop de 512
→ actualiza historial circular de 4096 por canal
→ procesa exactamente una vez por hop
→ publica frame
```

Reglas:

1. Mantener historia de 4096 frames/canal.
2. Extraer ventanas cronológicas de 1024/2048/4096 usando buffers preasignados.
3. Ejecutar las tres STFT por cada hop nuevo.
4. No ejecutar FFT cuando no llegó un hop completo.
5. Resetear onset, perfiles y estado de ventanas al cambiar dispositivo o configuración.
6. Medir por hop `L_c` en microsegundos.
7. No usar Rayon inicialmente; medir primero el rendimiento monohilo de `rustfft` Release.

Pruebas:

- Ventanas solapadas contienen exactamente las últimas muestras esperadas.
- Lecturas FFI rápidas sin captura nueva no aumentan el contador de FFT.
- Cambiar de dispositivo/perfil no mezcla generaciones de datos.
- Stress concurrente con productor 93.75 Hz y consumidor 60/120/144 Hz.

---

## Bloque 5 — LUFS, Pico Maestro y perfiles de presentación

Responsable exclusivo: agente Core DSP.
Archivos: `loudness.rs`, `master_peak.rs`, `features.rs`.

1. Alimentar LUFS una vez por hop, nunca desde una consulta FFI.
2. Mantener filtros K y acumulación por canal.
3. Conservar parámetros aprobados:
   - `Ltarget=-14 LUFS`
   - `gamma_base=1`
   - `gamma_max=2.2`
   - `sigma=6 dB`
   - `alpha_lufs=0.03`
4. Aplicar Pico Maestro y modo híbrido sobre bandas ya fusionadas.
5. No reintroducir tilt destructivo en híbrido.
6. Mantener energía cruda separada de la energía acondicionada.
7. Si se agrega peak-hold, será un vector independiente; nunca sustituirá la energía instantánea.
8. El perfil perceptual será explícito y configurable, no automático.

Pruebas:

- LUFS y energía no colapsan con estéreo antifase.
- El híbrido conserva relaciones entre bandas.
- Onset se emite una vez por hop transitorio, no por cada polling.
- Silencio prolongado restablece estados sin `NaN`/`Infinity`.

---

## Bloque 6 — ABI v2, triple buffer y leases seguros

Responsable exclusivo: integrador FFI.
Archivos: `ffi.rs`, nuevo `frame_store.rs`, `lib.rs`.

No modificar `AudioFrameData` v1 en sitio. Se conservará temporalmente para clientes existentes.

Añadir ABI v2:

```text
get_latest_frame                    → v1, compatibilidad
acquire_latest_analysis_frame_v2    → v2, sin ejecutar DSP
release_analysis_frame_v2           → libera el lease
```

El frame v2 incluirá:

```text
abi_version
flags
rms
rms_dbfs
spectral_centroid_hz
onset_detected
onset_score
band_count
raw_band_energies*
conditioned_band_energies*
band_peak_energies*
band_centers_hz*
sequence
capture_timestamp_us
analysis_sample_rate_hz
hop_frames
compute_latency_us
profile_generation
```

Modelo de ownership:

1. Tres slots preasignados con buffers de capacidad máxima.
2. El worker reserva un slot sin lectores.
3. Escribe todo el frame y publica con ordenamiento `Release`.
4. C# adquiere un lease con ordenamiento `Acquire`.
5. El puntero sólo es válido hasta `release`.
6. El worker nunca sobrescribe un slot arrendado.
7. Si los tres slots están ocupados, no bloquea captura/DSP: registra telemetría y aplica la política de descarte documentada.

Pruebas:

- Layout/offsets de structs Rust y C#.
- Cliente ABI v1 sigue funcionando.
- DLL antigua falla limpiamente al pedir v2.
- Un millón de lecturas sin audio nuevo no ejecuta DSP ni asigna.
- Stress de productor/lector no genera punteros colgantes ni frames parcialmente escritos.
- Reconfiguración con leases activos no destruye buffers aún utilizados.

---

## Bloque 7 — Migración C# y render

Responsable exclusivo: agente UI, después de congelar ABI v2.
Archivos: `src/ui/Audio/**`, `MainWindow`, visualizadores y pruebas .NET.

1. Añadir `AudioFrameLease` como `ref struct`.
2. Implementar:

```csharp
using var lease = audioCore.AcquireLatestFrame();
Render(lease.View);
```

3. Migrar `MainWindow.RenderTick`, Win2D, 3D y transiciones a lease v2.
4. Prohibir retener `ReadOnlySpan<float>` más allá del tick.
5. Mantener `AudioFrame` como DTO sólo para demo, presets y pruebas.
6. Marcar `Current`, `Advance` y `Snapshot()` como rutas legacy fuera del render.
7. Hacer que la UI renderice a su propia cadencia, aunque el DSP publique a 93.75 Hz.
8. Exponer telemetría de perfil, generación, drops y métricas sólo en diagnóstico.

Pruebas:

- 1,000,000 acquire/release sin asignaciones administradas.
- El render no usa `ToArray`, LINQ ni closures sobre spans.
- Cross-fade toma un snapshot explícito al inicio y libera el lease.
- Cambio de perfil/dispositivo no conserva referencias inválidas.
- Onset, centroide, RMS y bandas llegan coherentes al visualizador.

---

## Bloque 8 — Rendimiento, validación y aceptación

Responsable: agente de calidad e integrador.

Crear un benchmark Release reproducible con:

- tono puro;
- sweep 20–500 Hz;
- ruido rosa;
- música con subgrave;
- rock;
- electrónica;
- percusión;
- estéreo en contrafase;
- loopback 44.1/48/96;
- entrada directa.

Medir:

- `L_c` p50/p95/p99;
- CPU del worker DSP;
- working set;
- asignaciones por callback, hop, publicación FFI y render;
- drops, overflows y underflows;
- secuencia de frames;
- 60/120 FPS;
- latencia extremo a extremo desglosada.

Criterios de salida:

- `cargo fmt --check`
- `cargo clippy -- -D warnings`
- `cargo test`
- pruebas FFI/concurrencia
- pruebas .NET
- Build Debug y Release x64
- MSIX valida presencia de `EchoCore.dll` v2
- V3–V6 y VA1–VA5 sólo se marcan aprobadas con evidencia de audio, GPU y duración real.

---

## División de agentes y secuencia

| Orden | Agente | Propiedad exclusiva | Dependencia |
|---:|---|---|---|
| 1 | Requisitos/QA | `docs/**`, trazas, QA | Ninguna |
| 2 | Core DSP | `stft`, multirresolución, bandas, features | Requisitos aprobados |
| 3 | Core captura | `capture`, `preprocess`, `spsc` | Modelo de datos congelado |
| 4 | Integrador Core/FFI | `ffi`, `frame_store`, ABI v2 | DSP + captura |
| 5 | UI | `src/ui/Audio/**`, render, pruebas .NET | ABI v2 congelado |
| 6 | Calidad | benchmarks, V&V, MSIX | Integración completa |

Los agentes de documentación pueden trabajar en paralelo con el diseño offline del DSP. Captura, FFI y UI se integrarán secuencialmente para evitar conflictos sobre tipos compartidos y ownership.

El siguiente paso, si apruebas este plan, es ejecutar el Bloque 0 y el Bloque 1: consolidar `dev`, crear la rama única de feature y actualizar formalmente la especificación antes de tocar la arquitectura DSP.