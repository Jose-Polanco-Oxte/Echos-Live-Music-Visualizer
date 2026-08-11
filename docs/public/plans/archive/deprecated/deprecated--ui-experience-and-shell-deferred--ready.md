# Estado de Preparación: Shell UI y Experiencia del Visualizador (`ui-experience-and-shell-deferred`)

- **Estado:** Plan Aprobado y Consolidado. Listo para ejecución por agentes UI/Shell.
- **Plan Principal:** `ui-experience-and-shell-deferred.md`
- **Alineación Normativa:** Sección IV, RF6.1.3, RF6.1.4, RF6.2.4, RF6.3.1–RF6.3.7, RF6.5.1–RF6.5.3, RF6.6.1–RF6.6.2, RF6.7.1–RF6.7.3, RF6.8.1–RF6.8.2, RF-EQ.3.

---

## Resumen del Trabajo Planificado

1. **Agente A (Shell Inmersivo & Overlay Flotante):**
   - Viewport 100% RS-EB.
   - Overlay superpuesto con botones (catálogo, lápiz, engrane) y carrusel inferior.
   - Ocultamiento automático tras 4 segundos de inactividad de puntero/teclado.
   - Suspensión del temporizador durante foco o interacción en controles interactivos.

2. **Agente B (Catálogo, Favoritos y Configuración Contextual RS-EB):**
   - Selector del catálogo con ficha RS-EB y filtro "Sólo favoritos".
   - Marcador de estrella de favoritos en el carrusel. Botón informativo "Modo aleatorio".
   - Panel de lápiz exclusivo para RS-EB (bandas, escala, layout, espaciado, radio, peak hold, glow, reflejo y paleta).
   - Panel de engrane para ajustes globales (dispositivo de audio, tema, presets).

3. **Agente C (Disclaimer, Dispositivos y Temas):**
   - Aviso fotosensible de 5 segundos de avance automático sin botón "Aceptar".
   - Eliminación del rótulo literal "Fuente de audio" por "Dispositivo de audio".
   - Temas Noche, Claro y Sistema con persistencia.

4. **Agente D (Especificación, Trazabilidad y QA):**
   - Creación de registros de trazabilidad `REQ-TRACE` para el conjunto UI/Shell.
   - Suite de pruebas de regresión y matriz de aceptación manual.

---

## Estado de Actividades

- [x] Auditoría de requisitos e inconsistencias completada.
- [x] Actualización de la especificación y plan para ordenar la **eliminación total de código obsoleto** (`mesh3d`, `pulse`, `mirror`).
- [ ] Eliminar archivos de código obsoletos (`D3D11SpectralMeshVisualizer.cs`, `SpectralMesh3DMath.cs`, shaders 3D) y remover sus entradas en `VisualizerRegistry.cs`.
- [ ] Ejecución del Agente A (Overlay e inmersión sobre RS-EB).
- [ ] Ejecución del Agente B (Catálogo, Favoritos y Paneles Contextuales).
- [ ] Ejecución del Agente C (Disclaimer 5s, selector de dispositivo y temas).
- [ ] Registro de trazabilidad y verificación automatizada/manual.
