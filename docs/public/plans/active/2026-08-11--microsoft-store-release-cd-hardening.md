# Plan: Endurecimiento y corrección del release CI/CD de Microsoft Store

## Current State Snapshot

- **Plan ID:** `PLAN-20260811-RELEASE-CD-HARDENING`
- **Status:** `IN_PROGRESS`
- **Verification state:** `STALE` (implementation mutated modules/scripts since CP-002; CP-003 will revalidate)
- **Created:** 2026-08-11
- **Last updated:** 2026-08-11
- **Branch/worktree:** `ci/release-cd-hardening`, descendiente de `91eebe9` (contiene la implementación auditada y `.agents/`).
- **Planning baseline revision:** `6a1ed44` (`dev`, autoría) — la integración real de la implementación está en `91eebe9`.
- **Implementation evidence revision:** `91eebe9` (baseline confirmado como ancestro de HEAD).
- **Working tree at authoring:** `dev` con la implementación auditada integrada; la ejecución continúa sobre `ci/release-cd-hardening`.
- **Active milestone:** M4 — Release, provenance y publicación por workflow
- **Active step:** Step 4 — corregir resolución GitHub, idempotencia y payload provenance
- **Completed steps:** 3 / 6 (Step 1 M1, Step 2 M2, Step 3 M3)
- **Last checkpoint:** `CP-003`
- **Last validated checkpoint:** `CP-003`
- **Next action:** reescribir `release.yml` y `store-publish.yml` sobre `Echo.GitHubRelease.psm1` (C2/C3), sin filtros `.items[]` convertidos desde stdout; volver a comprobar hashes exactos tras download-artifact (C7, R5/R8).
- **Current blockers:** no hay bloqueo de implementación offline; Partner Center y los secretos de producción siguen siendo gates externos y no se deben activar durante la implementación offline.
- **Open plan deviations:** ninguna.
- **Supersedes:** —
- **Superseded by:** —

## Objective

Dejar operativa y verificable la automatización de releases de Echo Visualizer
para GitHub Releases y Microsoft Store, corrigiendo los fallos detectados en la
auditoría posterior a la ejecución de
`PLAN-20260811-MICROSOFT-STORE-RELEASE-CD`.

El estado observable al finalizar será:

1. El workflow de release resuelve el commit real de un tag ligero o anotado,
   valida los gates contra ese SHA y puede recuperarse de una ejecución
   repetida sin crear una publicación duplicada.
2. El workflow de Store acepta únicamente un GitHub Release estable que
   corresponda exactamente al tag, commit, manifest, asset y hashes esperados.
3. El adaptador de `msstore` distingue ausencia de submission, submission
   pendiente, estados activos, estados terminales y versiones publicadas; no
   muta Partner Center antes de un preflight seguro.
4. El instalador del CLI es sintácticamente válido y falla cerrado ante una
   discrepancia de digest o de versión.
5. `Product.props` continúa siendo la única fuente versionada para configuración
   de distribución, incluyendo arquitecturas, tipo de paquete, recipes de
   branding y coordenadas del CLI.
6. Las pruebas negativas reproducen los defectos encontrados sin necesitar una
   publicación real en Partner Center.

## Context and Evidence

La auditoría independiente se realizó sobre `ci/microsoft-store-release-cd`
en `91eebe9`. Sus resultados relevantes son:

- el bundle local x64 + ARM64 se construye correctamente;
- las pruebas existentes pasan: 77 Rust y 40 .NET;
- `actionlint` pasa los workflows;
- `scripts/Install-MicrosoftStoreCli.ps1` no pasa el parser de PowerShell por
  la interpolación `$expectedVersion:` en la línea 99;
- `release.yml` y `store-publish.yml` convierten salida JSON de `gh --jq` que
  contiene múltiples líneas en un único `ConvertFrom-Json`;
- `release.yml` no desreferencia tags anotados hasta el commit real;
- `release.yml` crea siempre un draft nuevo y no modela recuperación idempotente;
- `store-publish.yml` usa `target_commitish` como si fuera el SHA definitivo y
  no vuelve a comprobar el hash exacto del payload descargado;
- `Echo.StoreSubmission.psm1` pasa el estado textual como
  `LatestPublishedVersion`, no implementa el retry declarado y no correlaciona
  una submission pendiente con la versión/paquete objetivo;
- `Build-Distributions.ps1`, `New-EchoReleaseManifest.ps1` y
  `Test-StoreReleaseArtifact.ps1` todavía contienen valores de arquitecturas,
  extensión o tamaños que deberían consumirse desde `Product.props`;
- `Echo.ReleaseMetadata.psm1` tolera grupos de items desconocidos y no exige
  completamente todos los grupos/metadatos declarados por el esquema;
- el plan archivado declara algunos checkpoints como PASS pese a estos fallos
  y su matriz de cumplimiento contiene una fila mal formada.

La configuración actual de `build/Product.props` y la generación local de
assets son una base válida y se conservarán. La corrección no debe modificar
el comportamiento de Rust, C#, XAML, DSP, FFI, WASAPI, Win2D o renderizado.

## Repository Baseline

### Planning baseline

- Branch: `dev`
- HEAD: `6a1ed44`
- Upstream: `origin/dev`, sincronizado después de `git fetch --prune`
- Working tree: limpio al crear el plan
- Nota: `dev` todavía no contiene el control `.agents/` ni los archivos de la
  implementación Store CD que existen en `ci/microsoft-store-release-cd`.

### Implementation baseline

- Branch: `ci/microsoft-store-release-cd`
- HEAD: `91eebe9`
- Parent planning baseline: `c5b6a58`
- Esta es la revisión que contiene las superficies auditadas. Antes de ejecutar
  el Step 1 se debe confirmar que el branch de trabajo contiene ese commit o
  un equivalente reconciliado.

### Baseline validation already available

The prior audit established local success for Product.props parsing, branding
checks, Rust format/clippy/tests, .NET tests, actionlint and Store bundle
creation. Those successes do not satisfy the release workflow or Partner
Center gates; the new plan adds the missing negative and provenance tests.

## Requirements

### R1 — Baseline reconciliado

La ejecución debe comenzar en una rama descendiente de `91eebe9` o en una rama
que contenga su implementación equivalente y el pipeline `.agents/` completo.
Si la rama difiere materialmente, se debe detener y registrar una replanificación.

### R2 — Parser de API de GitHub correcto

Toda respuesta de `gh api` debe parsearse como un documento JSON válido. No se
debe usar salida por elemento (`.items[]`) seguida de un único
`ConvertFrom-Json`, ni depender de strings multilínea como si fueran arrays.

### R3 — SHA real del tag

Los tags ligeros y anotados deben resolverse hasta un objeto `commit`; el SHA
debe ser de 40 caracteres hexadecimales y ser el único SHA utilizado para
checkout, gates, manifest y provenance.

### R4 — Release estable idempotente

Una publicación repetida debe aceptar como no-op/verificación exitosa un
release estable existente con tag, commit, versión, asset set y hashes exactos.
Un release existente que sea draft, prerelease, apunte a otro commit o tenga
assets incompatibles debe fallar cerrado sin borrar ni sobrescribir datos.

### R5 — Asset set y hashes exactos

La validación debe comprobar nombres, roles, tamaños y SHA-256 exactos de los
ZIP, bundle, manifest y `SHA256SUMS.txt`. La coincidencia de un hash en cualquier
línea no sustituye la comparación con el nombre concreto del archivo.

### R6 — Instalador del CLI seguro

`Install-MicrosoftStoreCli.ps1` debe pasar el parser de PowerShell, comprobar el
digest fijado en `Product.props`, tratar una discrepancia del checksum del
publisher como error y validar que `msstore --version` informa exactamente la
versión declarada.

### R7 — Provenance coherente

El manifest debe representar el tag, commit real, versión de producto, versión
Store, configuración, identidad, arquitecturas, asset hashes y coordenadas del
CLI. El consumidor debe verificar esos valores contra los bytes descargados y
contra `Product.props`, no solo comprobar que los campos existan.

### R8 — Store source-bound

`store-publish.yml` debe resolver y usar el mismo tag/commit del GitHub Release
estable para checkout, scripts, manifest y bundle. `target_commitish` no se
considera una prueba suficiente del commit fuente.

### R9 — Preflight Store seguro

El preflight debe obtener por separado la submission actual, la versión
publicada más reciente y la identidad del paquete pendiente. Debe distinguir
`NoSubmission`, `PendingCommit`, estados activos, estados publicados y estados
fallidos/cancelados. Nunca debe convertir un estado textual en una versión.

### R10 — Correlación de submission

Una submission pendiente solo puede reanudarse si coincide con el Product ID,
versión Store objetivo, paquete/bundle objetivo y hash esperado. Si no coincide,
el flujo debe detenerse y solicitar una decisión explícita.

### R11 — Reintentos limitados

Las invocaciones del CLI deben reintentarse solo ante fallos transitorios
identificables, como 429 o 5xx, con límite y backoff documentados. Errores de
autenticación, validación, identidad, monotonicidad o estado desconocido no
deben reintentarse ni ocultarse.

### R12 — Recuperación destructiva restringida

La operación `delete-target-draft` solo puede ejecutarse mediante un input
explícito y después de verificar que el draft es exactamente el objetivo. No se
debe borrar una submission de otra versión o de otro paquete.

### R13 — Configuración central efectiva

Scripts y workflows deben consumir desde `Get-EchoDistributionConfiguration`
las arquitecturas, RuntimeIdentifier, RustTarget, ProcessorArchitecture, tipo
de artefacto, tamaños de iconos y cualquier otro valor declarable en
`Product.props`. Las duplicaciones activas deben producir fallo de validación o
ser eliminadas.

### R14 — Parser de Product.props estricto

El parser debe rechazar propiedades, items y metadatos desconocidos; elementos
duplicados; grupos obligatorios ausentes; metadata ausente o inválida; nombres
de capabilities inválidos; arquitecturas duplicadas y cualquier proyección que
no cumpla schema 1.

### R15 — Regresiones automatizadas

Fixtures y pruebas cubrirán tags ligeros/anotados, JSON de uno y varios
elementos, release existente compatible/conflictivo, assets alterados,
manifests inconsistentes, estados Store, ausencia de submission, reintentos,
configuración inválida y payload transferido con hash incorrecto.

### R16 — Runner y acciones controlados

Los jobs de build/release que requieran Windows usarán la imagen fijada por la
política del proyecto. Las acciones externas y cualquier acción usada por el
composite de setup deberán cumplir la política de pinning vigente, o la
excepción deberá quedar documentada y validada.

### R17 — Documentación coherente

La guía de publicación, README de Store, especificación/traceability aplicable
y el plan archivado deben reflejar el comportamiento real, no declarar PASS o
CONFORMING mientras exista un gate fallido. Las referencias activas a
StoreBroker o a configuraciones eliminadas deben eliminarse o marcarse como
históricas.

### R18 — Seguridad y autorización

No se añadirán secretos, valores de credenciales ni tokens al repositorio. La
implementación offline no publicará ni modificará Partner Center. El primer
workflow live y cualquier configuración del Environment requieren autorización
directa y separada del usuario.

### R19 — Sin cambios de producto

No se modificará código Rust, C#, XAML, DSP, FFI, WASAPI, Win2D, renderizado,
identidad del producto, versión publicada, listing ni algoritmo de versión.

## In Scope

- Workflows `.github/workflows/release.yml`,
  `.github/workflows/store-publish.yml` y sus validaciones de CI relacionadas.
- Composite action y runner references solo cuando sean necesarios para cumplir
  R16.
- `scripts/Install-MicrosoftStoreCli.ps1`.
- `scripts/modules/Echo.StoreSubmission.psm1` y un módulo compartido nuevo para
  resolver API/tag/release si se confirma que evita duplicación entre workflows.
- `scripts/Build-Distributions.ps1`,
  `scripts/New-EchoReleaseManifest.ps1`,
  `scripts/Test-StoreReleaseArtifact.ps1` y
  `scripts/modules/Echo.ReleaseMetadata.psm1`.
- Fixtures y tests en `tests/scripts/` para los contratos offline.
- Documentación de publicación, traceability y correcciones de evidencia del
  plan, sin reescribir el historial de forma engañosa.

## Out of Scope

- Rust, C#, XAML, DSP, FFI, WASAPI, Win2D, Direct3D y comportamiento de UI.
- Cambio de Product ID, PFN, publisher, package identity, capabilities,
  `msixbundle`, arquitecturas soportadas o algoritmo de versión.
- Metadata/listing de Partner Center y configuración real de secrets.
- Publicación, commit, borrado o rollout real en Microsoft Store.
- Rotación de versiones o creación de un release público nuevo.
- Sustitución de GitHub Actions por otro proveedor o rediseño de la arquitectura
  del producto.

## Design Decisions

### D1 — El plan corrige el branch de implementación auditado

**Decision:** el executor debe reconciliar el workspace con `91eebe9` antes de
editar. La autoría permanece en `dev` por la política del repositorio, pero el
plan no fingirá que los archivos de Store CD existen en el baseline `6a1ed44`.

**Rationale:** `dev` todavía no contiene la ejecución auditada; omitir esta
precondición haría que el executor creyera que debe crear la pipeline desde
cero o aplicara fixes sobre archivos ausentes.

**Consequence:** si la integración de la primera ejecución cambia la estructura
o las decisiones de distribución, el plan entra en `REPLANNING` antes de tocar
implementación.

### D2 — Un módulo compartido será la frontera de GitHub provenance

**Decision:** crear, si la inspección del target confirma que no existe un
equivalente, `scripts/modules/Echo.GitHubRelease.psm1` con las operaciones de
JSON, resolución de tag, carga de release y comparación de assets que usan
`release.yml` y `store-publish.yml`.

**Rationale:** mantener dos parsers de API y dos resoluciones de SHA permitió
que los workflows divergieran. `Echo.ReleaseMetadata.psm1` seguirá limitado a
`Product.props`; no se mezclará provenance de GitHub con metadata de producto.

**Consequence:** los workflows llamarán una única lógica comprobable offline y
no tendrán filtros `.items[]` convertidos directamente desde stdout.

### D3 — La identidad de un release es `(tag, commit, version, asset set, hashes)`

**Decision:** la recuperación solo será idempotente si todos esos componentes
coinciden. Cualquier conflicto se reporta y se detiene; no se hará clobber ni
delete automático.

**Rationale:** el nombre del tag o `target_commitish` por sí solos no prueban
que el payload sea el mismo.

### D4 — El estado Store se modela con datos separados

**Decision:** `Echo.StoreSubmission.psm1` mantendrá separados `CurrentState`,
`LatestPublishedVersion`, `PendingTarget` y `PendingPackageHash`. La acción
`upload` solo se autoriza para `NoSubmission` con target monotónico superior;
`commit-resume` solo para un `PendingCommit` que coincida exactamente; los
estados activos son `monitor-only`.

**Rationale:** el estado textual y la versión remota son conceptos distintos y
la implementación actual los mezcla.

### D5 — La configuración central gobierna también los targets de build

**Decision:** conservar `Product.props` y eliminar los defaults duplicados de
arquitectura, artefacto e icon sizes en consumers. Los scripts deben derivar
mapas runtime/Rust/processor desde los items parseados.

**Rationale:** validar una propiedad central mientras el builder ignora esa
propiedad no cumple el contrato de punto único de entrada.

### D6 — No se amplía el esquema de manifest sin necesidad

**Decision:** primero se comprobarán y validarán todos los campos que ya genera
schema 1. Solo si el hash/configuración requerida no puede expresarse en el
manifest actual se documentará una decisión de incremento de schema y se
detendrá para replanteamiento.

**Rationale:** un cambio de schema es una compatibilidad externa y no debe
introducirse como corrección incidental.

### D7 — El live gate queda separado de la validación offline

**Decision:** el plan debe dejar todos los contratos simulables cubiertos sin
usar credenciales. La lectura real de Partner Center y la primera submission
serán pasos operator-gated posteriores.

**Rationale:** las reglas de release prohíben inferir que una validación local
prueba la API externa o autoriza una publicación.

## Invariants

- **I1:** no se modifica el comportamiento del producto ni su arquitectura de
  Rust/C#/XAML/DSP/FFI/WASAPI/Win2D.
- **I2:** `build/Product.props` y `Get-EchoDistributionConfiguration` siguen
  siendo la única fuente versionada/programática de configuración de producto.
- **I3:** un release o submission conflictivo falla cerrado y no se elimina ni
  sobrescribe automáticamente.
- **I4:** el workflow Store solo puede ser autorizado por un release GitHub
  estable, no por una ruta o versión arbitraria.
- **I5:** cualquier hash usado para aceptación se recalcula sobre los bytes
  locales descargados y se compara con el nombre correcto.
- **I6:** los secretos se manejan únicamente por bindings simbólicos del
  Environment; nunca se escriben en archivos, logs o manifests.
- **I7:** el package identity, PFN, publisher, Store version derivada,
  arquitecturas x64/ARM64 y tipo `.msixbundle` permanecen sin cambio.
- **I8:** los scripts PowerShell modificados pasan parser y se ejecutan con
  `Set-StrictMode` sin ocultar errores de validación.
- **I9:** la reejecución de la misma entrada es determinista e idempotente.
- **I10:** una prueba PASS debe representar exactamente el contrato que dice
  validar; no se aceptan checks de nombre como sustituto de checks de contenido.

## Executor Discretion

### Allowed without replanning

- nombres privados de variables y funciones dentro de los módulos definidos;
- elección entre funciones auxiliares internas o una pequeña refactorización
  equivalente dentro de los scripts indicados;
- formato exacto de mensajes de error siempre que incluya operación, tag/versión
  segura y causa sin secretos;
- uso de fixtures JSON/PowerShell equivalentes que cubran el mismo contrato;
- organización de assertions, orden de propiedades JSON y formato de tablas;
- backoff concreto dentro del límite documentado, si distingue transitorio de
  permanente y no excede el tiempo del job.

### Locked by the plan

- la identidad de release definida en D3;
- la separación de estado definida en D4;
- la centralización de Product.props de D5;
- no cambiar el tipo de paquete, arquitecturas, identidad o algoritmo de versión;
- no añadir secretos ni ejecutar operaciones mutantes de Partner Center;
- no mover la lógica de producto a scripts de distribución;
- no convertir un fallo desconocido en `monitor-only`, `success` o retry infinito.

## Change Map

| ID | Área | Ubicación verificada | Cambio esperado | Requirements |
|---|---|---|---|---|
| C1 | API y provenance | `scripts/modules/` y workflows | Compartir parseo JSON, resolución de tag y comparación de release | R2, R3, R4, R5, R8 |
| C2 | Release | `.github/workflows/release.yml` | Usar SHA commit real, recuperación idempotente y asset verification exacta | R3–R5 |
| C3 | Store resolve | `.github/workflows/store-publish.yml` | Resolver release estable y checkout del mismo SHA, sin `target_commitish` como prueba | R4, R8 |
| C4 | CLI installer | `scripts/Install-MicrosoftStoreCli.ps1` | Corregir parser, checksum publisher y version smoke test | R6 |
| C5 | Store adapter | `scripts/modules/Echo.StoreSubmission.psm1` | Separar estado/versión/package, no-pending, correlación y retries | R9–R12 |
| C6 | Manifest | `scripts/New-EchoReleaseManifest.ps1` | Consumir arquitecturas/configuración central y registrar roles exactos | R5, R7, R13 |
| C7 | Artifact validator | `scripts/Test-StoreReleaseArtifact.ps1` | Validar tipo desde config, hash/manifest/identity exactos | R5, R7, R13 |
| C8 | Build projections | `scripts/Build-Distributions.ps1` | Derivar runtime/targets/icons/package type de Product.props | R13 |
| C9 | Config parser | `scripts/modules/Echo.ReleaseMetadata.psm1` | Rechazar unknowns, ausencias, duplicados e invalid metadata | R14 |
| C10 | Tests | `tests/scripts/` y fixtures | Cubrir cada fallo reproducible y estados Store | R15 |
| C11 | Supply chain | `.github/workflows/ci.yml`, composite y runners | Aplicar/preservar pinning y Windows runner contract | R16 |
| C12 | Documentation | `docs/public/publishing/`, `docs/store/`, traceability y plan archivado | Corregir contratos y reportar desviaciones reales | R17 |

## Dependency Map

1. C1/C10 establecen seams y fixtures para poder probar los cambios sin
   publicar.
2. C9 y C8 deben quedar consistentes antes de generar/validar el manifest y el
   bundle, porque esos consumidores dependen de la configuración parseada.
3. C4 y C5 dependen de la forma real de salida del CLI; si el comando de lectura
   no entrega los datos requeridos, se debe activar el replan trigger de D4.
4. C2/C3 consumen C1 y C7; no se debe activar el dispatch Store antes de que
   los checks de asset/provenance estén completos.
5. C12 se actualiza después de validar la implementación y no puede declarar
   PASS anticipadamente.
6. C11 puede ejecutarse en paralelo con C9/C10 solo después de confirmar que no
   cambia la imagen/toolchain necesaria para los tests.

# Execution Plan

## Milestone 1 — Baseline y regresiones reproducibles

**Outcome:** el executor trabaja sobre la revisión correcta y dispone de
fixtures que fallan con los defectos auditados, sin usar credenciales.

**Entry conditions:** rama descendiente de `91eebe9`, `.agents/` activable,
working tree reconciliado y plan leído completo.

**Exit conditions:** fixtures para JSON/tag/release/assets/Store/config están
identificados o creados, y el baseline de parser/build/tests queda registrado.

**Validation gate:** V1, V2 y `git diff --check`.

### Step 1 — Reconciliar baseline y preparar seams de prueba

**Status:** `NOT_STARTED`

**Objective:** verificar que el código auditado y el plan son el mismo
workstream; definir fixtures deterministas para probar fallos sin GitHub o
Partner Center mutantes.

**Requirements:** R1, R15, R18.

**Location:** branch/worktree; `tests/scripts/Test-StoreReleasePipeline.ps1`;
`tests/scripts/fixtures/`; scripts y módulos indicados en C1–C10.

**Changes:**

- comparar `git merge-base`, HEAD, `Product.props`, workflows, módulos y
  scripts contra `91eebe9`;
- ejecutar primero el parser PowerShell sobre todos los scripts relevantes y
  registrar las fallas actuales como baseline;
- ampliar o crear fixtures para respuesta JSON de GitHub como objeto, array,
  salida de múltiples elementos, tag ligero, tag anotado, release compatible,
  release conflictivo y checksum con nombre incorrecto;
- ampliar fixtures Store para `NoSubmission`, `Published`, `PendingCommit`,
  estados activos, errores permanentes y respuesta transitoria;
- definir seams de invocación que permitan simular `gh` y `msstore` sin imprimir
  tokens ni depender de comandos online.

**Rationale:** sin una prueba que falle por la causa exacta, una corrección
podría limitarse a hacer pasar un caso feliz y conservar el defecto.

**Dependencies:** D1; ninguna implementación previa.

**Invariants:** I1, I6, I8, I10.

**Validation:**

- confirmar que el target contiene los símbolos auditados;
- ejecutar un parser PowerShell y `actionlint` como baseline;
- ejecutar el test harness existente y verificar que sus PASS actuales no se
  presenten como cobertura de los nuevos casos;
- revisar que fixtures no contengan secretos.

**Completion evidence:** baseline de revisión registrado en el plan,
fixtures nombrados por caso y al menos una prueba que reproduzca cada uno de
los fallos R2–R5, R9–R11 y R14.

**Allowed discretion:** organización de fixtures y mecanismo de inyección de
comandos.

**Replan triggers:** el target no contiene la implementación auditada; el CLI
no ofrece una respuesta recuperable para identificar versión/package; o los
fixtures requieren cambiar el contrato público de release.

## Milestone 2 — Configuración y proyecciones estrictas

**Outcome:** todos los consumidores de distribución usan la configuración
central, y el parser rechaza cualquier configuración fuera del schema.

**Entry conditions:** Step 1 completo y `Product.props` schema 1 confirmado.

**Exit conditions:** C8/C9 pasan fixtures positivos y negativos sin alterar la
configuración actual.

**Validation gate:** V3, V4 y generación de assets/bundle local.

### Step 2 — Endurecer `Product.props` y eliminar duplicaciones activas

**Status:** `NOT_STARTED`

**Objective:** hacer efectivo el contrato de punto único de configuración.

**Requirements:** R13, R14, R19.

**Location:** `scripts/modules/Echo.ReleaseMetadata.psm1`;
`scripts/Build-Distributions.ps1`;
`scripts/New-EchoReleaseManifest.ps1`;
`scripts/Test-StoreReleaseArtifact.ps1`; fixtures Product.props.

**Changes:**

- validar explícitamente presencia y cardinalidad de cada item group requerido;
- rechazar grupos de items, metadata y propiedades desconocidas que estén dentro
  del documento de distribución; conservar solo las excepciones justificadas
  por MSBuild y documentarlas en el parser;
- rechazar metadata faltante, enums inválidos, capability names no permitidos,
  arquitecturas duplicadas y elementos repetidos;
- hacer que builder, manifest generator y artifact validator consuman los items
  `EchoStoreArchitecture` y el tipo de artefacto en lugar de mantener listas
  independientes;
- derivar las validaciones de icon sizes/branding desde la configuración;
- eliminar fallbacks literales activos que puedan ocultar una propiedad
  faltante; si un valor es una constante normativa de schema, validarlo en un
  solo lugar y documentar por qué no es configurable;
- conservar la configuración actual y no aumentar el schema salvo que el
  executor documente el replan trigger D6.

**Rationale:** el parser actual puede aprobar una configuración que los
consumidores no usan completamente.

**Dependencies:** Step 1; D5; Product.props actual.

**Invariants:** I2, I7, I8, I10.

**Validation:**

- `Test-ProductConfiguration.ps1 -AsJson` con Product.props actual;
- fixtures de propiedad desconocida, item desconocido, metadata desconocida,
  grupo ausente, arquitectura duplicada, capability inválida, URL/hash/tipo
  inválidos;
- `Generate-BrandAssets.ps1 -Check`;
- auditoría literal que incluya Product ID, PFN, artifact type, arquitecturas,
  packing base, capabilities, CLI version/hash e icon sizes;
- construir el Store bundle x64 + ARM64 y verificar que cambiar una fixture de
  arquitectura/target solo cambia lo esperado y no exige editar otro archivo.

**Completion evidence:** parser estricto, zero duplicate active literals,
fixtures negativas PASS y proyecciones positivas verificadas.

**Allowed discretion:** funciones privadas de validación y forma de reportar
las propiedades desconocidas.

**Replan triggers:** MSBuild necesita metadata que el schema no puede expresar;
el package type/arquitectura real difiere del contrato; o corregir el builder
requiere cambiar el formato de distribución.

## Milestone 3 — CLI y máquina de estados Store

**Outcome:** la instalación del CLI y las transiciones Store son fail-closed,
reanudables y comprobables offline.

**Entry conditions:** Step 2 completo; fixture del output real o read-only del
CLI disponible, sin credenciales persistidas.

**Exit conditions:** C4/C5 pasan casos de no submission, pending exacto,
conflictivo, activo, fallido y retry transitorio.

**Validation gate:** V5, V6 y V7.

### Step 3 — Corregir instalador, preflight, correlación y retries

**Status:** `NOT_STARTED`

**Objective:** asegurar que ninguna mutación Store ocurra con una versión,
submission o paquete incorrectos.

**Requirements:** R6, R9, R10, R11, R12, R18.

**Location:** `scripts/Install-MicrosoftStoreCli.ps1`;
`scripts/modules/Echo.StoreSubmission.psm1`;
`scripts/Invoke-MicrosoftStoreRelease.ps1`;
tests/fixtures Store.

**Changes:**

- corregir la interpolación PowerShell de la versión y añadir un parser
  regression test;
- separar la descarga/hash fijado del checksum opcional del publisher; una
  discrepancia explícita debe lanzar error y no caer en el catch de “archivo no
  disponible”; definir si la ausencia del endpoint publisher es warning
  permitido o bloqueo, preservando siempre el digest fijado como requisito;
- usar un wrapper de proceso que implemente el retry declarado, clasifique
  429/5xx/transitorios y no reintente errores permanentes;
- hacer que `Get-EchoStoreSubmissionState` retorne una representación explícita
  de ausencia de submission y de los campos de versión/package/hash;
- obtener la última versión publicada con el comando/endpoint read-only real,
  sin pasar `$current.State` como versión;
- permitir `upload` solo para `NoSubmission` y target estrictamente mayor;
- permitir `commit-resume` solo si la submission pendiente coincide con target
  version, package identity, bundle name y hash;
- dejar estados de procesamiento como monitor-only; fallos, cancelaciones y
  estados desconocidos deben fallar cerrado;
- proteger `delete-target-draft` con tag/versión/hash exactos y un input
  explícito; no añadir borrado automático como recovery default;
- conservar la separación configure/preflight/no-commit publish/verify/commit.

**Rationale:** la ejecución actual aparenta tener una máquina de estados, pero
mezcla un enum textual con una versión y no verifica el target pendiente.

**Dependencies:** Step 2 y D4; disponibilidad de una forma de simular el CLI.

**Invariants:** I3, I4, I6, I9, I10.

**Validation:**

- parser de todos los scripts y modules;
- fixtures para no submission, Published con target mayor/igual/menor,
  PendingCommit coincidente y conflictivo, estados activos, fallos y unknown;
- tests de retry: éxito inmediato, 429/5xx agotado, error auth/validation sin
  retry;
- comprobar que los comandos mutantes no son invocados en casos fail-closed;
- comprobar redacción de secrets en errores y reportes.

**Completion evidence:** cada estado tiene una acción única y comprobada; no
hay conversión de estados a `[version]`; el retry count se consume realmente;
los casos conflictivos no ejecutan publish/commit/delete.

**Allowed discretion:** implementación del backoff y del adaptador de campos
si el CLI entrega aliases equivalentes documentados por fixture.

**Replan triggers:** el CLI no expone versión/hash del pending target; el
endpoint de versión publicada no es read-only; o la única operación disponible
requiere una mutación destructiva para descubrir el estado.

## Milestone 4 — Release, provenance y publicación por workflow

**Outcome:** los workflows usan el commit real, parsean API correctamente,
validan bytes exactos y recuperan publicaciones compatibles sin duplicarlas.

**Entry conditions:** Steps 2 y 3 completos; módulo/seams de Step 1 listos.

**Exit conditions:** C1–C7 pasan simulaciones offline y actionlint.

**Validation gate:** V8, V9 y V10.

### Step 4 — Corregir resolución GitHub, idempotencia y payload provenance

**Status:** `NOT_STARTED`

**Objective:** unir el tag, el release, los artifacts y el Store submission por
  una identidad verificable.

**Requirements:** R2, R3, R4, R5, R7, R8, R13, R16.

**Location:** `.github/workflows/release.yml`;
`.github/workflows/store-publish.yml`;
`scripts/modules/Echo.GitHubRelease.psm1` si aplica;
`scripts/New-EchoReleaseManifest.ps1`;
`scripts/Test-StoreReleaseArtifact.ps1`.

**Changes:**

- centralizar `gh api` raw JSON parsing y convertir arrays/objects después de
  recibir el documento completo;
- resolver tags ligeros y anotados hasta commit con validación de tipo, SHA,
  tag name y versión;
- exigir que CI exact-SHA busque el commit real y que cada job checkout ese SHA;
- hacer que el Store workflow resuelva el mismo release/tag/SHA y haga checkout
  de esa revisión en los jobs que consumen scripts, en lugar de usar
  `target_commitish` como autoridad;
- reemplazar siempre-create-draft por lectura de release existente: compatible
  estable => verificar/no-op; draft/prerelease/conflict => fail-closed; ausente
  => crear draft una sola vez;
- después de upload, obtener assets como array JSON y comparar el set exacto,
  incluyendo filename, role, size y hash;
- hacer que `SHA256SUMS.txt` se valide por la pareja exacta `filename -> hash`;
- hacer que `Test-StoreReleaseArtifact.ps1` invoque la validación completa del
  manifest y compare cada asset record con el archivo descargado, el package
  identity/PFN, Store version, capabilities, architecture set y source SHA;
- después de `actions/download-artifact`, recalcular y validar el hash contra el
  manifest/checksum exacto antes de instalar el CLI o mutar Store;
- mantener `msixbundle`, x64/ARM64 y las recetas actuales sin introducir una
  segunda fuente de configuración;
- mantener los SHA de actions literales y revisar el composite de setup según
  R16.

**Rationale:** el flujo actual valida principalmente nombres y presencia, no la
  relación criptográfica y de commit que pretende garantizar.

**Dependencies:** Steps 1–3; D2/D3/D6.

**Invariants:** I2–I7, I9, I10.

**Validation:**

- tests para `gh api` con array/objeto/multilínea, tag ligero/anotado y tag
  inexistente;
- tests para release compatible, release conflictivo, draft/prerelease y
  creación única;
- alterar un byte del bundle, intercambiar un nombre de asset, cambiar un hash,
  source SHA, Product.props hash o manifest version y verificar fail-closed;
- `actionlint` en todos los workflows;
- auditoría que no encuentre `ConvertFrom-Json` aplicado a salida por elemento;
- workflow static audit de Product ID/PFN/artifact type/architectures/packing
  base/CLI coordinates;
- ejecutar build de distribución Store local y `Test-StoreReleaseArtifact` con
  manifest/checksums generados.

**Completion evidence:** un release compatible se recupera sin duplicación,
uno conflictivo se detiene, el Store job no puede aceptar bytes cuyo hash o
  commit difiera y la validación de actions pasa.

**Allowed discretion:** ubicación exacta del helper compartido si se conserva
  una sola implementación comprobable y no se duplica el parser.

**Replan triggers:** GitHub API no permite obtener el asset set/hashes requeridos
  con el token de workflow; los tags anotados requieren una API distinta a la
  disponible; o Partner Center exige un package contract distinto del actual.

## Milestone 5 — Documentación, gates y cierre de calidad

**Outcome:** implementación, documentación y evidencia reflejan el mismo
  contrato y todos los gates locales pasan sin ejecutar publicación live.

**Entry conditions:** Steps 1–4 completos.

**Exit conditions:** compliance matrix totalmente VERIFICADA, CP final y
  handoff listo para autorización operator-gated.

**Validation gate:** V11 y V12.

### Step 5 — Actualizar documentación y corregir la evidencia del plan anterior

**Status:** `NOT_STARTED`

**Objective:** eliminar ambigüedades y referencias que podrían llevar a operar
  una ruta ya eliminada.

**Requirements:** R17, R18.

**Location:** `docs/public/publishing/microsoft-store.md`;
`docs/store/README.md`;
traceability de Store CD; `.agents/rules/releases.md` si el contrato cambió;
plan archivado de Store CD; plan e INDEX actuales.

**Changes:**

- documentar resolución de tag, idempotencia, hash exacto, preflight Store,
  retry y recovery seguro;
- eliminar o marcar como histórico cualquier referencia activa a StoreBroker,
  `branding.json` u otros entry points eliminados;
- corregir la matriz/checkpoints del plan archivado sin borrar el registro de
  que la ejecución original fue parcial; enlazar la nueva corrección;
- si se modifica una especificación normativa o requirement, activar
  `req-traceability` durante la ejecución y generar su reporte correspondiente;
- no incluir valores de secrets, tokens o rutas privadas.

**Rationale:** una automatización corregida sigue siendo peligrosa si la guía o
la evidencia dice que una ruta distinta es la oficial.

**Dependencies:** resultados de Steps 2–4.

**Invariants:** I2, I4, I6, I10.

**Validation:** enlaces locales, búsqueda de referencias activas obsoletas,
`git diff --check`, revisión de consistencia entre plan/index/docs/workflows.

**Completion evidence:** documentación operativa coincide con el código y la
matriz no contiene PASS sin comando/evidencia correspondiente.

**Allowed discretion:** redacción y estructura local, preservando términos
exactos de comandos/inputs.

**Replan triggers:** la documentación revela que el contrato aprobado era
distinto; una especificación exige cambiar la arquitectura; o el plan anterior
no puede corregirse sin alterar su historial.

### Step 6 — Ejecutar el quality gate y dejar handoff operator-gated

**Status:** `NOT_STARTED`

**Objective:** demostrar que la corrección está lista para una revisión humana,
sin afirmar que Partner Center fue publicado.

**Requirements:** R1, R6, R13–R19.

**Location:** quality gate del repositorio, workflows, scripts, tests y plan.

**Changes:**

- ejecutar todos los comandos de V1–V12 en orden de dependencia;
- registrar los hashes/versiones y resultados, no logs completos innecesarios;
- dejar explícitos los checks que requieren credenciales, Partner Center o
  ejecución live como `BLOCKED/OPERATOR-GATED`, nunca como PASS;
- actualizar `Current State Snapshot`, compliance matrix, checkpoint final y
  Handoff Snapshot.

**Rationale:** build local y actionlint no prueban la respuesta real del CLI ni
  autorizan una publicación.

**Dependencies:** Steps 1–5.

**Invariants:** I1–I10.

**Validation:** V1–V12; ver sección de validación.

**Completion evidence:** todos los requirements locales están `VERIFIED`, los
  gates externos están separados y no hay desviaciones abiertas.

**Allowed discretion:** orden de comandos equivalentes y ubicación de logs
  temporales ignorados.

**Replan triggers:** cualquier fallo local, diferencia de contract, secret
  expuesto, cambio de package type/identity o resultado externo incompatible.

## Validation and State

### Validation Strategy

| ID | Validation | Expected result |
|---|---|---|
| V1 | `git status`, branch/HEAD/merge-base y presencia de `.agents/` | baseline reconciliado con `91eebe9` o replan trigger |
| V2 | parser PowerShell de scripts/modules modificados | cero errores de parseo |
| V3 | `scripts/Test-ProductConfiguration.ps1 -AsJson` y fixtures invalidas | schema actual PASS; invalidas fallan con mensaje específico |
| V4 | `scripts/Generate-BrandAssets.ps1 -Check` y literal audit ampliado | assets PASS y duplicaciones prohibidas = 0 |
| V5 | tests del instalador con versión/checksum mismatch | mismatch falla; ausencia permitida solo según política documentada |
| V6 | tests del Store adapter con fixtures de todos los estados | acción segura correcta y mutaciones bloqueadas cuando corresponde |
| V7 | tests de retry y redaction | retry limitado; auth/validation no retry; secretos ausentes |
| V8 | tests de API/tag/release/asset provenance | JSON, tag, idempotencia y conflictos correctos |
| V9 | `actionlint` sobre todos los workflows y composite audit | PASS sin referencias no fijadas fuera de excepciones documentadas |
| V10 | build Store local + `Test-StoreReleaseArtifact` + hash exacto | bundle actual x64/ARM64 y manifest/checksums coinciden byte a byte |
| V11 | `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` y `dotnet test` | regresión de producto = 0 |
| V12 | quality gate, `git diff --check`, links/reference scan y compliance audit | plan/documentación válidos; nada declarado PASS sin evidencia |

### Compliance matrix

| Requirement | Implementation | Validation | State | Evidence |
|---|---|---|---|---|
| R1 | Step 1 | V1 | PENDING | — |
| R2 | Step 4 / C1 | V2, V8 | PENDING | — |
| R3 | Step 4 / C1–C3 | V8 | PENDING | — |
| R4 | Step 4 / C2–C3 | V8 | PENDING | — |
| R5 | Step 4 / C2, C6, C7 | V8, V10 | PENDING | — |
| R6 | Step 3 / C4 | V2, V5 | PENDING | — |
| R7 | Step 4 / C6–C7 | V10 | PENDING | — |
| R8 | Step 4 / C3 | V8 | PENDING | — |
| R9 | Step 3 / C5 | V6 | PENDING | — |
| R10 | Step 3 / C5 | V6 | PENDING | — |
| R11 | Step 3 / C5 | V7 | PENDING | — |
| R12 | Step 3 / C5 | V6 | PENDING | — |
| R13 | Step 2 / C6–C8 | V3, V4, V10 | PENDING | — |
| R14 | Step 2 / C9 | V3 | PENDING | — |
| R15 | Step 1 / C10 | V5–V8 | PENDING | — |
| R16 | Step 4 / C11 | V9 | PENDING | — |
| R17 | Step 5 / C12 | V12 | PENDING | — |
| R18 | Steps 3–6 | V1, V7, V12 | PENDING | — |
| R19 | All steps | V10–V12 | PENDING | — |

### Replan Triggers

- `91eebe9` no es ancestro o la implementación integrada cambió package type,
  identity, architecture set, version algorithm o workflow contract.
- El CLI no entrega estado/versión/package/hash suficiente para cumplir R9/R10
  mediante comandos read-only.
- GitHub API no entrega assets/hashes o commit real con los permisos disponibles.
- Corregir un defecto requiere modificar Rust/C#/XAML/DSP/FFI/WASAPI/Win2D o
  el producto distribuido.
- La compatibilidad real de Partner Center contradice el contrato `.msixbundle`
  x64/ARM64 y exige un nuevo package design.
- Se descubre que un secret/token fue escrito, expuesto o incluido en un
  artifact.
- Un test requiere mutar una submission real para poder conocer su estado.

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| API/CLI schema differs from fixtures | High | read-only discovery, fixture contract and replan trigger |
| Existing release has assets from prior implementation | High | exact identity comparison; conflict is fail-closed |
| Tag is annotated | High | recursive tag dereference and dedicated regression test |
| Retry hides a permanent failure | High | classify errors, cap attempts, retain sanitized reason |
| Central config cleanup breaks build | Medium | projection tests, local bundle build and no product-source changes |
| `dev` lacks target implementation | High | explicit baseline precondition before execution |
| External Partner Center state differs | High | operator-gated read-only check; no automatic delete/submit |

# Living Execution Record

## Progress

- M1: `IN_PROGRESS`
- M2: `NOT_STARTED`
- M3: `NOT_STARTED`
- M4: `NOT_STARTED`
- M5: `NOT_STARTED`
- Current step: Step 1
- No implementation changes have been made by plan authoring.

## Checkpoint Ledger

### CP-003 — 2026-08-11

- **Plan status:** `IN_PROGRESS`
- **Verification state:** `VERIFIED` (validated at this checkpoint; becomes STALE on next mutation)
- **Active milestone:** M4
- **Active step:** Step 4
- **Repository revision:** `ci/release-cd-hardening`
- **Working tree:** implementation changes staged/committed per step
- **Changes since CP-002:** Step 1 committed as `7f0f931`; Step 2 (R13 centralization in Build-Distributions/New-EchoReleaseManifest/Test-StoreReleaseArtifact) and Step 3 (R6 installer, R9-R12 state adapter consumers, retry/redaction) implemented
- **Validation performed:** parser check now ZERO failures across all scripts/modules (installer `$expectedVersion:` fixed); Test-StoreReleasePipeline PASS; Test-ReleaseHardening PASS (R2-R6, R9-R11, R13, R14); Generate-BrandAssets -Check PASS; distribution literal audit PASS; Test-ProductConfiguration -AsJson correct; offline Store bundle + regenerated manifest validated via Test-StoreReleaseArtifact (V10-style)
- **Validation result:** PASS for M2/M3 scope
- **Conformance state:** CONFORMING
- **Compliance changes:** R6, R9, R10, R11, R12 → VERIFIED (offline); R13, R14 → VERIFIED; R2/R3/R4/R5 partial (module + fixtures verified; workflow wiring pending in Step 4)
- **Open deviations:** None
- **Blockers:** None (offline); Partner Center live gates remain operator-gated
- **Next exact action:** rewrite release.yml (C2) and store-publish.yml (C3) on Echo.GitHubRelease.psm1 with real SHA checkout in consuming jobs, exact-hash payload verification (C7), and remove `.items[]`→ConvertFrom-Json patterns

### CP-002 — 2026-08-11

- **Plan status:** `IN_PROGRESS`
- **Verification state:** `VERIFIED` for the reconciled baseline
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `ci/release-cd-hardening` at `91eebe9` (descendant of the audited implementation, `.agents/` present)
- **Working tree:** `dev` integrated the audited implementation; branch `ci/release-cd-hardening` created carrying user changes (deleted attachment, INDEX registration for this plan)
- **Changes since CP-001:** execution branch created; plan index registers this plan as Active; baseline commands run
- **Validation performed:** `git merge-base --is-ancestor 91eebe9 HEAD` (exit 0, ancestor confirmed); parser baseline on all audited scripts (11 files, exactly one defect: `Install-MicrosoftStoreCli.ps1:99` `$expectedVersion:`); `actionlint` PASS; existing `Test-StoreReleasePipeline.ps1` PASS (2 groups) but does not cover audited GitHub/Store defects
- **Validation result:** PASS for baseline reconciliation; new regression coverage is a Step 1 deliverable
- **Conformance state:** CONFORMING
- **Compliance changes:** R1 baseline satisfied; all requirements remain PENDING
- **Open deviations:** None
- **Blockers:** None (offline); Partner Center live gates remain operator-gated
- **Next exact action:** create regression fixtures for R2–R5, R9–R11, R14 and the shared `Echo.GitHubRelease.psm1` module skeleton before touching workflows

### CP-001 — 2026-08-11

- **Plan status:** `READY`
- **Verification state:** `VERIFIED` for plan authoring
- **Active milestone:** M1
- **Active step:** Step 1
- **Repository revision:** `dev` at `6a1ed44`; audited implementation at `91eebe9`
- **Working tree:** clean on `dev` at authoring time
- **Changes since previous checkpoint:** initial plan creation
- **Validation performed:** read `.agents/AGENTS.md` from the audited control branch; read implementation-plan-authoring, ci-cd-and-automation, project context, architecture, conventions, handoff, plan index and archived Store CD plan; reconciled audited workflow/script findings against source locations
- **Validation result:** PASS for plan completeness; implementation not executed
- **Conformance state:** CONFORMING for authoring scope
- **Open issues:** execution must first reconcile the target implementation branch; external Store gates remain operator-gated
- **Next exact action:** on a descendant of `91eebe9`, run Step 1 baseline commands and create/execute the regression fixtures before changing workflows or scripts

## Surprises & Discoveries

### DISC-001 — Planning branch predates the audited implementation

**Observed:** `dev` is at `6a1ed44` and does not contain the `.agents/` control
files or the Store CD implementation that was audited at `91eebe9`.

**Evidence:** branch/tree inspection and `git show ci/microsoft-store-release-cd:<path>`.

**Impact:** executing this plan directly on the current `dev` baseline would
not address the audited code and would force an unintended reconstruction.

**Plan effect:** execution precondition; replan if the target is not integrated
without preserving the audited contract.

### DISC-002 — Offline validation cannot prove Partner Center state

**Observed:** local build/tests succeed, but no authenticated read-only
Partner Center query or first live submission was available.

**Evidence:** archived Store CD handoff and release policy.

**Impact:** external state must remain a separate operator gate.

**Plan effect:** no change; V6/V7 use fixtures and Step 6 records the live gate
as operator-gated.

## Decision Log

Initial decisions are recorded in D1–D7. No post-authoring decision has been
made.

## Plan Deviations

None at authoring time.

## Validation Evidence

### Authoring evidence

- The previous implementation branch and archived plan were inspected before
  authoring this corrective plan.
- The known parser, workflow, provenance, Store state and centralization faults
  are represented by requirements, change map entries, steps and validations.
- No implementation, workflow, product or external Store changes were made.

### Required execution evidence

Execution must append command/result summaries for V1–V12 here and attach only
sanitized artifact paths or workflow run identifiers. Full secrets and raw
credential-bearing logs are prohibited.

## Handoff Snapshot

**Last safe checkpoint:** `CP-001`

**Current repository state:** planning artifact authored on `dev` at `6a1ed44`;
audited implementation remains on `ci/microsoft-store-release-cd` at `91eebe9`.

**Completed:** plan discovery, audit reconciliation, scope, decisions,
requirements, change map, validation contract and initial checkpoint.

**In progress:** none; authoring ends at `READY`.

**Next exact action:** switch to or create an execution branch descended from
`91eebe9`, verify `.agents/AGENTS.md`, read this plan completely, run Step 1
baseline and fixtures, then proceed only if R1 holds.

**Do not repeat:** do not treat the previous plan's local build, Rust/.NET
tests or actionlint PASS as evidence that release JSON parsing, Store preflight
or live Partner Center behavior works.

**Pending validation:** all V1–V12; external Partner Center read-only status and
first authorized stable release remain outside offline execution.

**Open discoveries:** `DISC-001`, `DISC-002`.

**Open decisions:** none beyond D1–D7.

**Open deviations:** none.

**Known blockers:** target branch integration and external operator gates.

**Files currently relevant:** workflows in `.github/workflows/`,
`scripts/Install-MicrosoftStoreCli.ps1`, `scripts/modules/`, distribution
scripts, `tests/scripts/`, `build/Product.props`, publishing docs and the
archived prior plan.

**Commands needed to resume verification:**

```powershell
git fetch --prune
git status --short --branch
git merge-base --is-ancestor 91eebe9 HEAD
Get-Content .agents\AGENTS.md -Raw
Get-Content docs\public\plans\active\2026-08-11--microsoft-store-release-cd-hardening.md -Raw
```

# Completion

## Completion Criteria

- [ ] R1–R19 are `VERIFIED` or explicitly marked `BLOCKED` only for external
      operator gates that are not part of offline implementation.
- [ ] All modified PowerShell files parse successfully.
- [ ] All GitHub workflows pass actionlint and the no-line-JSON audit.
- [ ] GitHub release recovery is idempotent for an exact compatible release and
      fail-closed for conflicts.
- [ ] Store preflight, correlation, retry and recovery tests pass.
- [ ] Store bundle, manifest, checksum and central configuration validation pass.
- [ ] Rust/.NET regression gates remain green with no product source changes.
- [ ] Documentation and the previous plan's evidence are internally coherent.
- [ ] No secrets/tokens are present in the diff, fixtures or artifacts.
- [ ] Final checkpoint and Handoff Snapshot are current.
- [ ] The plan remains non-terminal until explicit execution and final audit are
      completed; authoring does not authorize publishing.

## Outcomes & Retrospective

To be completed during execution. It must state which audit findings were
resolved, which external gates remain operator-gated, and whether any replan was
required. It must not claim a live Microsoft Store submission unless the user
explicitly authorizes it and the evidence is recorded.

