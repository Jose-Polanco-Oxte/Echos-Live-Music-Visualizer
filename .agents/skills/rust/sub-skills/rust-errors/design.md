# Error design: thiserror, anyhow, and the boundary between them

## Libraries — `thiserror`

A library's errors are part of its public API. Make them a typed enum so callers can match.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("record not found: {id}")]
    NotFound { id: String },

    #[error("connection to {host}:{port} failed")]
    Connection {
        host: String,
        port: u16,
        #[source]                      // preserves the cause for the error chain
        source: std::io::Error,
    },

    #[error(transparent)]              // delegate Display+source to the inner error
    Other(#[from] anyhow::Error),

    #[error("invalid data: {0}")]
    InvalidData(String),
}
```

- `#[error("…")]` is the `Display` impl; `{field}` / `{0}` interpolate fields.
- `#[from]` generates `From<Inner>` **and** sets it as the source — this is what powers `?`.
- `#[source]` marks the cause without generating `From` (use when several variants wrap the
  same inner type, which would make multiple `From` impls ambiguous).
- `#[error(transparent)]` forwards `Display` and `source` to the wrapped error — for a single
  pass-through variant.

Expose a crate `Result` alias so signatures stay short:

```rust
pub type Result<T> = std::result::Result<T, StorageError>;

pub fn get(id: &str) -> Result<Record> { /* ... */ }
```

Keep library error types `Send + Sync + 'static` so they work in async and can be boxed.

### thiserror 2.0 notes

`thiserror` 2.0 is a drop-in for most 1.0 code; it adds more flexible format-string field
access (e.g. referencing fields by name in more positions) and improved support for generic
error types. The derive attributes above are unchanged.

## Failures vs defects, in practice

ZIO splits the error channel `E` (typed, recoverable failures) from defects (untyped, fatal).
Rust has the same split — `Result`'s `E` vs `panic!` — but keeping the enum disciplined is on you.

**Keep the domain enum narrow** — only variants a caller branches on. Collapse everything
unexpected into one opaque variant that callers bubble up instead of matching:

```rust
#[derive(Debug, thiserror::Error)]
pub enum OrderError {
    #[error("order {0} not found")]
    NotFound(OrderId),
    #[error("insufficient funds: need {need}, have {have}")]
    InsufficientFunds { need: Money, have: Money },

    // The "carry a defect" escape hatch: unexpected failures ride here, untyped.
    // Callers don't match it — they propagate it.
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}
```

A caller handles the real cases and lets the rest flow:

```rust
match place_order(id) {
    Err(OrderError::InsufficientFunds { need, have }) => prompt_topup(need - have),
    Err(OrderError::NotFound(_))                      => show_404(),
    Err(e)                                            => return Err(e), // Internal: not ours to handle
    Ok(order)                                         => confirm(order),
}
```

**Turn a "can't fail here" `Result` into a defect** — ZIO's `orDie`. When *this* call site has
already proven the precondition, an `Err`/`None` is a bug, not a domain case → panic with a
message:

```rust
// We inserted this key one line above; its absence is an invariant violation, not a failure.
let v = cache.get(&key).expect("key inserted above must be present");
```

**Recover defects only at the edge** — ZIO's `catchAllCause` at the boundary. A defect inside
one request must not crash the server: map the opaque `Internal` to 500 and log the detail
(never leak it):

```rust
ApiError::Internal(e) => {
    tracing::error!("{e:#}");                              // defect detail -> logs only
    (StatusCode::INTERNAL_SERVER_ERROR, "internal error") // generic message -> client
}
```

The discipline in one line: **domain failures are typed and few; defects panic, or ride in one
opaque variant and are handled only at the process/request boundary.**

## Applications — `anyhow`

A binary doesn't need a typed taxonomy — it needs to report and exit. `anyhow::Error` boxes
any `std::error::Error` and accumulates context.

```rust
use anyhow::{Context, Result, bail, ensure};

fn load(path: &str) -> Result<Config> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("reading {path}"))?;

    ensure!(!raw.is_empty(), "{path} is empty");

    let cfg: Config = toml::from_str(&raw)
        .with_context(|| format!("parsing {path}"))?;

    if cfg.workers == 0 {
        bail!("workers must be > 0");
    }
    Ok(cfg)
}

fn main() -> Result<()> {
    let cfg = load("app.toml").context("startup failed")?;
    run(cfg)
}
```

Printing with `{:#}` (or returning `Result` from `main`) shows the full chain:

```text
Error: startup failed
Caused by:
    0: parsing app.toml
    1: TOML parse error at line 3 ...
```

`thiserror` typed errors slot straight into `anyhow` via `?` (they implement `Error`), so the
app layer never has to enumerate library variants — unless it wants to branch on one:

```rust
match storage::get(id) {                 // returns Result<_, StorageError>
    Ok(rec) => Ok(rec),
    Err(StorageError::NotFound { .. }) => Ok(Record::default()), // handle one case
    Err(e) => Err(e.into()),             // everything else -> anyhow::Error
}
```

To recover a typed error back out of an `anyhow::Error`, use `downcast_ref`:

```rust
if let Some(StorageError::NotFound { id }) = err.downcast_ref::<StorageError>() {
    // special-case
}
```

## The layering rule

```
Application (anyhow): add context at boundaries, log, map to user/exit code
        ▲  uses
Service  (your error or anyhow): map between layers, attach business context
        ▲  uses
Library  (thiserror): typed variants, #[source] chains, NO logging
```

Logging belongs at the application boundary, not inside libraries — a library that logs robs
the caller of the choice. Libraries return; applications decide and report.

## Mapping errors to the outside world

### HTTP (axum)

```rust
use axum::{response::IntoResponse, http::StatusCode, Json};

pub enum ApiError {
    NotFound(String),
    BadRequest(String),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        let (status, msg) = match self {
            ApiError::NotFound(m)   => (StatusCode::NOT_FOUND, m),
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            ApiError::Internal(e)   => {
                tracing::error!("{e:#}");                 // log internals, don't leak them
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into())
            }
        };
        (status, Json(serde_json::json!({ "error": msg }))).into_response()
    }
}
```

### CLI

```rust
fn main() {
    if let Err(e) = run() {
        eprintln!("error: {e:#}");   // full chain
        std::process::exit(1);
    }
}
```
