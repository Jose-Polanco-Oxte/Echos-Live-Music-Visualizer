---
trigger: always_on
---

# General Agent Operating Rules

These rules are the highest-priority repository rules after explicit user
instructions. They apply to every agent/model execution, including read-only
audits, delegated work, documentation changes, tests, builds and releases.

## 1. Source of truth and activation

- Treat repository files and observed tool output as the source of truth;
  conversation history is not authoritative.
- Before consequential work, follow the bootstrap order in `.agents/AGENTS.md`:
  project context, applicable rules, selected skills, local handoff/template,
  then the task-specific model context.
- Read only the relevant context and skills. Do not load the whole repository,
  specification, policy set or skill tree when a bounded selection is enough.
- If an instruction conflict remains after applying precedence, stop and surface
  it rather than silently choosing an interpretation.

## 2. Mandatory skill routing

- Load `.agents/skills/using-agent-skills/SKILL.md` for every execution and use
  it to select only skills that match the task.
- Use the persistent plan lifecycle only through this explicit activation gate:
  - load `implementation-plan-authoring` only when the user asks to create,
    formalize, or replan a plan;
  - load `plan-conformance-execution` only when the user explicitly asks to
    execute, implement, apply, or continue a plan provided or identified by
    the user/another agent;
  - do not infer either route from task complexity alone.
- For ordinary requests without an explicitly provided execution plan, use the
  relevant direct skills. If a broad or risky task cannot be executed safely
  without a plan, ask the user whether to provide/authorize one or request plan
  authoring; do not create or execute a plan silently.
- If a plan is supplied inline or by another agent and execution is explicitly
  authorized, persist it under `docs/public/plans/active/` when required by the
  lifecycle, preserving its scope and decisions.
- Use `req-traceability` whenever requirements, formulas or normative
  specifications are changed.
- Use `report-writer` for formal audits, technical findings and structured
  reports.
- Use the relevant Rust, C#, WinUI, testing, scripting or release sub-skill only
  when its trigger applies. Root skills route to sub-skills; they do not replace
  reading the selected sub-skill.
- Use `sub-agents-execution` only when delegation is useful and authorized by
  the task. The model decides whether to select zero, one or multiple roles.

## 3. Role-selection protocol

`.agents/roles/` is a catalog of reusable specializations, not a gate for
launching agents.

Before delegating, record one of these decisions in the task context:

1. **No role:** the task is adequately handled by the normal project context.
2. **One role:** one catalog descriptor provides the needed specialization.
3. **Multiple roles:** several compatible descriptors are composed in the order
   selected by the model.
4. **Ad-hoc role:** no catalog descriptor is a sufficiently close match; the
   model declares the role's objective, context, permissions, boundaries and
   output contract inline for that execution.

Role descriptors add scoped context and constraints. They never override user
instructions, this rule set, project policies or the active plan. When selected
roles conflict, resolve the conflict explicitly in a composite task-local role;
if the conflict changes architecture, scope or observable behavior, enter
replanning before continuing.

An empty or custom role directory does not prohibit generic agent execution.
An explicitly requested missing catalog role must be reported as unavailable;
it must not be silently replaced with a different specialization.

## 4. Scope and architecture protection

- Keep Rust DSP, WASAPI capture, ABI/FFI and Rust tests in `src/core/`.
- Keep WinUI, C#, Win2D, visualizers and UI tests in `src/ui/`.
- Do not modify product architecture, public behavior, ownership, threading,
  persistence, security, dependencies or lifecycle unless the active plan and
  user request explicitly authorize it.
- Do not convert a documentation discrepancy into an unrequested product-code
  change. Record it as a finding, plan gap or replan trigger.
- Preserve unrelated user/agent work. Never use destructive reset/checkout
  operations to make the tree appear clean.

## 5. Plans and repository state

- `docs/public/plans/INDEX.md` is the only plan catalog.
- A plan must be located under `docs/public/plans/active/` and must be read in
  full before implementation.
- Keep requirements, decisions, progress, checkpoints, deviations, validation
  evidence and handoff state in the living plan.
- Historical `deprecated--*` files are read-only and cannot be executed.
- Do not create alternate plan stores, sidecars, catalogs or compatibility
  commands.

## 6. Validation

- Run targeted validation after every material modification.
- For project modifications, run the applicable .NET/Rust tests and record
  skipped checks with their reason; see `.agents/rules/testing.md`.
- For agent/documentation changes, validate paths, links, references, script
  parsing and executable commands in addition to `git diff --check`.
- Do not call a skipped, unavailable or environment-limited check a pass.
- Record material validation in the plan using concise command, result, scope
  and evidence entries; do not paste large logs into plans or handoffs.

## 7. Git and release safety

- Work on the explicitly authorized task branch; use `dev` as the integration
  branch and `main` only for releases.
- Inspect branch, HEAD, status and relevant diff before changing Git state.
- Follow `.agents/rules/git.md` for commits and branch operations.
- Never infer permission to merge, push, tag, release, publish or force-push.
- Release, Store and version changes require direct user authorization and must
  follow `.agents/rules/releases.md`.

## 8. Public and local state

- Version stable operational contracts only: bootstrap, context, rules, skills,
  role descriptors and deterministic tool sources.
- Keep local handoffs, snapshots, generated results, caches, scratch files,
  credentials and machine-specific state ignored.
- If `.agents/state/PROJECT-HANDOFF.md` is absent, use the checked-in template
  and report that local resumability state is unavailable.
- Keep the global handoff concise; detailed plan state belongs in the active
  plan, and non-plan continuation details belong in a relevant handoff file.

## 9. Context compaction

When compaction is needed, run:

```powershell
.\.agents\tools\scripts\compact-context.ps1
```

Then reconcile the generated local snapshot, project handoff/template, plan
index, active plan and actual Git state. Update the living plan and local handoff
before treating conversational history as disposable. Do not copy raw logs or
large diffs into persistent context.
