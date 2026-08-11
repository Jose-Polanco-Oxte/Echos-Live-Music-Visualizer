# Plan de feature: Shell UI y experiencia del visualizador

## Propósito

Implementar los cambios de interfaz y experiencia solicitados.

## Alcance normativo

Requisitos relacionados:

- RF6.1.3: disclaimer fotosensible.
- RF6.2.1–RF6.2.3 y RF6.2.4: captura, selección de dispositivo y eliminación
  del rótulo literal “Fuente de audio”.
- RF6.3.1–RF6.3.7: catálogo, favoritos, overlay, carrusel y auto-ocultamiento.
- RF6.5.1–RF6.5.3: pantalla completa y restauración de controles.
- RF6.6.1–RF6.6.2: temas.
- RF6.7.1–RF6.7.3: configuración contextual del efecto activo.
- RF6.8.1–RF6.8.2: configuración global.

La versión actual sólo ejecuta RS-EB (Ecualizador de Barras Espectral). Conforme a
la Sección IV de la especificación, los efectos obsoletos `mirror`, `pulse` y `mesh3d` se
**ELIMINAN TOTALMENTE** de la base de código. Durante la ejecución de este plan se deben
borrar los archivos de visualizadores retirados (`D3D11SpectralMeshVisualizer.cs`, `SpectralMesh3DMath.cs`),
shaders 3D y remover sus registros en `VisualizerRegistry.cs` para mantener la arquitectura simple.

## Fuera de alcance

- Implementar el panel de configuración de lista aleatoria. Sólo se mostrará
  el botón informativo “Modo aleatorio”.
- Crear nuevos renderizadores o mantener código legacy/obsoleto de Malla 3D.

## Estado inicial que debe preservarse

- El último visualizador seleccionado se restaura al iniciar.
- El selector de dispositivo permanece disponible en configuración global.
- El texto “Fuente de audio” se elimina como leyenda/rótulo, no el selector.
- El disclaimer fotosensible permanece visible cinco segundos y se considera
  leído automáticamente al cumplirse el tiempo; no tendrá botón Aceptar.
- La configuración global no debe mezclarse con los parámetros del render.

## División de trabajo

### Agente A — shell inmersiva y overlay

Propiedad: `src/ui/MainWindow.xaml`, `MainWindow.xaml.cs`, ViewModels y estilos.

Entregables:

1. Convertir la vista principal en un viewport dominado por RS-EB.
2. Crear overlay con:
   - catálogo;
   - lápiz para ajustes del visual activo;
   - engrane para ajustes globales;
   - carrusel inferior horizontal.
3. Mostrar overlay al mover el puntero, pulsar una tecla o interactuar.
4. Ocultarlo después de cuatro segundos sin interacción.
5. Suspender el temporizador mientras un ComboBox, panel o selector tenga foco,
   esté bajo el puntero o reciba teclado. En especial, el selector de
   dispositivo nunca debe desaparecer durante la selección.
6. Mantener la restauración del último visualizador.

### Agente B — catálogo, favoritos y configuración contextual

Propiedad: ViewModels, catálogo, presets y paneles específicos.

Entregables:

1. El icono de catálogo abre una vista/selector con fichas.
2. El selector permite filtro “Sólo favoritos”.
3. El carrusel muestra una estrella para marcar/desmarcar favoritos.
4. El botón “Modo aleatorio” sólo comunica la función futura y no abre una
   configuración incompleta.
5. El lápiz abre exclusivamente ajustes de RS-EB: bandas, escala, disposición,
   separación, radio, peak hold, glow, reflexión y paleta.
6. El engrane abre sólo ajustes globales: fuente/dispositivo, tema y presets.
7. Persistir por separado ajustes del efecto y configuración global.

### Agente C — disclaimer, dispositivos y temas

Propiedad: startup, servicios globales y recursos de tema.

Entregables:

1. Eliminar el aviso interno de permisos de audio.
2. Mantener el disclaimer fotosensible durante cinco segundos, sin botón de
   aceptación.
3. Implementar Sistema, Claro y Noche con persistencia.
4. Verificar que el cambio de tema no modifica el estado del render.
5. Reorganizar el menu de la barra de tareas.

### Agente D — especificación y QA

Propiedad: `docs/spec/**`, trazas y procedimientos de aceptación.

Entregables:

1. Revisar que RF6.2.4, RF6.3.5–RF6.3.7, RF6.4.3, RF6.7 y RF6.8 coincidan
   exactamente con la implementación.
2. Crear trazas UI independientes para overlay, catálogo, configuración,
   disclaimer, dispositivos y temas.
3. Definir pruebas manuales de experiencia y regresión.

## Secuencia de integración

1. Agente A implementa overlay y ciclo de ocultamiento.
2. Agentes B y C implementan paneles, persistencia, disclaimer, dispositivos y
   temas sobre el contrato aprobado.
3. Integración principal elimina rutas duplicadas y conecta el overlay al único
   visualizador RS-EB.
4. Ejecutar pruebas unitarias, build Release x64, MSIX con versión nueva y
   smoke instalado.
5. Ejecutar aceptación manual de UX y registrar incidencias sin mezclar cambios
   al Core.

## Pruebas automatizadas

- Overlay: aparece con interacción, se oculta a los 4 s y no se oculta con un
  selector enfocado.
- Catálogo: lista RS-EB, favoritos y filtro.
- Carrusel: cambia selección sin duplicar instancias ni parpadear.
- Configuración: lápiz sólo muestra controles RS-EB; engrane sólo global.
- Persistencia: último visual, favoritos, tema y presets se restauran.
- Disclaimer: ausencia de botón y habilitación después de 5 s.
- Dispositivos: selector conserva foco y la fuente activa.
- Paleta: colores personalizados se editan, guardan y se reflejan en RS-EB.
- Regresión Core: los vectores y metadatos recibidos no cambian por la UI.

## Aceptación manual

1. Abrir la aplicación y confirmar que aparece el último RS-EB seleccionado.
2. Mover el ratón: aparece el overlay; dejarlo quieto cuatro segundos:
   desaparece sin afectar el visual.
3. Abrir el selector de dispositivo, mantener el puntero dos segundos y
   confirmar que permanece abierto.
4. Abrir lápiz y comprobar que no aparecen controles globales.
5. Abrir engrane y comprobar que no aparecen controles de RS-EB.
6. Abrir catálogo, activar favoritos y verificar el filtrado.
7. Confirmar que “Modo aleatorio” sólo es informativo.
8. Cambiar paleta personalizada, guardar preset, reiniciar y restaurar.
9. Esperar cinco segundos en disclaimer fotosensible sin pulsar Aceptar.
10. Repetir en Sistema, Claro y Noche.

## Criterio de finalización

El feature sólo se considera completo cuando los requisitos UI anteriores
tienen trazas, pruebas automatizadas y aceptación manual documentada. El
diagnóstico LUFS/gamma se considera completo sólo al entregar una conclusión
reproducible; no autoriza por sí mismo modificar el Core.
