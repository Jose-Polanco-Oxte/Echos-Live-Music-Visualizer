---
name: rust-errors
description: >-
  Rust error handling — Result vs Option vs panic, the ? operator, thiserror for libraries vs anyhow for applications, error design, context, and recovery (retry, fallback, circuit breaker). Use when designing or fixing error handling, choosing an error type/crate, propagating errors, or making code resilient. Triggers: ?, thiserror, anyhow, error propagation, retry, circuit breaker, E0277.
---

# Rust Error Handling

The decisions, the crates, and the recovery patterns. This entry covers *which* type to
return and the day-to-day mechanics; the deep crate usage and resilience patterns are in the
sub-files.

## When to Use

- Designing error handling for a new module, function, or crate
- Choosing between `Result`, `Option`, and `panic!`
- Choosing/structuring an error type (`thiserror` vs `anyhow` vs hand-rolled)
- Making fallible code resilient (retry, fallback, degrade)

## Decision: which return type?

Start from the nature of the failure, not the syntax.

| Situation | Return | Why |
|---|---|---|
| Can fail in normal operation (I/O, parse, network, validation) | `Result<T, E>` | caller must decide |
| Absence is normal and carries no reason | `Option<T>` | no error to report |
| Violated invariant / programmer bug / "can't happen" | `panic!` (or `unwrap`/`expect`) | not recoverable; fail loud |
| Unrecoverable startup precondition | `panic!`/`expect` at boot | better to crash than run broken |

### `unwrap` vs `expect`

- **Avoid `unwrap()` in code that ships.** It panics with only a line number — when it fires
  you learn *where* but never *why*.
- **Prefer `expect("…")` over `unwrap()`** when a panic is genuinely justified: the message
  documents the invariant you relied on and appears in the panic output.
- **`unwrap`/`expect` are fine in tests, benches, examples, and prototypes** — there a broken
  assumption *should* fail loudly and immediately.
- On a reachable production path, both are a bug: return `Result`/`?`, or handle the
  `None`/`Err`. See `rust-review` (CRITICAL — Safety).

```rust
// tests — fine: a broken fixture should blow up the test
let user = User::new("a", "a@x.com").expect("valid fixture");

// production — not fine
let cfg = load_config().unwrap();   // ✗ panics with no context
let cfg = load_config()?;           // ✓ propagate
let port = env_port.unwrap_or(8080);// ✓ sensible default

// justified panic (provably impossible) — document why with expect
let re = Regex::new(r"^\d+$").expect("hardcoded regex is valid"); // ✓ message explains it
```

## Two channels: domain failures vs defects

A useful frame from ZIO (Scala): keep two kinds of "went wrong" strictly apart.

- **Domain failure** — expected, recoverable, part of the contract ("not found",
  "insufficient funds", "invalid input"). The caller acts on it → typed
  `Result<T, DomainError>` (a `thiserror` enum). *(This is ZIO's typed error channel `E`.)*
- **Defect** — unexpected, unrecoverable, a bug or broken invariant (poisoned lock, a reached
  `unreachable!`, an "impossible" `None`). The caller can't do anything useful → `panic!`.
  *(This is ZIO's defect / `die`.)*

Keep the domain enum to failures a caller would actually branch on. Polluting it with
"can't happen" infrastructure noise forces every caller to `match` cases they can't handle and
buries the real ones. **Domain failures go in the type; defects panic.**

| Question | Yes → | No → |
|---|---|---|
| Can a caller sensibly recover? | domain failure: `Result<_, DomainError>` | defect: `panic!` |
| Is it part of the operation's contract? | a typed variant | opaque variant or panic |

Middle ground for "unexpected but don't kill the whole process" (e.g. one bad web request):
carry the defect **opaquely** instead of enumerating it, and recover only at the boundary —
patterns in [design.md](design.md).

## The `?` operator

`?` returns early on `Err`/`None`, converting the error via `From`:

```rust
fn read_count(path: &str) -> Result<usize, MyError> {
    let text = std::fs::read_to_string(path)?; // io::Error -> MyError via From
    let n: usize = text.trim().parse()?;       // ParseIntError -> MyError via From
    Ok(n)
}
```

The conversion is what makes `?` ergonomic — `thiserror`'s `#[from]` generates those `From`
impls for you (see [design.md](design.md)). `?` also works in functions returning `Option`.

## Return the consumed value on failure

When a fallible method takes an owned value *by value* (often `self`) and can fail, hand the value
back inside the `Err` so the caller can retry or recover without re-acquiring it:

```rust
fn connect(self) -> Result<Live, ConnectError>;          // ✗ on failure the caller has lost `self`
fn connect(self) -> Result<Live, (Self, ConnectError)>;  // ✓ failure returns the value to retry with
```

The same shape works for any owned input (a `Vec`, a buffer, a builder). Reserve it for values that
are expensive or impossible to reconstruct — for cheap `Copy`/clonable inputs it is just noise.
→ Rust Design Patterns (idiom: "Return consumed arg on error").

## Decision: which error crate?

This is the single most important error choice in Rust:

| You're writing | Use | Because |
|---|---|---|
| A **library** (others depend on it) | `thiserror` — typed enum | callers must `match` on failure modes; errors are part of your API |
| An **application** (binary, top level) | `anyhow` — one opaque error + context | you just need to report and exit; no caller to match |

Mixing is normal: libraries return typed errors; the app collects them into `anyhow` and adds
context at each boundary. Full patterns for both in [design.md](design.md).

```toml
[dependencies]
thiserror = "2.0"   # libraries
anyhow    = "1.0"   # applications
```

## Adding context

A bare error says *what* failed, not *where* or *with what input*. Add context at boundaries:

```rust
use anyhow::Context;

let config = std::fs::read_to_string(&path)
    .with_context(|| format!("reading config from {}", path.display()))?;
```

Include the *value* that broke (`path`, `id`, the bad input) — generic strings like
"parse error" waste the context. Use `with_context(|| …)` (lazy) over `context(…)` when the
message allocates.

## Cheatsheet

```rust
opt.ok_or(MyError::NotFound)?;          // Option -> Result (static)
opt.ok_or_else(|| MyError::Missing(id))?;// Option -> Result (lazy/owned)
res.map_err(MyError::Wrap)?;            // convert error type inline
let x = res.unwrap_or(default);         // swallow error -> default
let x = res.unwrap_or_else(|_| …);      // swallow -> computed default
if matches!(res, Err(MyError::NotFound)) { /* branch on a variant */ }
anyhow::bail!("bad state: {x}");     // early return an ad-hoc error (app)
anyhow::ensure!(cond, "must hold");  // bail unless cond (app)
```

## Boundaries

- *Recovery* (retry/backoff/circuit-breaker/fallback) → [recovery.md](recovery.md).
- *Is this idiomatic?* / "unwrap everywhere" as a smell → `rust-idioms`.
- *Flagging* bad error handling in a diff → `rust-review`.
- Errors that cross threads (`Send + Sync` bounds on error types) → `rust-concurrency`.
- Translating domain errors into transport responses at a service boundary → `rust-architecture`
  / `rust-web`.
