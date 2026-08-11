# Anti-patterns and code smells

The catalog of "this marks code as un-idiomatic," with the fix. `rust-review` cites these by
name; each links to the skill that owns the deeper explanation.

## `unwrap()` / `expect()` on a reachable path

```rust
let cfg = std::fs::read_to_string(path).unwrap();   // ✗ panics with no context
let cfg = std::fs::read_to_string(path)?;           // ✓ propagate
```

Fine in tests/prototypes; a bug in shipping code. → `rust-errors` (unwrap vs expect).

## `.clone()` to satisfy the borrow checker

```rust
let copy = data.clone(); use_it(&copy);             // ✗ allocates to dodge a borrow
use_it(&data);                                      // ✓ just borrow
```

→ `rust-ownership` (borrowing). Clone deliberately, not reflexively.

## `&Vec<T>` / `&String` parameters

```rust
fn sum(xs: &Vec<i32>) -> i32 { /* ... */ }          // ✗ over-specific
fn sum(xs: &[i32]) -> i32 { /* ... */ }             // ✓ accepts Vec, array, slice
fn greet(name: &String) { }                         // ✗
fn greet(name: &str) { }                            // ✓
```

clippy flags this (`ptr_arg`). → `rust-ownership`.

## Stringly-typed data

```rust
fn set_status(s: &str) { /* "active"? "Active"? typo? */ }   // ✗ invalid states compile
enum Status { Active, Suspended, Closed }
fn set_status(s: Status) { }                                 // ✓ compiler-checked
```

→ `rust-traits` (make illegal states unrepresentable).

## Boolean parameters

```rust
file.open(true, false);                             // ✗ what do these mean at the call site?
file.open(Mode::ReadOnly, Create::No);              // ✓ self-documenting enums
```

A `bool` argument loses meaning at the call site; an enum names it.

## Index loops instead of iterators

```rust
for i in 0..v.len() { process(&v[i]); }             // ✗ bounds checks, off-by-one risk
for item in &v { process(item); }                   // ✓ clearer, often faster
```

→ `rust-performance` (iterators elide bounds checks), `rust-idioms` patterns.

## Premature `Arc<Mutex<T>>`

```rust
let shared = Arc::new(Mutex::new(state));           // ✗ reflexive, single-threaded code
process(state);                                     // ✓ just pass `state` by value — no wrapper
```

Reach for `Arc<Mutex>` only when data truly crosses threads. → `rust-concurrency`.

## Overusing `dyn` where generics or an enum fit

```rust
fn run(handlers: Vec<Box<dyn Handler>>) { }         // ✗ alloc + vtable for a closed set
enum AnyHandler { A(A), B(B) }                       // ✓ enum dispatch — no alloc, static
```

Pick by open vs closed set. → `rust-traits` (dispatch).

## Returning `Result<_, String>`

```rust
fn parse() -> Result<T, String> { }                 // ✗ callers can't match; loses source
fn parse() -> Result<T, ParseError> { }             // ✓ typed (thiserror)
```

→ `rust-errors` (typed errors for libraries).

## Needless `collect` / `clone` in iterator chains

```rust
let v: Vec<_> = items.iter().collect();             // ✗ allocate just to iterate again
for x in v { }
for x in items.iter() { }                           // ✓ no intermediate Vec

ids.iter().cloned().filter(|x| *x > 0)              // ✗ cloning to compare
ids.iter().filter(|&&x| x > 0)                       // ✓ borrow
```

clippy's `needless_collect` / `redundant_clone` catch many of these — but both live in the
`nursery` group (allow-by-default), so the `all` + `pedantic` config this skill recommends won't fire them. Opt
in with `nursery = "warn"` (expect some false positives).

## Giant functions / deep nesting

A function over ~50 lines or nested past ~4 levels is doing too much — extract helpers, use
early returns and `?` to flatten. Readability is a correctness feature.

## Wildcard `match` on a business enum

```rust
match status {
    Status::Paid => ship(),
    _ => {}                                          // ✗ a new variant slips through silently
}
match status {
    Status::Paid => ship(),
    Status::Pending | Status::Failed => {}           // ✓ adding a variant = compile error
}
```

Use `_` only for genuinely open sets; on your own domain enums, stay exhaustive.

## `Deref` to fake inheritance

```rust
struct Stack { items: Vec<i32>, name: String }
impl std::ops::Deref for Stack {                    // ✗ "Stack is-a Vec" — every Vec method leaks onto Stack
    type Target = Vec<i32>;
    fn deref(&self) -> &Vec<i32> { &self.items }
}

impl Stack {                                        // ✓ expose what you mean, explicitly
    fn items(&self) -> &[i32] { &self.items }
    fn push(&mut self, x: i32) { self.items.push(x); }
}
```

`Deref`/`DerefMut` are for **smart pointers** — types that *are* a pointer to their `Target`
(`Box`, `Rc`, `Arc`). Using them for field access or inheritance makes every `Target` method
silently appear on your type, breaks when you later add an inherent method of the same name, and
confuses readers about what your type *is*. Smart pointers also shouldn't add inherent methods
(call them via the `Target`). → API guideline C-DEREF / C-SMART-PTR; smart-pointer mechanics →
`rust-ownership`.

## Out-parameters instead of return values

```rust
fn parse(input: &str, out: &mut Vec<Token>) -> bool { }        // ✗ &mut out-param + bool status
fn parse(input: &str) -> Result<Vec<Token>, ParseError> { }    // ✓ return the value
fn min_max(xs: &[i32]) -> (i32, i32) { }                        // ✓ multiple results → tuple/struct
```

Rust returns values cheaply (moves, no hidden copy). Reserve `&mut` parameters for genuine
in-place mutation of something the caller already owns — not for handing results back. → C-NO-OUT.

## Surprising operator overloads

```rust
impl std::ops::Add for Matrix {                     // ✗ `+` that actually multiplies
    type Output = Matrix;
    fn add(self, rhs: Matrix) -> Matrix { self.multiply(rhs) }
}
let total = a + b;                                  // reader expects addition, gets a product
```

Overload an operator only when the result is what the symbol means (`+` adds, `*` scales). If the
operation isn't obviously the operator's meaning, give it a named method. For domain types where a
bare `+` could silently lose precision or mix currencies, prefer explicit checked methods (→
`rust-fintech`). → C-OVERLOAD.

## Crate-level `#![deny(warnings)]`

```rust
#![deny(warnings)]   // ✗ in lib.rs/main.rs — a future rustc/clippy lint turns into a hard build break
```
```bash
# ✓ deny warnings where the toolchain is fixed — in CI, not baked into the source
RUSTFLAGS="-D warnings" cargo build
cargo clippy --all-targets -- -D warnings
```

Baking `#![deny(warnings)]` into a crate pins it to a toolchain: the next compiler or clippy
release can add a lint that becomes a hard error for you *and* everyone downstream, with no code
change on their part. Keep the crate lenient and enforce `-D warnings` in CI, where the toolchain
is pinned. → Rust Design Patterns (anti-pattern: `#[deny(warnings)]`).