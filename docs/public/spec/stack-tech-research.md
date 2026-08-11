# Investigación del stack tecnológico actual: Echo Visualizer

> Estado: referencia técnica del repositorio actual. Verificado contra los
> manifiestos y fuentes existentes durante la auditoría del 2026-08-11.

Este documento describe el stack que realmente está configurado en el checkout
actual. Las opciones evaluadas para futuras extensiones se separan de la ruta
activa y no constituyen cambios arquitectónicos del producto.

## 1. Toolchains y destinos

| Capa | Configuración actual | Evidencia |
| --- | --- | --- |
| Rust | `1.97.1`, perfil `minimal`, `rustfmt` y `clippy` | `rust-toolchain.toml` |
| Targets Rust | `x86_64-pc-windows-msvc` y `aarch64-pc-windows-msvc` | `rust-toolchain.toml` |
| .NET SDK | `10.0.302`, `latestFeature`, sin prerelease | `global.json` |
| UI target | `net8.0-windows10.0.26100.0`, mínimo `10.0.17763.0` | `src/ui/EchoVisualizer.csproj` |
| Runtime identifiers | `win-x64` por defecto y `win-arm64` | `src/ui/EchoVisualizer.csproj` |

La aplicación UI se configura para perfiles MSIX y unpackaged self-contained.
La publicación de distribución debe seguir `scripts/Build-Distributions.ps1`;
un `dotnet publish` directo sólo es evidencia diagnóstica.

## 2. Core DSP y captura

El crate `src/core` se compila como `cdylib` y `rlib`, con edición Rust 2021.
Sus dependencias directas actuales son:

| Componente | Versión declarada | Uso actual |
| --- | --- | --- |
| `wasapi` | `0.23` | Captura loopback y enumeración de dispositivos Windows |
| `rustfft` | `6.2` | FFT y análisis espectral |
| `ringbuf` | `0.4` | Buffers SPSC entre captura/procesamiento |
| `rubato` | `0.15` | Conversión/resampling de PCM |
| `thiserror` | `2` | Errores tipados del core |
| `approx` | `0.5` (dev) | Aserciones numéricas de pruebas |

No se usa `cpal` en el manifiesto actual. La captura activa es WASAPI; por lo
tanto, las decisiones de loopback, formato, resampling y transferencia deben
auditarse contra `capture.rs`, `preprocess.rs`, `spsc.rs` y `ffi.rs`, no contra
una abstracción de audio que ya no aparece en el proyecto.

El contrato FFI expone versiones ABI y el servicio C# verifica la versión antes
de consumir frames. La documentación de requisitos es la fuente normativa para
las fórmulas DSP; este documento sólo identifica tecnologías y fronteras de
implementación.

## 3. UI y renderizado

Dependencias directas de `src/ui/EchoVisualizer.csproj`:

- Microsoft Windows App SDK `1.8.260209005`.
- Microsoft.Graphics.Win2D `1.4.0`.
- CommunityToolkit.Mvvm `8.3.2`.
- Vortice.Direct3D11, Vortice.DXGI y Vortice.D3DCompiler `3.8.3`.

La ruta activa del visualizador es `Win2DGpuSpectralBarVisualizer`, conectado a
un `CanvasControl`. El renderizado se atiende en `CanvasControl.Draw`; la página
usa un `DispatcherTimer` de aproximadamente 16 ms para leer frames y solicitar
la actualización del canvas. La presencia de paquetes Vortice no implica que el
visualizador activo use un `SwapChainPanel` ni que deba migrarse a Direct3D 11
en esta auditoría.

La existencia de propiedades de renderizado adicionales en el renderer actual
se registra como candidato de revisión en el informe de auditoría; no se
elimina código de producto ni se altera su comportamiento en este cambio.

## 4. Interoperabilidad y límites de responsabilidad

La frontera Rust/C# se valida mediante el contrato FFI existente. Rust mantiene
la responsabilidad del procesamiento y de la memoria nativa; C# administra el
ciclo de vida del servicio, la lectura del frame y la presentación WinUI/Win2D.
Las afirmaciones de rendimiento, latencia, asignaciones y seguridad de hilos
requieren medición o pruebas específicas y no deben presentarse como garantías
derivadas únicamente de una dependencia o de una versión de framework.

## 5. Opciones evaluadas, no activas

Las siguientes tecnologías pueden aparecer en documentación histórica o en
paquetes preparados para extensiones, pero no representan la ruta activa del
producto:

- `cpal`: no está declarado en `src/core/Cargo.toml`.
- `Win2D.uwp`: la dependencia actual es `Microsoft.Graphics.Win2D` para la
  aplicación WinUI 3.
- `SwapChainPanel`/Vortice como renderer activo: no es la implementación actual
  del visualizador de barras.
- Native AOT y `[SuppressGCTransition]`: no son requisitos inferidos del
  proyecto actual y sólo deben documentarse si una implementación futura los
  adopta explícitamente.

## 6. Verificación y mantenimiento

Después de cambiar toolchains o dependencias, ejecutar el validador de
toolchains, `cargo fmt --check`, `cargo clippy -- -D warnings`, las pruebas del
core y las pruebas .NET aplicables. Si una afirmación deja de coincidir con los
manifiestos o fuentes, actualizar este documento junto con la trazabilidad; no
mantener recomendaciones históricas como si fueran configuración vigente.
