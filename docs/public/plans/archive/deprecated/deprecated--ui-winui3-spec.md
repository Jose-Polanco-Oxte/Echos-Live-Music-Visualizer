# Echo — Especificación de UI/UX para WinUI 3

> Documento de implementación derivado de `MockUp.png` (5 pantallas: Visualizer, Personalización, Catálogo, Configuración y Pantalla Completa). Pensado para ser ejecutado directamente por un agente/desarrollador sobre **Windows App SDK (WinUI 3)**.
>
> Todas las medidas en px son **aproximaciones visuales** del mockup (no extracción por pixel-picker); úsalas como punto de partida y ajústalas contra los assets de diseño reales si existen. Cada punto donde tuve que inferir algo que el mockup no muestra explícitamente está marcado con `🔶 Supuesto` y listado también en la sección 14.

**Decisiones de arquitectura clave (resumen):**
- Una sola `Window` con un `Frame` raíz. Las 4 pantallas son **páginas navegables** (`VisualizerPage`, `CatalogPage`, `SettingsPage`), no ventanas separadas — el mockup las muestra con su propia barra de título solo para claridad del diseño.
- El panel "Personalización" **no es una página**: es un `SplitView.Pane` dentro de `VisualizerPage`.
- El lienzo del visualizador se renderiza con **Win2D**; el resto de la UI es XAML estándar de Fluent Design.
- El comportamiento de auto-ocultado del overlay es una **máquina de 3 estados** (`Full` / `ManualCollapsed` / `IdleHidden`) — detallada por completo en la sección 9, que es el punto más delicado de esta spec.

---

## Índice
0. (arriba) Resumen y decisiones clave
1. [Fundamentos de diseño](#1-fundamentos-de-diseño)
2. [Arquitectura del proyecto](#2-arquitectura-recomendada-del-proyecto)
3. [Layout raíz de la ventana (Shell)](#3-layout-raíz-de-la-ventana-shell)
4. [Pantalla 1 — Echo Visualizer](#4-pantalla-1--echo-visualizer-vista-principal)
5. [Menú de Ajustes del Visualizador RS-EB (Icono Lápiz / Panel RS-EB)](#5-menú-de-ajustes-del-visualizador-rs-eb-icono-lápiz--panel-rs-eb)
6. [Pantalla 3 — Catálogo](#6-pantalla-3--catálogo)
7. [Menú de Configuración Global (Icono Engrane / Panel Global)](#7-menú-de-configuración-global-icono-engrane--panel-global)
8. [Pantalla Completa](#8-pantalla-completa)
9. [Splash Screen & Disclaimer Fotosensible de Inicio](#9-splash-screen--disclaimer-fotosensible-de-inicio)
10. [Sistema de auto-ocultado del overlay](#10-sistema-de-auto-ocultado-del-overlay)
11. [Guía de animaciones](#11-guía-de-animaciones)
12. [Flujo de navegación consolidado](#12-flujo-de-navegación-consolidado)
13. [Tabla maestra de componentes WinUI3](#13-tabla-maestra-de-componentes-winui3)
14. [Accesibilidad y responsividad](#14-accesibilidad-y-responsividad)
15. [Supuestos e inferencias](#15-supuestos-e-inferencias)

---

## 1. Fundamentos de diseño

### 1.1 Paleta de color (valores aproximados leídos del mockup)

| Token | Hex aprox. | Uso |
|---|---|---|
| `ColorBgBase` | `#060810` | Fondo raíz / cielo del lienzo del visualizador |
| `ColorBgElevated` | `#12161F` | Tarjetas de preset, sidebar, filas de ajustes |
| `ColorBgElevated2` | `#1B212E` | Hover de tarjetas/filas, fondo por defecto de botones pill |
| `ColorBorderSubtle` | `#262C3A` | Bordes de tarjetas, separadores |
| `ColorBorderStrong` | `#3A4256` | Bordes de inputs, chevrons |
| `ColorAccent` | `#2E8BFF` | Selección activa, toggle ON, texto de nav activo, thumb del slider |
| `ColorAccentGlow` | `rgba(46,139,255,.35)` | Resplandor/glow detrás de la tarjeta seleccionada |
| `ColorTextPrimary` | `#F2F4F8` | Texto principal |
| `ColorTextSecondary` | `#9AA3B5` | Descripciones, labels secundarios |
| `ColorTextDisabled` | `#5B6272` | Texto deshabilitado |
| `ColorBarGradientTop` | `#AEEBFF` | Extremo superior del degradado de cada barra |
| `ColorBarGradientBottom` | `#1660D6` | Extremo inferior del degradado de cada barra |
| `ColorToggleOffTrack` | `#333B4C` | Track de `ToggleSwitch` en OFF |

Define estos como `Color`/`SolidColorBrush` en `Resources/ColorPalette.xaml` y expórtalos como `ThemeResource` para no hardcodear hex en cada XAML.

### 1.2 Tipografía

Fuente base: **Segoe UI Variable** (default de WinUI3 — no cambiar).

| Rol | Familia | Tamaño | Peso |
|---|---|---|---|
| Título de ventana | Segoe UI Variable Text | 12 | Regular |
| Encabezado de panel (`Personalización`, `Configuración`, `General`) | Segoe UI Variable Display | 18–20 | SemiBold |
| Texto de botón / fila | Segoe UI Variable Text | 13–14 | Medium |
| Texto secundario / descripción | Segoe UI Variable Text | 12 | Regular |
| Etiqueta de tarjeta de preset | Segoe UI Variable Text | 11 | Regular |
| Valor numérico ("64") | Segoe UI Variable Text | 12 | SemiBold |

### 1.3 Espaciado
Grid de 4px: usa incrementos de **4 / 8 / 12 / 16 / 20 / 24 / 32**. Padding estándar de página: 20px. `Spacing` estándar entre elementos de un mismo grupo: 8px.

### 1.4 Radios de esquina
| Token | Valor | Uso |
|---|---|---|
| `RadiusSm` | 6 | Filas de lista, chips pequeños |
| `RadiusMd` | 8 | Botones pill del top bar, inputs, tarjetas pequeñas |
| `RadiusLg` | 10–12 | Tarjetas de preset, panel lateral |
| `RadiusFull` | height/2 | Botón "ojo" circular |

### 1.5 Materiales y elevación
- **Mica** como `SystemBackdrop` de la `Window` (chrome de la barra de título). No es visible detrás del lienzo del visualizador porque éste es opaco (contenido dibujado), pero mantiene coherencia con el resto del sistema y da un fondo correcto en los bordes/redimensionado.
- **Acrylic in-app** para las superficies flotantes que están *encima* del lienzo animado: `TopBarOverlay`, `BottomOverlay` (incluida la tira de presets) y el `SplitView.Pane` de Personalización. Esto es lo que da el efecto "cápsula translúcida flotando sobre las barras" del mockup.
- Las páginas `CatalogPage` y `SettingsPage` **no** llevan Acrylic — son páginas de fondo sólido (`ColorBgBase`/`ColorBgElevated`), ya que no hay lienzo animado detrás de ellas.
- Sombra: `ThemeShadow` sutil (blur 12px) bajo el `SplitView.Pane` y bajo la tarjeta de preset seleccionada.

### 1.6 Iconografía
No hay un mapeo 1:1 garantizado entre cada icono del mockup y un glyph exacto de Segoe Fluent Icons — para no dar codepoints incorrectos, usa este criterio:
- **Iconos estándar** (Editar, Config, Buscar, Filtro, Estrella, Cerrar/X, Chevron, Atrás, Pantalla completa, Grid/ViewAll): usa `SymbolIcon` con el `Symbol` correspondiente cuando exista en el enum de WinUI3, o `FontIcon FontFamily="Segoe Fluent Icons"` verificando el glyph exacto contra la [lista oficial de Segoe Fluent Icons](https://learn.microsoft.com/windows/apps/design/style/segoe-fluent-icons-font).
- **Iconos sin equivalente directo** (Velocidad, Espaciado, Grosor, Suavizado, Reflejo, Modo aleatorio/shuffle, Ojo/Ojo tachado): usa como fuente el repositorio open-source de Microsoft **Fluent System Icons** (`microsoft/fluentui-system-icons`, estilo *regular*, 20px), exportados como `PathIcon`.
- Tamaño estándar: 16px dentro de botones de texto, 18px en filas de lista, 20–24px en navegación de Configuración.
- Estilo: trazo fino (*regular/outline*), nunca *filled*, excepto estados activos puntuales (estrella marcada, ojo abierto vs. tachado).

---

## 2. Arquitectura recomendada del proyecto

Patrón **MVVM** con `CommunityToolkit.Mvvm` (`ObservableObject`, `[RelayCommand]`, `IMessenger` opcional para comunicar el preset seleccionado entre `CatalogPage` → `VisualizerPage`).

```
Echo/
├─ App.xaml / App.xaml.cs                  (DI container: Microsoft.Extensions.DependencyInjection)
├─ MainWindow.xaml                         (Shell: título custom + Frame raíz)
├─ Views/
│  ├─ VisualizerPage.xaml                  (Pantallas 1 + 2: canvas + sidebar)
│  ├─ CatalogPage.xaml                     (Pantalla 3)
│  ├─ SettingsPage.xaml                    (Pantalla 4, contenedor NavigationView)
│  └─ SettingsSubPages/
│     ├─ GeneralSettingsPage.xaml          (única con contenido confirmado por el mockup)
│     ├─ AppearanceSettingsPage.xaml
│     └─ ... Performance / Audio / Startup / Accessibility / Updates / About
├─ Controls/
│  ├─ PresetCard.xaml(.cs)                 (reutilizable: tira inferior + grid del catálogo)
│  ├─ VisualizerCanvas.xaml(.cs)           (control Win2D del render de barras)
│  └─ SettingsRow.xaml(.cs)                (icono + label + chevron del sidebar)
├─ ViewModels/
│  ├─ ShellViewModel.cs
│  ├─ VisualizerViewModel.cs
│  ├─ CatalogViewModel.cs
│  └─ SettingsViewModel.cs
├─ Services/
│  ├─ OverlayVisibilityService.cs          (máquina de estados — sección 9)
│  ├─ AudioCaptureService.cs               (captura loopback WASAPI)
│  ├─ PresetService.cs                     (CRUD de presets + favoritos, JSON local)
│  ├─ SettingsService.cs                   (ApplicationData.LocalSettings o JSON)
│  └─ FullScreenService.cs                 (wrapper de AppWindow.SetPresenter)
├─ Models/
│  ├─ VisualizerPreset.cs
│  └─ AppSettings.cs
└─ Assets/Icons/                           (SVG/PathIcon de Fluent System Icons)
```

**Navegación:** `MainWindow` aloja un `Frame` raíz (`RootFrame`). `VisualizerPage` es la página de inicio; se navega a `CatalogPage`/`SettingsPage` con `RootFrame.Navigate(typeof(X), null, new SlideNavigationTransitionInfo{...})` y se regresa con `RootFrame.GoBack()`.

**Estado compartido:** el preset activo y la lista de presets/favoritos viven en `PresetService`, registrado como singleton en el contenedor DI e inyectado tanto en `VisualizerViewModel` como en `CatalogViewModel`, para que seleccionar un preset en el Catálogo se refleje inmediatamente al volver al Visualizer.

---

## 3. Layout raíz de la ventana (Shell)

- `MainWindow`: `this.ExtendsContentIntoTitleBar = true`, con un `Grid AppTitleBar` de 40px de alto (icono 20x20 + `TextBlock "Echo"` a 12px del borde) pasado a `SetTitleBar(AppTitleBar)`. Botones de sistema con `AppWindowTitleBar.ButtonBackgroundColor = Colors.Transparent`, hover gris oscuro, cerrar en rojo estándar de Windows 11 (comportamiento nativo, no dibujar a mano).
- Dentro de `VisualizerPage` (la página "home"), estructura en capas:

```
Grid raíz de VisualizerPage  (Background="Transparent" ⚠️ explícito, no null — necesario para hit-testing de punteros)
├─ VisualizerCanvas                     (RowSpan/ColumnSpan completo → capa 0, fondo)
└─ SplitView                            (Pane = Personalización · Content = resto)
    └─ SplitView.Content → Grid overlay (capa 1)
        ├─ Row 0 = Auto  → TopBarOverlay      (fondo Transparent)
        ├─ Row 1 = *     → (vacío; deja pasar el puntero al canvas)
        └─ Row 2 = Auto  → BottomOverlay      (fondo Transparent)
```

`TopBarOverlay` y `BottomOverlay` deben tener `Background="Transparent"` explícito en su contenedor para que sus botones reciban punteros, pero sin pintar un fondo sólido (el canvas debe verse detrás). Solo los elementos hijos (botones, tarjetas) llevan su propio fondo Acrylic/sólido.

### 1.7 Responsividad (breakpoints sugeridos)
🔶 No visible en el mockup, añadido por buena práctica:
- `< 900px` de ancho: los botones del TopBar muestran solo icono (sin texto).
- `< 700px`: el `SplitView` de Personalización cambia de `PaneDisplayMode="Inline"` a `"Overlay"` (flota encima en vez de empujar el contenido) para no comprimir demasiado el lienzo.
- Tamaño mínimo de ventana recomendado: 640x480.

---

## 4. Pantalla 1 — Echo Visualizer (vista principal)

### 4.1 Barra superior (`TopBarOverlay`)
Altura ~56px, padding horizontal 20px.

**Grupo izquierdo** (`StackPanel Orientation="Horizontal" Spacing="8"`):
| Control | Tipo | Contenido | Comportamiento |
|---|---|---|---|
| "Lápiz" | `ToggleButton` | icono Editar (16px) + texto | `IsChecked` ↔ `VisualizerViewModel.IsSidebarOpen` ↔ `SplitView.IsPaneOpen`. Checked = fondo `ColorAccent`, texto blanco (así se ve en la Pantalla 2 del mockup) |
| "Catálogo" | `Button` | icono ViewAll/Grid (16px) + texto | Click → `RootFrame.Navigate(typeof(CatalogPage), ...)` |

**Grupo derecho** (`HorizontalAlignment="Right"`, mismo `Spacing`):
| Control | Tipo | Contenido | Comportamiento |
|---|---|---|---|
| "Configuración" | `Button` | icono engranaje + texto | Click → `RootFrame.Navigate(typeof(SettingsPage), ...)` |
| "Pantalla Completa" | `Button` | icono expandir + texto | Click → `FullScreenService.Toggle()` |

Ambos grupos comparten un `Style x:Key="ToolbarPillButtonStyle"`: `CornerRadius="8"`, padding `12,8`, fondo por defecto `ColorBgElevated2` @ ~60% opacidad (Acrylic), hover `ColorBgElevated2` @ 100%, sin borde cuando está "checked"/activo (fondo sólido `ColorAccent`).

### 4.2 Lienzo del visualizador (`VisualizerCanvas`)
Ocupa el 100% del área disponible, detrás de ambos overlays.

- **Fondo:** degradado "cielo nocturno" (`ColorBgBase` en el centro → azul muy oscuro en bordes) + capa de "estrellas": 60–100 puntos blancos, radio 0.5–1.5px, opacidad aleatoria 20–80%, generados con semilla fija por sesión (para que no cambien en cada frame).
- **Barras:**
  - Cantidad = "Número de barras" (rango sugerido 16–256; el mockup muestra 64 como ejemplo).
  - Ancho y separación controlados por "Grosor" y "Espaciado" (sección 5.3).
  - Cap superior redondeado (`CornerRadius` = mitad del ancho de barra).
  - Color: degradado vertical por barra, `ColorBarGradientTop` → `ColorBarGradientBottom`, más glow (blur gaussiano, radio 8–16px, mismo color a baja opacidad) — controlado por "Color" y "Efectos".
  - Reflejo: copia especular hacia abajo del baseline con opacidad decreciente (35%→0%) — controlado por el toggle "Reflejo".
  - Animación reactiva a audio por banda de frecuencia (FFT): ataque rápido (~50ms), liberación más lenta (~250–300ms) — el patrón típico de un ecualizador. "Velocidad" escala estos tiempos; "Suavizado" aplica un promedio móvil exponencial antes de mapear a altura; "Sensibilidad" multiplica la amplitud de entrada.
  - 🔶 Sugerido: sin audio activo, micro-oscilación ambiental (2–4% de la altura máx.) en vez de barras planas en cero.
- **Recomendación técnica:** renderizar con **Win2D** (`CanvasAnimatedControl`) para aplicar `GaussianBlurEffect`/`CompositeEffect` a 60fps con fidelidad al mockup. Alternativa más liviana: **Composition API** con un `SpriteVisual` por barra + `ImplicitAnimations` (menos costoso, blur más limitado). El resto de animaciones de UI (overlay, tarjetas) sí conviene hacerlas con Composition/`AnimationBuilder` independientemente del motor del canvas.

### 4.3 Overlay inferior (`BottomOverlay`)
Dos filas internas, padding horizontal 20px, padding inferior 16px, `Spacing="8"` vertical.

**Fila A — controles secundarios** (~32px alto):
- Columna izquierda: selector segmentado de 2 opciones ("vista de lista" / "vista de cuadrícula"), 32x32px cada botón — implementar con `SelectorBar` (si la versión de Windows App SDK del proyecto lo soporta) o con 2 `ToggleButton` agrupados manualmente (mutuamente excluyentes). 🔶 Supuesto: alternan el layout de la tira de presets (fila horizontal ↔ cuadrícula compacta de 2 filas); el mockup no muestra el estado alternativo — confirmar con producto.
- Columna derecha: `Button "Modo aleatorio"` (icono shuffle + texto, mismo `ToolbarPillButtonStyle`). Click → selecciona un preset aleatorio distinto al actual y lo aplica con crossfade (~300ms).

**Fila B — tira de presets** (~110px alto):
`Grid` de 2 columnas: Col0=`*` (tira scrollable) | Col1=`Auto` (botón "ojo", fijo, **no** se desplaza con el scroll).
- Col0: `ItemsRepeater`/`ListView` horizontal dentro de `ScrollViewer` (`HorizontalScrollMode="Enabled"`, `VerticalScrollMode="Disabled"`), `Spacing="12"`, cada ítem = control `PresetCard` (sección 4.4).
- Col1: `ToggleButton "EyeButton"` circular 44x44px, `CornerRadius="22"`, fondo Acrylic oscuro, icono ojo abierto por defecto. Lógica completa en la **sección 9**.

### 4.4 Componente reutilizable: `PresetCard`
Un solo `UserControl` con `DependencyProperty CardSize` (`Small` para la tira / `Large` para el grid del Catálogo), para no duplicar código.

| Tamaño | Dimensiones aprox. |
|---|---|
| Small (tira inferior) | 152 x 96 px |
| Large (grid del Catálogo) | 184 x 120 px |

Estructura (capas dentro de un `Grid`):
- Fondo `ColorBgElevated`, `CornerRadius="10"`, borde 1px `ColorBorderSubtle`.
- **Seleccionado:** borde 2px `ColorAccent` + `ThemeShadow`/glow exterior (blur 12px, `ColorAccentGlow`).
- **Hover:** fondo `ColorBgElevated2`, escala 1.02 (Composition, 150ms `EaseOut`).
- Esquina sup. izq. (padding 8px): `TextBlock` nombre del preset, 11px, `TextTrimming="CharacterEllipsis"`, `MaxLines="1"` (el mockup muestra el texto truncado cuando la tarjeta es más angosta — confirma que el trimming es intencional).
- Centro: miniatura del preset (ver nota de rendimiento).
- Esquina inf. der. (padding 8px): `ToggleButton` icono estrella (outline/filled), 16px, togglea favorito con animación "pop" (escala 1→1.3→1, 250ms `BackEase`).
- Tap en el cuerpo (no en la estrella) → selecciona el preset como activo.

**Nota de rendimiento:** con 20+ tarjetas visibles simultáneamente (grid del Catálogo), evita instanciar 20 `CanvasAnimatedControl` en vivo. Solo la tarjeta seleccionada/en foco renderiza en vivo; el resto muestra una miniatura pre-renderizada y cacheada (regenerada solo si cambian los parámetros del preset).

---

## 5. Menú de Ajustes del Visualizador RS-EB (Icono Lápiz / Panel RS-EB)

Contenedor: `SplitView` / panel lateral dentro de `VisualizerPage`. `PaneDisplayMode="Inline"`, `OpenPaneLength="260"`, `IsPaneOpen="{x:Bind ViewModel.IsSidebarOpen, Mode=TwoWay}"`.

Contiene **únicamente** los parámetros esenciales para adaptar el ecualizador espectral (sin opciones adicionales ni inventadas):

### 5.1 Encabezado
`Grid` 2 columnas: `TextBlock "Ajustes RS-EB"` (18px SemiBold) | `Button` icono X/Dismiss (transparente, 32x32). Click en X → `IsSidebarOpen = false` (desmarca el `ToggleButton "Lápiz"` del TopBar).

### 5.2 Bandas espectrales ($N$)
- **Control:** `Slider` para elegir la resolución de barras.
- **Rango y paso:** De **12 a 128 bandas**, con un paso exacto de **4** (`Minimum="12" Maximum="128" StepFrequency="4"`).
- **Muestreo visual:** Muestra dinámicamente el número actual de bandas ($N$) junto a la etiqueta del control.

### 5.3 Disposición (Layout)
- **Control:** Selector desplegable (`ComboBox`) para la orientación geométrica de las barras espectrales:
  - `Bottom-Up (Inferior)`: Crecimiento vertical de abajo hacia arriba.
  - `Top-Down (Superior)`: Crecimiento vertical de arriba hacia abajo.
  - `Center-Out / Espejo (Centro)`: Expansión simétrica desde el centro de la pantalla hacia los extremos superior e inferior.

### 5.4 Paleta de colores
- **Control:** Selector desplegable (`ComboBox`) para el modo de color del visualizador:
  - `Dinámico`: Asigna colores térmicos reactivos según la dinámica y frecuencia de la música.
  - `Paleta personalizada`: Habilita dos selectores de color (`ColorPicker` / `DropDownButton` con `Flyout`) para configurar:
    - **Color Primario:** Muestra un recuadro de vista previa (`Border`) y selector `ColorPicker`.
    - **Color Secundario:** Muestra un recuadro de vista previa (`Border`) y selector `ColorPicker`.

---

## 6. Pantalla 3 — Catálogo

Página `CatalogPage`, navegada desde "Catálogo" (TopBar). 🔶 Se recomienda añadir un botón "← Volver" (chevron-left, esquina superior izquierda del contenido) — no aparece explícito en el mockup pero es necesario para salir sin seleccionar nada.

### 6.1 Buscador y filtros
`Grid` 2 columnas, alto 44px, margen 20px:
- Col0 (`*`): `AutoSuggestBox` con `PlaceholderText="Buscar visualizadores..."`, icono lupa, fondo `ColorBgElevated`, `CornerRadius="8"`.
- Col1 (`Auto`, margen izq. 12px): `Button "Filtros"` (icono filtro + texto, `ToolbarPillButtonStyle`). Click → `Flyout`/`CommandBarFlyout` con categorías (🔶 el mockup solo muestra "Barras"; se generaliza a N categorías — Ondas, Círculos, Partículas, etc.), toggle "Solo favoritos", orden.

### 6.2 Grid de resultados
`ItemsRepeater` + `UniformGridLayout` (`MinItemWidth="184" MinItemHeight="120" MinRowSpacing="16" MinColumnSpacing="16" ItemsStretch="Fill"`) dentro de `ScrollViewer` vertical. Cada ítem = `PresetCard` (variante *Large*).

- Selección (tap en la tarjeta, no en la estrella) → `PresetService.SetActive(preset)` + `RootFrame.GoBack()` con `SlideNavigationTransitionInfo` inverso al de entrada → vuelve a `VisualizerPage` ya con el nuevo preset aplicado (coincide con el flujo que diagramaste: Catálogo → Seleccionar visualizador → Echo Visualizer).
- 🔶 Añadido por buena práctica: estado vacío para búsquedas sin resultados (mensaje + icono centrado, discreto).

---

## 7. Menú de Configuración Global (Icono Engrane / Panel Global)

Contiene los ajustes del sistema y control de entorno esenciales (sin opciones extra ni inventadas):

### 7.1 Encabezado
`TextBlock "Configuración Global"` (20px SemiBold), margen inferior 16px.

### 7.2 Dispositivo de audio
- **Control:** Selector desplegable (`ComboBox`) para elegir la fuente de captura/loopback activa del sistema.
- **Origen de datos:** Arreglo/lista de fuentes de captura activa (dispositivos WASAPI Loopback del sistema).
- **Comportamiento:** Permite cambiar dinámicamente la entrada de audio capturada sin reiniciar la aplicación.

### 7.3 Tema de interfaz
- **Control:** Selector desplegable (`ComboBox`) para controlar la apariencia visual global de la aplicación:
  - `Sistema`: Adopta el esquema de colores predeterminado del sistema operativo Windows.
  - `Claro`: Aplica el tema visual claro a toda la interfaz (`ElementTheme.Light`).
  - `Noche (Oscuro)`: Aplica el tema visual oscuro/noche a toda la interfaz (`ElementTheme.Dark`).

---

## 8. Pantalla Completa

- Trigger: botón "Pantalla Completa" del TopBar (🔶 + tecla `F11`, convención estándar de apps de medios en Windows).
- Implementación: `AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen)`.
- `TopBarOverlay` y la Fila A + tira de presets de `BottomOverlay` pasan a `Visibility="Collapsed"` (no solo opacidad 0, para liberar el espacio por completo). En su lugar aparece un único control flotante, anclado a la esquina inferior derecha:
  - `Button "HideInterfaceButton"`: pill oscuro Acrylic, padding `12,8`, `CornerRadius="8"`, contenido = `TextBlock "Ocultar interfaz (solo visualizador)"` (12px) + icono ojo-tachado (16px), margen 20px desde los bordes.
- Salir: mismo botón/estado "Pantalla Completa" otra vez, `Esc`, o `F11`. 🔶 `Esc` como salida rápida es convención estándar, no confirmada en el mockup.
- Este botón participa en la **misma** máquina de estados de overlay del resto de la app (sección 9) — con la particularidad de que en este modo el "overlay completo" se reduce únicamente a este botón (ver 9.4).

---

## 9. Splash Screen & Disclaimer Fotosensible de Inicio

Al iniciar la aplicación, se debe desplegar una pantalla/overlay de disclaimer de fotosensibilidad antes de permitir el uso de la aplicación.

### 9.1 Aspecto Visual
- **Disposición:** Panel centrado con fondo sobrio sobre la ventana principal.
- **Título principal:** `Advertencia` (centrado, tamaño amplio de tipografía).
- **Cuerpo del texto:** Párrafo centrado de advertencia indicando que la aplicación contiene luces parpadeantes, patrones visuales y cambios cromáticos reactivos a la música que pueden afectar a personas fotosensibles o con epilepsia.
- **Mensaje de espera inferior:** `TextBlock` centrado con el indicador de progreso:
  - `"Puedes continuar en 5 ..."` (donde el número decrementa cada segundo: 5, 4, 3, 2, 1).

### 9.2 Lógica de Ocultamiento Automático
- **Temporizador de 5 segundos:** Se ejecuta al inicializar `MainWindow` (`DispatcherTimer` con intervalo de 1 segundo).
- **Comportamiento:** Si el usuario no cierra ni sale de la aplicación durante los 5 segundos de espera, al llegar a 0 la pantalla de disclaimer se oculta automáticamente (`Visibility="Collapsed"`) y habilita el uso normal de la interfaz del visualizador.

---

## 10. Sistema de auto-ocultado del overlay

Este es el comportamiento que pediste especificar con más cuidado: hay que distinguir entre **ocultamiento manual** (pulsar el botón "ojo") y **ocultamiento por inactividad** (3 segundos sin tocar nada). Ambos coexisten así:

### 10.1 Los tres estados

| Estado | Qué se ve | Cómo se entra | Cómo se sale |
|---|---|---|---|
| **`Full`** (default) | TopBar + Fila A + tira de presets + botón "ojo" (icono abierto) | Estado inicial de la app / se recupera desde `IdleHidden` si era el estado previo / pulsar "ojo" desde `ManualCollapsed` | Pulsar "ojo" → `ManualCollapsed`. 3s sin actividad → `IdleHidden` |
| **`ManualCollapsed`** | Solo el botón "ojo" (icono ojo-tachado), todo lo demás oculto | Pulsar "ojo" estando en `Full` | Pulsar "ojo" otra vez → `Full`. 3s sin actividad → `IdleHidden` |
| **`IdleHidden`** | Nada visible, ni siquiera el botón "ojo" | 3s sin mover el mouse ni pulsar nada, desde `Full` o `ManualCollapsed` | Cualquier movimiento de mouse / click / tecla → regresa al estado que estaba activo antes de entrar aquí |

```
              pulsar "ojo"
        ┌──────────────────────┐
        │                      ▼
   ┌────┴─────┐          ┌───────────────────┐
   │   Full    │          │  ManualCollapsed   │
   │ (default) │          │ (solo botón "ojo") │
   └────┬──────┘          └─────────┬──────────┘
        │  pulsar "ojo" ▲           │
        └───────────────┘           │
        │                           │
        │ 3s sin actividad          │ 3s sin actividad
        ▼                           ▼
        └──────────►┌─────────────┐◄──────────┘
                     │ IdleHidden  │
                     │(nada visible)│
                     └──────┬──────┘
                            │ mover mouse / click / tecla
                            ▼
              vuelve al estado previo (Full o ManualCollapsed)
```

### 10.2 Temporizador de inactividad
`DispatcherQueueTimer` con `Interval = 3000ms`, reiniciado (`Stop()`+`Start()`) en cada evento de actividad: `PointerMoved`, `PointerPressed`, `PointerWheelChanged` y `KeyDown`, capturados a nivel de la **página raíz** (no solo en los botones — moverse sobre el propio canvas también debe contar). ⚠️ Para que `PointerMoved` se dispare sobre el `Grid`/canvas raíz en WinUI3, éste necesita `Background` explícito (aunque sea `Transparent`) — sin fondo, no participa del hit-testing de punteros.

```csharp
public sealed class OverlayVisibilityService
{
    public enum OverlayState { Full, ManualCollapsed, IdleHidden }

    public event EventHandler<OverlayState>? StateChanged;
    public OverlayState CurrentState { get; private set; } = OverlayState.Full;
    private OverlayState _stateBeforeIdle = OverlayState.Full;
    private readonly DispatcherQueueTimer _idleTimer;

    public OverlayVisibilityService(DispatcherQueue dispatcherQueue)
    {
        _idleTimer = dispatcherQueue.CreateTimer();
        _idleTimer.Interval = TimeSpan.FromMilliseconds(3000);
        _idleTimer.IsRepeating = false;
        _idleTimer.Tick += (_, _) => EnterIdleHidden();
        _idleTimer.Start();
    }

    // Llamar en PointerMoved / PointerPressed / PointerWheelChanged / KeyDown de la página raíz
    public void NotifyActivity()
    {
        if (CurrentState == OverlayState.IdleHidden)
            SetState(_stateBeforeIdle);

        _idleTimer.Stop();
        _idleTimer.Start();
    }

    // Llamar en el Click del botón "ojo"
    public void ToggleEyeButton()
    {
        if (CurrentState == OverlayState.IdleHidden) return; // no debería ser clickeable si es invisible
        SetState(CurrentState == OverlayState.Full
            ? OverlayState.ManualCollapsed
            : OverlayState.Full);
    }

    private void EnterIdleHidden()
    {
        if (CurrentState == OverlayState.IdleHidden) return;
        _stateBeforeIdle = CurrentState;
        SetState(OverlayState.IdleHidden);
    }

    private void SetState(OverlayState state)
    {
        CurrentState = state;
        StateChanged?.Invoke(this, state);
    }
}
```

### 10.3 Enlace a la UI (`VisualStateManager`)
Mapea los 3 estados a un `VisualStateGroup` en `VisualizerPage.xaml`, con `Storyboard` de fundido (200ms `EaseOut` al mostrar / `EaseIn` al ocultar) en vez de `Setters` instantáneos, y desactiva el hit-testing de lo oculto (`IsHitTestVisible="False"` — importante también para que el foco de teclado no "aterrice" en controles invisibles):

```xml
<VisualStateManager.VisualStateGroups>
  <VisualStateGroup x:Name="OverlayStates">
    <VisualState x:Name="Full" />

    <VisualState x:Name="ManualCollapsed">
      <Storyboard>
        <DoubleAnimation Storyboard.TargetName="TopBarOverlay"
                          Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2" />
        <DoubleAnimation Storyboard.TargetName="PresetStripRow"
                          Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2" />
      </Storyboard>
      <VisualState.Setters>
        <Setter Target="TopBarOverlay.IsHitTestVisible" Value="False" />
        <Setter Target="PresetStripRow.IsHitTestVisible" Value="False" />
      </VisualState.Setters>
    </VisualState>

    <VisualState x:Name="IdleHidden">
      <Storyboard>
        <DoubleAnimation Storyboard.TargetName="TopBarOverlay"
                          Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2" />
        <DoubleAnimation Storyboard.TargetName="PresetStripRow"
                          Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2" />
        <DoubleAnimation Storyboard.TargetName="EyeButton"
                          Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2" />
      </Storyboard>
      <VisualState.Setters>
        <Setter Target="OverlayRootGrid.IsHitTestVisible" Value="False" />
      </VisualState.Setters>
    </VisualState>
  </VisualStateGroup>
</VisualStateManager.VisualStateGroups>
```

Alternativa más moderna y con menos XAML: `CommunityToolkit.WinUI.Animations` → `AnimationBuilder.Create().Opacity(to: 0, duration: TimeSpan.FromMilliseconds(200)).Translation(...).Start(elemento)`, que además permite sumar un leve desplazamiento vertical (~8px) al aparecer/desaparecer para más naturalidad.

### 10.4 Caso especial: Pantalla Completa
En este modo, "todo lo demás" (TopBar + tira de presets) ya está `Collapsed` de forma permanente (sección 8) — el overlay de Pantalla Completa consiste únicamente en el botón "Ocultar interfaz". Por lo tanto `Full` y `ManualCollapsed` **coinciden visualmente** en este modo (ambos = "se ve el botón"), y pulsar el botón lleva directo al equivalente de `IdleHidden` (nada visible) — que es justo lo que promete su propia etiqueta, "solo visualizador". Para lograrlo sin duplicar la máquina de estados: cuando `IsFullScreen == true`, vincula también la opacidad del propio `EyeButton`/`HideInterfaceButton` al estado `ManualCollapsed` (además de `IdleHidden`), a diferencia del modo ventana donde el "ojo" permanece visible en `ManualCollapsed`.

### 10.5 Opcional: ocultar el cursor del sistema
🔶 No confirmado en el mockup, pero coherente con "solo visualizador": ocultar también el cursor del mouse durante `IdleHidden` y restaurarlo en `NotifyActivity()`. Común en reproductores multimedia (VLC, YouTube fullscreen, etc.).

---

## 11. Guía de animaciones

| Elemento | Propiedad | Duración | Easing | Notas |
|---|---|---|---|---|
| Overlay mostrar/ocultar | `Opacity` | 200ms | `CubicEase` (Out al mostrar / In al ocultar) | |
| Sidebar (`SplitView.Pane`) | Translation X + Opacity | 300ms (default) | `EaseInOut` | usar el comportamiento nativo de `SplitView` |
| Hover botón/tarjeta | `Background` + escala 1→1.02 | 150ms | `EaseOut` | `VisualState` estándar + Composition scale |
| Press de botón | escala 1→0.96→1 | 100ms | `EaseOut` | detalle de pulido opcional |
| Selección de `PresetCard` | color de borde + glow | 150ms | `EaseOut` | |
| Toggle de estrella | escala 1→1.3→1 | 250ms | `BackEase` | "pop" al marcar favorito |
| Navegación entre páginas | slide + fade | ~250ms | — | `SlideNavigationTransitionInfo` |
| Barras del visualizador | `Height` | ataque ~50ms / liberación ~250–300ms | Linear/`CubicOut` | ver 4.2 |

---

## 12. Flujo de navegación consolidado

| Desde | Acción | Hacia |
|---|---|---|
| (Inicio de la app) | — | Splash Screen Disclaimer Fotosensible (5 segundos de espera) |
| Splash Disclaimer | Fin de 5s (o navegación activa) | Echo Visualizer (Pantalla 1), overlay en `Full` |
| Echo Visualizer | click "Lápiz" | Se abre el sidebar Ajustes RS-EB (Menú Lápiz) — misma página |
| Ajustes RS-EB | click "X" o "Lápiz" de nuevo | Se cierra el sidebar, vuelve a Pantalla 1 |
| Echo Visualizer | click "Catálogo" | Navega a Catálogo (Pantalla 3) |
| Catálogo | click en una tarjeta (no la estrella) | Aplica el preset y **vuelve** a Echo Visualizer (Pantalla 1) |
| Catálogo | click "← Volver" 🔶 | Vuelve a Echo Visualizer sin cambiar el preset |
| Echo Visualizer | click "Engrane" / "Configuración" | Se abre el panel Configuración Global (Menú Engrane) |
| Echo Visualizer | click "Pantalla Completa" | Entra a Pantalla Completa |
| Pantalla Completa | click en "Ocultar interfaz" (si visible) / `Esc` / `F11` | Sale de Pantalla Completa, vuelve a ventana normal |
| Cualquier pantalla con overlay, `Full`/`ManualCollapsed` | 3s sin actividad | Overlay → `IdleHidden` |
| ... `IdleHidden` | mover el mouse (o click/tecla) | Overlay vuelve a su estado previo |
| Echo Visualizer / Pantalla Completa, overlay `Full` | click botón "ojo" | Overlay → `ManualCollapsed` |
| ... `ManualCollapsed` | click botón "ojo" | Overlay → `Full` |

---

## 13. Tabla maestra de componentes WinUI3

| Elemento del diseño | Control WinUI3 recomendado |
|---|---|
| Ventana + barra de título custom | `Window` + `ExtendsContentIntoTitleBar` + `AppWindowTitleBar` |
| Botones Lápiz / Catálogo / Engrane / Pantalla Completa | `ToggleButton` (Lápiz) / `Button` (resto), estilo pill compartido |
| **Splash Screen Disclaimer Fotosensible** | `Grid` overlay + `TextBlock` Advertencia + `DispatcherTimer` (5s auto-hide) |
| **RS-EB: Bandas espectrales ($N$)** | `Slider` (`Minimum="12" Maximum="128" StepFrequency="4"`) |
| **RS-EB: Disposición (Layout)** | `ComboBox` (Bottom-Up, Top-Down, Center-Out) |
| **RS-EB: Paleta de colores** | `ComboBox` (Dinámico / Personalizada) + 2 `ColorPicker` con preview |
| **Global: Dispositivo de audio** | `ComboBox` (Dispositivos WASAPI Loopback activos) |
| **Global: Tema de interfaz** | `ComboBox` (Sistema, Claro, Noche) |
| Sidebar Ajustes RS-EB | `SplitView` (`PaneDisplayMode="Inline"`) |
| Tarjetas de preset (tira y catálogo) | `UserControl PresetCard` reutilizable |
| Tira horizontal de presets | `ItemsRepeater`/`ListView` horizontal + `ScrollViewer` |
| Botón "ojo" | `ToggleButton` circular + `OverlayVisibilityService` |
| Buscador del Catálogo | `AutoSuggestBox` |
| Botón "Filtros" | `Button` + `Flyout`/`CommandBarFlyout` |
| Grid del Catálogo | `ItemsRepeater` + `UniformGridLayout` |
| Render del visualizador | `CanvasAnimatedControl` (Win2D) o `SpriteVisual`s (Composition) |
| Fundidos de overlay | `Storyboard`/`DoubleAnimation` o `AnimationBuilder` |
| Transiciones entre páginas | `SlideNavigationTransitionInfo` en `Frame.Navigate` |
| Pantalla Completa | `AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen)` |

---

## 14. Accesibilidad y responsividad

- `AutomationProperties.Name` en **todo** botón icon-only (ojo, estrella, X de cierre, filtros, view-toggle) — sin esto son invisibles para lectores de pantalla.
- No remover el rectángulo de foco por defecto de WinUI3 (`FocusVisualPrimaryBrush`); es clave para navegación por teclado.
- Elementos ocultos por el overlay (`ManualCollapsed`/`IdleHidden`) deben quedar fuera del orden de tabulación (`IsTabStop="False"` además de `IsHitTestVisible="False"`).
- Respetar el ajuste del sistema "Mostrar animaciones" (`Windows.UI.ViewManagement` / configuración de accesibilidad de Windows).
- Breakpoints de responsividad: ver sección 1.7.

---

## 15. Notas

1. Los iconos de "vista de lista/cuadrícula" (Fila A del overlay inferior) no tienen función actual.
2. "Modo aleatorio continuo" no tiene función actual.
3. El botón "← Volver" en Catálogo y Configuración se añade por necesidad de navegación; no aparece explícito en el mockup.
4. Categorías del Catálogo más allá de "Barras" están inferidas para generalizar el diseño. No codificar las categorías "Ondas, Círculos, Partículas..."
5. **Configuraciones especificadas:** Los paneles de Ajustes RS-EB (Icono Lápiz) y Configuración Global (Icono Engrane) contienen estrictamente los parámetros definidos por especificación (Bandas espectrales 12-128 paso 4, Layout, Paleta dinámico/personalizado, Dispositivo de audio WASAPI Loopback y Tema de interfaz); se omiten controles mock o inventados.
6. **Splash Disclaimer Fotosensible:** Se incluye el aviso inicial de sensibilidad fotosensible de 5 segundos con ocultado automático al cumplir el tiempo si el usuario no sale de la aplicación.
7. La micro-animación ambiental sin audio activo es una mejora sugerida.
8. Ocultar el cursor del sistema durante `IdleHidden` es una mejora opcional.
9. `Esc`/`F11` para Pantalla Completa son convenciones estándar añadidas.
10. La paleta de color son valores aproximados leídos visualmente, no extraídos por pixel-picker.
11. El comportamiento de `ManualCollapsed` en Pantalla Completa (el "ojo" se oculta a sí mismo al hacer click) es una interpretación para "solo visualizador" — ver sección 10.4.
