---
name: rust
description: >-
  Root skill that groups the Rust sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (ownership, errors, idioms, concurrency,
  performance, review, testing). Use when a Rust DSP/core task matches one of
  those areas; then load the matching sub-skill's SKILL.md.
---

# Rust — Root Skill

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
| Ownership | `sub-skills/rust-ownership/SKILL.md` | Borrow checker, lifetimes, `&`/`&mut`, `Box`/`Rc`/`RefCell`/`Cow`, RAII, `E0xx` borrow errors. |
| Errors | `sub-skills/rust-errors/SKILL.md` | `Result`/`Option` vs panic, `?`, thiserror/anyhow, error propagation, recovery. |
| Idioms | `sub-skills/rust-idioms/SKILL.md` | Idiomatic patterns and anti-patterns. |
| Concurrency | `sub-skills/rust-concurrency/SKILL.md` | Threads, async, atomics, `Send`/`Sync`. |
| Performance | `sub-skills/rust-performance/SKILL.md` | Optimizing, benchmarking, compile times. |
| Review | `sub-skills/rust-review/SKILL.md` | Code review, API design, FP rules. |
| Testing | `sub-skills/rust-testing/SKILL.md` | Unit/integration/async tests, rstest, proptest, fuzzing, mocking, coverage. |

## Project context

The Rust DSP core lives in `src/core/`. `rust-toolchain.toml` pins the toolchain
and the built library is `echo_core.dll` (FFI target). Build it through
`scripts/Build-Distributions.ps1` or the CI setup rather than ad-hoc `cargo`
commands so the pinned toolchain is respected.
