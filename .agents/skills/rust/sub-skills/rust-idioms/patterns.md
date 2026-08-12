# Idiomatic constructs

The patterns the standard library and ecosystem expect. Using them makes your API feel native
and composable.

## Conversions: `From` / `Into` / `TryFrom`

Implement `From`; `Into` comes free. Accept `impl Into<T>` to let callers pass either side.

```rust
struct Celsius(f64);
struct Fahrenheit(f64);

impl From<Celsius> for Fahrenheit {
    fn from(c: Celsius) -> Self { Fahrenheit(c.0 * 9.0 / 5.0 + 32.0) }
}

let f: Fahrenheit = Celsius(100.0).into();   // free via From

// Fallible conversions use TryFrom (and give TryInto free)
impl TryFrom<i64> for Age {
    type Error = AgeError;
    fn try_from(n: i64) -> Result<Self, AgeError> { /* ... */ }
}
```

Don't write `to_fahrenheit()` / `from_celsius()` methods where a `From` impl is the idiom — it
plugs into `?`, generic bounds, and `.into()` everywhere.

## `Default` + struct-update

```rust
#[derive(Default)]
struct Config { workers: usize, verbose: bool, name: String }

let cfg = Config { workers: 4, ..Default::default() };   // override some, default the rest
```

Prefer this to a constructor with many arguments. For staged/validated construction, use a
builder (→ typestate builder in `rust-traits`).

## Constructors and builders

```rust
impl Server {
    pub fn new(addr: SocketAddr) -> Self { /* the obvious constructor */ }
    pub fn with_tls(mut self, cfg: TlsConfig) -> Self { self.tls = Some(cfg); self } // chainable
}
let s = Server::new(addr).with_tls(tls);
```

## Iterators over loops

Express transformations as iterator chains — clearer, and often faster (→ `rust-performance`).

```rust
// Idiomatic
let names: Vec<_> = users.iter().filter(|u| u.active).map(|u| &u.name).collect();

// Fallible iteration: collect into Result to short-circuit on the first Err
let parsed: Result<Vec<i32>, _> = lines.iter().map(|l| l.parse::<i32>()).collect();

// Sum/find/any/all instead of manual accumulation
let total: u64 = items.iter().map(|i| i.size).sum();
```

## Concise control flow

```rust
if let Some(name) = maybe_name { greet(name); }          // one case
let Some(cfg) = load() else { return Err(Error::NoConfig); }; // bind-or-bail
if matches!(status, Status::Active | Status::Trial) { /* ... */ } // shape test, no PartialEq
```

## `Display` + `Error` for your types

User-facing string is `Display`; debugging is `Debug`. For error types use `thiserror`
(→ `rust-errors`) rather than hand-writing `Display`/`Error`.

```rust
impl std::fmt::Display for Money {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "${}.{:02}", self.dollars, self.cents)
    }
}
```

## Derives, in the conventional order

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Default)]
struct Point { x: i32, y: i32 }
```

Derive `Debug` on essentially everything public. Add `Serialize, Deserialize` after the std
derives. Don't derive `Copy` on types that own heap data (it won't compile) or large types. A
`Debug` impl should never be empty — `{:?}` must print something useful (the derive guarantees
this; don't hand-write a no-op).

## Visibility: expose the minimum

```rust
mod internal {
    pub(crate) fn helper() {}   // visible in the crate, not the public API
}
pub fn api() {}                 // pub only at the real boundary
```

A smaller `pub` surface is less to document, test, and keep stable. Prefer `pub(crate)` until
something genuinely needs to be public.

## Accept borrows, return owned

```rust
fn greet(name: &str) -> String { format!("hi {name}") }   // flexible in, owned out
fn longest(items: &[Item]) -> Option<&Item> { /* ... */ } // slice, not &Vec
```

Details and the `Cow` "borrow-usually-own-sometimes" return → `rust-ownership`.

## Plug into std: implement the traits callers expect

These impls let your types compose with `for`, `.collect()`, and generic std functions — being a
good ecosystem citizen costs a few lines and saves every caller a workaround.

```rust
// A collection you own: FromIterator enables .collect(), Extend enables .extend().
impl FromIterator<Item> for Bag { /* ... */ }
impl Extend<Item> for Bag {
    fn extend<I: IntoIterator<Item = Item>>(&mut self, it: I) { /* ... */ }
}
let bag: Bag = items.into_iter().collect();

// Take readers/writers generically, by value — works with File, TcpStream, Vec<u8>, Cursor, ...
fn write_report<W: Write>(mut w: W, r: &Report) -> io::Result<()> { writeln!(w, "{r}") }
fn parse_stream<R: Read>(mut r: R) -> io::Result<Data> { /* ... */ }

// Integer-/flag-like types: offer the alternative bases callers reach for with {:x}/{:o}/{:b}.
impl fmt::LowerHex for Mask { /* ... */ }   // plus UpperHex / Octal / Binary as relevant
```

- **`FromIterator` + `Extend`** on a collection you define (C-COLLECT) — `.collect()` / `.extend()`
  then work without callers writing a loop.
- **`R: Read` / `W: Write` by value** (C-RW-VALUE), not `&mut File` — the caller picks the
  source/sink, and `&mut R` itself impls the trait, so passing a borrow still works.
- **`Hex`/`Octal`/`Binary`** for numeric and bitflag types (C-NUM-FMT) so `{:x}`/`{:b}` format them.

## OOP design vocabulary in Rust (GoF & SOLID)

craft is organized by *mechanism*, not by GoF/SOLID name — so the patterns you know from OOP mostly
already live here under their Rust form. These tables are a bridge: they map the name you'd search
for to how Rust expresses it and the craft skill that owns it. The fuller catalog (and the patterns
craft deliberately skips) is in the
[Rust Design Patterns book](https://rust-unofficial.github.io/patterns/).

### GoF patterns → Rust

| GoF pattern | Rust form | Owns it | What to avoid |
|---|---|---|---|
| Strategy | choose a dispatch mechanism (generics / `dyn` / enum / a `fn`/closure field) | `rust-traits` (dispatch) | a `StrategyFactory` interface hierarchy — pick a dispatch and move on |
| State | an enum + `match`, or typestate for compile-checked transitions | `rust-traits` (type-driven) | a `dyn State` that downcasts to recover its type |
| Command | an enum of actions (+ `match`), or a boxed `FnOnce` | `rust-traits` (dispatch) | a `Command` trait with one `execute()` impl per verb when an enum fits |
| Observer | channels (`mpsc`/broadcast) or a `Vec` of callbacks | `rust-concurrency` | a self-referential observer graph fighting the borrow checker |
| Visitor | `match` for a closed variant set; a visitor trait for an open one | `rust-traits` — see [dispatch.md](../rust-traits/dispatch.md) | a visitor trait when a plain `match` over your own enum is enough |
| Builder | chainable `with_*` methods; typestate builder for required fields | `rust-idioms` / `rust-traits` | a builder for a struct `Default` + struct-update already handles |
| Newtype | a tuple struct wrapping one field | `rust-traits` (type-driven) | `Deref` to fake inheritance (see [anti-patterns.md](anti-patterns.md)) |
| RAII guard | a value whose `Drop` releases the resource | `rust-ownership` (pointers) | a manual `close()`/`release()` the caller must remember |
| Fold / accumulator | `Iterator::fold` / `try_fold` | `rust-idioms` / `rust-performance` | a hand-rolled accumulator loop where an iterator reads clearer |
| Generics as type classes | generic bounds `T: Trait` | `rust-traits` | reaching for `dyn` when a generic bound expresses the constraint |
| Object-Based API / Wrapper (FFI) | an opaque handle + a safe wrapper over the raw pointer | `rust-unsafe` (ffi) | leaking raw pointers across the FFI boundary |

Intentionally out of scope (use the book): **Interpreter**, **Functional Optics** — niche enough
that craft doesn't carry them.

### SOLID principles → Rust

| Principle | Rust form | Owns it | What to avoid |
|---|---|---|---|
| **S** — Single Responsibility | module/type cohesion; flagged as god-modules and giant functions in review | `rust-architecture-review`, `rust-review` | a `utils`/`manager` module that accretes unrelated responsibilities |
| **O** — Open/Closed | the **expression problem**: an enum is closed to new types but open to new operations; a trait is open to new types but closed to new operations — pick by the axis you expect to extend | `rust-traits` (dispatch; ties to Visitor) | forcing `dyn` extensibility on a set that is actually closed, or vice-versa |
| **L** — Liskov substitution | largely *dissolves* — Rust has no implementation inheritance; what remains is "honor the trait's documented contract/laws" (a total `Ord`, a `Hash` consistent with `Eq`) | `rust-traits`, `rust-idioms` | an impl that breaks the trait's laws (e.g. a partial order claiming to be total `Ord`) |
| **I** — Interface Segregation | many small, focused traits (std splits `Read`/`Write`/`Seek`); object-safety pushes the same way | `rust-traits` | one fat trait forcing impls to stub methods they don't support |
| **D** — Dependency Inversion | ports as traits: the domain depends on a trait, adapters implement it, dependencies flow toward the domain | `rust-architecture` (ports) | the domain `use`-ing a concrete adapter (sqlx, axum) directly |