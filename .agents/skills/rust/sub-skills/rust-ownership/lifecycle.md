# Resource lifecycle: guards and lazy init

Ownership decides *who* holds a value. Lifecycle decides *when* its cleanup runs and *when* it
comes into being. Two patterns cover most of it — **RAII guards** (cleanup tied to scope, the
generalization of `Drop` from [pointers.md](pointers.md)) and **lazy initialization** (creation
deferred to first use).

## RAII guards — cleanup that can't be forgotten

A *guard* is a value whose whole job is to run code when it drops. It's Rust's `defer`/`finally`
— except it can't be skipped by an early `return`, `?`, `break`, or panic, because `drop` runs on
**every** exit path. Tie the cleanup to a value and the compiler schedules it for you.

```rust
use std::cell::Cell;

/// While this guard is alive, `flag` reads `true`; it flips back on drop — even on panic.
struct BusyGuard<'a> { flag: &'a Cell<bool> }

impl<'a> BusyGuard<'a> {
    fn new(flag: &'a Cell<bool>) -> Self {
        flag.set(true);
        BusyGuard { flag }
    }
}
impl Drop for BusyGuard<'_> {
    fn drop(&mut self) { self.flag.set(false); }
}

fn handle(busy: &Cell<bool>) {
    let _guard = BusyGuard::new(busy);   // ✓ held to end of scope
    do_work_that_might_panic();          // flag still resets if this unwinds
}
```

**The footgun: bind the guard to a name.** `let _ = guard;` drops it *immediately* (the cleanup
runs on the next line, not at scope end); `let _g = guard;` holds it. `std::sync::MutexGuard`
fails the same way — `let _ = m.lock()` unlocks at once.

```rust
let _ = BusyGuard::new(busy);   // ✗ dropped now — flag is already false below
let _guard = BusyGuard::new(busy); // ✓ lives until the block ends
```

## Scope guards — cleanup on every exit, without a custom type

For one-off cleanup you don't want to hang a named struct on, the `scopeguard` crate is the
standard one-file answer. The killer feature is **defuse**: register a rollback that fires by
default, then *cancel* it on the happy path with `ScopeGuard::into_inner`. This is the
transaction idiom — roll back unless we reach the commit.

```rust
use scopeguard::ScopeGuard;

fn transfer(tx: &mut Tx) -> Result<(), Error> {
    tx.debit()?;
    // rolls back automatically on any early return / panic below…
    let guard = scopeguard::guard(&mut *tx, |tx| tx.rollback());
    guard.credit()?;            // if this `?` bails, rollback runs
    ScopeGuard::into_inner(guard); // …reached the commit → defuse the rollback
    tx.commit()
}
```

No dependency? Hand-roll the same as a `Drop` struct holding a closure, or use a bare guard type
as above. To *suppress* a drop deliberately, `std::mem::forget(value)` or `ManuallyDrop` — but
`forget` leaks (the destructor never runs); reach for it only when something else owns the
cleanup (FFI handing a pointer to C → `rust-unsafe`).

## Lazy initialization — create once, on first use

The modern std answer; no crate needed since 1.80. Pick by where the value lives and whether it
crosses threads:

| Need | Use | Notes |
|---|---|---|
| Lazily-initialized global / `static`, computed once | `LazyLock<T>` | replaces `lazy_static!` / `once_cell::sync::Lazy` |
| Lazily fill a struct field / local on first touch | `OnceLock<T>` + `get_or_init` | you control when first-touch happens |
| Same, single-thread only (no atomics) | `LazyCell<T>` / `OnceCell<T>` (`std::cell`) | cheaper; not `Sync` |

```rust
use std::sync::LazyLock;

// First deref runs the closure; every later deref is a cheap load.
static CONFIG: LazyLock<Config> = LazyLock::new(Config::load);

fn port() -> u16 { CONFIG.port }
```

```rust
use std::sync::OnceLock;

struct Client { pool: OnceLock<Pool> }

impl Client {
    // Connect on first call, reuse forever after. Thread-safe: concurrent
    // callers race to init, exactly one closure wins, the rest block then read.
    fn pool(&self) -> &Pool {
        self.pool.get_or_init(|| Pool::connect())
    }
}
```

- **Don't reach for `static mut`** — it's UB-prone and needs `unsafe` (`rust-unsafe`). `LazyLock`/
  `OnceLock` give you a safe, race-free global.
- `OnceLock`/`LazyLock` synchronize the *initialization*; the value itself still needs
  `Send`/`Sync` to be shared across threads → `rust-concurrency`. Init that can **fail** isn't
  served by `get_or_init` (it can't return an error on stable) — `get()` then `set()` by hand, or
  use `once_cell`'s `get_or_try_init`.

## Decision: which lifecycle tool?

| You want | Reach for |
|---|---|
| Release a resource at scope end, every path | `Drop` impl ([pointers.md](pointers.md)) |
| Restore/undo state while a scope is active | a named RAII guard (bind it to `_g`, not `_`) |
| Roll back unless we reach a commit point | `scopeguard::guard` + `ScopeGuard::into_inner` |
| Defer creating an expensive value to first use | `LazyLock` (global) / `OnceLock` (field) |
| Cleanup that must `.await` or flush over the network | explicit `async fn close(self)` → `rust-concurrency` |

## Boundary

- The two `Drop` rules (never panic, never block/`.await`) and *why* live in
  [pointers.md](pointers.md); this file is the patterns built on top of `Drop`.
- Anything that crosses threads (the value behind a `OnceLock`, async cleanup) → `rust-concurrency`.
- `ManuallyDrop` / `mem::forget` for layout control or FFI ownership transfer → `rust-unsafe`.
- Connection *pools* as a wired dependency (`deadpool`/`bb8`/`sqlx::Pool`) → `rust-web`.
