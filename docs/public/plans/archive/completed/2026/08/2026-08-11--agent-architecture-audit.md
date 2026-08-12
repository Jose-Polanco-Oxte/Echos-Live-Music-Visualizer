# Auditoría y saneamiento de la arquitectura agéntica

## Plan Metadata

| Field | Value |
|---|---|
| Plan ID | `PLAN-20260811-AGENT-ARCHITECTURE-AUDIT` |
| Status | `COMPLETE` |
| Verification state | `VERIFIED_WITH_DOCUMENTED_ENVIRONMENT_BLOCKER` |
| Created | 2026-08-11 |
| Last updated | 2026-08-11 |
| Owner | Repository maintainer |
| Authorized branch | `docs/agent-architecture-audit` |
| Planning baseline | `chore/plan-system-migration` at `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe` |
| Integration branch | `dev` |
| Initial checkpoint | `CP-001`; latest `CP-005` |

## Objective

Auditar y corregir la capa operativa de agentes del repositorio para que un
clon limpio pueda activar el pipeline, resolver únicamente referencias reales,
usar las skills disponibles según la fase de trabajo y ejecutar las
herramientas documentadas. Alinear también el contexto técnico, la
investigación del stack y la especificación funcional con el estado actual del
proyecto.

El trabajo no modifica la arquitectura ni el comportamiento del producto:
Rust DSP, captura WASAPI, ABI/FFI, WinUI 3, Win2D, renderizado y contratos de
audio permanecen fuera de alcance. Los cambios se limitan a gobierno operativo,
documentación, especificación vigente, trazabilidad y tooling de agentes.

## Current State Snapshot

- **Status:** `COMPLETE`
- **Verification state:** `VERIFIED_WITH_DOCUMENTED_ENVIRONMENT_BLOCKER`
- **Active step:** none; `S6` completed.
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`.
- **Execution branch:** `docs/agent-architecture-audit`, created from the
  recorded baseline.
- **Working tree:** contains task-owned `.agents/` and `docs/public/` changes;
  no product source or test files were modified.
- **Completed steps:** `S1`, `S2`, `S3`, `S4`, `S5`.
- **Last checkpoint:** `CP-005`.
- **Next action:** archived plan is the source of completion state.
- **Open validation condition:** the checkout lacks `build/Product.props`, so
  the UI portion of the quality gate cannot compile; the gate now reports this
  prerequisite explicitly. Rust and the independent .NET test project pass.

## Progress

| Step | Description | Requirements | Status |
|---|---|---|---|
| `S1` | Verify baseline and create the authorized branch. | `R1`, `R9` | `DONE` |
| `S2` | Establish the mixed visibility and bootstrap boundary. | `R1`, `R2`, `R8` | `DONE` |
| `S3` | Rewrite mandatory rules and skill routing. | `R2`, `R3` | `DONE` |
| `S4` | Add role catalog and make loader/tools executable. | `R4`, `R5`, `R10` | `DONE` |
| `S5` | Align context, specifications and audit evidence. | `R6`, `R7` | `DONE` |
| `S6` | Run final conformance validation and archive the plan. | `R1`–`R10` | `DONE` |

## Scope and Non-Goals

### In scope

- Create `docs/agent-architecture-audit` from the planning baseline.
- Make the reproducible operational contracts under `.agents/` versionable.
- Keep local state and personal execution artifacts outside the public contract.
- Correct stale paths, invalid skill names, missing script dependencies and
  documented commands that cannot run from the repository root.
- Rewrite `general.md` and related rules around the skills that actually exist.
- Reconcile bootstrap, branch, plan, handoff, compaction, testing and release
  instructions.
- Audit the complete active specification and update it to current behavior.
- Preserve a separate audit/removal register for obsolete code and historical
  items; do not put implementation-removal history in the normative spec.
- Update stack research, architecture context and requirement traceability.

### Out of scope

- Any Rust, C#, XAML, shader, FFI, DSP, audio-capture or rendering behavior
  change.
- Removal of the retained visualizer members unless a later product-code task
  explicitly authorizes it.
- Changes to package versions, product architecture, Store/release behavior,
  external integrations, credentials or plugins.
- Commit, push, tag, pull request, release or Store publication.
- Treating ignored local state, generated snapshots, benchmark output or
  historical plans as public source-of-truth documentation.

## Requirements

| ID | Requirement | Verification |
|---|---|---|
| `R1` | A clean checkout contains the stable agent bootstrap, context, rules, skills and deterministic scripts required by the documented pipeline. | Git tracking/ignore audit and clean-checkout path validation. |
| `R2` | The bootstrap and rules resolve only existing paths and current branch/release contracts; the required local handoff is optional with a documented template fallback. | Active-reference scan and bootstrap inspection. |
| `R3` | `general.md` routes every request through `using-agent-skills`, routes non-trivial work through the persistent plan lifecycle, and selects conditional skills only when their trigger applies. | Skill catalog audit and directive inspection. |
| `R4` | Subagent execution is truthful and safe: the model selects zero, one or multiple matching role definitions from `.agents/roles`, never treats root `AGENTS.md` as a role, and can continue with an explicitly declared task-local role when no catalog role fits. | Loader/CLI checks with zero, single and multiple role selection, ad-hoc role context and invalid explicit-role assertions. |
| `R5` | Quality-gate, toolchain, compaction and benchmark commands are executable from documented locations and fail clearly when prerequisites are absent. | PowerShell parse checks plus targeted command execution. |
| `R6` | Current project context and stack research match the repository's actual Rust/.NET/WinUI/Win2D implementation without changing that implementation. | Source/project-file comparison and documentation review. |
| `R7` | The normative specification describes current observable/product behavior only; historical removals and code-review candidates live in a separate audit register. | Full spec audit, diff review and traceability report. |
| `R8` | No secrets, machine-specific state or private handoff content enters versioned agent contracts or public documentation. | Path classification, secret/local-path scan and final diff review. |
| `R9` | The final change set contains no product architecture changes and passes the applicable repository validation gates. | Scoped diff, `git diff --check`, quality gate and plan conformance review. |
| `R10` | The project has a usable candidate role catalog covering general execution, agent-architecture audit, Rust/DSP, WinUI/visualization, requirements/traceability and quality validation, while allowing model-defined task-local roles. | Role inventory, frontmatter validation, zero/single/multiple-role selection and ad-hoc role-context checks. |

## Locked Decisions and Invariants

1. **Mixed visibility for `.agents/`.** Version stable, reproducible contracts:
   `.agents/AGENTS.md`, `context/`, `rules/`, `skills/` and deterministic tool
   sources/documentation. Keep `.agents/state/`, task handoffs, context
   snapshots, benchmark `target/`, benchmark results, scratch files and
   credentials local/ignored. A clean checkout must still run the bootstrap
   using an optional handoff and a checked-in template.
2. **Branch policy.** Create `docs/agent-architecture-audit` from the exact
   planning baseline. Use `dev` as the integration branch and `main` only for
   releases; direct `dev` to `main` integration remains forbidden. An explicit
   task branch is permitted even though `dev` is the normal development base.
3. **Current specification semantics.** `docs/public/spec/requirements-spec.md`
   contains current normative behavior, not a changelog or deletion list. The
   historical RF-EQ.5 removal statements and implementation filenames are
   removed from the normative section. The separate audit report records what
   was checked, what is absent, what is retained outside the UI contract and
   what would require a future code task.
4. **Retained visualizer members.** The active visualizer's legacy-named
   properties and the gap helper are not removed in this task. The audit report
   classifies them as internal/out-of-contract or review candidates; the spec
   describes only the current user-visible controls and behavior.
5. **Skill routing.** `using-agent-skills` is mandatory for every agent/model
   execution. `implementation-plan-authoring` is mandatory for non-trivial
   planning; `plan-conformance-execution` is mandatory only after execution is
   authorized. `req-traceability` is mandatory for requirement, formula or
   specification changes. `report-writer` is used for the audit report.
   `sub-agents-execution` is conditional on an explicit delegation and a real
   role definition; `multitask-coordinator` remains explicit-invocation only.
6. **No invented capabilities.** Absent upstream skill names, missing
   references and provider-specific workflows are removed or rewritten to the
   local catalog; they are not silently assumed to exist.
7. **Role catalog and launch semantics.** `.agents/roles/` is a catalog for
   model-selected specializations, not a switch that turns agent execution on
   or off. Add the following versioned candidate roles:
   `general-project-engineer`, `agent-architecture-auditor`,
   `rust-dsp-specialist`, `winui-visualizer-specialist`,
   `requirements-traceability-maintainer` and `quality-gate-validator`.
   `general-project-engineer` is a selectable role for broad project work, not
   an automatic fallback. Before delegating, the model records a role decision:
   no role, one role, multiple compatible roles, or an ad-hoc role synthesized
   for the task. An empty catalog does not prohibit launching an agent. If an
   explicitly requested catalog role is missing, report that fact; if the model
   selected it as only an approximate match, synthesize the task-local role
   instead of silently substituting another role.
8. **Role composition.** The launcher accepts a repeatable role argument and
   composes the selected descriptors in the order chosen by the model. Shared
   project rules and user instructions always override role text. If selected
   roles conflict, the model must resolve the conflict in a task-local
   composite role or trigger replanning when the conflict changes scope,
   architecture or externally observable behavior. A role descriptor is never
   required for launching a generic agent.
9. **Evidence ownership.** The living plan owns execution checkpoints and
   validation evidence. The public audit report owns durable findings and the
   obsolete/removal register. `PROJECT-HANDOFF.md` owns only concise global
   state; local handoff files remain resumability artifacts.

## Findings That Drive the Change Map

- `.agents/` is globally ignored, while the bootstrap treats it as mandatory;
  therefore a clean checkout cannot activate the documented pipeline.
- Root `AGENTS.md` names `Build-Distribution.ps1`, but the real script is
  `scripts/Build-Distributions.ps1`.
- `general.md` names the nonexistent
  `.agents/skills/subagent-work-divider/SKILL.md`.
- `testing.md` is empty, and `Invoke-QualityGate.ps1` calls the missing
  `Test-Toolchains.ps1`.
- `using-agent-skills` lists absent skills and a missing Definition of Done
  reference; it does not describe the local catalog accurately.
- The subagent loader scans `.agents/` and reports the bootstrap `AGENTS.md` as
  an agent; the real role directory is empty and no project role catalog exists.
- The current delegation contract assumes one named definition and has no
  protocol for selecting multiple roles or synthesizing a task-local role.
- Release rules contain stale `docs/pending-features/`, `docs/traceability/`
  and misspelled `PROYECT-HANDOFF.md` references.
- Architecture context names `Win2DSpectralBarVisualizer` and
  `CompositionTarget.Rendering`, while the active code uses
  `Win2DGpuSpectralBarVisualizer`, `CanvasControl.Draw` and a dispatcher timer.
- `stack-tech-research.md` describes obsolete or unselected versions and
  dependencies (`cpal`, Win2D UWP 1.28.1, wasapi 0.13.0, mixed .NET 8/9), while
  the project uses the versions in the current project manifests.
- Several secondary skills contain invalid output paths or executable claims:
  decision records target `.agents/status`, CI specifications target `/spec`,
  issue validation calls a nonexistent script, and the automation skill has a
  relative sibling-path error.
- The benchmark README invokes a root-level `scripts/Run-DspBenchmark.ps1`,
  but the executable lives under `.agents/tools/scripts/`.
- The normative RF-EQ.5 text contains historical removal statements and source
  filenames even though the current specification must describe the present
  product state.

## Change Map

### C1 — Bootstrap, repository visibility and local-state boundary

- Update root `AGENTS.md` to use the plural distribution script name and to
  document the mixed `.agents/` visibility policy without weakening the
  mandatory bootstrap.
- Update `.gitignore` so stable `.agents/` contracts and deterministic scripts
  can be tracked while state, handoffs, snapshots, generated benchmark output,
  scratch data and secrets remain ignored.
- Update `.agents/AGENTS.md` so missing local `PROJECT-HANDOFF.md` falls back to
  a checked-in template and is reported as local state, rather than making a
  clean checkout fail before any work can start.
- Add/update the checked-in handoff template with no personal paths, release
  credentials or machine-specific state.

### C2 — Mandatory rules and skill routing

- Rewrite `.agents/rules/general.md` as the authoritative always-on rule set:
  repository truth, mandatory skill discovery, plan lifecycle, conditional
  traceability/reporting, subagent safety, context loading, validation,
  privacy, scope control and compaction persistence.
- Populate `.agents/rules/testing.md` with current .NET/Rust commands,
  toolchain prerequisites, documentation/tooling-only validation expectations,
  physical-device limitations and failure-reporting rules.
- Correct `.agents/rules/skills.md`, `git.md`, `releases.md`,
  `context-management.md` and `plan-execution.md` where their paths or
  precedence conflict with the bootstrap or current plan system.
- Remove the incomplete changelog sentence and replace it with a precise
  release-documentation rule.
- Rewrite `.agents/skills/using-agent-skills/SKILL.md` to reference only the
  local root/sub-skill catalog, its actual conditional triggers and current
  project verification contract.

### C3 — Skill and subagent executability

- Change subagent loader defaults, documentation and examples to use
  `.agents/roles`; ensure it never discovers `AGENTS.md` as a role. Add the
  six candidate roles named in the role-catalog decision without designating
  any automatic fallback.
- Update `run_subagent.py` so `--agent` is optional and repeatable. With zero
  role arguments it launches with the normal project bootstrap and no role
  overlay; with one or more role arguments it loads and composes those
  descriptors in the supplied order. Preserve `--agents-dir` for isolated
  catalogs. A missing explicitly named role is an error, while an ad-hoc role
  is represented in the task prompt/context and does not require a catalog
  file.
- Define each role with a bounded objective, required context, allowed skill
  set, permission level, forbidden scope and output contract. Use read-only
  permissions for audit/validation roles and safe-edit only for roles whose
  purpose includes documentation or implementation changes; every role still
  inherits `general.md` and the explicit no-product-architecture constraint.

The role descriptors must be created at `.agents/roles/<role-name>.md` with
stable names and these responsibilities:

| Role | Permission | Responsibility | Required output |
|---|---|---|---|
| `general-project-engineer` | `safe-edit` | Default project work across Rust, C#, XAML, scripts and docs while obeying the selected plan and scope. | Changed paths, validation evidence, risks and next action. |
| `agent-architecture-auditor` | `read-only` | Inspect `.agents/`, active instructions, skill references, scripts, role loading and public/private boundaries. | Findings table with evidence, severity, disposition and replan triggers. |
| `rust-dsp-specialist` | `safe-edit` | Work on Rust DSP, WASAPI integration, FFI contracts and Rust tests when a task explicitly includes those surfaces. | Technical changes, invariants, test results and any audio/runtime limitation. |
| `winui-visualizer-specialist` | `safe-edit` | Work on WinUI 3, Win2D, visualizer lifecycle, UI bindings and UI tests when explicitly scoped. | UI behavior impact, accessibility/theming checks and validation evidence. |
| `requirements-traceability-maintainer` | `safe-edit` | Maintain current specifications, formulas, traceability reports and decision documentation without inventing behavior. | Normative diff, source mapping, unresolved ambiguity list and traceability result. |
| `quality-gate-validator` | `read-only` | Run and interpret PowerShell, .NET, Rust, documentation and agent-contract validation. | Command log summary, pass/skip/fail status and reproducible failure details. |

Role descriptors may reference the corresponding project skill roots, but must
not copy or override their rules. They must state that role selection is made by
the model, that `general-project-engineer` is not a fallback, and that a role
cannot authorize product-architecture changes outside the active plan.
- Correct the decision-writer output contract to
  `docs/public/decisions/` (creating the directory/readme contract if needed)
  and keep state directories for resumability only.
- Correct incident-writer and issues-writer resource paths; remove the claim
  that a nonexistent issue validator can be run, or replace it with an
  actually available deterministic validation command.
- Correct the CI workflow-specification destination to
  `docs/public/spec/`, the automation opportunity sibling path, and the .NET
  root-skill description that points to a nonexistent top-level subskill file.
- Audit the remaining active skill references for missing paths and remove
  provider-specific or uninstalled capabilities from local routing prose.

### C4 — Tooling that must actually run

- Add `.agents/tools/scripts/Test-Toolchains.ps1` with explicit checks for
  PowerShell, .NET SDK/targeting prerequisites and Rust/cargo when required;
  expose a clear `-RequireRust` failure path.
- Update `Invoke-QualityGate.ps1` only as needed to call that script and to
  preserve current solution/manifest paths and platform settings.
- Correct the benchmark README invocation and verify
  `Run-DspBenchmark.ps1` resolves its own benchmark manifest without including
  generated `target/` or results in the public set.
- Add a deterministic `Test-AgentArchitecture.ps1` (or equivalent existing
  script if the implementation can reuse it) that checks required paths,
  forbidden stale references, Markdown local links, Git ignore classification,
  PowerShell parseability and the empty-role subagent result. It must be
  read-only apart from normal process/cache effects and return nonzero on a
  contract violation.

### C5 — Current project context and specifications

- Update `.agents/context/architecture.md` to the actual active renderer and
  update loop; do not infer a product architecture change from the wording
  correction.
- Update `.agents/context/project.md`, conventions and domain context only when
  the source/manifests confirm a stale statement; preserve valid DSP/ABI and
  testing facts.
- Rewrite `docs/public/spec/stack-tech-research.md` to distinguish active
  dependencies and versions from evaluated/future options, using the current
  Cargo, project and package manifests as sources.
- Audit all normative requirements in
  `docs/public/spec/requirements-spec.md` against current source/tests. Keep
  current observable behavior, remove historical implementation-removal text
  from the norm, and move unresolved design intent to the audit register rather
  than silently changing product behavior.
- Create a structured report under `docs/public/reports/` using the report
  skill. Include executive summary, scope/method, findings with file/line
  evidence, risk/limitations, recommendations, and a removal/review register
  for obsolete filenames, retained internal members, missing paths and stale
  documentation.
- Create the required
  `docs/public/traceability/traceability-report-20260811-agent-architecture-audit.md`
  mapping changed specification requirements to normative sources,
  implementation evidence, verification and deviations.

### C6 — Persistent plan and handoff conformance

- Create the execution branch and update this living plan as prescribed by
  `plan-conformance-execution`; maintain one active plan in INDEX.
- Record CP-001 before implementation, then update progress, deviations,
  validation evidence and the handoff snapshot after each material phase.
- Update local `PROJECT-HANDOFF.md` only with the concise active-plan link and
  global state; do not commit local snapshots or task-specific handoffs under
  the mixed visibility policy.
- After all requirements pass, archive the completed plan according to the
  existing plan lifecycle and update `docs/public/plans/INDEX.md`.

## Dependency Map and Execution Order

1. **S1 — Baseline and branch:** verify the baseline is still
   `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`, verify no unrelated changes,
   create `docs/agent-architecture-audit`, persist CP-001 and mark the plan
   `IN_PROGRESS`. Depends on explicit execution authorization.
2. **S2 — Visibility/bootstrap:** apply C1 and validate clean-checkout path
   availability. S2 blocks all later rule/skill validation.
3. **S3 — Rules/catalog:** apply C2, then rerun path/reference discovery so
   later skill fixes target the canonical rules. Depends on S2.
4. **S4 — Skills/subagents/tools:** apply C3 and C4; run the architecture
   validator, PowerShell parser checks, toolchain checks and subagent listing.
   Depends on S3.
5. **S5 — Context/spec/report:** apply C5; use `req-traceability` for the
   normative spec changes and `report-writer` for the audit report. Depends on
   the executable contract from S4.
6. **S6 — Full validation and handoff:** run the repository quality gate and
   targeted documentation/tool tests, inspect the scoped diff, update plan
   evidence and handoff, then archive only after all requirements are verified.
   Depends on S2–S5.

## Execution Step Contracts

### S1 — Baseline, branch and checkpoint

- **Objective:** create the authorized task branch without losing the planning
  baseline or the plan/index changes.
- **Location:** Git repository root, this plan and `docs/public/plans/INDEX.md`.
- **Changes:** verify HEAD/worktree ownership, create
  `docs/agent-architecture-audit` from the recorded revision, keep the plan
  `READY` until the branch is verified, then record `CP-001` and transition to
  `IN_PROGRESS`.
- **Rationale:** all implementation work needs an auditable branch boundary.
- **Dependencies:** explicit execution authorization; no product files.
- **Invariants:** no reset/checkout-overwrite, no unrelated changes, no push.
- **Validation/evidence:** branch points at the baseline; status and ownership
  are recorded in the plan.
- **Replan trigger:** baseline drift or unowned dirty files.

### S2 — Visibility and bootstrap boundary

- **Objective:** make the stable operational layer available in a clean clone
  while keeping personal execution state local.
- **Location:** root `AGENTS.md`, `.gitignore`, `.agents/AGENTS.md`,
  `.agents/context/`, `.agents/state/` template and stable `.agents/tools/`.
- **Changes:** apply the mixed visibility policy, correct the distribution
  script name, make the local handoff optional with a template fallback and
  preserve state/generated exclusions.
- **Rationale:** the current global ignore rule makes the mandatory pipeline
  unavailable in a clean checkout.
- **Dependencies:** S1; no skill or role behavior is changed yet.
- **Invariants:** no secrets/state become public; bootstrap remains mandatory.
- **Validation/evidence:** Git tracking/ignore assertions and a clean-checkout
  path audit pass.
- **Replan trigger:** a required bootstrap file contains private state.

### S3 — Rules and skill catalog

- **Objective:** make `general.md` and related rules the executable, current
  contract for every agent/model execution.
- **Location:** `.agents/rules/`, `.agents/skills/using-agent-skills/SKILL.md`
  and active rule references.
- **Changes:** rewrite mandatory routing, plan/traceability/reporting triggers,
  testing, privacy, compaction and branch/release rules; remove nonexistent
  skill/path references.
- **Rationale:** current rules contain invalid skills, stale paths and an empty
  testing contract.
- **Dependencies:** S2 and the existing project plan lifecycle.
- **Invariants:** user instructions and product architecture remain higher
  priority; no uninstalled capability is presented as available.
- **Validation/evidence:** active-reference scan, catalog inspection and
  `git diff --check`.
- **Replan trigger:** a rule conflict cannot be resolved without changing the
  project lifecycle or product behavior.

### S4 — Role catalog, loader and executable tools

- **Objective:** provide real, scoped roles and make delegation/tool commands
  work from documented locations.
- **Location:** `.agents/roles/`, `sub-agents-execution/scripts/`, its skill
  documentation, `.agents/tools/scripts/` and benchmark documentation.
- **Changes:** add the six candidate role descriptors; allow
  `run_subagent.py` to receive zero, one or multiple `--agent` arguments;
  resolve definitions from `.agents/roles` when selected; permit a task-local
  role context when none fits; preserve custom directory overrides; add/fix
  toolchain, quality-gate and architecture validators.
- **Rationale:** role discovery currently misreads `AGENTS.md`, and an empty
  role directory was incorrectly treated as a reason not to launch agents.
- **Dependencies:** S3; actual backend availability remains environment-level.
- **Invariants:** role permissions cannot override `general.md`; no role may
  authorize product-architecture changes outside a plan.
- **Validation/evidence:** six-role listing, zero/single/multiple role
  composition, task-local role launch, actionable error for an explicitly
  missing role, isolated empty-custom-catalog check, script parsing and
  targeted tool execution.
- **Replan trigger:** a role requires an unavailable backend or a new external
  integration rather than repository-local delegation.

### S5 — Context, specification and audit evidence

- **Objective:** align current-state documentation and preserve a durable audit
  record without mixing history into the normative specification.
- **Location:** `.agents/context/`, `docs/public/spec/`,
  `docs/public/reports/` and `docs/public/traceability/`.
- **Changes:** update architecture/stack context, audit the full requirements
  specification, remove historical RF-EQ.5 deletion text from the norm, create
  the audit/removal register and generate traceability evidence.
- **Rationale:** current docs describe stale renderer timing, packages and
  historical removals.
- **Dependencies:** S4's executable path/role contract; `req-traceability` and
  `report-writer` instructions.
- **Invariants:** specification states current behavior only; no code removal
  is inferred from a documentation discrepancy.
- **Validation/evidence:** source-to-doc comparison, report structure review,
  traceability report and unresolved ambiguity register.
- **Replan trigger:** source/spec conflict requires product-intent choice or
  implementation change.

### S6 — Conformance, validation and archival

- **Objective:** prove the agentic contract works and close the living plan with
  complete evidence.
- **Location:** plan, INDEX, local handoff, quality/tool scripts and final diff.
- **Changes:** run all applicable checks, record skipped/environment-limited
  checks, inspect scope, update handoff and archive the plan only after all
  requirements are verified.
- **Rationale:** documentation correctness is insufficient if commands and
  delegation paths do not execute.
- **Dependencies:** S2–S5.
- **Invariants:** no push/merge/release; no unverified runtime claim.
- **Validation/evidence:** compliance matrix, command outcomes, final scoped
  diff and archived plan.
- **Replan trigger:** unresolved failure, deviation or product-file mutation.

## Invariants During Execution

- No file under `src/`, `tests/` or product build/package configuration is
  changed unless a pre-existing documentation claim cannot be corrected without
  a product change; that situation is a replan trigger, not executor discretion.
- No active rule may reference a path that fails `Test-Path` in the intended
  clean-checkout state.
- Historical plans and archived traceability records are read-only evidence;
  stale references inside them are not rewritten as part of active-document
  cleanup.
- Versioned `.agents/` content must contain no user profile paths, credentials,
  tokens, generated benchmark data or machine-specific release state.
- The specification must not use a removal register as normative product
  behavior and must not claim runtime validation that was not performed.
- The implementation branch must not be pushed or merged by this plan.

## Validation Plan

### Static and contract validation

- `git diff --check` over plan-owned/versioned paths.
- PowerShell parser validation for every `.ps1` changed or added.
- `Test-AgentArchitecture.ps1` from repository root, including required-path,
  stale-reference, local-link, ignore-boundary and skill-catalog checks.
- `git check-ignore`/`git ls-files` assertions proving stable `.agents/` files
  are versionable and local state/generated outputs remain ignored.
- `rg` audit allowing historical matches only under explicitly archived or
  historical documentation paths.
- `python .agents/skills/sub-agents-execution/scripts/run_subagent.py --list`
  with the roles directory; expected result includes the six project roles.
  Invoke the launcher with zero roles, one role and two compatible roles; verify
  the composed context. Invoke it with a task-local role prompt that has no
  catalog file and verify it can launch. Invoke it with an explicitly named
  nonexistent catalog role and verify the error is actionable. Separately
  verify that a temporary empty custom role directory returns zero discovered
  custom roles without disabling generic agent launch.

### Tool and project validation

- Execute `Test-Toolchains.ps1` both with available tools and with the Rust
  requirement path represented by its documented failure behavior.
- Execute `Invoke-QualityGate.ps1 -Configuration Debug` when the environment
  has the required SDKs; use `-SkipRust` only when the plan records why Rust is
  unavailable, and never convert a skipped gate into a pass.
- Run the existing Rust formatting/lint/test checks and .NET test project as
  required by the project rules; no product source is changed by this plan.
- Execute `compact-context.ps1` without build/test switches and inspect the
  generated local snapshot; do not commit that snapshot.
- Do not claim offline benchmark, physical WASAPI, GPU or endurance acceptance
  from documentation/tooling checks alone.

### Documentation and specification validation

- Inspect the audit report against the report-writer structure and ensure every
  finding has a repository-relative evidence path and disposition.
- Verify the normative spec contains only current behavior and no historical
  removal register; verify the separate audit report contains the removal/review
  inventory.
- Verify the traceability report names the changed normative sections,
  implementation evidence, validation commands and any unverified runtime
  conditions.
- Review the final diff for product-architecture files and fail the plan if any
  were changed.

## Compliance Matrix

| Requirement | Steps | Evidence | State |
|---|---|---|---|
| `R1` | S2, S6 | Stable `.agents/` paths tracked and clean-checkout audit passes. | `VERIFIED` |
| `R2` | S2, S3 | Bootstrap fallback and active-reference scan pass. | `VERIFIED` |
| `R3` | S3, S6 | `general.md`, skill router and lifecycle references are current. | `VERIFIED` |
| `R4` | S4, S6 | Model-selected zero/single/multiple roles compose correctly, ad-hoc role context launches, and explicitly missing catalog roles fail clearly. | `VERIFIED` |
| `R5` | S4, S6 | Toolchain, quality gate, compaction and benchmark checks execute as documented. | `VERIFIED_WITH_ENVIRONMENT_BLOCKER` |
| `R6` | S5 | Context and stack research match current manifests/source. | `VERIFIED` |
| `R7` | S5, S6 | Current-state specification, audit register and traceability report agree. | `VERIFIED` |
| `R8` | S2, S5, S6 | Privacy/local-state scan and final public diff review pass. | `VERIFIED` |
| `R9` | S1, S6 | Scoped diff and project validation show no product architecture changes. | `VERIFIED_WITH_ENVIRONMENT_BLOCKER` |
| `R10` | S4, S6 | Six role descriptors are discoverable, scoped and usable. | `VERIFIED` |

## Completion Evidence

## Validation Evidence

| ID | Command/check | Result |
|---|---|---|
| `VAL-001` | `pwsh -NoProfile -File .agents/tools/scripts/Test-AgentArchitecture.ps1` | PASS: six roles; 18 PowerShell files parsed. |
| `VAL-002` | `pwsh -NoProfile -File .agents/tools/scripts/Test-Toolchains.ps1 -RequireRust` | PASS: .NET SDK 10.0.302; Cargo/rustc 1.97.1. |
| `VAL-003` | Launcher `--list`, zero/single/multiple role composition, missing explicit role and empty custom catalog checks | PASS: generic launch is not blocked; six roles discoverable; missing role returns JSON error/code 1. |
| `VAL-004` | `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` | PASS: 77 Rust tests; no lint/format failures. |
| `VAL-005` | `dotnet build/test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj` | PASS: build succeeds; 40 .NET tests pass. |
| `VAL-006` | `Invoke-QualityGate.ps1 -SkipDotNet` | PASS: Rust quality gate completes successfully. |
| `VAL-007` | `Invoke-QualityGate.ps1 -SkipRust` | EXPECTED BLOCK: explicit missing `build/Product.props`; no product metadata was invented. |
| `VAL-008` | `compact-context.ps1` and ignored-state assertions | PASS: local snapshot generated under ignored `.agents/state/`. |
| `VAL-009` | `git diff --check` and scoped diff review | PASS: no product source/test files modified; only task-owned agent/docs contracts changed. |

The full UI quality gate is not claimed as passed because the baseline checkout
does not contain `build/Product.props`, which `src/ui/EchoVisualizer.csproj`
imports. This is isolated, reported, and outside the authorized product-code
scope.

The plan can be marked complete only when all of the following exist:

- The authorized branch is created from the recorded baseline and the final
  working tree contains only approved paths.
- INDEX contains exactly this active plan during execution and the completed
  plan is archived at the prescribed path afterward.
- Stable `.agents/` contracts are visible to Git and local/generated content is
  still ignored.
- The architecture validator, toolchain script, quality gate integration,
  compaction script, role listing and zero/single/multiple-role launch behave as
  documented.
- The six role descriptors are discoverable, parseable and scoped to actual
  project needs; no role claims permissions or capabilities unavailable to its
  selected backend.
- `general.md`, related rules, the local skill router, architecture context and
  stack research have no unresolved active invalid references.
- The current specification, audit/removal report and traceability report agree
  with each other and the source evidence.
- Validation outcomes, skipped checks, deviations and any environment limits
  are recorded in the plan; no unverified runtime claim is presented as passed.

## Executor Discretion

The executor may choose the exact Markdown wording, helper function names,
validator implementation details and the precise `.gitignore` negation syntax,
provided the visibility boundary, paths, commands, requirements and invariants
above remain unchanged. The executor may keep a finding as “review candidate”
instead of deleting code when source evidence does not prove it is unused. The
  executor may not add permanent roles beyond the six-role catalog, alter
  product code, broaden the public state surface, or introduce a compatibility
  alias for a missing capability without a replan. The executor may adjust role
  wording and frontmatter only within the catalog; a task-local role may be
  synthesized per invocation when the model documents its scope and boundaries.

## Replan Triggers

- The user changes the mixed visibility decision or wants the complete agent
  state public.
- A clean checkout requires a secret, a private integration or an external
  plugin to activate the pipeline.
- The specification audit finds a product-behavior contradiction that cannot be
  resolved from source/tests and requires user intent or product-code changes.
- A proposed fix requires modifying Rust/C#/XAML/FFI/rendering behavior.
- The current branch baseline, dirty-worktree ownership or integration policy
  differs from the recorded snapshot.
- Required SDK/toolchain failures prevent validation after safe retries, or the
  quality gate exposes a pre-existing product failure that cannot be isolated.
- A requested subagent role or integration needs to be made permanent rather
  than synthesized for one invocation, or task-local role composition would
  require product architecture changes.

## Initial Checkpoint

### CP-001 — Plan ready for authorized execution

- Baseline revision and clean working tree inspected.
- Mandatory repository pipeline activated and task-relevant context/rules/skills
  read.
- Invalid paths, stale references, missing tool dependency and ignored-required
  `.agents/` state identified.
- User decisions recorded: mixed visibility, `docs/agent-architecture-audit`,
  current-state specification plus separate removal/review register, no product
  architecture changes, and model-selected zero/single/multiple-role semantics
  with task-local role synthesis when the catalog has no suitable match.
- No branch creation or implementation mutation performed during Plan Mode.

### CP-002 — Execution branch established

- **Plan status:** `IN_PROGRESS`
- **Verification state:** `VERIFIED`
- **Active step:** `S2`
- **Repository revision:** `a279fb48d9572dccbdc415b7f79fbbf4ffdf0bfe`
- **Working tree:** plan and INDEX changes only; no unrelated modifications.
- **Changes since CP-001:** created `docs/agent-architecture-audit` from the
  recorded baseline and began execution-state tracking.
- **Validation:** branch, HEAD and status inspected.
- **Validation result:** `PASS`
- **Conformance:** `CONFORMING`
- **Open deviations:** none.
- **Blockers:** none.
- **Next exact action:** implement and validate S2's visibility/bootstrap boundary.

### CP-003 — Agent contract and role execution established

- **Plan status:** `IN_PROGRESS`
- **Active steps completed:** `S2`, `S3`, `S4`.
- **Changes:** mixed `.agents/` visibility, mandatory rules and skills router,
  six permanent role descriptors, optional zero/single/multiple role launcher,
  task-local role protocol, executable toolchain/architecture validators and
  corrected quality-gate root/project selection.
- **Validation:** architecture validator, toolchain validator, role listing,
  role composition, empty custom catalog and missing-role checks passed.
- **Conformance:** `CONFORMING`.
- **Open deviation:** full UI build still depends on absent baseline
  `build/Product.props`.

### CP-004 — Context, specification and validation evidence complete

- **Plan status:** `IN_PROGRESS`
- **Active steps completed:** `S5`; `S6` final archival pending.
- **Changes:** current architecture context, stack research, current-state
  requirements sections, audit report, traceability report and explicit gate
  prerequisite diagnostic.
- **Validation:** Rust 77/77 tests and clippy/format pass; .NET test project
  40/40 tests pass; compaction and diff checks pass; full UI gate is blocked
  only by absent `build/Product.props`.
- **Conformance:** `CONFORMING_WITH_DOCUMENTED_ENVIRONMENT_BLOCKER`.
- **Next exact action:** final status review, archive the plan and update INDEX.

### CP-005 — Final conformance and archival readiness

- **Plan status:** `COMPLETE`.
- **All execution steps:** `S1` through `S6` completed.
- **Final evidence:** `VAL-001` through `VAL-009` recorded above; architecture
  validator, role contract, compaction, Rust and independent .NET validation
  pass.
- **Documented environment condition:** the full UI quality gate is blocked by
  absent baseline `build/Product.props`; `Invoke-QualityGate.ps1` reports this
  explicitly and no product file was fabricated or changed.
- **Scope conformance:** no files under `src/` or `tests/` changed.
- **Archive action:** move this plan to
  `docs/public/plans/archive/completed/2026/08/` and remove it from Active in
  `docs/public/plans/INDEX.md`.

## Handoff Snapshot

- **Current objective:** execute this plan on `docs/agent-architecture-audit`.
- **Current step:** complete; archived plan.
- **Decisions:** mixed public/local `.agents/`; normative spec is current-state
  only; audit report owns historical/removal evidence; no product architecture
  changes; the model selects zero, one or multiple roles and may synthesize a
  task-local role when no catalog role fits.
- **Next actions:** use the archived plan and audit report as the completion
  record for this branch.
- **Known risks:** the checkout lacks `build/Product.props`; the UI quality gate
  remains an explicitly documented environment/baseline blocker.
