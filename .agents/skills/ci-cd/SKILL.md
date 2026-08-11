---
name: ci-cd
description: >-
  Root skill that groups the CI/CD sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (pipeline automation, GitHub Actions
  workflow specs, deployment engineering, workflow efficiency). Use when a
  CI/CD or deployment task matches one of those areas; then load the matching
  sub-skill's SKILL.md.
---

# CI/CD — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill under `sub-skills/`. See
`.agents/rules/skills.md` for the sub-skill structure.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at `sub-skills/<name>/SKILL.md`.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| CI/CD and Automation | `sub-skills/ci-cd-and-automation/SKILL.md` | Setting up or modifying build/deployment pipelines: quality gates, CI test runners, deployment strategies, GitHub Actions pipeline configuration. |
| GitHub Actions Workflow Specification | `sub-skills/create-github-action-workflow-specification/SKILL.md` | Creating a formal, AI-optimized specification document for an existing GitHub Actions CI/CD workflow. |
| Deployment Engineer | `sub-skills/deployment-engineer/SKILL.md` | Expert CI/CD design, GitOps (ArgoCD/Flux), progressive delivery, container/Kubernetes deployment patterns, supply-chain security, zero-downtime rollouts. Use proactively for deployment architecture. |
| GitHub Actions Efficiency | `sub-skills/github-actions-efficiency/SKILL.md` | Auditing workflow efficiency to reduce CI minutes and costs: caching, concurrency, path filters, matrix reduction, job optimization. |

## Project context

The project ships a WinUI 3 app through `.github/workflows/` (e.g.
`store-publish.yml`) and `scripts/` PowerShell automation; packaging follows
`.agents/skills/build-full`. For the actual build/packaging of the app use
`build-full`; use these CI/CD sub-skills when authoring, auditing, optimizing,
or documenting the workflows that run it. See `.agents/context/architecture.md`
and `docs/public/publishing/` for the delivery model.