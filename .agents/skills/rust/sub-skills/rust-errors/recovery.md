# Recovery: retry, timeout, fallback, circuit breaker

Returning an error is step one. Resilience is deciding *which* errors to recover from and how.

## First: classify the failure

You cannot recover correctly without knowing the failure's nature.

| Class | Examples | Strategy |
|---|---|---|
| **Transient** | timeout, 503, connection reset, lock contention | retry (with backoff) |
| **Permanent** | 404, validation error, auth failure, parse error | do **not** retry — fail fast |
| **Throttling** | 429, rate-limit | back off, respect `Retry-After` |
| **Catastrophic** | disk full, OOM, config invalid | stop; surface to operator |

Encode this on your error type so callers branch on intent, not on string matching:

```rust
impl StorageError {
    fn is_transient(&self) -> bool {
        matches!(self, StorageError::Connection { .. })
    }
}
```

Retrying a permanent error just multiplies latency and load — the most common recovery bug.

## Timeout

Bound every external call. With tokio:

```rust
use tokio::time::{timeout, Duration};

let resp = timeout(Duration::from_secs(5), client.get(url).send())
    .await                      // Err on timeout
    .map_err(|_| MyError::Timeout)?
    .map_err(MyError::Http)?;   // the inner call's own error
```

## Retry with backoff

Retry only transient failures, with exponential backoff + jitter, and a cap. Hand-rolled:

```rust
use tokio::time::{sleep, Duration};

async fn with_retry<T, E, F, Fut>(mut op: F, max: u32) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, E>>,
    E: Retryable,                  // your trait exposing is_transient()
{
    // precondition: max >= 1 (with max == 0 the loop never runs and we'd hit unreachable!)
    let mut delay = Duration::from_millis(100);
    for attempt in 0..max {
        match op().await {
            Ok(v) => return Ok(v),
            Err(e) if e.is_transient() && attempt + 1 < max => {
                sleep(delay).await;
                delay = (delay * 2).min(Duration::from_secs(10)); // cap
                // jitter omitted for brevity — see the closing note below
            }
            Err(e) => return Err(e),
        }
    }
    unreachable!("loop returns on the final attempt; max >= 1 by precondition")
}
```

Or use a crate instead of rolling your own — `backon` adds backoff to any fallible future:

```toml
[dependencies]
backon = "1.6"
```

```rust
use backon::{ExponentialBuilder, Retryable};

let result = (|| async { fetch(url).await })
    .retry(ExponentialBuilder::default().with_jitter())
    .when(|e: &MyError| e.is_transient())   // gate on classification
    .await?;
```

Always add jitter — backon via `.with_jitter()`, hand-rolled loops by randomizing the delay —
so retries from many clients don't synchronize into a thundering herd.

## Fallback / graceful degradation

When the primary path fails permanently, degrade instead of propagating — if the domain allows it.

```rust
let rate = fetch_live_rate(pair).await
    .unwrap_or_else(|e| {
        tracing::warn!("live rate failed: {e}; using cached");
        cached_rate(pair)            // stale but serviceable
    });
```

Degrade only where a worse-but-valid answer beats an error. Never fabricate data for a domain
that requires correctness (payments, auth) — there, fail closed.

## Circuit breaker

When a dependency is down, stop hammering it: after N consecutive failures, "open" the circuit
and fail fast for a cooldown, then allow a trial request.

```rust
enum State { Closed, Open { until: Instant }, HalfOpen }

// Closed   -> count failures; at threshold -> Open(now + cooldown)
// Open      -> reject immediately until `until`, then -> HalfOpen
// HalfOpen  -> allow one trial: success -> Closed, failure -> Open again
```

This protects both the caller (fast failure, no pile-up of blocked tasks) and the struggling
dependency (no retry storm). For production, prefer a maintained crate (e.g. `failsafe`) over a
hand-rolled breaker — the state transitions and metrics are easy to get subtly wrong.

## What not to do

- Don't retry permanent errors, or non-idempotent operations without an idempotency key.
- Don't retry without a cap and a timeout — unbounded retries become an outage.
- Don't `unwrap()` in a recovery path; that turns degradation into a crash.
- Don't swallow the final error after exhausting retries — report it with how many attempts failed.
