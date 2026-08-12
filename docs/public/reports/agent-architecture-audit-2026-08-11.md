# Informe de auditoría y saneamiento de la arquitectura agéntica

**Fecha:** 2026-08-11  
**Rama:** `docs/agent-architecture-audit`  
**Alcance:** `.agents/`, documentación pública de arquitectura/especificación,
scripts de validación y launcher de subagentes.  
**Fuera de alcance:** código de producto Rust, C#, XAML, DSP, FFI, WASAPI,
Win2D y renderizado.

## Resumen ejecutivo

La arquitectura agéntica tenía un problema funcional y varios contratos
desactualizados. El bootstrap dependía de un árbol `.agents/` globalmente
ignorado, el launcher confundía el root `AGENTS.md` con una definición de
agente, el catálogo vacío podía interpretarse como bloqueo y el quality gate
referenciaba un script inexistente. También había rutas históricas de skills,
release, contexto de renderizado, stack research y trazabilidad.

El saneamiento implementa un catálogo de roles opcional y explícito: el modelo
puede seleccionar cero, uno o varios roles; si ninguno cubre la tarea puede
declarar un rol ad hoc dentro del contexto de esa ejecución. No existe fallback
automático a `general-project-engineer`, y la ausencia de roles no impide una
ejecución genérica. Se añadieron seis roles candidatos permanentes y se
validaron las rutas críticas sin modificar la arquitectura del producto.

## Método y evidencia

Se compararon los archivos de bootstrap, reglas, skills, roles y scripts contra
el árbol real del repositorio; se inspeccionaron los manifiestos Rust/.NET y la
implementación activa de WinUI/Win2D; se ejecutaron validaciones PowerShell y
Python; y se revisó el diff para excluir `src/` y `tests/` de la mutación.

## Hallazgos y correcciones

| ID | Hallazgo | Corrección | Estado |
| --- | --- | --- | --- |
| A-01 | `.agents/` estaba globalmente ignorado aunque el bootstrap lo requiere. | Política de visibilidad mixta: contratos estables versionables y estado local ignorado, con template público de handoff. | Corregido |
| A-02 | El root nombraba `Build-Distribution.ps1`; el script real es plural. | Referencia corregida a `scripts/Build-Distributions.ps1`. | Corregido |
| A-03 | `general.md` apuntaba a `subagent-work-divider`, que no existe. | Router reescrito con el catálogo real y skills condicionales. | Corregido |
| A-04 | El launcher y el loader podían descubrir el root `AGENTS.md` como agente. | El catálogo permanente se resuelve en `.agents/roles/`; `AGENTS.md` no es rol. | Corregido |
| A-05 | La selección de roles no distinguía cero, uno, varios y ad hoc. | `run_subagent.py` acepta `--agent` repetible, permite cero roles y compone descriptores compatibles. | Corregido |
| A-06 | El quality gate llamaba `Test-Toolchains.ps1`, ausente y calculaba mal la raíz del repositorio. | Script determinista añadido; el gate ahora resuelve la raíz correcta y valida SDK, Cargo y manifests. | Corregido |
| A-07 | Skills de decisiones, issues, incidentes, CI/CD, scripting y .NET contenían rutas o validadores inexistentes. | Rutas y comandos alineados con el repositorio actual; se eliminó la dependencia de validadores inexistentes. | Corregido |
| A-08 | Contexto de UI indicaba `CompositionTarget.Rendering` y `Win2DSpectralBarVisualizer`. | Contexto alineado con `Win2DGpuSpectralBarVisualizer`, `CanvasControl.Draw` y `DispatcherTimer`. | Corregido |
| A-09 | Stack research describía `cpal`, Win2D UWP, versiones antiguas y Native AOT como si fueran activas. | Investigación reescrita desde `rust-toolchain.toml`, `Cargo.toml`, `global.json` y `EchoVisualizer.csproj`. | Corregido |
| A-10 | `requirements-spec.md` mezclaba comportamiento actual con historial de remociones. | RF6.4 y RF-EQ.5 expresan estado actual; las candidaturas de limpieza quedan en este informe. | Corregido |
| A-11 | El checkout no contiene `build/Product.props`, requisito importado por `src/ui/EchoVisualizer.csproj`; el gate completo no puede compilar la UI. | El quality gate falla ahora con un mensaje explícito y no inventa metadata de producto dentro de esta tarea. | Bloqueo preexistente |

## Contrato operativo de roles

La decisión de roles es parte del contexto de delegación:

1. **Cero roles:** tarea autocontenida o sin especialización adicional.
2. **Un rol:** una especialización cubre la tarea.
3. **Varios roles:** las especializaciones son compatibles y aportan
   perspectivas distintas; se componen en el orden seleccionado.
4. **Rol ad hoc:** no existe una definición adecuada; se declara inline con
   objetivo, contexto, límites y formato de salida.

Las instrucciones del usuario, `general.md` y las políticas del proyecto
prevalecen. Una combinación con conflicto material de CLI, modelo, esfuerzo o
alcance debe fallar con un mensaje claro o replantearse; no se resuelve con un
fallback silencioso. Al combinar permisos se conserva el nivel más restrictivo.

## Catálogo permanente incorporado

- `general-project-engineer`: trabajo general; opción explícita, no fallback.
- `agent-architecture-auditor`: bootstrap, reglas, skills, roles y scripts.
- `rust-dsp-specialist`: Rust DSP, WASAPI, FFI y pruebas del core.
- `winui-visualizer-specialist`: WinUI 3, Win2D, visualizador y UI testing.
- `requirements-traceability-maintainer`: requisitos, fórmulas y trazabilidad.
- `quality-gate-validator`: PowerShell, Rust, .NET y documentación.

Cada descriptor delimita contexto requerido, skills permitidas, permisos,
formato de salida y la prohibición de alterar la arquitectura de producto fuera
del plan autorizado.

## Registro de referencias históricas o candidatas

| Referencia | Clasificación | Acción |
| --- | --- | --- |
| Trazas antiguas que nombran `Win2DSpectralBarVisualizer`, `D3D11SpectralMeshVisualizer` o `VisualizerTransitionState` | Evidencia histórica en `docs/public/traceability/` y planes archivados | Conservar como histórico; no usar como contrato actual. Revisar en una tarea documental separada si se requiere consolidación. |
| Propiedades internas de `Win2DGpuSpectralBarVisualizer` para gap, esquinas, peak hold, bloom y reflection | Candidatos de revisión del renderer actual; no todos son controles UI ni están cubiertos por RF-EQ.5 | No eliminar en esta auditoría. Confirmar intención y cobertura antes de cambiar producto. |
| Dependencias Vortice presentes en el proyecto | Dependencias declaradas, pero no evidencia de que sean el renderer activo de RS-EB | Mantener; documentar como stack disponible/evaluado, no como ruta activa. |
| Rutas `docs/pending-features`, `docs/traceability` y typo `PROYECT-HANDOFF` | Referencias obsoletas en documentos históricos o reglas antiguas | Corregir contratos activos; no reescribir archivos `deprecated--` salvo una migración histórica explícita. |

## Riesgos y límites

- La validación de sintaxis y tests no sustituye una sesión física de WASAPI,
  GPU, pérdida de dispositivo o endurance.
- El quality gate completo queda condicionado a recuperar `build/Product.props`,
  que no está presente en el checkout auditado. Rust y las pruebas .NET
  independientes sí se ejecutaron correctamente.
- La presencia de Vortice no prueba uso en runtime; el análisis se basa en el
  código actualmente conectado a `VisualizerPage`.
- Los documentos históricos conservan valor forense, pero no deben entrar en el
  contexto activo salvo que la tarea sea precisamente su auditoría.
- Los roles son especializaciones operativas, no una nueva capa de arquitectura
  del producto.

## Recomendaciones

1. Usar el protocolo de selección de roles en cada delegación y registrar la
   decisión en el prompt o handoff de la tarea.
2. Tratar `docs/public/spec/requirements-spec.md` como estado vigente y los
   informes/archivos archivados como evidencia histórica.
3. Crear una tarea independiente si se decide eliminar las propiedades internas
   de renderizado aún presentes; esa decisión requiere pruebas y revisión de
   comportamiento observable.
4. Repetir `Test-AgentArchitecture.ps1` y el quality gate cuando se agreguen
   roles, skills o scripts.

## Conclusión

La arquitectura agéntica queda coherente con el comportamiento solicitado:
roles opcionales, selección explícita por el modelo, composición segura,
fallback genérico inexistente y soporte de roles ad hoc. El saneamiento queda
confinado al control operativo y documental, y no introduce cambios en la
arquitectura técnica del visualizador.
