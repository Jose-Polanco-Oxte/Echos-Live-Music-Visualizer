# Lifetimes: annotations, elision, and returning references

A lifetime is not how long a value lives — it's a **region of code** over which a reference is
valid. Annotations don't change behavior; they *describe* relationships the compiler then checks.

## Elision — when you don't write them

Most reference-passing needs no annotations because three rules infer them:

1. Each input reference gets its own lifetime parameter.
2. If there's exactly **one** input lifetime, it's assigned to all outputs.
3. If there's `&self`/`&mut self`, **its** lifetime is assigned to all outputs.

```rust
fn first_word(s: &str) -> &str { /* ... */ }        // rule 2: output borrows from s
impl Doc { fn title(&self) -> &str { &self.title } } // rule 3: output borrows from self
```

You only annotate when elision can't decide — typically multiple input references where the
output could borrow from either.

## E0106 — missing lifetime specifier

```rust
// Bad — which input does the output borrow from?
fn longest(a: &str, b: &str) -> &str { if a.len() > b.len() { a } else { b } }
```

```rust
// Good — say both inputs and the output share lifetime 'a
fn longest<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() > b.len() { a } else { b }
}
```

`'a` here means "the result lives no longer than the shorter of `a` and `b`."

## E0515 — returning a reference to a local

```rust
fn make() -> &str {            // ✗ E0515
    let s = String::from("hi");
    &s                         // s is dropped at return; the ref would dangle
}
```

You can't return a reference to something created inside the function — it's destroyed on
return. Return the **owned** value instead:

```rust
fn make() -> String { String::from("hi") }
```

## E0597 — borrowed value does not live long enough

```rust
let r;
{
    let x = 5;
    r = &x;        // ✗ E0597: x dropped at end of block, r outlives it
}
println!("{r}");
```

Fix by making the owner live at least as long as the borrow — usually hoist the owner up:

```rust
let x = 5;
let r = &x;        // ✓ same scope
println!("{r}");
```

The general cure for "doesn't live long enough": **store the owner, not the borrow.** If a
struct keeps a reference, it needs a lifetime parameter and the referent must outlive it:

```rust
struct Parser<'a> { input: &'a str, pos: usize }   // borrows input for 'a
```

If that lifetime plumbing becomes painful, it's often a signal to **own** the data instead
(`String` rather than `&'a str`) — self-borrowing structs are a known pain point; don't fight it.

## `'static`

`'static` means "valid for the whole program." Two distinct cases:

```rust
let s: &'static str = "literal";   // string literals are baked into the binary
fn spawn<T: Send + 'static>(t: T)  // bound: T contains no non-'static references
```

The bound `T: 'static` does **not** mean "lives forever" — it means "contains no borrowed
references" (owned data like `String` satisfies it). You'll meet this most when moving data
into threads → `rust-concurrency`.

## `Cow` — borrow usually, own when needed

`Cow<'_, str>` ("clone on write") returns a borrow in the common case and only allocates when
it must mutate — the right return type for "I'll usually hand back the input unchanged":

```rust
use std::borrow::Cow;

fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains(' ') {
        Cow::Owned(input.replace(' ', "_"))   // allocate only when changing
    } else {
        Cow::Borrowed(input)                  // zero-cost passthrough
    }
}
```
