# Benchmarking and profiling

You can't optimize what you don't measure. Two scales: **micro** (a function, with criterion)
and **whole-program** (the binary, with hyperfine/profilers).

## Principles

- **Always release.** Benchmark `--release`; a dev build's numbers are meaningless.
- **Noise is real.** "Tiny changes in memory layout can cause significant but ephemeral
  fluctuations." Wall-time is noisy; instruction/cycle counts vary less. Run enough samples and
  treat small deltas with suspicion.
- **Realistic workloads** over synthetic ones — microbenchmarks are useful "in moderation."
- **Start anyway.** "Mediocre benchmarking is far better than no benchmarking" — a rough
  baseline you can compare against beats waiting for the perfect harness.

## Microbenchmarks — `criterion`

Statistical benchmarking that compares against the previous run automatically.

```toml
[dev-dependencies]
criterion = "0.8"

[[bench]]
name = "bench"
harness = false        # criterion provides its own main
```

```rust
// benches/bench.rs
use criterion::{criterion_group, criterion_main, Criterion};
use std::hint::black_box;

fn fib(n: u64) -> u64 { if n < 2 { n } else { fib(n - 1) + fib(n - 2) } }

fn bench_fib(c: &mut Criterion) {
    c.bench_function("fib 20", |b| b.iter(|| fib(black_box(20))));
}

criterion_group!(benches, bench_fib);
criterion_main!(benches);
```

Run with `cargo bench`. criterion prints `change: -12.3%` vs the last run and flags whether it's
statistically significant.

### `black_box` — the one thing you must not forget

`std::hint::black_box` stops the optimizer from deleting the code under test (constant-folding
the answer, or eliminating it as dead). Wrap **inputs** so they can't be precomputed and the
**result** so it can't be discarded. Without it you often benchmark nothing.

### `divan` — a lighter alternative

[`divan`](https://crates.io/crates/divan) (`divan = "0.1"`) is a simpler, attribute-based
microbenchmark harness — less ceremony than criterion when you don't need its statistics.

## Whole-program

- **`hyperfine`** — measures end-to-end wall time of a command, with warmup and statistics.
  Great for CLIs: `hyperfine './app input.txt'`.
- **`cargo flamegraph`** — sampling profiler that renders a flamegraph; the widest frames are
  your hot spots. Needs debug symbols even in release: `[profile.release] debug = true`.
- **`samply`** — cross-platform sampling profiler with a web UI; a good `perf` alternative on
  macOS/Windows.
- **`dhat`** — heap profiler (the `dhat-rs` crate, cross-platform, no Valgrind): shows *where*
  allocations come from and how many — which a CPU sampler can't. Set `dhat::Alloc` as the
  `#[global_allocator]` **and** create a profiler at the top of `main`
  (`let _p = dhat::Profiler::new_heap();`) — on exit it writes `dhat-heap.json` for the DHAT viewer.
  Reach for it when allocation is the suspected cost (→ heap allocations in
  [optimizing.md](optimizing.md)).

Profile to decide *what* to optimize; benchmark to prove the optimization *worked*. A CPU profiler
(flamegraph/samply/perf) finds *time*; a heap profiler (`dhat`) finds *allocations* — use the one
that matches the symptom.

## Pitfalls

- Benchmarking a debug build (the #1 mistake).
- Forgetting `black_box` → the optimizer removes the work → "infinitely fast" nonsense.
- Cold-cache first run skewing results — criterion warms up; one-shot timers don't.
- Measuring a microbenchmark that doesn't reflect real input sizes/shapes.
