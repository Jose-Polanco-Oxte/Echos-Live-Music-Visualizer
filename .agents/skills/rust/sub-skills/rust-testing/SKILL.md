---
name: rust-testing
description: >-
  Rust testing — unit, integration, async, table-driven (rstest), property-based (proptest), fuzzing (cargo-fuzz), mutation (cargo-mutants), mocking (mockall), snapshot (insta), doc tests, and coverage. Use when writing or reviewing Rust tests, adding coverage, choosing a testing crate, or setting up CI. Triggers: #[tokio::test], rstest, proptest, cargo-fuzz, cargo-mutants, mockall, insta, nextest.
---

# Rust Testing

Self-contained guide to testing Rust: what to reach for, the TDD loop in Rust terms, and the commands. Deep examples live in the sub-files below — read the one you need, not all three.

## When to Use

- Writing tests for new functions, methods, traits, or modules
- Adding coverage to existing code
- Choosing the right testing crate for a case (table-driven, property, mock, snapshot)
- Setting up the test runner and CI for a Rust project

## Pick the right tool

| Situation | Reach for | Where |
|---|---|---|
| One behavior, one input | plain `#[test]` | [core.md](core.md) |
| Function returns `Result` / can panic | `?` in test / `#[should_panic]` | [core.md](core.md) |
| Cross-crate / public API behavior | integration test in `tests/` | [core.md](core.md) |
| Show usage in the docs | doc test (` ``` ` in `///`) | [core.md](core.md) |
| Same logic, many input/output pairs | `rstest` `#[case]` | [advanced.md](advanced.md) |
| Shared setup across tests | `rstest` `#[fixture]` | [advanced.md](advanced.md) |
| `async fn` under test | `#[tokio::test]` | [advanced.md](advanced.md) |
| Invariant must hold for *all* inputs | `proptest` | [advanced.md](advanced.md) |
| Isolate a unit from a trait dependency | `mockall` | [advanced.md](advanced.md) |
| Behavior spec in Given/When/Then (or Gherkin `.feature`) | plain test, or `cucumber` | [advanced.md](advanced.md) |
| Assert on large/structured output | `insta` snapshot | [tooling.md](tooling.md) |
| Faster runs, better output, CI | `cargo nextest` | [tooling.md](tooling.md) |
| Prove what's tested | `cargo llvm-cov` | [tooling.md](tooling.md) |
| Find crashes/panics on adversarial bytes (parser, untrusted input, `unsafe`) | `cargo-fuzz` | [advanced.md](advanced.md) |
| Check tests actually *catch* bugs, not just run | `cargo-mutants` | [tooling.md](tooling.md) |

> Benchmarking (`criterion`, `cargo bench`) is **not** testing — it belongs to `rust-performance`, not here.

## The TDD loop in Rust

Discipline is RED → GREEN → REFACTOR. In Rust the mechanics are:

```rust
// RED — write the test first; stub the impl with todo!() so it compiles but fails
pub fn slugify(s: &str) -> String { todo!() }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lowercases_and_dashes() {
        assert_eq!(slugify("Hello World"), "hello-world");
    }
}
// `cargo test` → panics at "not yet implemented" = RED
```

```rust
// GREEN — minimal code to pass
pub fn slugify(s: &str) -> String {
    s.to_lowercase().replace(' ', "-")
}
// `cargo test` → PASS. Now REFACTOR with the test as a safety net.
```

Rules that keep the loop honest:
- Watch the test **fail first** — a test that was never red proves nothing.
- One behavior per test; the name states the scenario (`rejects_empty_input`, not `test1`).
- Tests must be independent — no shared mutable state, no ordering assumptions.

## Command cheatsheet

```bash
cargo test                     # all tests (unit + integration + doc)
cargo test name_substring      # only tests whose name matches
cargo test -- --nocapture      # show println!/dbg! output
cargo test --lib               # unit tests only
cargo test --test api          # one integration binary (tests/api.rs)
cargo test --doc               # doc tests only
cargo test -- --include-ignored  # also run #[ignore] tests
cargo test --no-fail-fast      # don't stop at first failure
```

(For `cargo nextest` and coverage, see [tooling.md](tooling.md).)

## DO / DON'T

**DO**
- Test behavior, not implementation details.
- Prefer `assert_eq!` over `assert!(a == b)` — better failure messages.
- Return `Result` from tests and use `?` instead of unwrapping each step.
- Put unit tests in a `#[cfg(test)] mod tests` next to the code; integration tests in `tests/`.
- Quarantine or fix flaky tests immediately — never `#[ignore]` and forget.

**DON'T**
- Use `#[should_panic]` when you could assert `result.is_err()` (panic tests can pass for the wrong reason).
- Mock everything — prefer a real or in-memory implementation when feasible; mock only at true boundaries.
- Use `thread::sleep` to "wait" in async tests — use `tokio::time::pause`/`advance` or channels.
- Assert on debug-formatted blobs by hand when a snapshot (`insta`) is clearer.

## Project defaults

This collection targets the latest stable toolchain:

```toml
[package]
edition = "2024"
```

Test crates are `[dev-dependencies]` — they never ship in the final binary.

## Boundaries

This skill covers writing and running Rust tests. Adjacent concerns belong elsewhere:

- Benchmarking and profiling (`criterion`, `cargo bench`, flamegraphs) → `rust-performance`.
- Fake-port unit tests and hexagonal adapter layering (what to fake vs. integrate) → `rust-architecture`.
- Deriving BDD scenarios from requirements → `specs`.
- Reporting and owning skipped-test status (don't let "no Docker" pass as "covered").
- Flagging weak or missing tests in a diff → `rust-review`.
