# Plan de Implementación: Optimización de Rendimiento y Eliminación de GC (Performance & GC Optimization)

## 1. Contexto, Diagnóstico y Objetivos

### 1.1 Diagnóstico del Rendimiento Actual
Tras la integración del pipeline de audio multirresolución HI-FI y el escalado espectral logarítmico en decibelios (dB), se realizó una auditoría de rendimiento y perfilado de asignaciones de memoria (GC profiling) en la ruta caliente (*hot path*) de renderizado 2D/3D y procesamiento DSP.

Se identificaron 5 focos de ineficiencia y asignaciones de memoria por frame tick:

1. **Mutación Redundante de DependencyProperties XAML en 2D (`Win2DSpectralBarVisualizer.cs`):**
   En cada tick de dibujado (60–120 Hz), el método `SetRectangle` escribe incondicionalmente en las propiedades XAML (`Width`, `Height`, `Opacity`, `Canvas.Left`, `Canvas.Top`) y `brush.Color` de 192 objetos `Rectangle` (48 barras $\times$ 4 elementos). Esto desencadena notificaciones internas de layout e interop nativo en WinUI 3 aun cuando los valores se mantienen estacionarios o varían por debajo de la resolución visible.

2. **Asignaciones Heap de Vectores 3D por Tick (`D3D11SpectralMeshVisualizer.cs` & `SpectralMesh3DMath.cs`):**
   En el renderizador 3D Direct3D 11 (`D3D11SpectralMeshVisualizer.cs`), la función `RenderMesh` instancia `new MeshVertex[mesh.Columns.Length * 2]` en cada frame. Adicionalmente, `SpectralMesh3DMath.BuildFrameState` realiza `new SpectralMeshColumn[count]` en cada frame tick. A 120 FPS, esto genera miles de asignaciones de arreglos temporales en el GC Gen0/LOH por segundo.

3. **Cálculo Logarítmico Redundante por Cancelación Matemática (`SpectralBarMath.cs`):**
   En `SpectralBarMath.AudioMappedColor`, la frecuencia central $f_c$ se calcula mediante exponenciación $\text{MinimumFrequencyHz} \cdot \left(\frac{\text{MaximumFrequencyHz}}{\text{MinimumFrequencyHz}}\right)^{\text{progress}}$, y acto seguido se toma $\frac{\log(f_c / f_{\min})}{\log(f_{\max} / f_{\min})}$. Ambas operaciones trascendentes (`MathF.Pow` y dos `MathF.Log`) se cancelan algebraicamente de forma exacta a `progress`. Evaluarlas en cada barra y tick ($5,760$ veces/seg a 120 Hz / 48 barras) resulta en consumo inútil de ciclos de CPU.

4. **Asignación Indiscriminada de Cadenas de Texto UI (`MainWindow.xaml.cs`):**
   En `RenderFrame`, se ejecutan llamadas incondicionales a `activeId.ToUpperInvariant()` e interpolación de cadenas en `AudioStatusText.Text` a 60–120 Hz. Dado que el ojo humano no percibe cambios de texto de estado a 120 Hz, esto asigna innecesariamente entre 240 y 480 objetos `System.String` por segundo en el Heap de .NET.

5. **Reevaluación Trascendente de Tilt y Ramificaciones en Bucle STFT en Rust (`master_peak.rs` & `stft.rs`):**
   En Rust Core (`master_peak.rs`), `condition_hybrid_band_energies` ejecuta `.powf(MASTER_PINK_NOISE_EXPONENT)` para cada banda en cada hop (93.75 Hz), pese a que las frecuencias centrales son fijas. En `stft.rs`, el bucle de ventanado ejecuta `if sample.is_finite()` por cada muestra PCM, introduciendo posibles *branch mispredictions* en la canalización del procesador.

### 1.2 Objetivo del Plan
Eliminar el 100% de las asignaciones de memoria por frame tick en la capa gráfica (0 GC allocations per frame tick), suprimir llamadas trascendentes redundantes en C# y Rust, y reducir las notificaciones XAML nativas en más del 85%, alcanzando un rendimiento fluido y determinista a 60–120 Hz (cumpliendo RNF-PERF.1, RNF-MEM.1 y RNF-REL.2).

---

## 2. Especificación Técnica y Matemática de los 5 Ítems de Optimización

### 2.1 Ítem A: Dirty Checks de Propiedades XAML en `Win2DSpectralBarVisualizer.cs`

#### Ubicación del Código
src/ui/Visualizers/Win2DSpectralBarVisualizer.cs

#### Especificación Matemática & Algorítmica
Dado un rectángulo XAML $R$ y un valor objetivo de geometría $(x, y, w, h)$, color $C$ y opacidad $\alpha$, se define una tolerancia flotante $\epsilon = 10^{-3} = 0.001$.

Las asignaciones nativas de XAML se ejecutan **únicamente** si se cumple la condición de *dirty*:

\[
\text{IsDirty}_w \iff |R.\text{Width} - w| > \epsilon
\]
\[
\text{IsDirty}_h \iff |R.\text{Height} - h| > \epsilon
\]
\[
\text{IsDirty}_\alpha \iff |R.\text{Opacity} - \alpha| > \epsilon
\]
\[
\text{IsDirty}_x \iff |\text{Canvas.GetLeft}(R) - x| > \epsilon
\]
\[
\text{IsDirty}_y \iff |\text{Canvas.GetTop}(R) - y| > \epsilon
\]
\[
\text{IsDirty}_c \iff \text{brush}.\text{Color} \neq C
\]

#### Reducción de Overhead Computacional
Para $B$ barras y $S=4$ formas por barra a $f_{\text{fps}} = 120\text{ Hz}$:
- **Sin dirty check:** $6 \times S \times B \times f_{\text{fps}} = 6 \times 4 \times 48 \times 120 = 138,240$ mutaciones XAML/seg.
- **Con dirty check (estado estacionario/silencio):** $0$ mutaciones XAML/seg.
- **Con dirty check (música continua):** Reducción de $\ge 85\%$ en escrituras de propiedades de posición XAML.

---

### 2.2 Ítem B: Arreglos Preasignados Reutilizables `MeshVertex[]` y `SpectralMeshColumn[]`

#### Ubicación del Código
- src/ui/Visualizers/D3D11SpectralMeshVisualizer.cs
- src/ui/Visualizers/SpectralMesh3DMath.cs

#### Especificación Técnica & Algorítmica
1. En `D3D11SpectralMeshVisualizer`, preasignar un buffer de staging de vértices de tamaño máximo fijo:
   ```csharp
   private readonly MeshVertex[] _vertexStaging = new MeshVertex[SpectralMesh3DMath.MaximumBands * 2];
   ```
2. En `SpectralMesh3DMath`, reutilizar o devolver un buffer preasignado o `Span<SpectralMeshColumn>` sin instanciar `new SpectralMeshColumn[count]` en cada frame.
3. Modificar `RenderMesh` para rellenar los elementos de `_vertexStaging` hasta `mesh.Columns.Length * 2` y pasar un slice `ReadOnlySpan<MeshVertex>` a `UploadVertices`.

#### Métrica de Memoria
\[
\text{GCAlloc}_{\text{tick}} = 0\ \text{bytes} \quad (\text{cumpliendo RNF-MEM.1})
\]

---

### 2.3 Ítem C: Progreso Lineal Libre de Cancelación en `AudioMappedColor`

#### Ubicación del Código
src/ui/Visualizers/SpectralBarMath.cs

#### Demostración y Derivación Matemática
En la implementación original:
1. `CentralFrequencyHz(index, count)` calcula:
   \[
   f(i) = f_{\min} \cdot \left( \frac{f_{\max}}{f_{\min}} \right)^{p_i}, \quad \text{donde } p_i = \frac{i}{N - 1}
   \]
2. `AudioMappedColor` calcula la frecuencia relativa $r_i$:
   \[
   r_i = \frac{\ln\left( \frac{f(i)}{f_{\min}} \right)}{\ln\left( \frac{f_{\max}}{f_{\min}} \right)}
   \]
3. Sustituyendo $f(i)$ en $r_i$:
   \[
   r_i = \frac{\ln\left( \frac{f_{\min} \cdot \left( \frac{f_{\max}}{f_{\min}} \right)^{p_i}}{f_{\min}} \right)}{\ln\left( \frac{f_{\max}}{f_{\min}} \right)} = \frac{\ln\left( \left( \frac{f_{\max}}{f_{\min}} \right)^{p_i} \right)}{\ln\left( \frac{f_{\max}}{f_{\min}} \right)} = \frac{p_i \cdot \ln\left( \frac{f_{\max}}{f_{\min}} \right)}{\ln\left( \frac{f_{\max}}{f_{\min}} \right)} \equiv p_i
   \]

#### Algoritmo Optimizado
Sustituir el cálculo trascendente por la asignación directa:
```csharp
public static Vector3 AudioMappedColor(int index, int count, float spectralCentroidHz)
{
    var relativeFrequency = count <= 1 ? 0.5f : Math.Clamp(index / (float)(count - 1), 0f, 1f);
    var centroid = Math.Clamp(SanitizeFrequencyHz(spectralCentroidHz) / MaximumFrequencyHz, 0f, 1f);
    var hue = Wrap01(0.54f + (relativeFrequency * 0.37f) + ((centroid - 0.5f) * 0.14f));
    return HsvToRgb(hue, 0.82f, 1f);
}
```
Complejidad temporal reducida de $O(\text{pow} + 2\ln)$ a $O(1)$ operaciones FP32 escalares primarias.

---

### 2.4 Ítem D: Throttling de Asignaciones de Cadenas en `MainWindow.xaml.cs`

#### Ubicación del Código
src/ui/MainWindow.xaml.cs

#### Especificación Técnica & Algorítmica
1. **`ActiveVisualizerText.Text`:** Cachear el resultado de `activeId.ToUpperInvariant()` en un campo de instancia `_cachedActiveIdUpper`. Actualizar la cadena únicamente cuando cambie `activeId` en `ConfigureVisualizerHost`.
2. **`AudioStatusText.Text`:** Introducir un acumulador de tiempo `_statusUpdateTimer` para actualizar el texto UI únicamente a un intervalo de $100\text{ ms}$ (10 Hz), o cuando se detecte un cambio de estado en `OnsetDetected`.

#### Impacto en Garbage Collection
Eliminación de $\sim 480$ instancias de `System.String` por segundo en el hilo principal de la UI.

---

### 2.5 Ítem E: Vectores de Inclinación Precalculados (`pink_noise_tilts`) y Sanitización Branchless en Rust

#### Ubicación del Código
- src/core/src/master_peak.rs
- src/core/src/stft.rs

#### Especificación Técnica & Algorítmica

##### E.1 Precálculo de Pink Noise Tilts (`master_peak.rs`)
En la estructura `MasterPeakScaler`, añadir el vector precalculado `pink_noise_tilts: Vec<f32>`:
```rust
pub struct MasterPeakScaler {
    master_peak: f32,
    hybrid_was_silent: bool,
    scaling_mode: SpectralScalingMode,
    pink_noise_tilts: Vec<f32>,
}
```
Al cambiar el número de bandas o la configuración de rangos (`update_band_ranges(&mut self, band_ranges: &[BandRange])`):
\[
\text{pink\_noise\_tilts}[i] = \left( \frac{\max(f_{c,i}, 1.0)}{1000.0} \right)^{0.10}
\]
En `condition_hybrid_band_energies`, reemplazar la llamada `.powf(...)` por la lectura directa indexada `self.pink_noise_tilts[i]`.

##### E.2 Sanitización Branchless de Muestras PCM (`stft.rs`)
Reemplazar la bifurcación condicional:
`let sample = if sample.is_finite() { *sample } else { 0.0 };`
por una evaluación sin ramificación (*branchless*) basada en operaciones de bits o multiplicación por máscara de validez:
```rust
let bits = sample.to_bits();
// La máscara es 1.0f32 (0x3F800000) si es finito, 0.0f32 (0x0) si es NaN/Inf.
let is_finite_mask = if (bits & 0x7F80_0000) != 0x7F80_0000 { 1.0_f32 } else { 0.0_f32 };
let sample = sample * is_finite_mask;
```
Esto garantiza la eliminación de fallos de predicción de salto en la canalización del procesador durante el procesamiento STFT de muestras audio.

---

## 3. Matriz de Componentes Afectados

| Componente | Archivo | Modificación Principal | Impacto de Rendimiento |
|---|---|---|---|
| Retained 2D Visualizer | `Win2DSpectralBarVisualizer.cs` | Dirty checks en `SetRectangle` | -85% escrituras XAML DP |
| Direct3D 11 Renderer | `D3D11SpectralMeshVisualizer.cs` | Reuso de `_vertexStaging` `MeshVertex[]` | 0 GC allocs per frame en 3D |
| 3D Mesh Math | `SpectralMesh3DMath.cs` | Reuso de arreglo de `SpectralMeshColumn` | 0 GC allocs per frame |
| 2D Bar Math | `SpectralBarMath.cs` | Simplificación $O(1)$ de `AudioMappedColor` | Eliminación de `Pow` y 2 `Log` por barra |
| WinUI Host Window | `MainWindow.xaml.cs` | Cacheo de `ToUpperInvariant()` y throttling UI text | -480 strings alloc/sec |
| Master Peak Scaler | `master_peak.rs` | Pre-cómputo de `pink_noise_tilts: Vec<f32>` | Eliminación de `powf()` en el bucle DSP |
| STFT Core Analyzer | `stft.rs` | Sanitización branchless de PCM | Eliminación de branch mispredictions en STFT |

---

## 4. Plan de Pruebas y Criterios de Aceptación

### 4.1 Pruebas Automáticas en Rust
- `cargo test`: Verificar que `rf4_3_4_hybrid_decibel_scaling_bounds_and_reactivity` y la suite completa de 71 pruebas en Rust continúen pasando al 100%.

### 4.2 Pruebas Automáticas en .NET
- `dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Debug -p:Platform=x64`: Verificar que las 38 pruebas unitarias e integrales en C# pasen sin fallos.

### 4.3 Validación de Asignaciones y Latencia
- **Criterio RNF-MEM.1:** Verificar que durante un ciclo continuo de renderizado de 60 segundos en 2D y 3D, las asignaciones en Gen0 provocadas por las clases visualizadoras sean $0\text{ bytes/frame}$.
- **Criterio RNF-PERF.1:** Mantener una cadencia estable de render de 60 a 120 FPS sin picos de congelamiento (*stuttering*) producidos por recolección de basura.
