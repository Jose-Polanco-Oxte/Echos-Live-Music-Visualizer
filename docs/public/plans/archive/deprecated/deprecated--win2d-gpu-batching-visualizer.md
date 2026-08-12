# Plan de Implementación: Visualizador 2D con Batching GPU Direct2D en Win2D (Win2D GPU Batching Visualizer)

## 1. Contexto, Diagnóstico y Objetivos

### 1.1 Diagnóstico Arquitectónico y Necesidad Técnica
Actualmente, la visualización 2D de barras espectrales en `src/ui/Visualizers/Win2DSpectralBarVisualizer.cs` utiliza un modelo *retained-mode* mediante elementos `Rectangle` de XAML administrados. Si bien las optimizaciones de *dirty checking* reducen el impacto en el árbol visual, el dibujado mediante la composición de XAML incurre en sobrecostos de notificaciones de propiedades y recorrido de árbol.

El renderizado mediante **Win2D Direct2D GPU Batching** en modo inmediato (*immediate-mode*) a través de `Microsoft.Graphics.Canvas.UI.Xaml.CanvasControl` y `CanvasDrawingSession` permite enviar comandos de dibujo directamente al pipeline de Direct2D acelerado por GPU (Direct3D 11/12), alcanzando una latencia de dibujado ultrabaja (< 0.5 ms por cuadro) a tasas de refresco de 60 a 120 Hz.

Anteriormente, el uso de `CanvasControl` causaba una excepción de violación de acceso (`0xc0000005`) durante la inicialización de la ventana principal en aplicaciones empacadas WinUI 3 (QA-INC-20260729). Para superar esta restricción de forma segura, el presente plan establece el ciclo de vida riguroso de inicialización diferida (*deferred resource loading*), captura de pérdida de dispositivo GPU (*device loss recovery*) y batching de primitivas de Direct2D sin asignaciones de memoria en el hilo principal de dibujado.

### 1.2 Objetivos Principales
1. **Implementar el Renderizador Direct2D Inmediato:** Crear el visualizador `Win2DGpuSpectralBarVisualizer` basado en `CanvasControl` y `CanvasDrawingSession`.
2. **Garantizar 0 Asignaciones GC en la Cadena de Renderizado:** Preasignar pinceles (`CanvasLinearGradientBrush`, `CanvasSolidColorBrush`) y buffers geométricos para lograr 0 bytes de asignación Heap por frame tick (`RNF-MEM.1`).
3. **Soporte de Recuperación de Dispositivo GPU:** Manejar eventos `CreateResources` y captura de `CanvasException` por pérdida de dispositivo Direct3D/Direct2D sin bloquear la UI ni provocar fallos de ejecución.
4. **Mantener Paridad Visual y Modos:** Renderizar barras con esquinas redondeadas, reflejos dinámicos con gradientes de atenuación alfa, resplandor (*bloom glow*) y marcadores de pico (*peak hold*) en layouts `BottomUp`, `TopDown` y `CenterOut`.

---

## 2. Especificación Técnica y Matemática de los Componentes

### 2.1 Ciclo de Vida e Inicialización de `CanvasControl`

#### 2.1.1 Suscripción a Eventos y Registro de Recursos
La integración con WinUI 3 requiere suscribirse a dos eventos clave de `CanvasControl`:
- `CreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)`: Ejecutado durante la inicialización y tras la recreación de dispositivos GPU perdidos.
- `Draw(CanvasControl sender, CanvasDrawEventArgs args)`: Invocado en cada ciclo de repintado controlado por la tasa de refresco de la pantalla.

```csharp
private void OnCreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
{
    if (args.Reason == CanvasCreateResourcesReason.FirstTime)
    {
        // Preasignación de pinceles estáticos y estructuras reutilizables
        InitializeGpuResources(sender);
    }
    else if (args.Reason == CanvasCreateResourcesReason.NewDevice)
    {
        // Recreación de recursos GPU dependientes del dispositivo
        RecreateDeviceResources(sender);
    }
}
```

#### 2.1.2 Manejo de Pérdida de Dispositivo (*Device Lost Recovery*)
Si la GPU experimenta un reinicio de controlador o cambio de modo de pantalla, `DrawingSession` lanzará un fallo de dispositivo Direct3D. La clase captura el evento y delega a `sender.RemoveFromVisualTree()` o re-invoca la reconstrucción de recursos de forma transparente.

---

### 2.2 Algoritmo y Geometría de Renderizado Direct2D Batching

#### 2.2.1 Cálculo de Geometría de Barras y Resplandor
Dado el tamaño de la superficie de dibujado $W \times H$, el número de barras $B$, el espacio entre barras $g$ (*gap*) y el relleno lateral $P = 28\text{ px}$:

\[
\text{barWidth} = \max\left(1.0, \frac{W - 2P - g \cdot (B - 1)}{B}\right)
\]

Para cada barra $i \in [0, B-1]$ con energía suavizada $E_i \in [0, 1]$:
\[
H_{\max} = (H - 2P) \cdot 0.75
\]
\[
h_i = \begin{cases} 0 & \text{si } E_i \le 10^{-4} \\ \max(h_{\min}, E_i \cdot H_{\max}) & \text{si } E_i > 10^{-4} \end{cases}
\]
\[
x_i = P + i \cdot (\text{barWidth} + g)
\]

La posición $y_i$ según la disposición (*layout*):
- **BottomUp:** $y_i = H - P - h_i$
- **TopDown:** $y_i = P$
- **CenterOut:** $y_i = \frac{H - h_i}{2}$

#### 2.2.2 Formato de Dibujado de Primitivas Direct2D en `DrawingSession`
En lugar de mutar objetos XAML, `DrawingSession` escribe comandos en el buffer de comandos de Direct2D en una sola pasada:

1. **Fondo y Resplandor Bloom:**
   Para cada barra $i$, se calcula el radio de resplandor $r_{\text{glow}} = \max(0, \text{BloomRadius}) \cdot (0.45 + 0.55 \cdot \text{RMS})$.
   Se emite la llamada de resplandor mediante `FillRoundedRectangle`:
   \[
   \text{ds.FillRoundedRectangle}(x_i - r_{\text{glow}}, y_i - r_{\text{glow}}, \text{barWidth} + 2r_{\text{glow}}, h_i + 2r_{\text{glow}}, r_c, r_c, \text{glowColor})
   \]

2. **Cuerpo Principal de la Barra:**
   \[
   \text{ds.FillRoundedRectangle}(x_i, y_i, \text{barWidth}, h_i, r_c, r_c, \text{barColor})
   \]

3. **Marcador de Pico (*Peak Indicator*):**
   Dado el valor de pico retenido $P_i$, la altura del pico es $h_{p,i} = \max(h_{\min}, P_i \cdot H_{\max})$.
   Posición vertical del pico $y_{p,i} = H - P - h_{p,i}$ (para `BottomUp`).
   \[
   \text{ds.FillRoundedRectangle}(x_i, y_{p,i}, \text{barWidth}, \text{peakThickness}, 1.0, 1.0, \text{barColor})
   \]

4. **Reflejo Inferior con Gradiente de Atenuación Alfa:**
   Si `ReflectionEnabled == true`, se dibuja el reflejo atenuado usando un pincel reutilizable `CanvasLinearGradientBrush` con gradiente desde $\alpha_{\text{refl}} = 0.10 + 0.16 \cdot \text{RMS}$ hasta $\alpha = 0.0$:
   \[
   \text{ds.FillRoundedRectangle}(x_i, y_{\text{refl}}, \text{barWidth}, h_{\text{refl}}, r_c, r_c, \text{reflectionBrush})
   \]

---

### 2.3 Cero Asignaciones GC en el Render Loop (`RNF-MEM.1`)

Para asegurar la ausencia de asignaciones de memoria Heap en `CanvasControl_Draw`:
1. **Pinceles Preasignados:** Se utilizan campos miembros de tipo `CanvasSolidColorBrush` y `CanvasLinearGradientBrush` cuya propiedad `.Color` se actualiza in-situ.
2. **Estructuras Struct de Geometría:** La estructura `Vector4` o `Rect` nativa de `Windows.Foundation` se pasa por valor sin instanciaciones de clases.
3. **No String Conversions / Closures:** No se crean expresiones lambda ni delegados temporales dentro del callback `Draw`.

---

## 3. Matriz de Componentes Afectados

| Componente | Archivo / Ubicación | Modificación Principal | Impacto en Rendimiento |
|---|---|---|---|
| Win2D Direct2D Renderer | `src/ui/Visualizers/Win2DGpuSpectralBarVisualizer.cs` | Nueva clase visualizadora basada en `CanvasControl` | Direct2D GPU Batching ultra-fluido |
| Main UI Window | `src/ui/MainWindow.xaml` | Incorporación del control `<canvas:CanvasControl x:Name="Win2DCanvasControl" />` | Host nativo Win2D |
| MainWindow Controller | `src/ui/MainWindow.xaml.cs` | Enrutamiento de fotogramas `AudioFrame` hacia `Win2DGpuSpectralBarVisualizer` | Integración del render loop GPU 2D |
| Visualizer Common Math | `src/ui/Visualizers/SpectralBarMath.cs` | Reuso de funciones $O(1)$ de mapeo de color HSV y envolventes | Paridad exacta de algoritmos |

---

## 4. Plan de Pruebas y Criterios de Aceptación

### 4.1 Pruebas Automáticas de Compilación y Unidad (.NET)
- `dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Debug -p:Platform=x64`: Verificar que las 38 pruebas unitarias e integrales en C# se ejecuten limpiamente sin regresiones.

### 4.2 Criterios de Aceptación Cuantitativos
1. **Tasa de Refresco y Latencia (RNF-PERF.1):**
   - Ejecución continua a 60–120 FPS sin caídas de cuadros (*frame drops*).
   - Tiempo de ejecución de `CanvasControl_Draw` en GPU/CPU $\le 0.8\text{ ms}$ por cuadro.
2. **Perfilado de Memoria GC (RNF-MEM.1):**
   - Asignaciones Gen0 en el callback `Draw`: $0\text{ bytes/frame}$.
3. **Resiliencia de Dispositivo (RNF-REL.2):**
   - Ante la re-inicialización del adaptador de pantalla o minimización de ventana, el control invalida recursos y ejecuta `CreateResources` sin registrar excepciones no controladas.
