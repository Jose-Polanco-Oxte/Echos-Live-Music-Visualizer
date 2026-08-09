# SECCIÓN I: INTERPRETE DE AUDIO

### Módulo 1: Análisis Frecuencial y Mapeo Espectral

**Descripción:** Procesa el flujo de audio continuo para descomponerlo en el dominio frecuencial y parametrizar la energía en bandas discretas.

- **Requisitos Funcionales:**

**RF1.1 Ingesta, Normalización y Hop:** Capturar PCM de 1 a 8 canales a tasas
de entrada de 44.1, 48 o 96 kHz. Cada canal se remuestrea con estado continuo a
$f_a=48,000\text{ Hz}$ y se conserva separado hasta después del análisis. El
quantum de análisis es $H=512$ frames por canal (10.667 ms); no se usará $N$
para nombrar simultáneamente el hop, la FFT y el número de bandas. La captura
entrega frames ordenados a un ring buffer SPSC lock-free de capacidad inicial
mínima de 16,384 frames por canal y nunca bloquea el callback WASAPI.

**RF1.2 Descomposición Frecuencial Multirresolución:** En cada hop completo se
actualizan tres STFT deslizantes sobre historia por canal: $N_{fft}=4096$ para
20–250 Hz, $N_{fft}=2048$ para 250–4000 Hz y $N_{fft}=1024$ para 4000–20000 Hz.
Todas usan la ventana Blackman-Harris de cuatro términos:

$$
w[n]=0.35875-0.48829\cos\left(\frac{2\pi n}{N_{fft}-1}\right)
+0.14128\cos\left(\frac{4\pi n}{N_{fft}-1}\right)
-0.01168\cos\left(\frac{6\pi n}{N_{fft}-1}\right)
$$

$$
X_c[k] = \sum_{n=0}^{N_{fft}-1}x_c[n]w[n]e^{-j\frac{2\pi}{N_{fft}}kn},
\qquad P[k]=\frac{1}{C}\sum_{c=1}^{C}|X_c[k]|^2
$$

No se aplicará $\sqrt{L^2+R^2}$ ni downmix lineal a PCM antes de FFT.

**RF1.3 Agrupación Espectral Dinámica y Paramétrica ($B$ Bandas)**: El módulo
Core permite configurar dinámicamente el total de bandas de salida $B$ y sus
rangos. El perfil HI-FI por defecto es ERB; Log-Octave 1/3 y 1/6 son perfiles
alternos. Se conservan Lineal, Logarítmica y Mel para compatibilidad de presets.
La integración de potencia será continua mediante filtros triangulares o
trapezoidales y no podrá producir bandas estructuralmente vacías.

- **Comportamiento y Reglas de Dominio:**
    1. **Configuración de Ranuras:** El Core recibirá un arreglo o matriz de rangos de frecuencia $[f_{min}, f_{max}]_i$ para $i = 1, \dots, B$.
    2. **Partición por Defecto ($B=3$):** Si no se especifica una configuración personalizada, el sistema adopta por defecto el triplete estándar:
        - Bandas básicas: $[20 - 250\text{ Hz}]$, $[250 - 4000\text{ Hz}]$, $[4000 - 20000\text{ Hz}]$.
    3. **Escalas Paramétricas Avanzadas ($B > 3$):** El Core debe soportar distribuciones calculadas automáticamente según modelos psicoacústicos cuando el visualizador requiera alta densidad de bandas:
        - **ERB / Logarítmica / Bark / Mel:** Para agrupaciones equiespaciadas perceptivamente.
        - **Escala Lineal:** Para ecualizadores de barras de precisión uniforme.
    4. **Salida de Datos:** Generar un vector continuo de energía de tamaño variable:

$$
\mathbf{E} = [E_1, E_2, \dots, E_B] \quad \text{donde } E_i \in [0.0, 1.0]
$$

**RF1.4 Fusión Multirresolución:** Los análisis vecinos se fusionarán sin salto
con cross-fade cosenoidal entre 200–300 Hz y 3800–4200 Hz. Para cada cruce
$[f_{low},f_{high}]$:

$$
u=clamp\left(\frac{f-f_{low}}{f_{high}-f_{low}},0,1\right),\quad
W_A=\cos^2\left(\frac{\pi}{2}u\right),\quad W_B=1-W_A
$$

$$
P_{fused}(f)=W_A(f)P_A(f)+W_B(f)P_B(f)
$$

---

### Módulo 2: Suavizado y Inercia Temporal

**Descripción:** Modula la variabilidad de las magnitudes espectrales para otorgar comportamiento inercial y estabilidad perceptiva.

- **Requisitos Funcionales:**

**RF2.1 Filtro Exponencial Asimétrico:** Aplicar suavizado temporal de primer orden sobre las energías crudas:

$$
S[t] = \alpha \cdot E[t] + (1 - \alpha) \cdot S[t-1]
$$

**Respuesta a Ataque ($\alpha_{attack}$):** Asignar coeficiente elevado cuando $E[t] > S[t-1]$ para respuesta inmediata ante transitorios.

**Respuesta a Decaimiento ($\alpha_{decay}$):** Asignar coeficiente reducido cuando $E[t] \le S[t-1]$ para retorno progresivo al reposo.

**RF2.2 Inercia Mapeada por Posición Relativa Espectral**: Asignar el coeficiente de suavizado $\alpha_i$ a cada una de las $N$ bandas mediante una función interpolada según su frecuencia central $f_{c,i}$:

$$
\alpha(f_{c,i}) = \alpha_{low} + \left( \alpha_{high} - \alpha_{low} \right) \cdot \left( \frac{\log(f_{c,i}) - \log(f_{min})}{\log(f_{max}) - \log(f_{min})} \right)
$$

- **Comportamiento:**
    - Frecuencias bajas ($f_{c,i} \to 20\text{ Hz}$): Asignan dinámicamente $\alpha_i \approx 0.15$ (Inercia alta).
    - Frecuencias altas ($f_{c,i} \to 20000\text{ Hz}$): Asignan dinámicamente $\alpha_i \approx 0.80$ (Alta volatilidad).

---

### Módulo 3: Extracción de Características Acústicas (*Feature Extraction*)

**Descripción:** Determina descriptores de bajo y alto nivel para caracterizar las dinámicas globales y tímbricas de la señal.

- **Requisitos Funcionales:**

**RF3.1 Potencia Global (RMS):** Evaluar continuamente el valor Root Mean Square en el dominio del tiempo como descriptor de amplitud sonora total:

$$
x_{RMS} = \sqrt{\frac{1}{N} \sum_{n=0}^{N-1} (x[n])^2}
$$

El RMS se calcula por hop de 512 frames y combina potencia multicanal; no se
obtiene de un downmix que pueda cancelar canales antifase.

**RF3.2 Centroide Espectral ($f_C$):** Calcular el centro de gravedad del espectro de magnitud para determinar la variación del brillo tímbrico:

$$
f_C = \frac{\sum k \cdot \vert{}X[k]\vert{}}{\sum \vert{}X[k]\vert{}}
$$

**RF3.3 Detección de Inicios (*Onset/Beat Detection*):** Evaluar el flujo espectral (*Spectral Flux*) para identificar transitorios de alta energía y emitir la señal discreta `Onset`.

El onset se calcula en la ruta rápida de 1024 y se publica una vez por hop como
`onset_detected` y `onset_score \in [0,1]`; el polling FFI no puede repetirlo.

---

### Módulo 4: Calibración Psicoacústica

**Descripción:** Normaliza las amplitudes según la curva de sonoridad percibida por el oído humano.

- **Requisitos Funcionales:**

**RF4.1 Ponderación Psicoacústica:** ISO 226 o A-weighting sólo podrán
aplicarse como perfil de presentación explícito y configurable. La ponderación
K de BS.1770-4 se usa exclusivamente para medir LUFS y no colorea por segunda
vez el vector físico de bandas.

**RF4.3 Acondicionamiento Dinámico y Calibración de Sonoridad (LUFS):** El módulo debe adaptar continuamente el rango dinámico y la amplitud del vector de magnitudes espectrales $E_i$ antes de transferirlo al visualizador activo. Esto garantiza que la señal permanezca dentro del intervalo normalizado $[0.0, 1.0]$ con suficiente impacto visual ("pegada"), eliminando la necesidad de reajustes manuales ante variaciones en la fuente sonora.

**1. Medición de Sonoridad en Tiempo Real ($L_{short}(t)$ - ITU-R BS.1770-4)**

- **Etapa 1.1: Filtrado de Ponderación $K$ (*K-Weighting*)**
Cada canal de audio temporal PCM $x_i[n]$ (donde $i \in \{L, R\}$) debe ser procesado secuencialmente por dos filtros IIR en cascada para aproximar la acústica de la cabeza humana:
    1. **Filtro de Estante Alto (*High-Shelf*) $H_{stage1}(z)$:** Amplifica altas frecuencias (ganancia de $+4\text{ dB}$ sobre $1.5\text{ kHz}$).
    2. **Filtro de Paso Alto / RLB (*Revised Low-frequency B曲线*) $H_{stage2}(z)$:** Atenúa frecuencias sub-graves por debajo de $100\text{ Hz}$.

$$
\tilde{x}_i[n] = H_{stage2}(z) \cdot H_{stage1}(z) \cdot x_i[n]
$$

- **Etapa 1.2: Integración Temporal de Ventana Corta (*LUFS Short-Term*)**
Se evalúa la energía cuadrática promedio en una ventana rectangular deslizante de duración $T_w = 3.0\text{ s}$ ($M = T_w \cdot f_s$ muestras):

$$
z_i[t] = \frac{1}{M} \sum_{n=t-M}^{t} \left( \tilde{x}_i[n] \right)^2
$$

- **Etapa 1.3: Cálculo del Nivel de Sonoridad Corta ($L_{short}(t)$)**
Integra los canales aplicando las ponderaciones estandarizadas ($G_L = G_R = 1.0$ para estéreo):

$$
L_{short}(t) = -0.691 + 10 \log_{10} \left( \sum_{i \in \{L, R\}} G_i \cdot z_i[t] \right) \quad \text{[LUFS]}
$$

**2. Estimación del Desvío Dinámico y Modos Operacionales**

- **Cálculo del Desvío de Sonoridad ($\Delta L(t)$):**
Se mide la diferencia entre la sonoridad instantánea $L_{short}(t)$ y un nivel de referencia perceptual $L_{target}$ (configurable, por defecto $L_{target} = -14\text{ LUFS}$):

$$
\Delta L(t) = L_{short}(t) - L_{target} \quad \text{[LU/dB]}
$$

- **Modos de Operación:**
    1. **Modo A (Manual):** Desactiva el cálculo de $\Delta L(t)$ y fija los parámetros con valores estáticos definidos por el cliente: $G(t) = G_{user}$, $\gamma(t) = \gamma_{user}$.
    2. **Modo B (Automático - Adaptativo):** Calcula dinámicamente $G(t)$ y $\gamma(t)$ en función de $\Delta L(t)$.

**3. Funciones Adaptativas de Ganancia ($G$) y Contraste Gamma ($\gamma$)**

**A. Ganancia de Normalización ($G_{raw}(t)$)**

Compensa la falta o exceso de volumen general para centrar la señal en el rango dinámico del visualizador:

$$
G_{raw}(t) = 10^{-\frac{\Delta L(t)}{20}}
$$

**B. Exponente Gamma de "Pegada" / Contraste Visual ($\gamma_{raw}(t)$)**

Modula la curvatura de la señal para enfatizar picos transitorios respecto al fondo constante mediante una función sigmoidal acotada:

$$
\gamma_{raw}(t) = \gamma_{base} + (\gamma_{max} - \gamma_{base}) \cdot \tanh\left( \frac{\Delta L(t)}{\sigma} \right)
$$

- **Donde:**
- $\gamma_{base} = 1.0$ (respuesta neutra/lineal).
- $\gamma_{max} = 2.2$ (límite superior de expansión de picos).
- $\sigma = 6.0\text{ dB}$ (factor de escala de la transición sigmoidal).
- **Comportamiento:**
    - Si la señal está muy comprimida ($\Delta L(t) > 0\text{ dB}$ / música alta), $\gamma_{raw}(t) \to \gamma_{max}$, **forzando el contraste visual** para que los golpes rítmicos sobresalgan.
    - Si la señal es débil ($\Delta L(t) < 0\text{ dB}$ / pasaje suave), $\gamma_{raw}(t) \to 1.0$, priorizando la visibilidad del espectro.

---

**4. Inercia Dinámica y Prevención de Pumping**

Para evitar cambios bruscos o parpadeos molestos en pantalla entre compases (*bombeo de volumen*), los parámetros $G(t)$ y $\gamma(t)$ se filtran secuencialmente mediante un filtro IIR de primer orden con un coeficiente de respuesta lenta $\alpha_{lufs} \in [0.01, 0.05]$ ($\tau \approx 1 - 2\text{ s}$):

$$
G[t] = \alpha_{lufs} \cdot G_{raw}[t] + (1 - \alpha_{lufs}) \cdot G[t-1]
$$

$$
\gamma[t] = \alpha_{lufs} \cdot \gamma_{raw}[t] + (1 - \alpha_{lufs}) \cdot \gamma[t-1]
$$

---

#### **5. Ecuación Final de Salida Acondicionada**

Cada valor de energía de banda $E_i[t]$ proveniente del Módulo 2/3 se transforma individualmente mediante la función de atenuación/expansión acotada:

$$
E_{final, i}[t] = \text{clamp}\left( \left( E_i[t] \cdot G[t] \right)^{\gamma[t]}, \; 0.0, \; 1.0 \right)
$$

$$
\text{donde } \text{clamp}(x, a, b) = \max(a, \min(x, b))
$$

**RF4.3.1 -- Actualizado (calibración contra colapso de señal):** Antes de
alterar los valores normativos o la ecuación anterior, el sistema deberá ser
instrumentado y evaluado con audio real de duración suficiente para determinar
si $L_{short}$, $\Delta L$, $G$, $\gamma$, $E_i$ y $E_{final,i}$ derivan con el
tiempo hacia una reducción sostenida de la altura de las barras. La investigación
deberá distinguir la contribución del acondicionamiento LUFS/Gamma de cualquier
suavizado o escalado propio del visualizador.

- Se conservarán como norma vigente $L_{target}=-14\ \text{LUFS}$,
  $\gamma_{base}=1.0$, $\gamma_{max}=2.2$, $\sigma=6.0\ \text{dB}$ y
  $\alpha_{lufs}\in[0.01,0.05]$ mientras no se apruebe una modificación
  trazable de la fórmula.
- **Pendiente de calibración:** el usuario ha comunicado el síntoma de barras
  que se reducen tras un tiempo, pero aún no ha definido una señal de referencia,
  duración, métrica ni umbral de aceptación. Por tanto, esta actualización no
  autoriza a cambiar coeficientes, límites o la función de ganancia por
  intuición; esos criterios deberán especificarse después de la investigación.
- **Protocolo de diagnóstico previo a una recalibración:** la aplicación debe
  permitir seleccionar y registrar sesiones separadas para (a) automático
  normativo, (b) referencia manual neutra $G=1,\ \gamma=1$, (c) control de
  ganancia $G\approx0.50,\ \gamma=1$ y (d) control de gamma
  $G=1,\ \gamma\approx1.91$. Para cada muestra debe registrarse a cadencia
  limitada $L_{short}$, $G$, $\gamma$, estadísticas de energía antes/después
  del acondicionamiento y si el bloque de captura era nuevo o repetido. Los
  valores (c) y (d) son controles de investigación, no nuevos defaults de
  producción.

**RF4.3.2 -- Nuevo (comparativa de mitigación de acondicionamiento):** A partir
de la evidencia registrada por RF4.3.1, la aplicación deberá proporcionar dos
modos de prueba seleccionables antes de publicar el vector por FFI. No sustituyen
el modo normativo automáticamente ni se persisten como defaults de producción.

1. **LUFS estabilizado con pivote:** con RMS menor o igual a $-50\text{ dBFS}$,
   restablecer $G=1$ y $\gamma=1$. Para señal activa, conservar la ganancia
   LUFS pero aplicar una zona neutra de $1.5\text{ LU}$ al contraste:

$$
d(t)=\max(\Delta L(t)-1.5,0)
$$

$$
\gamma_{raw}(t)=1+1.2\tanh\left(\frac{d(t)}{6}\right)
$$

   Con pivote fijo de investigación $P=0.02$ y
   $x_i=\text{clamp}(E_iG,0,1)$, publicar:

$$
E_{pivot,i}=\text{clamp}\left(P\left(\frac{x_i}{P}\right)^{\gamma},0,1\right)
$$

2. **Pico Maestro con headroom:** usar
   $W_i=E_i(f_{c,i}/1000\text{ Hz})^{0.35}$,
   $M_{frame}=\max_i(W_i)$ y un pico maestro asimétrico con ataque $0.20$,
   decay $0.003$, piso $0.05$ y congelación si RMS $\le-50\text{ dBFS}$:

$$
M_t=\begin{cases}
M_{t-1}+0.20(M_{frame}-M_{t-1}), & M_{frame}>M_{t-1}\\
M_{t-1}(1-0.003), & M_{frame}\le M_{t-1}
\end{cases}
$$

$$
Y_i=\tanh\left(\frac{W_i}{\max(M_t,0.05)}\cdot0.75\right)
$$

   La frecuencia se normaliza a 1 kHz para que el tilt sea adimensional. El
   selector de prueba debe indicar con claridad qué ruta está activa y permitir
   la comparación sin reiniciar la captura. La telemetría deberá registrar el
   modo y el valor de $M_t$ para el segundo modo.

**RF4.3.3 -- Nuevo (comparativa híbrida LUFS + Pico Maestro):** Se añadirá un
tercer modo de prueba, seleccionable junto con RF4.3.2, sin sustituir el modo
normativo ni persistirse como default de producción. El modo separa la
normalización macro por LUFS del encuadre micro por Pico Maestro. Usa el tilt
adimensional $W_i=E_i(f_{c,i}/1000\text{ Hz})^{0.35}$, objetivo
$L_{target}=-14\text{ LUFS}$, $H_{target}=0.75$, puerta
$L_{silence}=-50\text{ LUFS}$, zona muerta $\pm2.0\text{ LU}$, límite de
ganancia $[0.5,2.0]$, $\alpha_{lufs}=0.01$, ataque $0.20$, decay $0.003$ y
piso $0.05$.

$$
G_{raw}=\begin{cases}
1, & L_{short}< -50\text{ LUFS}\ \text{o}\ |L_{short}-L_{target}|\le2\text{ LU}\\
\text{clamp}(10^{-(L_{short}-L_{target})/20},0.5,2.0), & \text{en otro caso}
\end{cases}
$$

$$
G_t=G_{t-1}+0.01(G_{raw}-G_{t-1}),\quad E_{lufs,i}=W_iG_t
$$

Con $M_{frame}=\max_i(E_{lufs,i})$, calcular $M_t$ con la misma ecuación
asimétrica de RF4.3.2 y $M_t=\max(M_t,0.05)$; después publicar:

$$
S_i=\frac{E_{lufs,i}}{M_t}\cdot0.75,\quad C_i=S_i,\quad Y_i=\tanh(C_i)
$$

La corrección gamma con pivote es opcional: mientras no exista una fórmula
aprobada para derivarla, este modo fija $C_i=S_i$ (equivalente a
$\gamma=1$). Al pasar de silencio prolongado a señal activa, reiniciar
$G=1$ y usar $M=\max(M_{frame},0.05)$ en el primer frame activo. La telemetría
debe registrar el modo y $M_t$; el selector de prueba debe presentar las tres
rutas sin reiniciar la captura.

**RF4.3.4 -- Nuevo (ganancia espectral natural del híbrido):** Para conservar
la dinámica macro controlada por LUFS sin colorear artificialmente la relación
entre bandas FFT, el modo híbrido aplicará ganancia espectral unitaria:

$$
W_i=E_i,\quad E_{lufs,i}=E_iG_t
$$

No se aplicará el tilt experimental $(f_{c,i}/1000\text{ Hz})^{0.35}$ al modo
híbrido. La K-weighting BS.1770-4 se conservará exclusivamente en la medición
de $L_{short}$ que calcula $G_t$, y no se aplicará una segunda vez por banda.
El Pico Maestro mantendrá el divisor común de RF4.3.3; por ello, antes del
limitador $\tanh$, dos bandas de igual energía FFT tendrán igual salida para el
mismo $G_t$ y $M_t$.

El Core publicará por separado energía física cruda, energía acondicionada y,
si se habilita, peak-hold. La inercia exclusiva de barras permanece en
RF-EQ.2 y no se aplicará de forma irreversible al vector físico.

### Módulo 5: Infraestructura y Garantía de Desempeño

**Descripción:** Establece los límites operacionales y la sincronización entre el cálculo de señales y la entrega de parámetros.

- **Requisitos Funcionales:**

**RF5.1 Desacoplamiento Operacional:** Aislar la ejecución del cálculo acústico respecto a cualquier proceso externo de representación gráfica.

**RF5.2 Entrega Continua sin Bloqueos:** Proveer un mecanismo de intercambio de datos sin interrupción del flujo principal de audio.

- **Restricciones de Calidad (ISO 25010 - Eficiencia de Desempeño y Fiabilidad):**

**Latencia de Procesamiento:** Reportar por separado: (a) $L_c$, desde la
entrada de un hop hasta publicar el frame, con objetivo p99 menor a 1.5 ms en
hardware de referencia; (b) $L_g$, edad de grupo de la ventana, que se reporta
para cada $N_{fft}$ y no se presenta como latencia de cómputo; y (c) latencia
extremo a extremo medida en hardware. Las edades aproximadas son 10.66 ms para
1024, 21.32 ms para 2048 y 42.66 ms para 4096.

**Tasa de Refresco de Datos:** Garantizar una cadencia DSP de 93.75 Hz
($48,000/512$). El render consume el último frame a su propia cadencia, como
mínimo 60 FPS y con objetivo 120 FPS, sin disparar DSP.

**Robustez:** Prevenir bloqueos e interrupciones en tiempo real. Ante
underflow/overflow o falta de slot de publicación, el sistema no bloquea el
callback ni el worker, aplica la política SPSC documentada y expone contadores
de frames capturados/consumidos, underflows, overflows, drops, high-water mark,
timestamp del último hop y latencia de cómputo.

Aquí tienes la especificación expandida del **Módulo 6**, redactada con un nivel de detalle formal, granular e inambiguo, desglosando cada sub-funcionalidad sin incluir detalles de código o implementación específica.

---

### Módulo 6: Interfaz de Usuario y Experiencia del Sistema (Application Shell & UX)

**Descripción:** Controla el contenedor principal de la aplicación (*Application Shell*), la infraestructura de la experiencia de usuario (UX), la navegación global, el ciclo de vida de la interfaz gráfica, la gestión de fuentes de entrada de audio y la orquestación dinámica de los módulos de visualización.

---

### Requisitos Funcionales

#### RF6.1 Secuencia de Inicio, Identidad y Avisos

- **RF6.1.1 Actualizado -- Secuenciación de Arranque:** El sistema debe mostrar la identidad de la aplicación y después permitir el acceso a la interfaz principal y a la renderización de audio. No debe bloquear el acceso con un aviso de permisos de audio, captura, dispositivo u otros permisos del sistema ya declarados por el paquete.
- **RF6.1.2 Pantalla de Identidad (SplashScreen):** Desplegar de forma inicial el elemento de marca visual que incluye el isologotipo y el nombre oficial de la aplicación (*Echo*).
- **RF6.1.3 Actualizado -- Aviso Fotosensible:** Presentar una advertencia exclusivamente sobre sensibilidad a destellos/cambios visuales; no puede presentarse como solicitud ni explicación de permisos del sistema. Debe permanecer visible cinco (5) segundos y continuar automáticamente al concluir ese tiempo, sin botón "Aceptar" ni otra confirmación explícita; la espera constituye la confirmación de lectura del usuario.
- **RF6.1.4 Nuevo -- Permisos del paquete:** Las capacidades requeridas por Echo se declararán en el manifiesto MSIX y se mostrarán durante la instalación mediante el mecanismo estándar de Windows/MSIX. La aplicación ya instalada no duplicará ese listado ni solicitará una aceptación propia para esos permisos.
- **RF6.1.5 Nuevo -- Inicio en distribuciones soportadas:** La aplicación debe iniciar y presentar el contenedor principal tanto en la distribución MSIX empaquetada como en la distribución unpackaged self-contained para GitHub. La variante unpackaged no debe requerir identidad de paquete, instalación independiente de Windows App Runtime ni privilegios administrativos, y debe resolver correctamente los recursos de WinUI incluidos en su publicación.
- **RF6.1.6 Nuevo -- Paridad de identidad visual:** Las distribuciones MSIX y unpackaged deben proyectar la misma identidad visual desde una fuente de marca común. El ejecutable debe contener un icono Win32 multirresolución y publicar los recursos sueltos que consume en ejecución; el paquete debe incluir todos los recursos base y variantes de escala/tamaño declarados por su manifiesto. Ninguna superficie validable de Windows (archivo ejecutable, ventana/barra de tareas, menú Inicio o aplicación instalada) debe recurrir al icono genérico por ausencia o invalidez del recurso.

#### RF6.2 Gestión y Captura de Fuentes de Audio

- **RF6.2.1 Captura Predeterminada del Sistema Operativo:** El sistema debe configurar de forma predeterminada la captura global de audio del sistema operativo (*System Loopback*) para procesar cualquier señal sonora emitida por el dispositivo.
- **RF6.2.2 Actualizado -- Selector y tipo de dispositivo:** Proveer en la sección de ajustes un control de lista desplegable que detecte y enumere dinámicamente los dispositivos de audio disponibles (interfaces externas, micrófonos, entradas de línea o bucles virtuales) y distinga de forma explícita entre captura directa y captura *System Loopback* de una salida de reproducción.
- **RF6.2.3 Actualizado -- Re-conmutación transaccional en tiempo real:** Permitir el cambio entre dispositivos de audio durante la ejecución, sin reiniciar la aplicación ni interrumpir el hilo de renderizado gráfico. La selección y su persistencia sólo se confirmarán cuando la nueva captura haya iniciado correctamente; si falla, el sistema conservará la última fuente funcional, expondrá el motivo y no guardará la selección fallida. Si el dispositivo persistido ya no existe al arrancar, se restablecerá el *System Loopback* predeterminado y se sincronizarán la interfaz y la configuración persistida.
- **RF6.2.4 Actualizado -- Sin leyenda "Fuente de audio":** La aplicación no debe mostrar el rótulo literal "Fuente de audio". Esta eliminación no altera la captura predeterminada ni el control de selección de dispositivo definido por RF6.2.1--RF6.2.3, que debe mantenerse disponible.
- **RF6.2.5 Nuevo -- Diagnóstico de actividad y privacidad:** Tras seleccionar una fuente, el sistema debe comprobar en un intervalo máximo de tres (3) segundos que avanzan las marcas de tiempo de captura. Si el dispositivo se abre pero no entrega datos, o si Windows deniega el acceso, la interfaz debe mostrar un estado no bloqueante con una acción de recuperación. En MSIX se conservará la capacidad `microphone` y se consultará el estado de acceso mediante las API compatibles con la identidad empaquetada; en la distribución unpackaged se explicará que el acceso depende del control global de micrófono para aplicaciones de escritorio y se podrá abrir `ms-settings:privacy-microphone`. La aplicación no debe simular ni prometer un aviso individual de consentimiento que Windows no proporcione para aplicaciones de escritorio unpackaged.

#### RF6.3 Catálogo, Navegación y Gestión de Favoritos

- **RF6.3.1 Actualizado -- Menú Catálogo de Visualizadores:** El icono de catálogo del overlay debe abrir un selector que muestre las fichas de los visualizadores disponibles. El catálogo debe poder crecer a varios visualizadores; en la versión actual sólo RS-EB será seleccionable/ejecutable.
- **RF6.3.2 Ejecución por Selección:** Iniciar y desplegar inmediatamente en la zona principal de renderizado cualquier visualizador seleccionado por el usuario desde el catálogo.
- **RF6.3.3 Marcado de Favoritos:** Permitir al usuario asignar o remover un estado de "Favorito" (mediante un marcador explícito) a cada uno de los visualizadores del catálogo.
- **RF6.3.4 Actualizado -- Filtro de Favoritos:** El catálogo debe ofrecer un control explícito para activar/desactivar el filtro de favoritos; al estar activo sólo se mostrarán visualizadores marcados como favoritos.
- **RF6.3.5 Actualizado -- Vista de visualizador seleccionado y overlay:** Al iniciar, se debe restaurar el último visualizador seleccionado y ocupar todo el viewport con él. Sobre esa vista se mostrará un único overlay de interacción compuesto por: (a) icono de catálogo, (b) icono de lápiz para la configuración del visualizador activo, (c) icono de engrane para la configuración global y (d) un carrusel horizontal inferior para cambiar directamente de visualizador.
- **RF6.3.6 Actualizado -- Auto-ocultamiento del overlay:** Tras cuatro (4) segundos sin interacción del usuario, el overlay debe ocultarse y el visualizador debe quedar en primer plano. Cualquier interacción de entrada destinada a recuperar controles debe volver a mostrar el overlay sin modificar el estado del visualizador. El temporizador se suspenderá mientras un control interactivo del overlay esté abierto, tenga foco, se encuentre bajo el puntero o reciba interacción de teclado; en particular, no debe ocultar ni cerrar el selector de dispositivo mientras el usuario lo inspecciona o elige una opción.
- **RF6.3.7 Nuevo -- Acciones rápidas del carrusel:** El carrusel debe permitir marcar/desmarcar un visualizador como favorito mediante una estrella visible y contener un botón etiquetado "Modo aleatorio". En esta versión el botón sólo comunica la futura función: la edición de la lista aleatoria y su panel de configuración quedan fuera de alcance hasta contar con las especificaciones pendientes.

#### RF6.4 Secuenciador Dinámico y Gestión de Presets -- Actualizado

- **RF6.4.1 Retirado -- Autorrotación y Presets:** Los modos de conmutación autorrotativa, selección aleatoria, ordenamiento manual de itinerario y gestión de presets de rotación han sido retirados de esta versión para eliminar sobre-parametrización.
- **RF6.4.2 Retirado -- Transición de Fundido Configurable:** Al existir un único efecto activo (RS-EB), las transiciones de fundido y sincronizaciones multivisualizador quedan fuera de alcance.

#### RF6.5 Control de Interfaz e Inmersión a Pantalla Completa

- **RF6.5.1 Conmutación a Modo Inmersivo:** Proveer una acción global (mediante botón de UI o atajo de teclado) para alternar entre el modo de configuración/navegación y el modo de pantalla completa.
- **RF6.5.2 Ocultamiento de Overlays y Ajustes:** Al activar el modo de pantalla completa, el sistema debe ocultar automáticamente todos los menús, barras de herramientas, laterales de ajustes, avisos superpuestos y controles de interfaz, maximizando el viewport de renderizado al 100% de la pantalla.
- **RF6.5.3 Restauración de Interfaz:** Re-mostrar los elementos gráficos de control al detectar interacción activa del usuario (movimiento del cursor o evento de entrada especifico) o al presionar la tecla de salida del modo inmersivo.

#### RF6.6 Personalización Estética y Tema de la Interfaz

- **RF6.6.1 Selector de Tema de Interfaz:** Permitir al usuario alternar entre modos visuales para los paneles de control del sistema.
- **RF6.6.2 Modo Noche (Dark Mode):** Proveer un tema visual enfocado en tonos oscuros y bajo nivel de luminancia para la interfaz del contenedor, reduciendo la fatiga visual y garantizando que el foco de atención siga siendo el canvas del visualizador reactivo.
- **RF6.6.3 Nuevo -- Tema del sistema sincronizado:** La opción predeterminada *Sistema* debe resolver el tema actual de aplicaciones de Windows tanto al iniciar como cuando cambie durante la ejecución. El tema resuelto debe aplicarse de forma coherente a recursos XAML, barra de título y superficies Win2D; las opciones explícitas Claro y Oscuro deben permanecer estables. La implementación debe respetar el modo de contraste alto y no sustituir sus colores de accesibilidad.

#### RF6.7 Configuración Contextual del Visualizador

- **RF6.7.1 Actualizado -- Apertura desde overlay:** El icono de lápiz del overlay debe abrir el panel de configuración del visualizador actualmente seleccionado.
- **RF6.7.2 Alcance por efecto:** Dicho panel debe mostrar exclusivamente los controles que correspondan a los parámetros de renderizado y comportamiento del efecto activo. No debe mezclar controles de otros visualizadores ni la configuración diferida de rotación aleatoria.
- **RF6.7.3 Persistencia de selección:** Los ajustes confirmados para un efecto deben conservarse con el preset/estado de ese efecto sin afectar la configuración de otro visualizador.

#### RF6.8 Nuevo -- Configuración Global

- **RF6.8.1 Apertura desde overlay:** El icono de engrane del overlay debe abrir la configuración global de la aplicación.
- **RF6.8.2 Alcance global:** Este panel alojará controles que no son propios del render de un efecto, incluyendo el selector de dispositivo de audio, tema de interfaz y gestión global de presets. No debe mezclar parámetros específicos del visualizador activo.

#### Supuestos y alcance diferido -- Actualizado 2026-07-29

- El aviso retirado de inicio es el relativo a permisos/capacidades de audio o
  sistema. El aviso fotosensible se conserva durante cinco segundos y no
  presenta permisos ni requiere un botón de aceptación.
- El carrusel se ubica en la franja inferior de la vista seleccionada. Los
  iconos de catálogo/configuración y las acciones rápidas pueden disponerse en
  la zona superior/lateral del overlay; no se fija una coordenada visual más
  precisa en esta especificación.
- El selector de dispositivo de audio se mantiene como control global, sin el
  rótulo literal "Fuente de audio", y se abre desde la configuración global.
- El catálogo está preparado para crecer, pero sólo RS-EB se muestra como
  opción ejecutable en esta versión. Las futuras fichas no deberán simular ni
  activar renderizadores inexistentes.
- La configuración de lista/reglas del modo aleatorio y su panel son trabajo
  futuro pendiente de las especificaciones que el usuario indicó como faltantes.

# SECCIÓN II: Requisitos No Funcionales y Atributos de Calidad (ISO 25010)

De acuerdo con la norma ISO/IEC 25010 y la Versión 4.0 de la especificación, los requisitos no funcionales se estructuran en atributos de calidad críticos para garantizar el rendimiento en tiempo real, la estabilidad del motor de audio y la escalabilidad del sistema de visualización.

## 1. Eficiencia de Desempeño (Performance Efficiency)

- RNF-PERF.1 Latencia de Cómputo Core: Medir `L_c` desde la entrada de un hop hasta el frame publicado; objetivo p99 < 1.5 ms en hardware de referencia. Reportar por separado la edad de grupo `L_g` de cada ventana (1024/2048/4096) y la latencia extremo a extremo; no atribuir `L_g` al cómputo.
- RNF-PERF.2 Tasa de Refresco Gráfico: Las soluciones de visualización deben mantener ≥ 60 FPS continuos, con objetivo 120 FPS, mientras el DSP publica a 93.75 Hz con `H=512` y el render sólo lee el último frame disponible.
- RNF-PERF.3 Desacoplamiento Multihilo: El motor de audio (DSP Engine) debe ejecutarse en un hilo prioritario síncrono separado del hilo de renderizado gráfico (GPU/Render Engine) para evitar saturación de recursos.

## 2. Fiabilidad (Reliability)

- RNF-REL.1 Tolerancia a Desbordamientos: Garantizar cero desbordamientos de búfer (buffer overflow/underflow) durante la ingesta y procesamiento de flujos PCM en ejecuciones continuas de larga duración.
- RNF-REL.2 Memoria Compartida Sin Bloqueos: Utilizar estructuras atómicas de tipo Single-Producer Single-Consumer (SPSC) Ring Buffer para la transferencia de datos sin sobrecostes por cerrojos (mutex locks).

## 3. Modulabilidad y Mantenibilidad (Maintainability)

- RNF-MAN.1 Extensibilidad de Soluciones: Debe ser posible agregar una nueva solución visual (ej. Solución D) mediante la simple adición de su perfil de datos y reglas de mapeo, sin modificar ninguna línea de código de los Módulos Core 1 al 5.

## 4. Intercambiabilidad y Portabilidad (Compatibility / Portability)

- RNF-PORT.1 Hot-Swapping (Intercambio en Caliente): El sistema debe permitir cambiar la solución visual activa (ej. de Solución A ≤ 3 bandas a Solución C ≤ 256 bandas) en tiempo de ejecución sin interrumpir la ingesta de audio ni perder frames (transición ≤ 16.6 ms).

## 5. Reusabilidad (Reusability)

- RNF-REU.1 Reuso del Pipeline Matemático: El 100% de la lógica matemática de la FFT, suavizado exponencial y calibración psicoacústica debe ser compartida y reutilizada de forma transparente por todas las soluciones visuales a través del contrato estandarizado (AudioFrameData).

# SECCIÓN III: MARCO DE ESPECIFICACIÓN DE SOLUCIONES (Consumidores de Datos)

Este marco establece las reglas para extender el sistema mediante nuevas representaciones visuales sin duplicar requisitos ni tocar el código del Core.

---

## 1. Reglas de Contrato de Solución (Interfaz de Requisitos)

Para que cualquier solución sea compatible con el sistema, su especificación de requisitos debe declarar **tres capas obligatorias**:

```
[ Estructura de Requisitos de una Solución Visual ]
├── 1. Declaración de Perfil de Datos (Solicitud al Core: N, Distribución)
├── 2. Reglas de Mapeo Geométrico / Estético (Transformación)
└── 3. Reglas de Respuesta a Eventos y Dinámicas (Comportamiento)
```

---

Utiliza esta interfaz de checklist estructurada cada vez que planifiques, diseñes o especifiques un nuevo visualizador (solución) sobre el Core. Esto garantiza que la especificación sea ordenada, clara, completa y 100% alineada con el contrato de datos y la norma ISO/IEC 25010.

## Plantilla de Especificación de Nueva Solución Visual

- Identificador y Nombre: [Ej. RS-SOL-D: Visualizador Circular 3D]
- Descripción Conceptual: [Breve descripción de la representación visual y su propósito estético/técnico].

### Fase 1: Declaración de Perfil de Datos (Contrato Core)

- [ ]  Definir cantidad de bandas N (ej. N = 64, N = 128 o N dinámico).
- [ ]  Seleccionar tipo de escala (Lineal, Logarítmica, Bark/Mel o Manual).
- [ ]  Declarar descriptores globales necesarios: x_RMS (Potencia Global), f_C (Centroide Espectral), Onset (Eventos).

### Fase 2: Mapeos Continuos y Transformación Geométrica

- [ ]  Asignar el vector de energías E_i a propiedades físicas/visuales continuas (escala, altura, radio, deformación de malla).
- [ ]  Mapear descriptores de alto nivel (x_RMS, f_C) a cinemática de cámara, velocidad de rotación o paleta cromática (Hue/Saturation).

### Fase 3: Respuestas Discretas y Dinámicas (Eventos)

- [ ]  Definir la respuesta reactiva exacta ante Onset == true (ej. destello de luz, onda de choque radial, impulso de partículas, flash de fondo).

# SECCIÓN IV: Visualizadores

## Alcance de la versión actual -- Actualizado

Esta versión contiene un único visualizador ejecutable y configurable:
**RS-EB: Ecualizador de Barras Espectral**. Los visualizadores llamados
"Ecualizador espejo", "Pulso espectral" y "Malla espectral" se retiran de
esta versión: no deben registrarse, aparecer como opciones ejecutables del
catálogo/carrusel/rotación ni compartir configuración con RS-EB.

El *layout* **Espejo/Center-Out** definido para RS-EB no constituye un
visualizador independiente; sigue siendo sólo una disposición geométrica de
las mismas barras. La plantilla de la Sección III conserva la extensibilidad
para soluciones futuras, pero éstas requerirán una especificación independiente
antes de añadirse al catálogo ejecutable.

## RS-EB: Ecualizador de Barras Espectral

**Descripción:** Representación bidimensional del espectro mediante barras
dinámicas configurables. Es el único efecto activo de esta versión y ofrece
parametrización de resolución espectral, color, disposición geométrica y
tratamiento estético de las barras.

### Requisitos funcionales

**RF-EQ.1 Configuración Dinámica de Bandas ($N$):**

- Permitir la selección del número de barras $N$ en un rango configurable de
  $N \in [12, 128]$.
- Agrupar dinámicamente el vector de magnitudes de la FFT en $N$ bandas de
  frecuencia mediante escala logarítmica/Mel, distribuyendo la energía entre
  graves, medios y agudos.

**RF-EQ.2 Suavizado Asimétrico de Amplitud (Ataque Rápido / Caída Lenta):**

Aplicar a cada barra $i$ el siguiente valor de altura renderizada $v_i[t]$:

$$
v_i[t] = \begin{cases} E_i[t] & \text{si } E_i[t] \ge v_i[t-1] \quad \text{(ataque instantáneo, } \alpha_{attack} = 1.0\text{)} \\ \alpha_{decay} \cdot v_i[t-1] + (1 - \alpha_{decay}) \cdot E_i[t] & \text{si } E_i[t] < v_i[t-1] \quad \text{(caída exponencial, } \alpha_{decay} \in [0.85, 0.95]\text{)} \end{cases}
$$

El incremento no debe introducir latencia perceptible y el descenso debe
prevenir parpadeo de alta frecuencia.

**RF-EQ.3 Modos de Coloración Espectral -- Actualizado:**

- **Modo Mapeado por Audio:** Asignar el matiz de la barra $i$ según su
  frecuencia central relativa $f_i$ y aplicar una fase cromática global en
  respuesta al centroide espectral $f_C$.
- **Modo Paleta Personalizada:** El panel contextual de RS-EB debe permitir
  editar realmente los colores de la paleta/gradiente, aplicarlos a las barras
  y persistirlos con el estado del efecto. Ofrecer únicamente la opción de
  personalización sin un control para definir/aplicar la paleta no satisface
  este requisito. La orientación del gradiente será vertical por altura u
  horizontal por índice de barra.

**RF-EQ.4 Modos de Disposición Geométrica (Layout):**

1. **Estándar:** crecimiento desde la línea base inferior hacia arriba
   (*Bottom-Up*).
2. **Invertido:** crecimiento desde la línea base superior hacia abajo
   (*Top-Down*).
3. **Espejo:** crecimiento simétrico bidireccional desde un eje central
   (*Center-Out*), como variante de RS-EB, no como visualizador distinto.

**RF-EQ.5 Parametrización Simplificada de RS-EB -- Actualizado:**

El panel contextual de RS-EB se simplifica para ofrecer únicamente los parámetros
de **Disposición Geométrica (Layout)**, **Número de Bandas ($N$)** y **Modo de Coloración**
(Mapeado por Audio / Paleta Personalizada).

- **RF-EQ.5.1 Retirado -- Sobre-parametrización:** Se retiran los controles de
  espaciado de barras (gap), radio de esquinas (cápsulas), marcadores de picos (peak hold),
  velocidad de caída de picos, resplandor posterior (glow/bloom) e intensidad, y reflejo
  en línea base para garantizar un renderizado limpio, directo y de ultra-bajo consumo.
- **RF-EQ.5.2 Retirado -- Selector de Escala Espectral en UI:** Se retira el control selector
  de escala espectral de la interfaz gráfica del usuario. El Core mantendrá internamente la
  agrupación espectral perceptual/logarítmica optimizada (ERB/Log-Octave) como valor por defecto
  para el ecualizador de barras.
- **RF-EQ.5.3 Eliminación Física de Componentes Obsoletos:** Se eliminan físicamente del repositorio
  y de la compilación los archivos no utilizados de efectos y transiciones retiradas:
  `D3D11SpectralMeshVisualizer.cs`, `SpectralMesh3DMath.cs`, `Win2DSpectralBarVisualizer.cs` y `VisualizerTransitionState.cs`.
