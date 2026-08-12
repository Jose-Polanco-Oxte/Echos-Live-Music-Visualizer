# Smart pointers and interior mutability

All single-threaded here. The moment data crosses threads, swap `Rc`→`Arc` and `RefCell`→`Mutex`
and read `rust-concurrency` — the *why* lives there.

## `Box<T>` — owned heap allocation

One owner, value on the heap. Three reasons to reach for it:

```rust
// 1. Recursive type — needs a known size, so box the recursive edge
enum List { Cons(i32, Box<List>), Nil }

// 2. Trait object — store "some T that impls Trait" behind a pointer
let shapes: Vec<Box<dyn Shape>> = vec![Box::new(Circle), Box::new(Square)];

// 3. Move a large value without copying it around by value
let big = Box::new([0u8; 1_000_000]);
```

## `Rc<T>` — shared ownership (single thread)

When one value needs **multiple owners** and there's no single clear owner. Reference-counted;
dropped when the last `Rc` goes. `Rc` gives **shared, immutable** access.

```rust
use std::rc::Rc;
let a = Rc::new(vec![1, 2, 3]);
let b = Rc::clone(&a);          // cheap: bumps the count, no deep copy
assert_eq!(Rc::strong_count(&a), 2);
```

`Rc::clone` is explicit on purpose — it signals "new owner," not "deep copy."

## `Cell<T>` / `RefCell<T>` — interior mutability

Mutate through a shared `&` reference. They move the borrow rule from compile time to **runtime**.

```rust
use std::cell::{Cell, RefCell};

let counter = Cell::new(0);     // Copy values: get/set/replace, no borrows
counter.set(counter.get() + 1);

let log = RefCell::new(Vec::new());   // non-Copy: hands out borrows at runtime
log.borrow_mut().push("event");       // panics if a conflicting borrow is live
```

`RefCell` enforces the same "many `&` or one `&mut`" rule — but a violation **panics at
runtime** (`already borrowed`) instead of failing to compile. Keep `borrow_mut()` scopes short.

## `Rc<RefCell<T>>` — shared *and* mutable (single thread)

The combination for graph-like structures: many owners, each able to mutate.

```rust
use std::rc::Rc;
use std::cell::RefCell;

let shared = Rc::new(RefCell::new(0));
let clone = Rc::clone(&shared);
*clone.borrow_mut() += 1;
assert_eq!(*shared.borrow(), 1);
```

Use it when you actually need shared mutation; if a single owner with `&mut` works, prefer that —
`Rc<RefCell<T>>` trades compile-time guarantees for runtime checks.

## `Weak<T>` — break cycles

`Rc` cycles leak (the count never hits zero). Make one direction `Weak` — a non-owning
reference that doesn't keep the value alive.

```rust
use std::rc::{Rc, Weak};
use std::cell::RefCell;

struct Node {
    parent: RefCell<Weak<Node>>,    // child -> parent: weak, no ownership
    children: RefCell<Vec<Rc<Node>>>, // parent -> children: strong
}
// upgrade() turns a Weak into Option<Rc> if the value is still alive
let p: Option<Rc<Node>> = node.parent.borrow().upgrade();
```

Owner→owned edges are `Rc` (strong); back-references are `Weak`.

## `Arc` — the threaded cousin (pointer here, details elsewhere)

`Arc<T>` is `Rc` with an atomic count, so it's `Send`/`Sync`-safe to share across threads; for
shared mutation across threads you pair it with `Mutex`/`RwLock`, not `RefCell`. All of that —
plus `Send`/`Sync`, poisoning, and deadlocks — is `rust-concurrency`. Single thread: stay with
`Rc`/`RefCell` (cheaper, no atomics).

## `Drop` — RAII cleanup, and its two rules

A type with a `Drop` impl runs cleanup when its owner leaves scope (fields drop in declaration
order, locals in reverse). This is RAII: tie a resource to a value and release it automatically.

```rust
struct TempFile { path: PathBuf }
impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);   // best-effort; ignore the error
    }
}
```

Two rules the API guidelines call out:

- **A destructor must never panic** (C-DTOR-FAIL). If `drop` panics *while another panic is
  unwinding*, the process aborts. Keep cleanup infallible — ignore/log errors (`let _ = …`), don't
  `unwrap`. If teardown can genuinely fail and the caller should handle it, give them an explicit
  `fn close(self) -> Result<…>` and leave `Drop` as the best-effort fallback.
- **`Drop` can't run async or block usefully** (C-DTOR-BLOCK). `drop` is sync and can't `.await`;
  blocking inside it (sync I/O, `block_on`) stalls the executor thread. For cleanup that must flush
  or close over the network, expose an explicit `async fn shutdown(self)` / `close().await` →
  `rust-concurrency` (async cleanup).

To release early, call the free function `drop(value)` — you can't call `.drop()` directly.

The patterns built on `Drop` — RAII *guards* (cleanup that survives early return and panic),
scope guards with transaction-rollback "defuse", and lazy initialization (`OnceLock`/`LazyLock`)
— are in [lifecycle.md](lifecycle.md).

## Which one?

| Owners | Mutable? | Threads | Use |
|---|---|---|---|
| one | via `&mut` | 1 | plain `T` / `Box<T>` |
| one | through `&` | 1 | `RefCell<T>` (`Cell` if `Copy`) |
| many | no | 1 | `Rc<T>` |
| many | yes | 1 | `Rc<RefCell<T>>` |
| many | no | N | `Arc<T>` → `rust-concurrency` |
| many | yes | N | `Arc<Mutex<T>>` → `rust-concurrency` |
