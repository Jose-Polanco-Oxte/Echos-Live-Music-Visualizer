# Reporte de trazabilidad: auditoría de arquitectura agéntica

**Fuente normativa principal:** `docs/public/spec/requirements-spec.md`  
**Fuente operativa:** `.agents/AGENTS.md`, `.agents/rules/general.md`,
`.agents/skills/` y `.agents/roles/`  
**Fecha:** 2026-08-11

## Matriz de cambios y evidencia

| ID | Requisito/contrato | Implementación o documento | Verificación | Resultado |
| --- | --- | --- | --- | --- |
| TR-01 | El bootstrap debe activar un árbol estable y no depender de estado privado. | `AGENTS.md`, `.agents/AGENTS.md`, `.gitignore`, `.agents/state/PROJECT-HANDOFF.template.md` | Revisión de rutas y `Test-AgentArchitecture.ps1` | Cumplido |
| TR-02 | Las skills obligatorias deben existir y seguir sus triggers reales. | `.agents/rules/general.md`, `.agents/skills/using-agent-skills/SKILL.md` | Auditoría de catálogo y referencias activas | Cumplido |
| TR-03 | El launcher debe aceptar cero roles sin bloquear la ejecución genérica. | `run_subagent.py`, `_loader.py`, `sub-agents-execution/SKILL.md` | Composición de cero roles; invocación interna sin overlay | Cumplido |
| TR-04 | El modelo puede seleccionar un rol o componer varios compatibles. | `run_subagent.py`, seis descriptors en `.agents/roles/` | Composición simple y múltiple; permiso efectivo más restrictivo | Cumplido |
| TR-05 | Un rol explícito inexistente debe producir un error claro. | `_loader.py`, `run_subagent.py` | Ejecución con `--agent does-not-exist`; salida JSON de error y código 1 | Cumplido |
| TR-06 | Un rol ad hoc no necesita archivo permanente. | `.agents/rules/general.md`, `sub-agents-execution/SKILL.md` | Prueba de contexto inline en la ruta de composición | Cumplido |
| TR-07 | La especificación debe representar estado actual, no remociones históricas. | `requirements-spec.md` RF6.4, RF-EQ.5 | Revisión de diff y escaneo de lenguaje de remoción | Cumplido para el alcance auditado |
| TR-08 | El contexto y stack research deben coincidir con el código actual. | `.agents/context/architecture.md`, `.agents/context/conventions.md`, `stack-tech-research.md` | Comparación con `Cargo.toml`, `rust-toolchain.toml`, `global.json`, `.csproj` y `VisualizerPage` | Cumplido |
| TR-09 | Los scripts documentados deben ser ejecutables o fallar claramente. | `Test-Toolchains.ps1`, `Test-AgentArchitecture.ps1`, `Invoke-QualityGate.ps1` | Parseo PowerShell, toolchain check y arquitectura check; el gate completo informa explícitamente la ausencia de `build/Product.props` | Cumplido con bloqueo preexistente |
| TR-10 | No se modifica la arquitectura del producto. | Diff de rama | Ningún archivo bajo `src/` o `tests/` modificado | Cumplido |

## Desviaciones y notas

- Los archivos históricos bajo `docs/public/plans/archive/` y trazas previas se
  conservan para no destruir evidencia. Sus rutas o nombres antiguos no son
  contratos activos.
- El quality gate completo y las pruebas del producto son evidencia separada de
  la validación estática. Rust y las pruebas .NET independientes pasan; el
  build UI queda bloqueado por la ausencia preexistente de `build/Product.props`.
- Las propiedades internas adicionales del renderer se registran como revisión
  futura, no como eliminación realizada por este cambio.

## Criterio de cierre

La trazabilidad se considera cerrada cuando las validaciones finales del plan
confirman los contratos TR-01 a TR-10, el diff permanece fuera del producto y el
plan se archiva en `docs/public/plans/archive/completed/2026/08/`.
