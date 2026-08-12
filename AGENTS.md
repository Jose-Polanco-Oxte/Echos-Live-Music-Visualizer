# Echo Agent Pipeline Bootstrap

This repository uses `.agents/` as its architectural and operational control
layer. This root file exists only to activate that layer through Codex's native
project-instruction discovery.


> Note: If the person taking over the repository needs to modify the entry point or specific rules, they should edit this file to reflect those changes.

## Mandatory Per-Request Activation

For **every user request while this repository is the active workspace**, before
substantive planning, analysis, repository inspection, tool use, editing, or a
final answer:

1. Read `.agents/AGENTS.md` completely, even if it was read earlier in the
   conversation.
2. Execute the mandatory pipeline defined there in its stated order.
3. Load only the task-relevant context, rules, skills, handoffs, specifications,
   roles, tools, and integrations selected by that pipeline.
4. Apply the resulting instruction set to the entire request.

This activation applies to read-only questions, reviews, planning, debugging,
implementation, testing, documentation, Git operations, builds, packaging, and
release work. A request being small or apparently self-contained does not skip
the bootstrap.

If `.agents/AGENTS.md` is missing or unreadable, stop before consequential work
and report that the project pipeline could not be activated.

System and developer instructions, followed by the user's explicit request,
remain higher priority than repository instructions.

## Planning

The persistent plan lifecycle is opt-in and authorization-gated. Task
complexity alone MUST NOT create or activate a plan.

Use the two-phase lifecycle only in one of these cases:

1. The user explicitly asks to create, formalize, or replan an implementation
   plan. In that case, apply
   `.agents/skills/implementation-plan-authoring/SKILL.md` and stop after the
   plan is READY unless the user separately authorizes execution.
2. The user explicitly asks to execute, implement, apply, or continue a plan
   that the user or another agent has provided or identified. In that case,
   apply `.agents/skills/plan-conformance-execution/SKILL.md` to the selected
   active plan.

For an ordinary request without an explicitly provided execution plan:

- Do not create a plan automatically because the task is non-trivial.
- Use the relevant direct skills and perform the requested bounded work when
  it is safe to do so.
- If the task is too broad or risky to execute safely without a plan, ask the
  user whether they want to provide/authorize a plan or request plan authoring;
  do not author or execute one silently.

When a plan is supplied inline or by another agent and execution is explicitly
authorized, persist it under `docs/public/plans/active/` before execution when
the repository lifecycle requires a file, preserving its stated scope and
decisions.

The two-phase lifecycle is therefore:

1. Explicitly requested plan authoring uses
   `.agents/skills/implementation-plan-authoring/SKILL.md`.
2. Explicitly authorized execution uses
   `.agents/skills/plan-conformance-execution/SKILL.md` to execute, validate,
   checkpoint, and archive that plan.

Discover plans through `docs/public/plans/INDEX.md`, then read the selected
active plan completely. The index is the only plan catalog. Detailed execution
state, checkpoints, validation evidence, deviations, and handoff state belong
inside the living plan.

Plans must be implementation-grade, not summaries.

Do not optimize plans for brevity.

Every material step must identify:
- objective;
- verified code locations;
- exact behavioral changes;
- rationale;
- dependencies;
- invariants;
- validation;
- completion evidence;
- allowed executor discretion;
- replan triggers.

A plan is not complete if another agent would need to rediscover
architectural or behavioral decisions before implementing it.

Prefer explicit detail over compression when information affects implementation.

Do not invent alternate plan stores, sidecar progress files, or command-based
plan catalogs. Historical files prefixed `deprecated--` under the plan archive
are read-only migration artifacts and are never executable plans.

## Context Verification Contract

Only when explicitly asked to verify project instructions, respond with:

CONTEXT_OK

    PIPELINE=./scripts/Build-Distributions.ps1

RELEASE_BRANCH=main

INTEGRATION_BRANCH=dev

DIRECT_DEV_TO_MAIN=forbidden
