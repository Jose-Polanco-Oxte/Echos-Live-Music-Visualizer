---
name: using-agent-skills
description: Select and apply the repository skills that match the current task. This is mandatory for every agent/model execution.
---

# Using Agent Skills

## Purpose

Use this skill to route work to the skills that actually exist in this
repository. It is a selector and workflow contract, not a catalog of
uninstalled provider skills.

## Required selection process

1. Identify the task type, affected subsystem and requested outcome.
2. Inspect the local skill catalog under `.agents/skills/`.
3. Select the smallest set of relevant skills; load each selected `SKILL.md`
   completely before acting on that skill.
4. Load a root skill first when it routes to sub-skills, then load only the
   applicable sub-skills on demand.
5. Record the selected skills and why they apply in the task context or active
   plan.
6. Run the selected skill's verification and the project validation required by
   `.agents/rules/testing.md`.

Do not reference or invoke a skill name that is not present in this repository.
If a missing skill would materially change the implementation, stop and report
the gap instead of pretending it exists.

## Mandatory project skills

| Situation | Skill | Requirement |
|---|---|---|
| Every agent/model execution | `using-agent-skills` | Select applicable skills before consequential work. |
| User explicitly asks to create, formalize or replan a plan | `implementation-plan-authoring` | Create or amend the persistent plan; stop at `READY` unless execution is separately authorized. |
| User explicitly asks to execute, implement, apply or continue a provided/identified plan | `plan-conformance-execution` | Execute with checkpoints, evidence and conformance. |
| Requirements, formulas or normative specification changes | `req-traceability` | Update the spec and generate traceability evidence. |
| Formal audit, technical findings or structured report | `report-writer` | Produce an evidence-based Markdown report. |

## Project skill catalog

These are the available top-level skills and their routing areas:

| Skill | Use when |
|---|---|
| `build-full` | Building, packaging or deploying Echo Visualizer. |
| `ci-cd` | Reviewing or changing CI/CD automation; descend to its applicable sub-skill. |
| `csharp` | C# coding or MSTest-related work; descend to the applicable sub-skill. |
| `decision-writer` | Recording a durable decision or ADR. |
| `dependency-upgrade` | Upgrading framework, package or toolchain dependencies. |
| `dotnet` | .NET architecture/testing routing; descend to the applicable sub-skill. |
| `graphics` | Graphics work; descend to Direct3D, Win2D or RenderDoc sub-skills. |
| `incident-writer` | Writing an objective operational incident report. |
| `issues-writer` | Writing an issue, defect or technical-debt record. |
| `localization` | Localization work; descend to the relevant translation sub-skill. |
| `multitask-coordinator` | Only when the user explicitly invokes multi-workstream coordination. |
| `report-writer` | Formal reports and technical findings. |
| `req-traceability` | Requirements/specification/formula maintenance. |
| `rust` | Rust work; descend to the applicable ownership, errors, concurrency, performance, review or testing sub-skill. |
| `scripting` | PowerShell/automation work; descend to the applicable scripting sub-skill. |
| `sub-agents-execution` | Delegating work to an external CLI agent when useful and authorized. |
| `windows` | Windows API/platform work; descend to the applicable sub-skill. |
| `winui` | WinUI 3 work; descend to design, workflow, packaging, review or UI-testing sub-skills. |
| `writing-style` | Voice analysis or voice-matched editing. |

## Role selection for delegation

Role selection is separate from skill selection. Before delegation, the model
may choose zero, one or multiple compatible descriptors from `.agents/roles/`.
If no descriptor is a close match, declare a task-local role in the prompt or
execution context. A role adds scoped context; it does not replace this skill,
the general rules or project policies.

## Verification contract

Every selected skill must have a concrete verification result. For project
changes, also follow `.agents/rules/testing.md`. For documentation or agent
contract changes, validate paths, references, scripts and links; do not claim
runtime behavior that was not exercised.

## Plan activation boundary

Do not select either plan skill merely because the task is non-trivial. An
ordinary request without a provided execution plan uses the relevant direct
skills. If the task is too broad or risky to execute safely without a plan,
ask the user to provide one or authorize plan authoring before making the
change.
