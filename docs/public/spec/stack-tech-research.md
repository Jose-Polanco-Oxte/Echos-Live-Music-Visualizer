# Investigación del Stack Tecnológico: Echo Visualizer

Este documento detalla la investigación de viabilidad, compatibilidad y licenciamiento del stack tecnológico seleccionado para **Echo Visualizer**. Proporciona pautas de ingeniería para la integración entre Rust y C#, junto con la matriz de versiones óptimas para mitigar problemas en Windows.

---

## 1. Análisis Técnico por Capa y Componente

### Capa A: Core de Procesamiento DSP (Rust)

#### Crate `cpal` (Cross-Platform Audio Library)
- **Propósito**: Abstracción del sistema de entrada/salida de audio.
- **Limitación en Windows**: `cpal` está diseñado principalmente para capturar desde dispositivos de entrada física (micrófonos, entradas de línea). De manera nativa, **no expone el flag `AUDCLNT_STREAMFLAGS_LOOPBACK`** necesario para capturar la salida de audio global del sistema (WASAPI Loopback) sin necesidad de software de terceros (ej. cables virtuales).
- **Mitigación / Solución**: 
  1. Utilizar la crate **`wasapi`** para el motor de captura en Windows. Esta crate proporciona envoltorios directos y seguros para la API WASAPI nativa de Microsoft y expone explícitamente la inicialización de flujos de tipo loopback.
  2. Integrar `rustfft` directamente con los buffers obtenidos de `wasapi`.

#### Crate `rustfft`
- **Propósito**: Cálculo de la Transformada Rápida de Fourier (FFT).
- **Rendimiento**: Es una de las librerías de FFT más optimizadas en Rust. Emplea vectorización SIMD automática (AVX, SSE, NEON) para resolver transformadas en microsegundos, lo cual garantiza que el Core DSP cumpla con la restricción de latencia $\le 30\text{ ms}$.
- **Compatibilidad**: Completamente compatible con cualquier flujo continuo de datos de audio de tipo punto flotante (`f32`) provisto por la capa de captura.

---

### Capa B: Puente de Integración (ABI / FFI)

La comunicación entre el Core de Rust (compilado en una `.dll` dinámica) y la interfaz de usuario en C# se realizará mediante P/Invoke y un búfer circular en memoria compartida.

#### Optimización en .NET 8 / .NET 9 (`LibraryImport`)
- En lugar del tradicional `[DllImport]`, utilizaremos **`[LibraryImport]`** (generación de código fuente a nivel de compilador). Esto elimina el overhead de marshalling en tiempo de ejecución, reduce la latencia de la llamada y es totalmente compatible con la compilación Native AOT (Ahead-Of-Time) de .NET.

#### Atributo `[SuppressGCTransition]`
- Las llamadas a funciones nativas que consultan el búfer de espectro a alta frecuencia (ej. 60 Hz o más) deben decorarse con `[SuppressGCTransition]`. Esto evita que la máquina virtual de .NET notifique al Garbage Collector sobre la transición de contexto, reduciendo el costo de llamada a una fracción infinitesimal (equivalente a una llamada de C pura).

#### Estructura del Búfer Circular (Lock-Free)
- Para evitar condiciones de carrera y la sobrecarga de bloqueos de tipo exclusión mutua (`Mutex` o `lock`), se implementará una cola circular de tipo **Single-Producer Single-Consumer (SPSC)**.
- El productor (hilo de audio en Rust) escribe datos espectrales.
- El consumidor (hilo gráfico de WinUI 3 en C#) lee a través de un puntero directo (`Span<T>`) expuesto por Rust, eliminando copias innecesarias de memoria.

---

### Capa C: Interfaz y Aplicación Shell (C# + WinUI 3)

#### WinUI 3 y Windows App SDK
- **Propósito**: Implementar la UI, ciclo de vida de la aplicación, menús, Drawer lateral de ajustes y la orquestación general.
- **Rendimiento Gráfico (2D vs 3D)**: Para lograr renderizado suave a $\ge 60\text{ FPS}$ sin cuellos de botella en la CPU, se descartan los controles tradicionales de XAML. La arquitectura debe estructurarse según el tipo de visualizador:
  
  1. **Para Visualizadores 2D (Ecualizadores de Barras)**:
     - **Tecnología Recomendada**: **Win2D (`Win2D.uwp`)**.
     - *Justificación*: Wrapper oficial y maduro de Direct2D para Windows App SDK. Permite operaciones de dibujo en 2D inmediatas y aceleradas por hardware directamente dentro de un `CanvasControl` XAML, con una complejidad de implementación muy baja.
     
  2. **Para Visualizadores 3D (Caleidoscopios y Mallas Geométricas Complejas)**:
     - **Tecnología Recomendada**: **Vortice.Windows (`Vortice.Direct3D11` + `Vortice.DXGI`)**.
     - *Justificación*: SharpDX está obsoleto/abandonado, y soluciones como Evergine son demasiado pesadas para este alcance. Vortice es un wrapper moderno y activo para Direct3D11/Direct3D12 en .NET 8/9. Permite renderizar directamente sobre un **`SwapChainPanel`** de WinUI 3.
     
- **Integración 3D via SwapChainPanel**:
  - Para conectar el renderizado 3D de Direct3D al panel XAML, C# debe acceder a la interfaz nativa COM `ISwapChainPanelNative` de WinUI 3.
  - El flujo de inicialización implica:
    1. Crear el dispositivo `ID3D11Device` y su contexto con Vortice.
    2. Crear la cadena de intercambio (`IDXGISwapChain1`) para composición mediante `CreateSwapChainForComposition`.
    3. Recuperar la interfaz COM nativa del panel XAML mediante `ComObject.As<ISwapChainPanelNative>(mySwapChainPanel)` y llamar a su método `SetSwapChain(m_SwapChain)`.
    4. Manejar el evento `CompositionScaleChanged` en C# para redimensionar dinámicamente los buffers de Direct3D ante cambios de DPI o redimensionamiento de ventana.

---

## 2. Cuestiones de Hardware y Sistema Operativo (Windows)

1. **Inyección de Silencio (Silence Injection)**:
   - *Comportamiento de WASAPI*: Si no hay ningún reproductor de audio emitiendo sonido en Windows, el dispositivo Loopback de WASAPI **detiene el envío de eventos de datos**. Esto puede congelar o colgar el hilo de captura en Rust si este espera indefinidamente.
   - *Mitigación*: El código de captura en Rust debe implementar un temporizador de desconexión (*timeout*) que inyecte un bloque ficticio de muestras de silencio (`0.0`) si no se reciben datos del kernel en un intervalo de 100 ms. Esto mantiene activo el flujo de renderizado en la UI.
2. **Latencia Acumulada**:
   - Para cumplir con la restricción de latencia total $\le 30\text{ ms}$:
     - Ingesta de audio (WASAPI): Buffer de 512 muestras a 48 kHz $\approx 10.6\text{ ms}$.
     - FFT + DSP (Rust): $\approx 1.5\text{ ms}$.
     - FFI + Transferencia (P/Invoke): $\le 0.1\text{ ms}$.
     - Renderizado (Win2D / GPU): $\approx 16.6\text{ ms}$ (a 60 FPS).
     - *Total Estimado*: $\approx 28.8\text{ ms}$, cumpliendo estrictamente con el objetivo de diseño.

---

## 3. Licenciamiento de Componentes

Todo el stack tecnológico seleccionado está libre de regalías y es apto para uso comercial/privado:

| Componente | Tecnología | Tipo de Licencia | Notas de Uso |
| --- | --- | --- | --- |
| **Capa DSP** | Rust Compilador | MIT / Apache 2.0 | Software libre y de código abierto sin restricciones. |
| **Librería de Audio** | `wasapi` (Crate) | MIT | Permite modificación, distribución y uso comercial. |
| **Librería DSP** | `rustfft` (Crate) | MIT / Apache 2.0 | Libre de regalías. |
| **Librería Audio** | `cpal` (Crate) | Apache 2.0 | Libre de regalías. |
| **Plataforma Core** | .NET 8 / .NET 9 | MIT | Totalmente comercializable. |
| **Motor de UI** | WinUI 3 (SDK) | MIT | Código abierto de Microsoft. |
| **Distribución** | MSIX | N/A | Formato nativo de Windows, gratuito. |

---

## 4. Problemas Comunes (Gotchas) y Mitigaciones

### 1. Incompatibilidad de RIDs (Runtime Identifiers) en .NET 8/9
- **Problema**: Al compilar proyectos con el Windows App SDK en .NET 8 o 9, pueden surgir errores `NETSDK1083` de restauración debido a identificadores de sistema obsoletos (ej. `win10-x64`).
- **Mitigación**: Configurar explícitamente en el archivo `.csproj` el RID unificado y genérico `win-x64` o `win-arm64`:
  ```xml
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  ```

### 2. Pérdida de Referencias de Memoria en FFI (Garbage Collector)
- **Problema**: Si pasamos estructuras o arreglos creados en el montón de C# directamente a la DLL de Rust, el Garbage Collector de C# puede moverlas de dirección física durante una recolección de basura, corrompiendo las lecturas de Rust.
- **Mitigación**: Fijar permanentemente la dirección de memoria usando bloques `fixed` en C# o utilizar memoria no administrada asignada en el montón de Rust (`Box` o punteros crudos expuestos por Rust) para la comunicación del búfer circular.

---

## 5. Reporte Definitivo de Versiones y Dependencias

A continuación, se detalla la matriz de versiones óptimas y completamente compatibles entre sí para garantizar el correcto despliegue e integración en Windows:

| Tecnología / Dependencia | Versión Recomendada | Origen / Canal | Notas de Compatibilidad |
| --- | --- | --- | --- |
| **Rust Toolchain** | `1.81.0` o superior | `stable` | Asegura soporte Native AOT y optimizaciones de compilación recientes. |
| **wasapi (Crate)** | `0.13.0` | Crates.io | Soporte nativo para captura loopback estable en Windows 10/11. |
| **cpal (Crate)** | `0.18.1` | Crates.io | Utilizada como fallback de control de dispositivos externos. |
| **rustfft (Crate)** | `6.4.1` | Crates.io | Rendimiento optimizado con vectorización AVX/SSE. |
| **C# / .NET SDK** | `.NET 8.0 LTS` o `.NET 9.0` | Microsoft Oficial | `.NET 8.0` es preferido por su soporte a largo plazo (LTS). |
| **Microsoft.WindowsAppSDK**| `1.8.10` (o superior) | NuGet Package | Canal estable de WinUI 3 compatible con .NET 8 y .NET 9. |
| **Win2D.uwp** | `1.28.1` | NuGet Package | Módulo de aceleración 2D por GPU recomendado para WinUI 3. |
| **Vortice.Direct3D11** | `3.8.3` | NuGet Package | Wrapper de Direct3D 11 optimizado y compatible con Native AOT para 3D. |
| **Vortice.DXGI** | `3.8.3` | NuGet Package | Requerido para la creación del SwapChain de composición en 3D. |
| **Windows 10/11 SDK** | `10.0.22621.0` (o sup.) | Windows SDK | Target de SDK requerido en el archivo `.csproj` para soportar las APIs modernas del sistema. |
