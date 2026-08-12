# Plan: Correcciones posteriores a la auditoría del release CD

## Current State Snapshot

- **Plan ID:** `PLAN-20260811-RELEASE-CD-POST-AUDIT-FIXES`
- **Status:** `COMPLETED`
- **Verification state:** `VERIFIED` (implementación, regresiones y quality gate comprobados)
- **Created / updated:** 2026-08-11
- **Planning branch:** `dev@91eebe9`.
- **Execution baseline:** `ci/release-cd-hardening@28055b6`, descendiente de `91eebe9`, contiene la implementación que debe corregirse.
- **Working tree:** implementación del follow-up; conserva la eliminación preexistente de `attachments/Quiero que investigu.txt` y los cambios de authoring del plan/INDEX.
- **Active milestone / step:** M5 / Step 5 — cierre done.
- **Completed steps:** 5 / 5
- **Last checkpoint:** `CP-004`
- **Next action:** integración en `dev`/push y gates live de Partner Center (externos, operator-gated).
- **Blockers:** ninguno offline; Partner Center, secrets del Environment y primera submission son gates externos.
- **Related plan:** `PLAN-20260811-RELEASE-CD-HARDENING`, archivado en `docs/public/plans/archive/completed/2026/08/2026-08-11--microsoft-store-release-cd-hardening.md`.
- **Supersedes / superseded by:** — / —

## Objective

Corregir los cuatro defectos de seguridad detectados en la auditoría posterior
del release CD:

1. Una release existente solo puede ser `no-op` cuando su commit coincide con
   el SHA real resuelto del tag.
2. `Published` sin `LatestPublishedVersion` válido nunca puede autorizar
   `upload`.
3. `PendingCommit` requiere versión, bundle, PFN y SHA-256 presentes y exactos.
4. `publish --noCommit` debe volver a validar la correlación completa antes de
   `commit`.

El resultado debe demostrarse offline con fixtures y seams, sin cambiar la
versión ni ejecutar operaciones live de Partner Center.

## Context and Evidence

La auditoría se ejecutó sobre `ci/release-cd-hardening@28055b6`. Los gates
generales ya pasan: `Test-ReleaseHardening.ps1`,
`Test-StoreReleasePipeline.ps1`, parser PowerShell, configuración, branding,
`actionlint`, Rust (77 pruebas), .NET (40 pruebas) y `git diff --check`.

Los defectos reproducidos fueron:

- `scripts/modules/Echo.GitHubRelease.psm1`,
  `Test-EchoGitHubReleaseCompatibility`, declara `ExpectedCommitSha` pero no lo
  compara antes de devolver `no-op` (líneas 181–223 auditadas).
- `scripts/modules/Echo.StoreSubmission.psm1`, líneas 380–388, trata
  `Published` como `NoSubmission` cuando falta la versión y devuelve `upload`.
- El bloque `PendingCommit`, líneas 390–404, compara campos solo si ambos están
  presentes y devuelve `commit-resume` con datos remotos ausentes.
- `scripts/Invoke-MicrosoftStoreRelease.ps1`, líneas 164–169, solo comprueba
  `verify.State -eq 'PendingCommit'` antes de llamar a `commit`.
- `release-conflicted-commit.json` también cambiaba el tamaño del bundle, por
  lo que no aislaba el conflicto de commit.

## Repository Baseline

- `dev`: `91eebe97ae03bf168703f1b89ea78d1e0489b620`.
- `origin/dev`: `6a1ed449e5096c47c77167d54477b8d472f5b2f2`.
- Prior hardening branch: `ci/release-cd-hardening@28055b68c9cee4139ffe43634dd183749f15610f`.
- No active plan existed before authoring.
- La ejecución debe comprobar que `28055b6` es ancestro o que existe un
  equivalente reconciliado con `.agents/`, workflows y módulos. Si cambió
  package type, identidad, PFN, arquitecturas, D5 o contrato de workflows, debe
  entrar en `REPLANNING` antes de editar.

## Requirements

### R1 — Baseline reconciliado

La implementación empieza desde `28055b6` o un equivalente documentado, no
desde `dev@91eebe9` aislado.

### R2 — Commit provenance obligatorio

`Test-EchoGitHubReleaseCompatibility` valida `ExpectedCommitSha` como SHA
lowercase de 40 caracteres y lo compara con `ReleaseInfo.target_commitish`.
Ausencia, branch, formato inválido o mismatch devuelve `fail-closed`, nunca
`no-op`. El draft creation payload guarda el SHA resuelto como
`target_commitish`. `store-publish.yml` conserva la resolución independiente
tag -> SHA y checkout de ese SHA.

### R3 — Conflicto de commit aislado

El fixture conflictivo conserva exactamente nombres y tamaños del fixture
compatible y cambia únicamente el marcador de commit. La prueba verifica que
la causa es el commit.

### R4 — Published exige versión

Solo `NoSubmission` puede carecer de versión previa. `Published` con versión
vacía, malformada o no canónica falla cerrado. Solo una versión objetivo válida
y estrictamente mayor puede devolver `upload`.

### R5 — PendingCommit es all-or-nothing

Para `commit-resume` deben estar presentes y coincidir: Product ID consultado,
versión Store, nombre del bundle, Package Family Name y SHA-256 recalculado.
Falta de cualquier campo remoto u objetivo es `fail-closed`, no wildcard.

### R6 — Todos los mutators usan el mismo verdict

Después de `publish --noCommit`, `commit` solo se invoca si la correlación
completa devuelve exactamente `commit-resume`. `delete-target-draft` usa el
mismo guard, incluido el hash, antes de `submission delete`.

### R7 — Fallos cerrados no mutan

Cada caso negativo demuestra con un fake CLI/process invoker cero llamadas a
`publish`, `commit` y `submission delete`.

### R8 — Regresiones honestas

El harness cubre commit compatible/distinto/ausente/no-SHA, Published válido y
sin versión, PendingCommit completo/incompleto/mismatched, post-publish y delete
con hash incorrecto. Los helpers fallan cuando no ocurre el error/verdict
esperado.

### R9 — Documentación veraz

La guía Store y el README de operaciones indican que provenance y todos los
campos pending son obligatorios. El plan previo no se reescribe; este plan
registra la corrección.

### R10 — Sin cambios de producto

No modificar Rust, C#, XAML, DSP, FFI, WASAPI, Win2D, rendering, `Product.props`,
identidad, PFN, formato, arquitecturas, D5, versión publicada o listing. No
hay version bump, tag ni release.

### R11 — Seguridad y frontera externa

No añadir secretos/tokens/credenciales a repositorio, fixtures, logs, manifests
o plan. No acceder ni mutar Partner Center durante la implementación offline.

### R12 — Hardening previo permanece verde

Deben permanecer PASS el parseo JSON, resolución de tags, checksum exacto por
nombre, pin del CLI, retries/redaction, parser Product.props, pinning de
workflows y regresiones de producto.

## In Scope

- `scripts/modules/Echo.GitHubRelease.psm1` y
  `.github/workflows/release.yml` para comparar/persistir el SHA.
- `scripts/modules/Echo.StoreSubmission.psm1` para Published/PendingCommit.
- `scripts/Invoke-MicrosoftStoreRelease.ps1` para post-publish/delete.
- Tests, fixtures y seams bajo `tests/scripts/` y `tests/fixtures/`.
- `docs/public/publishing/microsoft-store.md`, `docs/store/README.md` y este
  plan.

## Out of Scope

- Producto/arquitectura Rust, C#, XAML, DSP, FFI, WASAPI, Win2D o rendering.
- Cambios de Product.props, package identity, PFN, package type, arquitecturas,
  D5, versión, listing o dependencias.
- Live GitHub/Partner Center, secrets, submission, deletion remota, tag, release
  o push automático.
- Reescritura del plan archivado anterior.

## Design Decisions

### D1 — Follow-up correctivo

El plan anterior conserva su historial. Este follow-up corrige las brechas que
la auditoría posterior demostró sin reabrir ni falsear sus checkpoints.

### D2 — SHA explícito para recuperación

El pipeline crea el draft con el SHA real en `target_commitish` y solo permite
no-op con igualdad exacta. Una release antigua sin marker verificable falla
cerrada y no se modifica.

### D3 — Evidencia ausente es insegura

La falta de versión o identidad pending nunca autoriza mutación. Solo
`NoSubmission` puede omitir datos pending; Published requiere versión y
PendingCommit requiere identidad completa.

### D4 — Un verdict para cada mutator

Preflight, post-publish y delete consumen la misma transición estricta. No se
permiten checks parciales específicos del caller.

### D5 — Producto inmutable y validación offline

La corrección queda limitada a automatización/tests/docs; fixtures y seams
prueban el contrato sin credenciales. Partner Center queda operator-gated.

## Invariants

- **I1:** no cambia producto ni arquitectura.
- **I2:** Product.props sigue siendo la fuente única de configuración.
- **I3:** commit desconocido/conflictivo falla cerrado y no sobrescribe.
- **I4:** Published sin versión no puede mutar.
- **I5:** PendingCommit incompleto/conflictivo no puede commit/delete.
- **I6:** commit requiere correlación completa después de publish.
- **I7:** fallos cerrados no invocan mutators ni retries permanentes.
- **I8:** no se exponen secrets y los gates live permanecen separados.
- **I9:** identidad, PFN, bundle x64/ARM64, D5 e historia publicada no cambian.
- **I10:** ninguna prueba pasa por un mismatch no relacionado.

## Executor Discretion

### Allowed without replanning

- Nombres de helpers privados/variables y extracción interna dentro de los
  módulos indicados.
- Nombres/orden de fixtures y organización de asserts.
- Wording seguro del error, sin secrets.

### Locked by the plan

- Nunca no-op sin comparar SHA.
- Nunca upload Published sin versión válida.
- Nunca commit-resume con campos pending ausentes.
- Nunca commit/delete tras comprobar solo `State`.
- No cambiar producto, configuración, package o release identity.

## Change Map

| ID | Location | Expected change | Requirements |
|---|---|---|---|
| C1 | `Echo.GitHubRelease.psm1` / compatibility | Comparar SHA estricto y rechazar marker ausente/no-SHA/conflictivo. | R2, R3 |
| C2 | `release.yml` / create draft | Persistir SHA resuelto y mantener gate corregido. | R2, R12 |
| C3 | `Echo.StoreSubmission.psm1` / verdict | Separar Published/NoSubmission y exigir versión/pending completos. | R4, R5 |
| C4 | `Invoke-MicrosoftStoreRelease.ps1` | Reusar verdict completo antes de commit/delete. | R6, R7 |
| C5 | tests/fixtures | Casos negativos aislados y mutation counters. | R3, R7, R8 |
| C6 | docs/plan | Alinear contrato y registrar evidencia. | R9–R12 |

## Dependency Map

1. Baseline antes de editar.
2. Fixtures/seams antes de cambiar behavior.
3. Módulos antes de workflows/callers.
4. Callers después del verdict estricto.
5. Docs y quality gate al final.
6. Integración en `dev` solo tras autorización y validación; no se presume en
   este plan.

# Execution Plan

## Milestone 1 — Baseline y regresiones reproducibles

### Step 1 — Reconciliar baseline y aislar defectos

**Status:** `NOT_STARTED`

**Objective:** confirmar `28055b6` y añadir pruebas que fallen por la causa
específica de cada defecto.

**Requirements:** R1, R3, R7, R8, R12.

**Location:** branch de hardening, `tests/scripts/`, fixtures GitHub/Store.

**Changes:** confirmar merge-base y módulos; igualar assets del fixture de
conflicto; añadir markers ausentes/no-SHA/branch, Published sin versión y
Pending incompleto; contar mutators.

**Rationale:** el harness previo podía pasar por un mismatch distinto.

**Dependencies:** autorización y baseline.

**Invariants:** I3–I7, I10.

**Validation:** las pruebas nuevas deben fallar contra el código actual por la
causa específica; después pasarán al completar Steps 2–4.

**Completion evidence:** cada defecto tiene un caso negativo aislado y prueba
de cero mutaciones.

**Allowed discretion:** nombres equivalentes.

**Replan triggers:** baseline ausente, CLI sin campos o necesidad de live API.

## Milestone 2 — Provenance de release

### Step 2 — Hacer efectivo `ExpectedCommitSha`

**Status:** `NOT_STARTED`

**Objective:** impedir no-op cuando el commit de la release no es demostrable.

**Requirements:** R2, R3, R8, R12.

**Location:** `Echo.GitHubRelease.psm1`, `release.yml`, fixtures/harness.

**Changes:** validar SHA esperado y `target_commitish`; fail-closed ante marker
ausente, branch, formato inválido o mismatch; persistir SHA en draft; mantener
tag resolution y exact-SHA checkout en Store.

**Rationale:** cierra el parámetro ignorado sin cambiar package/product.

**Dependencies:** Step 1 y `Resolve-EchoTagCommitSha`.

**Invariants:** I3, I9, I10.

**Validation:** compatible -> no-op; todo marker inválido/conflictivo ->
fail-closed; actionlint y audit estático PASS.

**Completion evidence:** todo no-op compara SHA y todo draft nuevo lo persiste.

**Allowed discretion:** helper privado y mensajes.

**Replan triggers:** el API no preserva el marker explícito; no aceptar branch.

## Milestone 3 — Estado Store estricto

### Step 3 — Corregir Published y PendingCommit

**Status:** `NOT_STARTED`

**Objective:** impedir upload/commit con evidencia incompleta.

**Requirements:** R4, R5, R7, R8, R12.

**Location:** `Echo.StoreSubmission.psm1`, fixtures y harness.

**Changes:** NoSubmission como única excepción sin versión; Published exige
versión canónica; PendingCommit exige versión, bundle, PFN y hash remotos y
objetivo; cualquier ausencia/input vacío falla cerrado.

**Rationale:** unknown external state no puede autorizar mutación.

**Dependencies:** Step 1.

**Invariants:** I4, I5, I7–I9.

**Validation:** matriz válida/ausente/malformada/mismatch; negativos fail-closed
y sin mutators; retry/redaction intactos.

**Completion evidence:** los tres probes originales devuelven fail-closed.

**Allowed discretion:** helper y mensajes.

**Replan triggers:** CLI sin campo obligatorio read-only.

## Milestone 4 — Callers mutantes protegidos

### Step 4 — Gate post-publish y delete

**Status:** `NOT_STARTED`

**Objective:** impedir bypass del verdict por callers posteriores.

**Requirements:** R5, R6, R7, R8, R12.

**Location:** `Invoke-MicrosoftStoreRelease.ps1` y módulo Store.

**Changes:** tras no-commit, pasar todos los datos al verdict y exigir
`commit-resume`; delete usa el mismo guard incluido el hash; configure/read-only
permanecen separados de mutators.

**Rationale:** comprobar State solamente permitía commitar otra submission.

**Dependencies:** Step 3.

**Invariants:** I5–I8.

**Validation:** fake CLI: estado incompleto/mismatch -> commit count 0; exacto
-> un commit; delete incorrecto -> delete count 0; parser 0 errores.

**Completion evidence:** ninguna mutación alcanza el CLI desde un check de State
solo.

**Allowed discretion:** seam y helper.

**Replan triggers:** API nueva o cambio de producto necesario.

## Milestone 5 — Docs, quality gate y handoff

### Step 5 — Cierre offline

**Status:** `NOT_STARTED`

**Objective:** dejar evidencia lista para revisión/integración separada.

**Requirements:** R8–R12.

**Location:** publishing docs, plan y diff de automation/tests.

**Changes:** documentar marker/campos obligatorios; ejecutar V1–V10; actualizar
compliance, checkpoint final y handoff; mantener live gates como BLOCKED/
operator-gated.

**Rationale:** código, tests y operación deben compartir contrato.

**Dependencies:** Steps 1–4.

**Invariants:** I1–I10.

**Validation:** V1–V10.

**Completion evidence:** requirements VERIFIED, sin plan gap/deviation y sin
claims de Partner Center live.

**Allowed discretion:** formato de evidencia.

**Replan triggers:** gate fallido, secreto, cambio de producto o live mutation.

## Verification and State

### Validation Strategy

| ID | Validation | Pass criterion |
|---|---|---|
| V1 | status/branch/merge-base | rama contiene `28055b6`; deletion preexistente no se stagea. |
| V2 | `Test-ReleaseHardening.ps1` provenance | compatible no-op solo con SHA igual; conflictos fail-closed. |
| V3 | matriz Published/Pending | ausencia/formato/mismatch fail-closed; exacto autorizado. |
| V4 | fake CLI/process invoker | negativos tienen cero publish/commit/delete. |
| V5 | `Test-StoreReleasePipeline.ps1` | regresiones previas PASS. |
| V6 | parser PowerShell | cero errores. |
| V7 | `actionlint` y audit estático | workflows PASS; draft persiste SHA; branch no es source proof. |
| V8 | config/branding/bundle validation | proyecciones PASS; Product.props/producto sin cambios. |
| V9 | cargo fmt/clippy/test y dotnet test | Rust/.NET PASS. |
| V10 | quality gate, diff/reference/secret scan | docs coherentes; cada PASS tiene evidencia actual. |

### Compliance matrix

| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Step 1 | V1 | VERIFIED | `dev@28055b6` HEAD; `git merge-base --is-ancestor 28055b6 HEAD` exit 0 |
| R2 | Step 2 | V2, V7 | VERIFIED | `Test-ReleaseHardening.ps1` provenance cases PASS; `actionlint` PASS; draft persiste `target_commitish` |
| R3 | Steps 1–2 | V2 | VERIFIED | conflicted fixture: assets idénticos, solo commit difiere; `fail-closed` |
| R4 | Step 3 | V3 | VERIFIED | Published sin/versión malformada → `fail-closed`; NoSubmission sin versión → upload |
| R5 | Steps 3–4 | V3, V4 | VERIFIED | PendingCommit all-or-nothing; ausencia/mismatch → `fail-closed` |
| R6 | Step 4 | V4 | VERIFIED | post-publish exige `commit-resume`; delete usa verdict completo con hash |
| R7 | Steps 1, 3, 4 | V3, V4 | VERIFIED | mutation counters: 0 publish/commit/delete en fail-closed |
| R8 | Steps 1–5 | V2–V6 | VERIFIED | casos negativos cubiertos; helpers fallan en mismatch |
| R9 | Step 5 | V10 | VERIFIED | docs store + README actualizados |
| R10 | All steps | V8–V10 | VERIFIED | sin cambios de producto/config (dif vacía) |
| R11 | Steps 1, 5 | V4, V10 | VERIFIED | sin secrets; ninguna llamada live |
| R12 | Steps 2–5 | V2, V5–V10 | VERIFIED | hardening previo + parser + workflows + Rust/.NET green |

### Replan Triggers

- `28055b6` no es reconciliable o los contratos cambiaron materialmente.
- GitHub no preserva el SHA explícito; branch no es fallback válido.
- CLI no expone versión, bundle, PFN y hash read-only.
- La corrección requiere tocar producto, Product.props, identity, package,
  arquitecturas, D5 o listing.
- Se requiere live mutation para conocer el estado.
- No se puede probar cero mutators en casos fail-closed.
- Aparece cualquier secreto/token en repo, reportes o artefactos.

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Release sin SHA demostrable | High | fail closed; no rewrite; decisión operator-gated |
| CLI omite hash/version pending | High | stop y replan; nunca wildcard |
| Caller bypassa verdict | High | mutation counters y audit estático |
| Fixture pasa por mismatch distinto | Medium | assets idénticos en conflicto |
| Hardening no está en dev | High | baseline obligatorio antes de editar |

# Living Execution Record

## Progress

- M1–M5: `COMPLETED`.
- Current step: Step 5 done.
- Step 1 (baseline/aislar defectos): fixture conflicto igualado; casos negativos GitHub (no-SHA/branch/malformed/expected inválido) y Store (Published sin versión, Pending incompleto/mismatch); mutation counters añadidos.
- Step 2 (ExpectedCommitSha): módulo GitHub compara SHA estricto y fail-closed ante marker ausente/branch/formato/mismatch; `release.yml` persiste `target_commitish` resolvido.
- Step 3 (Published/PendingCommit): NoSubmission única excepción sin versión; Published exige versión canónica; PendingCommit all-or-nothing.
- Step 4 (post-publish/delete): `Invoke-MicrosoftStoreRelease.ps1` reusa verdict completo antes de commit y delete.
- Step 5 (cierre): docs actualizadas; V1–V10 ejecutadas.
- Implementation **AUTORIZADA y EJECUTADA**; baseline `28055b6` confirmado como HEAD/ancestro de `dev`.

## Checkpoint Ledger

### CP-001 — 2026-08-11 (authoring complete)

- **Plan status:** `READY`; **verification:** `VERIFIED`.
- **Repository:** `dev@91eebe9`; target `ci/release-cd-hardening@28055b6`.
- **Working tree:** pre-existing attachment deletion only; no implementation
  changes made by authoring.
- **Evidence:** instructions, prior plan, handoff, workflows, modules, fixtures
  and publishing docs inspected; gates rerun; direct probes reproduced all four
  defects.
- **Result:** PASS for authoring/baseline; implementation intentionally
  unexecuted.
- **Next exact action:** after authorization, use a branch containing `28055b6`,
  run Step 1 negative cases, then execute Steps 2–5.

### CP-002 — 2026-08-11 (execution baseline)

- **Plan status:** IN_PROGRESS; **verification:** VERIFIED.
- **Repository:** `dev@28055b6` (HEAD); `git merge-base --is-ancestor 28055b6 HEAD` exit 0 (R1). `origin/dev` = `6a1ed44`.
- **Working tree:** pre-existing attachment deletion + authoring plan/INDEX only; no prior implementation overlap.
- **Changes since CP-001:** Step 1 fixture igualado (`release-conflicted-commit.json` → solo commit difiere, R3) y módulos/workflows/callers aún no tocados.
- **Validation:** V1 PASS.
- **Result:** baseline reconciled; Step 1 in progress.
- **Next exact action:** implementar Steps 2–4, luego Step 5.

### CP-003 — 2026-08-11 (Steps 2–3 core)

- **Plan status:** IN_PROGRESS; **verification:** STALE (durante mutación).
- **Changes since CP-002:** `Echo.GitHubRelease.psm1` (SHA estricto, R2), `release.yml` (target_commitish, R2), `Echo.StoreSubmission.psm1` (Published/PendingCommit, R4/R5).
- **Validation:** `Test-ReleaseHardening.ps1` y `Test-StoreReleasePipeline.ps1` PASS locales.
- **Conformance:** CONFORMING.
- **Next exact action:** Step 4 callers (commit/delete) y Step 5 cierre.

### CP-004 — 2026-08-11 (Steps 4–5 complete)

- **Plan status:** COMPLETED; **verification:** VERIFIED.
- **Repository:** `dev@28055b6` (sin commit nuevo en esta sesión; cambios en working tree).
- **Changes since CP-003:** `Invoke-MicrosoftStoreRelease.ps1` (post-publish/delete verdict completo, R6); docs (`microsoft-store.md`, `docs/store/README.md`, R9).
- **Validation:** V1–V10 PASS (ver Validation Evidence).
- **Conformance:** CONFORMING.
- **Compliance changes:** R1–R12 → VERIFIED.
- **Open deviations:** None. **Blockers:** None (offline; Partner Center/primera submission externos).
- **Next exact action:** archivar plan, actualizar INDEX y handoff.

## Surprises & Discoveries

### DISC-001 — Previous tests did not isolate the contracts

The conflict fixture changed asset size as well as commit, and no tests covered
missing Published version, missing pending fields or post-publish state-only
commit. This is why prior green gates did not authorize integration.

### DISC-002 — Hardening implementation is not in dev

`dev` remains at `91eebe9`; the hardening implementation is only at
`ci/release-cd-hardening@28055b6`. Running this plan without reconciliation
would target absent/stale files.

## Decision Log

### DEC-001 — Strict SHA marker

**Date:** 2026-08-11. **Decision:** persist the resolved SHA in draft creation
and require exact 40-hex equality for recovery. **Rationale:** closes the
unused-parameter bug without changing product/package architecture.

### DEC-002 — Missing Store evidence fails closed

**Date:** 2026-08-11. **Decision:** missing version/PFN/bundle/hash never acts as
a wildcard; all mutators use one strict verdict. **Rationale:** unknown state
cannot safely authorize mutation.

## Plan Deviations

None at authoring time.

## Validation Evidence

Authoring evidence: `INDEX.md`, prior plan/handoff, both branches, relevant
workflows/modules/fixtures/docs and all listed offline gates were inspected or
rerun.

### VAL-001 — V1 Baseline (CP-002)
- **Command:** `git merge-base --is-ancestor 28055b6 HEAD`; `git status`.
- **Result:** PASS. HEAD=`28055b6`; ancestro confirmado; `dev` ahead of `origin/dev`.
- **Evidence:** exit 0; solo attachments deletion + plan/INDEX authoring en el tree.

### VAL-002 — V2 Provenance GitHub (CP-004)
- **Command:** `powershell -File .\tests\scripts\Test-ReleaseHardening.ps1`.
- **Result:** PASS. `R2 Commit provenance`, `R4 Release idempotency` verdes; conflicted fail-closed con assets idénticos; no-op solo con SHA igual.

### VAL-003 — V3 Matriz Published/Pending (CP-004)
- **Command:** mismo harness (secciones R4/R5).
- **Result:** PASS. Published sin versión/malformada → `fail-closed`; NoSubmission sin versión → `upload`; Pending ausencia/mismatch → `fail-closed`; exacto → `commit-resume`.

### VAL-004 — V4 Mutation counters (CP-004)
- **Command:** sección `R6/R7` del harness (fake CLI process invoker).
- **Result:** PASS. Preflight fail-closed: publish=0, commit=0, delete=0, get=1.

### VAL-005 — V5 Store pipeline regressions (CP-004)
- **Command:** `powershell -File .\tests\scripts\Test-StoreReleasePipeline.ps1`.
- **Result:** PASS. S2/S5 y state machine verdes (PendingCommit resume ahora exige identidad completa).

### VAL-006 — V6 Parser PowerShell (CP-004)
- **Command:** parser `ParseFile` sobre módulos, callers y tests.
- **Result:** PASS. 0 errores en `Echo.GitHubRelease.psm1`, `Echo.StoreSubmission.psm1`, `Invoke-MicrosoftStoreRelease.ps1`, ambos harness.

### VAL-007 — V7 GitHub Actions lint (CP-004)
- **Command:** `actionlint release.yml store-publish.yml store-build.yml store-status.yml ci.yml`.
- **Result:** PASS. Cero errores. Draft persiste `target_commitish`.

### VAL-008 — V8 Config/branding sin cambios (CP-004)
- **Command:** `git diff --stat build/Product.props src/core src/ui`.
- **Result:** PASS. Sin cambios de producto/config/identity/PFN/arquitecturas/D5/versión.

### VAL-009 — V9 Rust/.NET (CP-004)
- **Command:** `Invoke-QualityGate.ps1 -Configuration Debug`.
- **Result:** PASS. Rust 77 pruebas, .NET 40 pruebas, build UI/test OK, fmt/clippy OK.

### VAL-010 — V10 Quality gate / diff / secret scan (CP-004)
- **Command:** `git diff --check`; `git status`; review de diff.
- **Result:** PASS. Sin whitespace errors; diff mapea a C1–C6; sin secrets; docs coherentes.

## Handoff Snapshot

**Last safe checkpoint:** `CP-004`.

**Current state:** plan COMPLETED. Corrección ejecutada en `dev@28055b6`
(working tree sin commit nuevo en esta sesión). Baseline `28055b6` reconciliado
como HEAD/ancestro. Attachment deletion y authoring del plan/INDEX quedan como
estaban; no se stagean.

**Completed:** baseline, Steps 1–5 (fixtures, módulo GitHub, store verdict,
callers, docs, quality gate), compliance R1–R12 → VERIFIED.

**Next exact action:** revisar/commits separados y, si el usuario lo autoriza,
integrar/pushear a `dev` y ejecutar los gates live de Partner Center (externos,
operator-gated).

**Do not repeat:** no reintroducir no-op sin comparar SHA, ni upload Published
sin versión, ni PendingCommit wildcard, ni commit/delete por check de State solo.

**Pending validation:** V1–V10 completas. Live Partner Center confirmation y
primera submission autorizada siguen externos.

**Open discoveries:** `DISC-001` (resuelto por fixtures), `DISC-002` (resuelto:
baseline integrado en `dev@28055b6`). **Open decisions:** `DEC-001`, `DEC-002`
(ejecutadas). **Open deviations:** none.

**Files relevant:** `scripts/modules/Echo.GitHubRelease.psm1`,
`scripts/modules/Echo.StoreSubmission.psm1`, `.github/workflows/release.yml`,
`scripts/Invoke-MicrosoftStoreRelease.ps1`, tests/fixtures, publishing docs.

**Resume commands:** `git merge-base --is-ancestor 28055b6 HEAD`;
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\scripts\Test-ReleaseHardening.ps1`;
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\scripts\Test-StoreReleasePipeline.ps1`;
`actionlint`; `powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\tools\scripts\Invoke-QualityGate.ps1 -Configuration Debug`.

# Completion

## Completion Criteria

- [x] Baseline reconciled and checkpointed.
- [x] Commit conflict/missing/non-SHA fails closed; compatible source compares
  and returns no-op.
- [x] Published missing/malformed version never uploads.
- [x] Pending missing/mismatched fields never resumes.
- [x] Post-publish commit and delete use complete correlation.
- [x] Mutation counters prove negative paths do not call mutators.
- [x] Prior hardening, parser, workflow, product, Rust and .NET gates remain
  green.
- [x] Documentation, compliance, final checkpoint and handoff are current.
- [x] No product/version/identity changes, secrets or live Store calls.

## Outcomes & Retrospective

### Delivered

- Provenance estricta de release: `Test-EchoGitHubReleaseCompatibility` ahora
  valida el SHA esperado y lo compara con `target_commitish`; marker ausente,
  branch, formato inválido o mismatch → `fail-closed`. `release.yml` persiste el
  SHA resolvido como `target_commitish`.
- `Test-EchoStoreStateSafeToProceed` separa `NoSubmission` (única excepción sin
  versión previa) de `Published` (exige versión canónica) y hace `PendingCommit`
  all-or-nothing (versión, bundle, PFN y SHA-256 presentes y exactos).
- `Invoke-MicrosoftStoreRelease.ps1` reusa el verdict completo (no solo State)
  antes de `commit` post-`publish --noCommit` y antes de `submission delete`.
- Mutation counters y casos negativos aislados añadidos al harness; fixture de
  conflicto ahora cambia solo el commit (R3).
- Documentación veraz en `microsoft-store.md` y `docs/store/README.md`.

### Validation

V1–V10 PASS: baseline, harness GitHub/Store, mutation counters 0-mutators,
parser 0 errores, actionlint, sin cambios de producto, quality gate completo
(Rust 77 + .NET 40).

### Differences from original plan

Ninguna material. Variación local permitida: helper `Test-EchoCanonicalStoreVersion` privado y organización de asserts/fixtures.

### Important discoveries

`DISC-001` y `DISC-002` resueltos durante la ejecución: el baseline hardening
ya estaba integrado en `dev@28055b6`, y el fixture de conflicto anterior no
aislaba la causa del commit.

### Decisions worth preserving

`DEC-001` (SHA estricto) y `DEC-002` (evidencia ausente → fail-closed) quedaron
implementados como estaba planificado.

### Follow-up work

Integración/commit y push a `dev` (autorización separada); confirmación
read-only de Partner Center y primera submission autorizada (gates externos).

### Final result

SUCCESS (offline scope). Los gates live de Partner Center y la primera
submission quedan como pasos operativos externos separados.
