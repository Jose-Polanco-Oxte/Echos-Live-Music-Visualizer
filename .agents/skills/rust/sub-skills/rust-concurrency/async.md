# Async: tokio tasks, Send futures, and the await traps

For I/O-bound work: thousands of concurrent tasks on a few threads. The hard parts are all
about what happens **at an `.await`**.

```toml
[dependencies]
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "time"] }
```

## Runtime and tasks

```rust
#[tokio::main]                       // sets up the multi-thread runtime
async fn main() {
    let handle = tokio::spawn(async {    // a task — scheduled onto the runtime
        fetch("https://example.com").await
    });
    let body = handle.await.unwrap();    // await the task's result
}
```

`async fn` returns a `Future` that does nothing until polled (`.await`ed or `spawn`ed). An
`.await` is a **yield point**: the task may suspend there and the thread runs other tasks.

## The Send rule for tasks

`tokio::spawn` requires the future to be `Send + 'static` — it can move between worker threads.
A future is `Send` only if **everything held across an `.await`** is `Send`. This is the #1
async error:

```rust
// Bad — Rc is not Send, and it's alive across the await -> "future cannot be sent"
let counter = std::rc::Rc::new(0);
tokio::spawn(async move {
    do_io().await;            // counter is held across this await
    println!("{counter}");
});
```

```rust
// Fix: use a Send type (Arc), or scope the non-Send value so it's dropped before the await
let counter = std::sync::Arc::new(0);
tokio::spawn(async move {
    do_io().await;
    println!("{counter}");
});
```

A value used only *between* awaits (created and dropped without an await in between) doesn't
have to be `Send` — it never crosses a yield.

## Never hold a lock across `.await`

The most common async deadlock/perf bug:

```rust
// Bad — std MutexGuard held across await: blocks the worker thread, risks deadlock,
// and isn't Send -> future-not-Send error
let mut g = state.lock().unwrap();
g.value = fetch().await;        // ✗ guard alive across await
```

Fixes, in order:

```rust
// 1. Best: don't hold the lock across the await — compute, then lock briefly
let v = fetch().await;
state.lock().unwrap().value = v;

// 2. If you truly must hold it across an await, use tokio's async Mutex
let mut g = state.lock().await;     // tokio::sync::Mutex
g.value = fetch().await;            // allowed, but serializes tasks — use sparingly
```

Prefer the std `Mutex` with short, await-free critical sections; reach for `tokio::sync::Mutex`
only when the lock genuinely must span an await.

## Async channels

`tokio::sync` channels, chosen by shape:

```rust
use tokio::sync::{mpsc, oneshot};

let (tx, mut rx) = mpsc::channel::<Job>(100);   // bounded -> back-pressure (preferred)
tx.send(job).await.unwrap();                    // .await blocks when the buffer is full
while let Some(job) = rx.recv().await { handle(job).await; }

let (done_tx, done_rx) = oneshot::channel();    // single value, request/response
done_tx.send(result).unwrap();
let r = done_rx.await.unwrap();
```

- `mpsc::channel(n)` — bounded work queue (use this); `unbounded_channel()` only with a reason.
- `oneshot` — one task hands one result back to another.
- `broadcast` / `watch` — fan-out / latest-value-state, when you need them.

## Blocking and CPU work inside async

Never run blocking or heavy-CPU code directly in an async task — it stalls the executor thread
and starves every other task. Offload it:

```rust
let parsed = tokio::task::spawn_blocking(move || {
    expensive_sync_parse(&bytes)        // blocking/CPU work on a dedicated pool
}).await.unwrap();
```

Use `spawn_blocking` for blocking I/O and short CPU bursts; for sustained CPU parallelism, do it
on real threads / `rayon` (see [threads.md](threads.md)) and `await` the result via a channel.

## Concurrency within a task

```rust
use tokio::join;
let (a, b) = join!(fetch_a(), fetch_b());   // run both, wait for both

use tokio::select;
select! {                                    // race: take whichever finishes first
    r = fetch() => handle(r),
    _ = tokio::time::sleep(timeout) => give_up(),
}
```

`select!` is how you add a timeout or cancellation. Beware **cancellation safety**: when a
branch loses the race its future is dropped mid-flight — only `.await` cancel-safe operations in
`select!` arms, or restructure so a dropped future leaves no half-done state. (Timeout/retry
patterns themselves: `rust-errors` → recovery.)
