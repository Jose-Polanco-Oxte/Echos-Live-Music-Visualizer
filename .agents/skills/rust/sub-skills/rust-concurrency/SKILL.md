---
name: rust-concurrency
description: >-
  Rust concurrency and async — threads vs async, Send/Sync, sharing with Arc/Mutex/RwLock, channels, tokio tasks, holding locks across await, and deadlocks. Use when parallelizing work, sharing state across threads, choosing threads vs async, or fixing Send/Sync errors and deadlocks. Triggers: tokio, Send/Sync, mpsc, deadlock, future is not Send, rayon, parking_lot.
---

# Rust Concurrency

Two questions decide everything: **what kind of work** (CPU vs I/O) and **what's the sharing
model** (messages vs shared memory). Get those right and the `Send`/`Sync` errors resolve
themselves. Mechanics in the sub-files.

## When to Use

- Parallelizing work across threads, or running many I/O tasks concurrently
- Sharing state across threads (`Arc`, `Mutex`, `RwLock`, channels)
- Deciding between OS threads and async
- Fixing "cannot be sent between threads" / "future is not `Send`" / deadlocks

## Decision 1 — threads or async?

| Workload | Use | Why |
|---|---|---|
| CPU-bound (compute, parsing, hashing) | OS threads — `std::thread`, or `rayon` for data parallelism | real parallelism across cores; async gives you nothing here |
| I/O-bound (network, many sockets, DB) | async — `tokio` | thousands of cheap tasks, no thread-per-connection |
| Mixed | async runtime + `spawn_blocking` for the CPU/blocking parts | keep the executor unblocked |

Don't reach for async by default. If you have a handful of CPU tasks, threads are simpler and
faster. Async earns its complexity at high I/O concurrency. Details: [threads.md](threads.md),
[async.md](async.md).

## Decision 2 — how do threads share?

| Sharing | Use |
|---|---|
| Nothing — hand off ownership | channels (message passing) — the default, fewest footguns |
| Read-only shared data | `Arc<T>` |
| Shared mutable data | `Arc<Mutex<T>>` (or `Arc<RwLock<T>>` for read-heavy) |
| Simple counters/flags | atomics (`AtomicUsize`, `AtomicBool`) |

Prefer message passing. "Share memory by communicating" — channels turn data races into
ownership transfers the compiler already checks.

Higher-level compositions — structured concurrency (`JoinSet`), cooperative cancellation
(`CancellationToken`), the **actor pattern** (own state in one task), graceful shutdown of a task
tree, and choosing `watch`/`broadcast`/`DashMap` — are in [patterns.md](patterns.md).

## `Send` and `Sync`

Two auto-traits the compiler derives; they're the whole basis of thread safety.

- **`Send`** — a value can be **moved** to another thread. Almost everything is; `Rc` and raw
  pointers are not.
- **`Sync`** — `&T` can be **shared** across threads (equivalently: `T: Sync` ⇔ `&T: Send`).
  `Mutex`/`RwLock` are `Sync`; `RefCell`/`Cell` are **not**.

The single-thread vs multi-thread pointer pairs:

| Single thread (`rust-ownership`) | Across threads (here) |
|---|---|
| `Rc<T>` (not `Send`/`Sync`) | `Arc<T>` (atomic count) |
| `RefCell<T>` (not `Sync`) | `Mutex<T>` / `RwLock<T>` |

## Error → fix

| Error | Cause | Fix |
|---|---|---|
| **E0277** `Rc` cannot be sent between threads | `Rc`/`RefCell` shared across threads | `Rc`→`Arc`, `RefCell`→`Mutex`; or pass via a channel |
| **E0277** future is not `Send` | a non-`Send` value (e.g. `Rc`, `MutexGuard`) is **held across an `.await`** | drop it before the await, or don't use a non-`Send` type (see [async.md](async.md)) |
| closure may outlive borrowed value (spawn) | thread closure borrows a local | `move` the data in, or use `std::thread::scope` (see [threads.md](threads.md)) |
| deadlock (no error — it hangs) | locks acquired in inconsistent order, or a lock held across `.await` | consistent lock order; never hold a lock across `.await` |

## Defects vs failures here

A poisoned `Mutex` (`lock()` returns `Err` because a holder panicked) is a **defect**, not a
domain failure — see the failures-vs-defects model in `rust-errors`. Don't model `PoisonError`
as a recoverable case; `unwrap()`/`expect()` the lock or propagate it as opaque.

## Boundary

- Single-threaded sharing/mutation (`Rc`, `RefCell`, `Cell`) → `rust-ownership`.
- Timeouts and retry around concurrent I/O → `rust-errors` (recovery).
