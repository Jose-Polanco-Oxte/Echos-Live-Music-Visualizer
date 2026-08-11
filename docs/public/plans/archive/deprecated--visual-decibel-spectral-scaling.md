# Plan de Implementación: Escalado Espectral Visual en Decibelios (dB) y Compensación Perceptual

## 1. Contexto, Diagnóstico y Objetivo

### 1.1 Diagnóstico de la Arquitectura Actual
En el modulo Core de Rust (`src/core/src/master_peak.rs`), la función `MasterPeakScaler::condition_hybrid_band_energies` procesa el vector de energías por banda $E_i = |X_i|^2$ entregado por el analizador STFT multi-resolución:
1. Convierte potencia física a amplitud lineal: $w_i = \sqrt{E_i} \cdot G_t$ (donde $G_t$ es la ganancia macro LUFS).
2. Determina el **Pico Maestro** de la trama: $M_{\text{frame}} = \max_i(w_i)$ y actualiza el divisor suavizado IIR $M_t$.
3. Calcula el valor escalado: $S_i = \frac{w_i}{M_t} \cdot H_{\text{target}}$ (con $H_{\text{target}} = 0.75$).
4. Aplica el limitador suave: $Y_i = \tanh(S_i). \text{clamp}(0.0, 1.0)$.

**Fallo de Percepción Visual:**
Debido a que la distribución espectral de la música real concentra la mayor parte de su potencia física en bajas frecuencias ($30\text{ Hz} - 1\text{ kHz}$), el valor $S_i$ para bandas de altas frecuencias ($>6\text{ kHz}$) resulta ser extremadamente pequeño ($S_i \approx 0.005 - 0.02$). En escala de amplitud lineal pura, $\tanh(0.01) \approx 0.01$, provocando que el 35% de las barras en pantalla permanezcan inmóviles en el piso visual ($P_{\text{floor}} = 0.05$).

### 1.2 Objetivo del Plan
Transformar el módulo de acondicionamiento de señales en Rust (`src/core/src/master_peak.rs` y `src/core/src/ffi.rs`) para incorporar un modo de **Escalado Espectral en Decibelios ($\text{dB}$)** con **Compensación Perceptual de Sonoridad por Octava (+3 dB/octava)** acotado rígidamente en $[0.0, 1.0]$. Esto ofrecerá dinamismo completo en 2D (Win2D) y en los futuros visualizadores 3D (Vortice D3D11).

---

## 2. Especificación Matemática del Algoritmo Proyectado

### 2.1 Ecuación de Escalado Logarítmico dB
Dado el valor de amplitud lineal normalizado por Pico Maestro $S_i \in [0.0, 1.0]$:
1. **Piso Dinámico Visual:** Se establece un rango dinámico visual de $D_{\text{floor\_db}} = -50.0\text{ dB}$ ($S_{\text{floor}} = 10^{-50/20} \approx 0.003162$).
2. **Conversión a Decibelios:**
   $$L_i = 20 \cdot \log_{10}\left( \max(S_i, S_{\text{floor}}) \right) \in [-50.0\text{ dB}, 0.0\text{ dB}]$$
3. **Mapeo Normalizado $[0.0, 1.0]$:**
   $$Y_{\text{db}, i} = 1.0 + \frac{L_i}{50.0}$$

### 2.2 Compensación Perceptual de Sonoridad por Octava (*Pink Noise Tilt*)
Para compensar la caída física natural de la música manteniendo una respuesta visual plana ante ruido rosa (*Pink Noise*):
1. Para cada banda con frecuencia central $f_{c,i}$, se calcula la elevación perceptual relativa a $1,000\text{ Hz}$:
   $$T_i = \left( \frac{f_{c,i}}{1000.0\text{ Hz}} \right)^{\alpha}, \quad \text{con } \alpha = 0.15 \quad (\approx +3\text{ dB por octava})$$
2. **Salida Acondicionada Final:**
   $$Y_{\text{final}, i} = \text{clamp}\left( Y_{\text{db}, i} \cdot T_i, P_{\text{floor}}, 1.0 \right)$$

---

## 3. Desglose Módulo por Módulo de Cambios

### 3.1 Módulo `src/core/src/master_peak.rs`
* **Nuevas constantes:**
  * `pub const MASTER_VISUAL_DB_FLOOR: f32 = -50.0;`
  * `pub const MASTER_PINK_NOISE_EXPONENT: f32 = 0.15;`
* **Nuevos tipos / Enums:**
  ```rust
  #[derive(Debug, Clone, Copy, PartialEq, Eq)]
  #[repr(C)]
  pub enum SpectralScalingMode {
      Linear = 0,
      Decibels = 1,
      PerceptualPinkNoise = 2,
  }
  ```
* **Extensión de `MasterPeakScaler`:**
  * Incorporar campo `scaling_mode: SpectralScalingMode`.
  * Actualizar `condition_hybrid_band_energies` para aplicar la transformación logarítmica/perceptual cuando `scaling_mode != Linear`.

### 3.2 Módulo `src/core/src/ffi.rs`
* **Exportación ABI FFI:**
  * Exponer la función C `echo_core_set_spectral_scaling_mode(handle: *mut c_void, mode: u32) -> u8`.
  * Garantizar que la estructura `AnalysisFrameDataV2` continue entregando `conditioned_band_energies` en $[0.0, 1.0]$ sin alterar el contrato zero-copy.

### 3.3 Capa C# / WinUI 3 UI (`src/ui/`)
* **`src/ui/Audio/EchoCoreNative.cs`:**
  * Declarar `[LibraryImport(DllName, EntryPoint = "echo_core_set_spectral_scaling_mode")]`.
* **`src/ui/Services/AudioCoreService.cs`:**
  * Exponer el método `SetSpectralScalingMode(SpectralScalingMode mode)`.
* **`src/ui/Visualizers/Win2DSpectralBarVisualizer.cs` y `D3D11SpectralMeshVisualizer.cs`:**
  * Consumir las energías acondicionadas resultantes. Al estar acotadas en $[0.0, 1.0]$, los renderizadores 2D y 3D funcionarán de manera inmediata sin modificar sus loops de dibujo.

---

## 4. Plan de Pruebas y Criterios de Aceptación

### 4.1 Pruebas Automáticas en Rust (`src/core/src/master_peak.rs`)
* **Prueba `rf4_3_4_hybrid_decibel_scaling_bounds`:** Verificar que valores infinitesimales ($E_i \to 0$) resultan en $P_{\text{floor}} = 0.05$ y valores máximos ($E_i \to 1.0$) resultan en $\le 1.0$.
* **Prueba `rf4_3_4_high_frequency_reactivity`:** Confirmar que ante una señal con amplitud $0.01$ en $10\text{ kHz}$, la salida $Y_{final}$ pasa de $0.037$ (modo lineal antiguo) a $\approx 0.35$ (modo perceptual nuevo).

### 4.2 Pruebas de Integración en C# (`tests/EchoVisualizer.Tests/`)
* Ejecutar `dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Debug -p:Platform=x64` para validar que el ABI v2 zero-copy y la suite de pruebas pasan al 100%.

### 4.3 Validación Manual e Visual
* Probar con música real (pistas con platillos y sintetizadores agudos) en 12, 48 y 68 bandas.
* Verificar que las bandas de la derecha ($>6\text{ kHz}$) muestren movimiento proporcional y reactivo sin saturar los graves.
