---
name: rust-idioms
description: >-
  Idiomatic Rust — naming conventions, the constructs that read as native Rust, clippy/rustfmt as enforcers, and a catalog of common anti-patterns. Use when writing or polishing Rust to be idiomatic, naming things, deciding "is this the Rust way?", or reviewing for code smells. Triggers: clippy, rustfmt, is this idiomatic, the Rust way, stringly typed, missing_docs.
---

# Rust Idioms

What makes Rust read like Rust: naming the standard library would recognize, constructs the
ecosystem expects, and the anti-patterns that mark code as ported-from-another-language. The
idiomatic-construct catalog is in [patterns.md](patterns.md); the smell catalog (Good/Bad) is in
[anti-patterns.md](anti-patterns.md).

## When to Use

- Writing new Rust you want to read as native
- Naming types, functions, methods, conversions
- Polishing / reviewing for idiom and code smells
- Settling "is this the Rust way?"

## Naming conventions

Follow the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) — these are what
clippy and other Rustaceans expect:

| Item | Convention | Example |
|---|---|---|
| Types, traits, enum variants | `UpperCamelCase` | `HashMap`, `IntoIterator`, `Pending` |
| Functions, methods, vars, modules | `snake_case` | `read_to_string`, `max_len` |
| Constants & statics | `SCREAMING_SNAKE_CASE` | `MAX_SIZE` |
| Conversions | `as_` borrow→borrow (cheap), `to_` →owned (costly), `into_` consume (owning) | `as_str`, `to_owned`, `into_bytes` |

- **Getters have no `get_` prefix** — `name()`, not `get_name()` (`get`/`get_mut` are for
  indexing-style access like `slice.get(i)`).
- **Iterators**: `iter` (`&T`), `iter_mut` (`&mut T`), `into_iter` (`T`); the iterator *types* they
  return mirror the method names — `Iter`, `IterMut`, `IntoIter`.
- **Constructors**: `new` for the obvious one; `with_capacity`/`from_*` for variants.
- **Don't stutter**: `author::Author`, not `author::AuthorStruct`; a method on `Error` isn't
  `error_kind()`, it's `kind()`.
- **Booleans** read as predicates: `is_empty`, `has_root`, `should_retry`.
- **Consistent word order**: pick one order for a family of names and keep it — siblings of
  `RecvError` are `SendError`, not `ErrorOnSend`. Don't mix verb-noun and noun-verb in one crate.

## Idiomatic constructs (the short list)

Full examples in [patterns.md](patterns.md):

- Implement `From`/`TryFrom`; you get `Into`/`TryInto` for free. Don't write `to_x`/`from_x`
  methods where a `From` impl belongs.
- `Default` + struct-update (`..Default::default()`) over many-arg constructors.
- Iterator chains (`.iter().map().filter().collect()`) over index loops; `collect::<Result<_,
  _>>()` to short-circuit fallible iteration.
- `matches!`, `if let`, and `let … else` over verbose `match` for one-armed checks.
- Accept `&str` / `impl AsRef<str>`, return owned (→ `rust-ownership`).
- `derive` the common set in a conventional order: `Debug, Clone, Copy, PartialEq, Eq, Hash,
  PartialOrd, Ord, Default` (then `Serialize, Deserialize`).
- Minimal visibility: default private, `pub(crate)` for crate-internal, `pub` only at the API.

## Clippy & rustfmt are the enforcers

Don't argue style by hand — let the tools. Turn them up and keep them green:

```toml
# Cargo.toml — lint this crate
[lints.clippy]
all = "warn"
pedantic = "warn"
```
```bash
cargo fmt            # formatting is not a matter of opinion
cargo clippy --all-targets -- -D warnings
```

clippy's categories: `correctness` (bugs), `suspicious`, `complexity`, `perf`, `style`,
`pedantic` (opt-in). When you must `#[allow(clippy::lint)]`, add a comment saying why — an
unexplained `allow` is itself a smell.

## Documentation

Doc comments are part of the code's quality, not an afterthought — and they compile.

```rust
//! Crate- or module-level docs: what this is for, a quickstart. (top of lib.rs / a module)

/// One-line summary of what the item does (this line shows in the item list).
///
/// More detail in following paragraphs. Link other items with intra-doc links:
/// see [`Config`] and [`parse`].
///
/// # Examples
/// ```
/// # use mycrate::parse;
/// let cfg = parse("port = 8080").unwrap();   // examples are compiled & run as tests
/// assert_eq!(cfg.port, 8080);
/// ```
///
/// # Errors
/// Returns [`ParseError`] when the input isn't valid TOML.
///
/// # Panics
/// State any panic path here — or that it never panics.
pub fn parse(input: &str) -> Result<Config, ParseError> { /* ... */ }
```

Conventions:

- `///` documents the item that follows; `//!` documents the enclosing crate/module (use it for
  a crate-level overview at the top of `lib.rs`).
- First line is a concise summary — it's what appears in the generated item list; lead with the
  verb ("Parses…", "Returns…").
- Use the standard sections where they apply: **`# Examples`**, **`# Errors`** (for `Result`),
  **`# Panics`**, **`# Safety`** (for `unsafe fn` — required; → `rust-unsafe`).
- Examples are doc tests — they're compiled and run, so they can't go stale (→ `rust-testing`).
- Link with intra-doc links (``[`Type`]``) rather than bare names — they resolve and stay valid.
- Document the *why/contract*, not the obvious *what*: `/// Returns the cached value` on
  `fn cached_value()` is noise; document the invariant, the units, the edge cases.
- For published crates, enforce coverage with `#![warn(missing_docs)]` and treat docs as part of
  the semver contract → `rust-ecosystem` (libraries).

## Boundaries

- This skill is the **catalog** (how to write it well). The review *process* — gate, severity,
  verdict — is `rust-review`, which cites this skill for the "why" and the fix.
- Topic mechanics live in their skills: ownership fixes → `rust-ownership`, error design →
  `rust-errors`, dispatch → `rust-traits`, sharing → `rust-concurrency`. This skill links to
  them rather than re-explaining.

## Further reading

- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/) (rust-unofficial) — the
  broader community catalog of idioms, design patterns, and anti-patterns. craft owns the
  action-first, review-relevant subset; the book covers the rest, including the GoF patterns craft
  deliberately doesn't duplicate (mapped by mechanism in the GoF/SOLID Rosetta in
  [patterns.md](patterns.md)).