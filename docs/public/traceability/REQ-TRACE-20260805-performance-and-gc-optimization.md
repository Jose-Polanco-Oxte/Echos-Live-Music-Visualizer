# Trazabilidad de requisitos y fórmulas: Optimización de Rendimiento y Eliminación de GC

- **Feature / incremento:** Optimización de Rendimiento y Eliminación de GC (Performance & GC Optimization)
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** Especificado / Listo para Implementación

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RNF-PERF.1 | `Especificacion-de-requerimientos.md` §RNF-PERF.1 | Relleno de cuadro gráfico a 60–120 FPS sin vacilaciones (*stuttering*) ni demoras por GC | Mantener cadencia de render de 60–120 FPS con p99 compute latency < 1.5 ms |
| RNF-MEM.1 | `Especificacion-de-requerimientos.md` §RNF-MEM.1 | 0 asignaciones de memoria Heap en el bucle caliente de renderizado (Zero-GC hot path) | 0 bytes/frame de asignación Gen0/LOH en los ciclos de dibujado 2D y 3D |
| RNF-REL.2 | `Especificacion-de-requerimientos.md` §RNF-REL.2 | Reproducción determinista y eficiente sin uso excesivo de CPU o notificaciones UI redundantes | Reducción de $\ge 85\%$ en mutaciones XAML nativas y eliminación de $5,760$ op. trascendentes/seg redundantes |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula / optimización |
|---|---|---|---|
| RNF-REL.2 | [`Win2DSpectralBarVisualizer.cs`](../../src/ui/Visualizers/Win2DSpectralBarVisualizer.cs) :: `SetRectangle` | $\epsilon = 10^{-3}$, `IsDirty` checks | Asigna propiedades XAML (`Width`, `Height`, `Opacity`, `Canvas.Left`, `Canvas.Top`, `Color`) solo si $|V - V_{\text{prev}}| > \epsilon$ |
| RNF-MEM.1 | [`D3D11SpectralMeshVisualizer.cs`](../../src/ui/Visualizers/D3D11SpectralMeshVisualizer.cs) :: `RenderMesh` | `_vertexStaging: MeshVertex[]` | Reutiliza buffer preasignado `MaximumBands * 2` evitando `new MeshVertex[]` por tick |
| RNF-MEM.1 | [`SpectralMesh3DMath.cs`](../../src/ui/Visualizers/SpectralMesh3DMath.cs) :: `BuildFrameState` | `SpectralMeshColumn[]` buffer reusable | Elimina la instanciación `new SpectralMeshColumn[count]` en cada frame tick |
| RNF-REL.2 | [`SpectralBarMath.cs`](../../src/ui/Visualizers/SpectralBarMath.cs) :: `AudioMappedColor` | `relativeFrequency = index / (count - 1)` | Simplifica la cancelación matemática $\frac{\ln(f_0 (f_1/f_0)^p / f_0)}{\ln(f_1/f_0)} \equiv p$ a $O(1)$ |
| RNF-MEM.1 | [`MainWindow.xaml.cs`](../../src/ui/MainWindow.xaml.cs) :: `RenderFrame` | `_cachedActiveIdUpper`, UI status text throttler | Cancela la creación de $\sim 480$ instancias de `System.String` por segundo |
| RNF-REL.2 | [`master_peak.rs`](../../src/core/src/master_peak.rs) :: `MasterPeakScaler` | `pink_noise_tilts: Vec<f32>` | Almacena factores $(f_c / 1000.0)^{0.10}$ precalculados, suprimiendo `.powf()` por hop |
| RNF-REL.2 | [`stft.rs`](../../src/core/src/stft.rs) :: `analyze_windows` | PCM branchless sanitization | Elimina `if sample.is_finite()` evitando *branch mispredictions* en el bucle STFT |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado proyectado |
|---|---|---|---|
| RNF-MEM.1 | Perfilado de memoria .NET / Benchmark de render de 60s | Asignaciones Gen0 en render loop | PASS: 0 bytes/frame |
| RNF-PERF.1 | Pruebas de integración FFI `dotnet test tests/EchoVisualizer.Tests/` | 100% de la suite de pruebas C# FFI | PASS: `dotnet test` |
| RNF-REL.2 | Pruebas unitarias Core Rust `cargo test` | 100% de la suite de pruebas Rust (71/71) | PASS: `cargo test` |
