---
name: dependency-upgrade
description: >-
  Plan, execute, and verify safe dependency, framework, and runtime upgrades
  across any stack (npm/pnpm/yarn, Composer/PHP, pip/poetry/uv/Python, Go, Rust,
  .NET). Covers changelog-driven planning, one-major-at-a-time sequencing,
  breaking-change detection mapped to the actual codebase, peer/runtime gates,
  rollback planning, post-update verification, and supply-chain security audits
  against compromised or malicious updates. Merges the dependency-upgrade-planner
  procedure, the event4u upgrade workflow, and guardrails from Addy Osmani's
  engineering rules (dependency discipline, source-driven verification, security
  review). Use when upgrading a key dependency, responding to a security
  advisory, or scoping a framework migration.
---

# Dependency Upgrade

Plan, execute, verify, and audit dependency upgrades so that "bump the version"
becomes a safe, evidence-backed change instead of an act of faith.

This skill merges three sources into one coherent workflow:

1. **Planning** (`references/planning.md`) — from *dependency-upgrade-planner*:
   map the version path, read every intermediate migration guide, and pin the
   breaking changes to your actual call sites.
2. **Execution** (`references/execution.md`) — from the *event4u* upgrade
   workflow: per-stack commands, verification pipeline, multi-package rules,
   and pitfalls.
3. **Guards** (`references/security-and-audit.md`,
   `references/review-and-verification.md`) — from Addy Osmani's engineering
   rules: dependency discipline, source-driven verification, and the
   post-update malware/behavior audit that makes the result *safer than any of
   the three alone*.

The safety win is the combination: the planner prevents blind multi-major
jumps, the workflow forces per-step verification, and the security audit
catches the compromised update that CVE scanners miss.

## Reference documents

| Reference | Contents | Load when |
| --- | --- | --- |
| [`references/planning.md`](references/planning.md) | Pinning versions from the lockfile, reading migration guides for every major, grep-based call-site inventory, peer/runtime gates, one-major-at-a-time sequencing, rollback planning. | Scoping a large upgrade or framework migration; multi-major gaps. |
| [`references/execution.md`](references/execution.md) | Assess → plan → execute → verify → document per stack (Composer, npm, pip/poetry/uv, Go, Cargo), multi-package upgrades, pitfalls, version constraints, security upgrades, conflict detection. | Actually performing the upgrade and its verification. |
| [`references/security-and-audit.md`](references/security-and-audit.md) | Triaging audit results by reachability, post-update malware/behavior audit (install-without-scripts, capability/purpose-vs-behavior diff, provenance checks), supply-chain hygiene. | Any upgrade after a security advisory, or any add/upgrade in general. |
| [`references/review-and-verification.md`](references/review-and-verification.md) | Dependency discipline (one per change, tests decide, transitive graph, lockfile honesty), new-dependency gates, source-driven verification, review red flags, verification checklist. | Reviewing an upgrade before merge. |

## How to use

1. **Plan first** — load `references/planning.md` to pin versions, read the
   migration guides, and scope breaking changes against the real codebase.
2. **Execute one step, verify it** — follow `references/execution.md` per stack,
   one major at a time, running the full suite plus type-checker after each step.
3. **Audit before you ship** — run the post-update malware/behavior audit from
   `references/security-and-audit.md` and surface any finding to the user for
   confirmation.
4. **Review the diff** — apply the discipline and checklist in
   `references/review-and-verification.md` before merging.

## Core rules

- Two or more majors behind → **one major at a time**, each land behind a green build.
- Never upgrade without reading the migration guide for every version in between.
- Never hand-edit the lockfile; always commit and review its diff.
- Never apply forced audit remediation automatically (`npm audit fix --force`).
- After any upgrade: full test suite, type-checker, and a supply-chain audit — a
  trusted package can still ship a compromised version.