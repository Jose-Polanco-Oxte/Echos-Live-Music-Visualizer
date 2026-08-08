# Trazabilidad de requisitos y fórmulas: Visualizador 2D con Batching GPU Direct2D en Win2D

- **Feature / incremento:** Visualizador 2D con Batching GPU Direct2D en Win2D (Win2D GPU Batching Visualizer)
- **Fecha:** 2026-08-05
- **Responsable:** Codex
- **Estado:** Especificado / Listo para Implementación

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RF-VIS.1 | `Especificacion-de-requerimientos.md` §RF-VIS.1 | Visualización espectral 2D bidimensional acelerada por hardware GPU | Dibujado inmediato acelerado por GPU vía Direct2D / Win2D |
| RF-VIS.2 | `Especificacion-de-requerimientos.md` §RF-VIS.2 | Variantes de visualización 2D (barras, espejo, pulso, resplandor, reflejo) | Renderizado dinámico de resplandor bloom, reflejos atenuados por alfa y marcadores de pico |
| RNF-PERF.1 | `Especificacion-de-requerimientos.md` §RNF-PERF.1 | Relleno de cuadro gráfico a 60–120 FPS sin vacilaciones (*stuttering*) | Mantener cadencia de render de 60–120 FPS con tiempo GPU/CPU por cuadro < 0.8 ms |
| RNF-MEM.1 | `Especificacion-de-requerimientos.md` §RNF-MEM.1 | 0 asignaciones de memoria Heap en el bucle caliente de renderizado (Zero-GC hot path) | 0 bytes/frame de asignación Gen0/LOH en los callbacks de dibujado `CanvasControl_Draw` |
| RNF-REL.2 | `Especificacion-de-requerimientos.md` §RNF-REL.2 | Recuperación transparente ante eventos de pérdida de dispositivo GPU | Recreación limpia de pinceles y recursos GPU en `CreateResources` ante reset de Direct3D |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula / optimización |
|---|---|---|---|
| RF-VIS.1 | [`Win2DGpuSpectralBarVisualizer.cs`](../../src/ui/Visualizers/Win2DGpuSpectralBarVisualizer.cs) :: `OnDraw` | `CanvasControl`, `CanvasDrawingSession` | Emisión de primitivas Direct2D batching en modo inmediato |
| RF-VIS.2 | [`Win2DGpuSpectralBarVisualizer.cs`](../../src/ui/Visualizers/Win2DGpuSpectralBarVisualizer.cs) :: `DrawBars` | $r_{\text{glow}}$, $\alpha_{\text{refl}}$, $h_{p,i}$ | Emisión de `FillRoundedRectangle` para resplandor, cuerpo, pico y reflejo lineal |
| RNF-PERF.1 | [`MainWindow.xaml`](../../src/ui/MainWindow.xaml) :: `Win2DCanvasControl` | Target FPS: 60–120 Hz | Renderizado directo en superficie GPU acelerada `CanvasControl` |
| RNF-MEM.1 | [`Win2DGpuSpectralBarVisualizer.cs`](../../src/ui/Visualizers/Win2DGpuSpectralBarVisualizer.cs) :: `InitializeGpuResources` | `CanvasLinearGradientBrush`, `CanvasSolidColorBrush` | Preasignación estática de pinceles y reutilización in-situ sin instanciar objetos Heap en `OnDraw` |
| RNF-REL.2 | [`Win2DGpuSpectralBarVisualizer.cs`](../../src/ui/Visualizers/Win2DGpuSpectralBarVisualizer.cs) :: `OnCreateResources` | `CanvasCreateResourcesEventArgs`, `CanvasCreateResourcesReason` | Re-creación y restauración automática de recursos GPU al producirse `NewDevice` |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado proyectado |
|---|---|---|---|
| RF-VIS.1 / RF-VIS.2 | Ejecución de `dotnet test tests/EchoVisualizer.Tests/` | 100% de la suite de pruebas C# FFI | PASS: `dotnet test` |
| RNF-PERF.1 | Perfilado de rendimiento de render a 120 FPS | Tiempo de dibujado en GPU/CPU < 0.8 ms | PASS: Render fluido a 120 Hz |
| RNF-MEM.1 | Perfilado de memoria .NET / Benchmark de render loop | Asignaciones Gen0 en callback `OnDraw` | PASS: 0 bytes/frame |
| RNF-REL.2 | Simulación de reset de dispositivo GPU / Minimización | Re-ejecución de `OnCreateResources` sin crash | PASS: Recreación transparente sin excepciones |
