# Concurrency patterns: structured tasks, cancellation, actors, shutdown

The primitives in [threads.md](threads.md)/[async.md](async.md) compose into a few patterns that
keep concurrent code correct under failure and shutdown. Most use `tokio-util`:

```toml
[dependencies]
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync"] }
tokio-util = "0.7"   # CancellationToken, TaskTracker
```

## Structured concurrency — `JoinSet`

Don't scatter `tokio::spawn` and forget the handles — orphan tasks leak and swallow errors.
A `JoinSet` owns a group of tasks so you await them together and propagate the first failure:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
for job in jobs { set.spawn(async move { process(job).await }); }   // task body returns a Result -> enables joined??

let mut results = Vec::new();
while let Some(joined) = set.join_next().await {
    let out = joined??;          // ?? : first ? = JoinError (panic/abort), second = your Result
    results.push(out);
}
// Dropping the JoinSet aborts any still-running tasks — no orphans.
```

To fail fast: on the first `Err`, drop/abort the set so siblings stop instead of running on
wastefully.

## Cancellation — `CancellationToken`

Async tasks are cancelled by **dropping** their future, but you often need *cooperative*
cancellation across a tree of tasks. A shared token broadcasts "stop":

```rust
use tokio_util::sync::CancellationToken;

let token = CancellationToken::new();
let child = token.clone();
tokio::spawn(async move {
    loop {
        tokio::select! {
            _ = child.cancelled() => break,        // someone called token.cancel()
            item = source.next()  => handle(item).await,
        }
    }
    // cleanup runs here, deterministically
});

// later, from anywhere:
token.cancel();                                    // every clone's cancelled() resolves
```

`select!` on `cancelled()` is how a long-running task stays interruptible. Mind **cancel safety**
(async.md): only `.await` cancel-safe operations in `select!` arms, or a dropped branch may leave
half-done state.

## The actor pattern — own state in one task, talk via channels

The idiomatic Rust answer to "shared mutable state" is often **no sharing**: give the state to one
task and send it messages. No `Arc<Mutex>`, no lock contention, no deadlocks.

```rust
use tokio::sync::{mpsc, oneshot};

enum Msg { Get { key: String, reply: oneshot::Sender<Option<String>> } }

struct Actor { rx: mpsc::Receiver<Msg>, store: std::collections::HashMap<String, String> }
impl Actor {
    async fn run(mut self) {
        while let Some(msg) = self.rx.recv().await {   // ends when all handles drop
            match msg {
                Msg::Get { key, reply } => { let _ = reply.send(self.store.get(&key).cloned()); }
            }
        }
    }
}

#[derive(Clone)]
pub struct Handle { tx: mpsc::Sender<Msg> }           // cheap to clone, share freely
impl Handle {
    pub async fn get(&self, key: String) -> Option<String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Msg::Get { key, reply }).await.ok()?;
        rx.await.ok().flatten()                        // request/response over oneshot
    }
}
```

State is single-owned and `Send`-clean; the `Handle` is the public API. Bounded `mpsc` gives
back-pressure. This is the standard pattern for connection managers, caches, schedulers.

## Graceful shutdown of a task tree — `TaskTracker` + token

Combine the two: a token to *signal* stop, a tracker to *wait* for tasks to drain.

```rust
use tokio_util::{sync::CancellationToken, task::TaskTracker};

let tracker = TaskTracker::new();
let token = CancellationToken::new();

for w in 0..workers {
    let (t, tk) = (tracker.clone(), token.clone());   // TaskTracker is cheap to clone
    t.spawn(async move {
        tokio::select! { _ = tk.cancelled() => {}, _ = worker(w) => {} }
    });
}
tracker.close();                 // no more tasks will be added

shutdown_signal().await;         // SIGTERM/ctrl-c (→ rust-cloud-native)
token.cancel();                  // tell everyone to stop
tracker.wait().await;            // wait for in-flight work to finish, then exit
```

## Async cleanup needs an explicit `shutdown().await` — `Drop` can't await

`Drop` is synchronous: it can't `.await`, and blocking inside it (`block_on`, sync I/O) stalls the
runtime. So a type holding an async resource — a connection that must send a close frame, a writer
that must flush over the network — can't clean itself up in `Drop` the way a `File` can. Give it an
explicit async teardown and call it before the value drops:

```rust
impl Connection {
    pub async fn shutdown(mut self) -> Result<(), Error> {
        self.flush().await?;            // the work Drop cannot do
        self.send_close_frame().await?;
        Ok(())
    }
}

let conn = Connection::connect(addr).await?;
// ... use conn ...
conn.shutdown().await?;                 // explicit — don't rely on Drop
```

Keep a best-effort `Drop` as a backstop (abort/log if `shutdown` wasn't called), but the correct
path is the explicit `await`. This is the async face of the destructor rules in `rust-ownership`
(Drop); `AsyncWriteExt::shutdown` and `Sink::close` follow the same shape.

## Choosing a shared-state primitive

When sharing *is* the right model, pick by access pattern:

| Need | Use |
|---|---|
| exclusive mutation, short critical section | `Mutex<T>` |
| many readers, rare writer | `RwLock<T>` |
| broadcast the *latest* value (config, state) | `tokio::sync::watch` |
| fan out *every* event to many consumers | `tokio::sync::broadcast` |
| a concurrent map that's the contention point | `dashmap::DashMap` (`dashmap = "6"`) — sharded, no global lock |
| a counter / flag | an atomic (threads.md) |

Default to **message passing** (channels/actor) over shared mutable state; reach for locks only
when the data genuinely must be shared in place.
