# Trazabilidad de requisitos y fórmulas

- **Feature / incremento:** RS-SM3D — Malla espectral 3D D3D11
- **Fecha:** 2026-07-29
- **Responsable:** agentes `d3d_visualizer` y `d3d_host`
- **Estado:** `[OBSOLETO / RETIRADO DE ALCANCE - SECCIÓN IV]` (La Malla 3D fue retirada del alcance según la Sección IV de `Especificacion-de-requerimientos.md`).

## Fuente normativa

| ID de requisito | Sección exacta | Fórmula, rango, unidad o regla transcrita | Criterio de aceptación |
|---|---|---|---|
| RS-SOL-D | `Especificacion-de-requerimientos.md` §Plantilla de Especificación de Nueva Solución Visual | Declarar perfil: N, distribución y `x_RMS`, `f_C`, `Onset`; asignar `E_i` a geometría; mapear descriptores globales a cámara/rotación/paleta; definir respuesta exacta a `Onset == true`. | Las tres capas están declaradas y el visualizador sólo consume `AudioFrameData` administrado. |
| Fase V — Malla Espectral 3D | `Echo-Development-Plan.md` §Fase V | Usar `Vortice.Direct3D11`, `SwapChainPanel`, RTV, DSV, viewport, `SizeChanged`; compilar/cargar `MeshTransform.hlsl` y `SpectrumGlow.hlsl`; actualizar a 60 FPS el constant buffer con MVP y vector `E_i`. | Host D3D11 crea/libera recursos y expone `Render`; shaders existen; el host recibe frame y el código de integración debe llamarlo a 60 Hz. |
| RNF-REU.1 | `Especificacion-de-requerimientos.md` §2 Reusabilidad | El 100 % de la FFT, suavizado y calibración se reutiliza por `AudioFrameData`. | No hay FFT, filtro o cálculo psicoacústico en este módulo. |
| RNF-PERF.2 | `Especificacion-de-requerimientos.md` §1 Eficiencia de Desempeño | Mantener ≥60 FPS continuos sin frame drops. | No se declara validado hasta ejecutar el host sobre GPU/panel reales. |

## Perfil y mapeos de la solución

| Capa | Definición implementada |
|---|---|
| Datos | `N = clamp(BandEnergies.Length, 1, 128)`, distribución entregada por el Core (no se reagruppa); consume RMS normalizado `[0,1]`, centroide Hz y onset. |
| Geometría | Para la columna `i`: `x = ((i / max(N-1,1)) - 0.5) * 12`, `height = 0.10 + 4.00 * clamp(E_i,0,1)`, `z = 0`. Cada `E_i` controla altura continua; las unidades espaciales son unidades de mundo. |
| Cámara/paleta | `rotationRadians = elapsedSeconds * (0.35 + 1.15 * clamp(RMS,0,1))`; el brillo del shader usa `saturate(E_i + 0.25 * RMS + onsetFlash)`. El centroide se normaliza a `saturate(f_C / 20000 Hz)` y modula el tono de cian a magenta. |
| Evento | `Onset == true` fija `onsetFlash = 1.0`; en frames siguientes decae como `max(0, flash - deltaSeconds * 2.5)`. |

## Mapeo de implementación

| Requisito | Archivo y símbolo | Variables/parámetros y unidades | Relación exacta con la fórmula |
|---|---|---|---|
| RS-SOL-D | `src/ui/Visualizers/SpectralMesh3DMath.cs` :: `BuildFrameState` | `E_i`, RMS `[0,1]`, `f_C` Hz, delta s | Produce alturas, rotación y flash exactamente según la tabla anterior. |
| Fase V | `src/ui/Visualizers/D3D11SpectralMeshVisualizer.cs`, `MainWindow.xaml(.cs)`, shaders y dependencias de `EchoVisualizer.csproj` | Constant buffer: MVP, 128 `E_i` f32, tiempo s y RMS `[0,1]`; Vortice 3.8.3 | El host crea el `SwapChainPanel` de composición, RTV, DSV y viewport; el temporizador existente de 16 ms llama `Render(frame)` después de consumir `AudioFrameData`. El vertex shader indexa `BandEnergies[band / 4][band % 4]` (mediante operaciones de bits equivalentes) para colorear cada columna. |
| Fase V | `src/ui/Shaders/MeshTransform.hlsl`, `SpectrumGlow.hlsl` | matrices float4x4 y energía normalizada | Vertex transforma con MVP; pixel calcula glow de la fórmula declarada. |
| RNF-REU.1 | `D3D11SpectralMeshVisualizer.Render` | `AudioFrame` | Sólo copia los descriptores del contrato administrado; no procesa PCM/FFT. |

## Verificación

| Requisito | Prueba automatizada / procedimiento manual | Casos límite y tolerancia | Resultado |
|---|---|---|---|
| RS-SOL-D | `SpectralMesh3DMathTests`: N=1, energía fuera de rango, onset/decay y valores no finitos. | No NaN/Inf; alturas en `[0.1,4.1]`; columna única centrada. | 2026-07-29: 2 pruebas superadas. |
| Fase V | `MSBuild EchoVisualizer.sln Debug|x64`; compilar `MeshTransform.hlsl` (`vs_5_0`) y `SpectrumGlow.hlsl` (`ps_5_0`) con `fxc`. Manual: seleccionar la malla, redimensionar a 0 y a tamaño válido, comprobar que no hay recursos obsoletos y que la malla responde al audio. | La asociación COM necesita panel WinUI real; la prueba manual queda pendiente de ejecutar en GPU/panel reales. | Compilación y ambos HLSL correctos; prueba manual pendiente. |
| RNF-PERF.2 | Medir Present/Render a 1080p y 4K por ≥60 s en GPU objetivo. | ≥60 FPS sin drop. | pendiente (no inferido). |

## Desviaciones o decisiones

La medición de 60 FPS, la transición híbrida y la validación sobre GPU real siguen pendientes. El host no introduce FFT, agrupación ni suavizado: consume únicamente los descriptores ya normalizados de `AudioFrameData` (RNF-REU.1). La meta de 60 FPS no se afirma como aprobada: el timer solicita frames cada 16 ms, pero la tasa presentada debe medirse en el equipo objetivo.
