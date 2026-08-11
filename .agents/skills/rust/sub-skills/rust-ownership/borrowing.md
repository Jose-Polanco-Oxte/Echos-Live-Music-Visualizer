# Borrowing: the borrow checker and how to satisfy it

The rule again: **either** many `&T` **or** one `&mut T`, never both, and no reference outlives
its value. Modern Rust uses *non-lexical lifetimes* (NLL) — a borrow ends at its **last use**,
not at the end of the block. Many "conflicts" disappear once you see that.

## E0382 — use of moved value

```rust
// Bad — `s` is moved into `print`, then used again
fn print(s: String) { println!("{s}"); }
let s = String::from("hi");
print(s);
println!("{s}");   // ✗ E0382: value used after move
```

Fixes, in order of preference:

```rust
// 1. Borrow instead of move — the usual fix
fn print(s: &str) { println!("{s}"); }
print(&s);
println!("{s}");   // ✓ s still owned

// 2. Reorder so the move is the last use
println!("{s}");
print(s);          // ✓ no use after this

// 3. Clone — only when you genuinely need a second owned copy
let s2 = s.clone();
print(s);
println!("{s2}");
```

`.clone()` is the last resort, not the first. Reaching for it to silence E0382 usually means a
`&` would have worked — that's a HIGH finding in `rust-review`.

## E0502 — `&` and `&mut` at the same time

```rust
let mut v = vec![1, 2, 3];
let first = &v[0];      // shared borrow
v.push(4);              // ✗ E0502: needs &mut while `first` is alive
println!("{first}");
```

```rust
// Fix: copy the value out so the shared borrow ends before the mutation
let first = v[0];       // i32 is Copy — `first` no longer borrows v
v.push(4);              // ✓
println!("{first}");
```

When the read value isn't `Copy`, finish using it (NLL ends the borrow) before mutating, or
clone the bit you need.

## E0499 — two `&mut` at once / split borrows

```rust
struct Point { x: i32, y: i32 }
let mut p = Point { x: 0, y: 0 };
let a = &mut p.x;
let b = &mut p.y;       // OK in modern Rust — disjoint fields
*a += 1; *b += 1;
```

The borrow checker tracks **fields** separately, so two `&mut` to *different* fields are fine.
It can't split through a method call, though:

```rust
// Bad — method borrows all of self
let a = p.x_mut();
let b = p.y_mut();      // ✗ E0499: second &mut self
```

For slices/vecs, use the std splitters instead of two indexed `&mut`:

```rust
let mut v = vec![1, 2, 3, 4];
let (left, right) = v.split_at_mut(2);   // two disjoint &mut [i32]
left[0] += right[0];
```

## E0505 — move while borrowed

```rust
let s = String::from("hi");
let r = &s;
drop(s);          // ✗ E0505: move out of s while borrowed by r
println!("{r}");
```

Fix: ensure the borrow's last use precedes the move (NLL), or don't move until the reference is
done.

## E0507 — cannot move out of borrowed content

You have `&T` (or `&mut T`) and try to move a non-`Copy` field out:

```rust
fn take(opt: &mut Option<String>) -> String {
    opt.unwrap()             // ✗ E0507: moves String out of &mut
}
```

```rust
// std::mem::take leaves a default (None) behind and hands you the value
fn take(opt: &mut Option<String>) -> Option<String> {
    std::mem::take(opt)      // ✓
}
// or mem::replace to leave something specific; or .clone() to copy it out
```

## Iterating without moving

```rust
let v = vec![String::from("a"), String::from("b")];

for s in &v { println!("{s}"); }      // &String — v still usable after

let mut v = v;                        // rebind as mutable
for s in &mut v { s.push('!'); }      // &mut String — mutate in place

for s in v { println!("{s}"); }       // moves each String OUT of v; v consumed (do this last)
```

Choosing `into_iter` (move) vs `iter` (`&`) vs `iter_mut` (`&mut`) is the most common
ownership decision in everyday code — pick by what you need to do to the elements.

## When clone is the right answer

Cloning isn't forbidden — it's wrong only when it *hides* a borrow that would have worked.
Legitimate clones: small `Copy`-ish data, breaking a self-referential tangle, handing an owned
value to a thread, or when the clone is genuinely cheap relative to the code's job. Make it a
deliberate choice, not a reflex to make the compiler stop talking.
