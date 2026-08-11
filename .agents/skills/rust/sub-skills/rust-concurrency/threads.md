# Threads: spawn, share, synchronize

For CPU-bound work and real parallelism across cores.

## Spawning

```rust
use std::thread;

let handle = thread::spawn(move || {        // `move` takes ownership of captures
    expensive_compute()
});
let result = handle.join().unwrap();        // join returns the closure's value
```

A spawned closure must be `Send + 'static`: it may outlive the spawning function, so it can't
borrow locals. Either `move` owned data in, or use scoped threads.

## Scoped threads — borrow locals safely

`std::thread::scope` guarantees all threads finish before it returns, so they *can* borrow
stack data without `'static`:

```rust
let data = vec![1, 2, 3];
std::thread::scope(|s| {
    s.spawn(|| println!("{:?}", &data));    // borrows data — no move, no Arc needed
    s.spawn(|| println!("len {}", data.len()));
}); // all scoped threads joined here
```

This removes most needs for `Arc` when the work is bounded to a scope.

## Data parallelism — `rayon`

For "do this to every element in parallel," `rayon` is the easy win — change `iter` to
`par_iter`:

```rust
use rayon::prelude::*;
let total: u64 = items.par_iter().map(|x| heavy(x)).sum();
```

```toml
[dependencies]
rayon = "1"
```

Reach for `rayon` before hand-rolling a thread pool for CPU-bound collection work.

## Shared mutable state — `Arc<Mutex<T>>`

When threads must share *and* mutate, wrap the data:

```rust
use std::sync::{Arc, Mutex};
use std::thread;

let counter = Arc::new(Mutex::new(0));
let mut handles = vec![];
for _ in 0..4 {
    let c = Arc::clone(&counter);
    handles.push(thread::spawn(move || {
        let mut n = c.lock().unwrap();      // guard; lock released when `n` drops
        *n += 1;
    }));
}
for h in handles { h.join().unwrap(); }
assert_eq!(*counter.lock().unwrap(), 4);
```

`RwLock<T>` instead of `Mutex<T>` when reads vastly outnumber writes (many concurrent readers,
exclusive writer). Keep critical sections short — hold the guard only as long as needed.

### Poisoning

If a thread panics while holding the lock, the `Mutex` is *poisoned* and later `lock()` calls
return `Err(PoisonError)`. That's a **defect** (a holder already crashed), not a domain case —
`unwrap()` it or propagate opaquely (see `rust-errors`). `.lock().unwrap()` is the norm.

### `parking_lot` — faster, non-poisoning alternative

`parking_lot::Mutex` / `RwLock` are smaller and faster under low contention, and **don't poison** —
`lock()` returns the guard directly, no `unwrap()`:

```rust
// parking_lot = "0.12"
let counter = Arc::new(parking_lot::Mutex::new(0));
*counter.lock() += 1;          // no unwrap, no PoisonError
```

The trade-offs: a third-party dep, and you lose poisoning as a "holder crashed" signal. `std`'s
locks have closed much of the historical gap — swap only if a profiler shows lock overhead (or the
no-poison ergonomics are worth it to you), and benchmark it (→ `rust-performance`).

## Atomics — lock-free for simple values

For a counter or flag, skip the mutex:

```rust
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

let hits = Arc::new(AtomicUsize::new(0));
hits.fetch_add(1, Ordering::Relaxed);       // Relaxed is fine for a plain counter
let n = hits.load(Ordering::Relaxed);
```

Use `Relaxed` for independent counters; reach for `Acquire`/`Release` only when an atomic guards
*other* memory (publishing a value). When in doubt and it's not a hot path, a `Mutex` is easier
to reason about than picking orderings.

## Channels — share by communicating

```rust
use std::sync::mpsc;
use std::thread;

let (tx, rx) = mpsc::channel();              // unbounded; sync_channel(n) for bounded
for id in 0..3 {
    let tx = tx.clone();                     // multiple producers
    thread::spawn(move || tx.send(id * 10).unwrap());
}
drop(tx);                                    // drop the original so rx ends
for msg in rx { println!("got {msg}"); }    // iterates until all senders drop
```

Prefer `sync_channel(n)` (bounded) for back-pressure — an unbounded channel under a fast
producer is an unbounded memory leak.

## Avoiding deadlock

A deadlock isn't a compile error — the program just hangs. Rules:

- **Acquire multiple locks in a consistent global order** everywhere.
- Hold one lock at a time when you can; never call back into code that locks the same mutex.
- Keep critical sections tiny; don't do I/O or call unknown code while holding a lock.
- `try_lock()` to fail fast instead of blocking when contention is expected.
