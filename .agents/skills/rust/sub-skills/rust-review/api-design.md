# Public-API design pass

Run this **in addition** to the Step-2 severity checklist when a diff changes a **public API** — a
library crate, a `pub` surface other crates depend on, or anything published to crates.io. It's the
[Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) checklist, condensed and mapped
to the craft skill that owns each fix (this file is the *index* — the rule and examples live in the
owning skill, never duplicated here).

Don't run it on application-internal code — the bar there is lower. Severity: an unmet item is
**MEDIUM** (warn) by default, **HIGH** when it breaks callers or leaks into the semver contract.

## Naming

| Guideline | Check | Owner |
|---|---|---|
| C-CASE | `UpperCamelCase` types, `snake_case` fns, `SCREAMING_SNAKE_CASE` consts | `rust-idioms` |
| C-CONV | `as_`/`to_`/`into_` prefixes match cost & ownership | `rust-idioms` |
| C-GETTER | getters have no `get_` prefix | `rust-idioms` |
| C-ITER / C-ITER-TY | `iter`/`iter_mut`/`into_iter`; iterator types `Iter`/`IterMut`/`IntoIter` | `rust-idioms` |
| C-FEATURE | feature names free of `use-`/`with-` placeholder words | `rust-ecosystem` (cargo) |
| C-WORD-ORDER | consistent word order across a name family | `rust-idioms` |

## Interoperability

| Guideline | Check | Owner |
|---|---|---|
| C-COMMON-TRAITS | eagerly derive `Debug`/`Clone`/`PartialEq`/`Eq`/`Hash`/`Ord`/`Default` where they fit | `rust-idioms` |
| C-CONV-TRAITS | conversions via `From`/`TryFrom`/`AsRef`/`AsMut`, not ad-hoc `to_x` | `rust-idioms` |
| C-COLLECT | collections you define impl `FromIterator` + `Extend` | `rust-idioms` (patterns) |
| C-SERDE | offer `Serialize`/`Deserialize`, feature-gated | `rust-idioms` / `rust-ecosystem` |
| C-SEND-SYNC | types are `Send` + `Sync` wherever possible | `rust-concurrency` |
| C-GOOD-ERR | typed, meaningful, non-leaky error types | `rust-errors` |
| C-NUM-FMT | numeric/flag types impl `Hex`/`Octal`/`Binary` | `rust-idioms` (patterns) |
| C-RW-VALUE | generic I/O takes `R: Read` / `W: Write` by value | `rust-idioms` (patterns) |

## Type safety & predictability

| Guideline | Check | Owner |
|---|---|---|
| C-NEWTYPE | newtypes give static distinctions | `rust-traits` |
| C-CUSTOM-TYPE | meaning via types, not `bool`/`Option` arguments | `rust-idioms` (anti-patterns) |
| C-BITFLAG | flag sets use `bitflags`, not enums or bare ints | `rust-traits` |
| C-BUILDER | builders for complex/staged construction | `rust-idioms` / `rust-traits` (typestate) |
| C-CTOR | constructors are static inherent `new` / `from_*` | `rust-idioms` |
| C-NO-OUT | return values/tuples; no `&mut` out-parameters | `rust-idioms` (anti-patterns) |
| C-DEREF / C-SMART-PTR | only smart pointers impl `Deref`/`DerefMut`, and they add no inherent methods | `rust-idioms` (anti-patterns) |
| C-OVERLOAD | operator overloads are unsurprising | `rust-idioms` (anti-patterns) |
| C-VALIDATE | validate arguments / parse-don't-validate | `rust-traits` / `rust-architecture` |

## Dependability & debuggability

| Guideline | Check | Owner |
|---|---|---|
| C-DEBUG / C-DEBUG-NONEMPTY | every public type impls a **non-empty** `Debug` | `rust-idioms` |
| C-DTOR-FAIL | destructors never panic | `rust-ownership` (Drop) |
| C-DTOR-BLOCK | blocking/async cleanup has an explicit `close`/`shutdown().await` | `rust-concurrency` / `rust-ownership` |

## Future-proofing

| Guideline | Check | Owner |
|---|---|---|
| C-SEALED | seal traits you don't want implemented downstream | `rust-traits` |
| C-STRUCT-PRIVATE / C-NEWTYPE-HIDE | struct fields private; newtypes hide their representation | `rust-traits` / `rust-ecosystem` |
| C-STRUCT-BOUNDS | no trait bounds on the type definition (bound the impls) | `rust-traits` |
| (semver) | `#[non_exhaustive]` reserves room on public enums/structs | `rust-ecosystem` |

## Macros

| Guideline | Check | Owner |
|---|---|---|
| C-EVOCATIVE / C-MACRO-* | exported macros read like their output and compose with attributes/visibility | `rust-macros` |

## Documentation & necessities

| Guideline | Check | Owner |
|---|---|---|
| C-CRATE-DOC / C-EXAMPLE / C-QUESTION-MARK | crate-level docs + runnable examples that use `?`, not `unwrap`/`try!` | `rust-idioms` (docs) |
| C-FAILURE / C-LINK | `# Errors`/`# Panics`/`# Safety` sections; intra-doc links | `rust-idioms` (docs) |
| C-METADATA | `Cargo.toml` has license/description/repository/keywords/categories | `rust-ecosystem` |
| C-RELNOTES | a `CHANGELOG.md` records each release's user-visible changes | `rust-ecosystem` |
| C-HIDDEN | `#[doc(hidden)]` on public-but-not-API items | `rust-ecosystem` |
| C-STABLE | public dependencies of a stable crate are themselves stable | `rust-ecosystem` |
| C-PERMISSIVE | permissive license (MIT/Apache-2.0) and license-compatible deps | `rust-security` (cargo-deny) |

A finding here is reported like any other: `severity · file:line · which C-guideline · the fix`,
citing the owning skill for the how.
