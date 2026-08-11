# AGENT.md

This repository uses `.agents/` as the operational control layer for all agents.

## Branch Management Policy

* **Primary Working Branch**: All development, features, fixes, and agent operations MUST always be performed on the `dev` branch unless the user explicitly requests another branch (such as `main` for official releases). Always ensure the agent is working on `dev` before creating commits or builds.

## Mandatory Reading Order

Before taking any meaningful action, read and apply the following **strictly in this order**:

1. Update the barnch (with git).
2. `.agents/context/project.md`
3. `.agents/rules/`

   * **`.agents/rules/general.md` is mandatory and has highest operational priority for every action.**
   * Read any additional rules relevant to the current task.
4. `.agents/skills/`

   * Select and apply any relevant skills at your own discretion.
   * Do not use unrelated skills.
5. `.agents/state/PROJECT-HANDOFF.md` when the local handoff exists; otherwise
   read `.agents/state/PROJECT-HANDOFF.template.md` and report that local
   handoff state is unavailable.
6. `.agents/state/handoffs/` if and only if it is relevant to continuing a certain task or implementation.
7. The model context.

Do not skip, reorder, or ignore these steps.

## Persistent Implementation Plans

The persistent plan lifecycle is opt-in and requires explicit user intent.
Non-trivial work MUST NOT create or activate a plan automatically.

Route to the lifecycle only as follows:

1. When the user explicitly asks to create, formalize, or replan a plan,
   `implementation-plan-authoring` creates and verifies the persistent plan.
   Authoring stops at `READY` unless execution is separately authorized.
2. When the user explicitly asks to execute, implement, apply, or continue a
   plan provided or identified by the user/another agent,
   `plan-conformance-execution` performs authorized implementation, continuous
   conformance checks, checkpoints, final validation, and archival.

For ordinary requests without an explicitly provided execution plan, do not
invoke either plan skill merely because the task is complex. Use the relevant
direct skills. If safe execution requires a plan, ask the user to provide one
or authorize plan authoring before changing repository state.

If an execution plan is supplied inline or by another agent, persist it under
`docs/public/plans/active/` before execution when required by the lifecycle;
preserve its scope and decisions rather than inventing a different plan.

Use `docs/public/plans/INDEX.md` as the only catalog. Read the selected active
plan completely before implementation. Store detailed status, requirements,
decisions, deviations, checkpoints, validation evidence, and the task handoff
inside that living plan.

Files named `deprecated--*` in `docs/public/plans/archive/` are read-only legacy
artifacts. They are not active plans, cannot be resumed, and do not define a
valid lifecycle state.

## Project References

Use these sources when relevant:

* **Project specification:** `docs/public/spec/`
* **Architecture:** `.agents/context/architecture.md`
* **Development conventions:** `.agents/context/conventions.md`
* **Domain knowledge:** `.agents/context/domain.md`

These files define project intent, structure, conventions, and required domain understanding. Do not contradict them without explicit authorization.

## Agent Roles

Role definitions are located in:

`.agents/roles/`

Before delegating or starting a specialized task, the model decides whether to
use zero, one, or multiple compatible roles from this catalog. If no catalog
role fits, the model declares a task-local role in the execution context. A
role descriptor is guidance and scoped context; it never overrides project
rules or is required for generic agent execution.

When roles are selected, read and follow their descriptors in addition to all
mandatory project rules and policies. If selected roles conflict materially,
resolve the conflict explicitly or stop for replanning.

A role may specialize behavior, but it does **not** override `.agents/rules/general.md` or project policies.

## Tools

Agent-specific tools, scripts, services, MCP resources, and usage instructions are located in:

`.agents/tools/`

Use them only when applicable and according to their documented constraints.

## Integrations

Provider- or platform-specific configuration is located in:

`.agents/integrations/`

This directory contains adapters and instructions for external agent platforms, services, plugins, MCP clients, IDEs, scripts, or other integrations.

Integration-specific behavior must never override the project's shared rules, policies, architecture, or specifications.

## Precedence

When instructions conflict, follow this priority:

1. Explicit user instruction
2. `.agents/rules/general.md`
3. Relevant project rules
4. Project specification and architecture
5. Assigned role
6. Applicable skills
7. Integration-specific instructions

If a conflict remains unresolved, do not silently choose an interpretation. Surface the conflict before making a consequential change.

## Operating Rule

Before modifying code, configuration, documentation, dependencies, repository state, or external resources:

* understand the project context,
* apply mandatory rules,
* select applicable skills,
* review the current handoff,
* verify relevant policies,
* then act.

## Context Management

Conversation context is disposable. The repository is the source of truth.

Global repository information required after context loss MUST be persisted in
`.agents/state/PROJECT-HANDOFF.md`. Plan-specific continuation state MUST remain
in the active plan; the global handoff links to it without duplicating its
checkpoints or detailed execution record.

The agent MUST perform context compaction when:

- a significant milestone is completed;
- the active task changes substantially;
- debugging or investigation has accumulated substantial context;
- several implementation approaches have been attempted;
- conversational context is becoming large, noisy, or expensive;
- before handing work to another agent;
- explicitly instructed with `/context-compact`.

Context compaction MUST follow the procedure defined in
`.agents/rules/general.md`.

Do not attempt to preserve large logs, code already present in the repository,
obsolete plans, or recoverable implementation details in conversational memory.
