# Optimizations

Apply these **after** profiling points at a hot spot — and re-benchmark each one. Distilled from
the [Rust Performance Book](https://nnethercote.github.io/perf-book/).

## Build configuration (free, no code change)

Often the best effort:reward ratio. In `Cargo.toml`:

```toml
[profile.release]
lto = "fat"          # cross-crate inlining + dead-code elim: 10-20%+, much slower compile
codegen-units = 1    # whole-crate optimization (default 16 parallelizes but misses opts)
panic = "abort"      # abort instead of unwind: removes landing pads — smaller/slightly faster; catch_unwind can no longer recover.
```

```toml
# .cargo/config.toml — emit instructions for the build machine's CPU (AVX, etc.)
[build]
rustflags = ["-C", "target-cpu=native"]   # ⚠ binary won't run on older CPUs
```

For size instead of speed: `opt-level = "z"` (or `"s"`) and `strip = "symbols"`.

## Profile-guided optimization (PGO)

When `lto`/`codegen-units` are already maxed and you need more, PGO feeds *real* runtime behavior
back into the compiler so it lays out branches and inlines around the paths your workload
actually hits — typically another 5–15% on branch-heavy code. Not free: it needs a representative
workload and a three-step build, so reach for it on a release-cadence binary, not day-to-day.

The flow is instrument → run representative workload → rebuild with the profile. The
[`cargo-pgo`](https://github.com/Kobzol/cargo-pgo) tool wraps it:

```bash
cargo install cargo-pgo            # needs the llvm-tools-preview rustup component
cargo pgo instrument run -- <args> # build instrumented, run your real workload to collect data
cargo pgo optimize build           # rebuild using the merged profile
```

The workload must resemble production traffic — profiling an unrepresentative run can make things
*slower*. Re-benchmark like any other change. (BOLT is a further, separate post-link step;
overkill unless PGO already paid off.)

## Heap allocations

Allocation is often the hidden cost. Reduce the count:

- **Pre-size**: `Vec::with_capacity(n)` / `reserve(n)` and `HashMap::with_capacity` — one
  allocation instead of several reallocations as it grows. Same for strings.
- **Reuse buffers**: pass `&mut Vec<T>` instead of returning a fresh one; `.clear()` and refill
  in a loop; `clone_from(&src)` reuses the destination's allocation.
- **Drop capacity overhead**: `vec.into_boxed_slice()` turns a `Vec` into `Box<[T]>` (3 words →
  2) when you won't resize it again.
- **Inline small collections**: `smallvec` (`SmallVec<[T; N]>`) keeps up to N elements on the
  stack, heap only on overflow; `arrayvec::ArrayVec` when the max is fixed (no heap at all);
  `tinyvec` for the same when `T: Default` and you want all-safe code.
- **Inline small strings**: a `String` is 24 bytes + a heap allocation even for `"ok"`. When you
  store millions of short strings, `compact_str::CompactString` (or `smartstring`) keeps strings up
  to ~24 bytes inline behind a near-drop-in `String` API — same footprint, far fewer allocations;
  `ecow::EcoString` does the same and makes clones O(1). (Same idea as `smallvec`, for text.)
- **Arena / bump allocation**: for many small, same-lifetime allocations (parse trees,
  request-scoped scratch), allocate from a `bumpalo::Bump` (or `typed-arena`) — each `alloc` is a
  pointer bump returning `&'a mut T`, and the whole region is freed at once when the arena drops,
  instead of N individual `malloc`/`free`. Suits build-then-discard phases, not long-lived graphs.
  Caveat: `bumpalo` does **not** run `Drop` on its contents (use `bumpalo::boxed::Box` if `T` owns
  resources); `typed-arena` does.
- **Avoid throwaway allocations** in hot code: skip needless `.clone()`, prefer `&str` over
  `String`, `Cow<str>` for "usually borrowed", and `write!` into a reused buffer over `format!`.
- **Files**: `BufRead::read_line` into a reused `String` rather than `.lines()` (which allocates
  a `String` per line).

**Swap the global allocator.** When allocation is unavoidably hot — especially multithreaded — the
system allocator can be the bottleneck, and replacing it needs no call-site changes:

```rust
// tikv-jemallocator = "0.6"   (or  mimalloc = "0.1")
#[cfg(not(target_env = "msvc"))]   // jemalloc doesn't build on MSVC; mimalloc does
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
```

`jemalloc`/`mimalloc` often beat the system allocator on allocation-heavy, multithreaded code — but
not always; benchmark, it can be neutral or worse.

To **find** the allocations a CPU profiler is blind to — use a heap profiler (`dhat`,
[benchmarking.md](benchmarking.md)). Its testing mode (`dhat::Profiler::builder().testing()`) also
lets a test **assert** an allocation count, so a fix can't silently regress (the heap analogue of a
benchmark regression test).

## Hashing

The default `HashMap` uses SipHash 1-3 — collision-resistant but slow, especially for small
keys like integers. If profiling shows hashing is hot **and** HashDoS isn't a concern (not
attacker-controlled keys):

```toml
[dependencies]
rustc-hash = "2"     # FxHashMap / FxHashSet — very fast, low quality, great for int keys
# or
ahash = "0.8"        # uses AES instructions where available
```

```rust
use rustc_hash::FxHashMap;
let mut m: FxHashMap<u32, u32> = FxHashMap::default();
```

Don't change the default blindly — for untrusted keys, SipHash's DoS resistance is the point.

## Type sizes

Big types cost `memcpy`s, stack space, and cache misses.

- **Measure**: `RUSTFLAGS=-Zprint-type-sizes cargo +nightly build --release` (or the
  `top-type-sizes` crate) shows sizes, padding, and discriminants.
- **Box large/rare enum variants**: an enum is as big as its biggest variant. If one variant is
  huge and uncommon, box it — `Z(Box<LargeThing>)` — so the enum shrinks to a pointer for the
  common cases.
- **Smaller integers** for indices/counts: `u32` instead of `usize` where the range allows,
  coercing at use sites.
- **`Box<[T]>` / `ThinVec`**: boxed slice drops `Vec`'s capacity word; `thin_vec::ThinVec` is one
  word wide — len/cap live in a heap header alongside the elements — ideal for frequently-empty
  vectors in hot structs.
- Field ordering is automatic — the compiler reorders for you unless `#[repr(C)]`. Don't hand-pack.

## Iterators and bounds checks

Iterator chains are zero-cost — they compile to the same (often better) code as a manual loop,
and they let the compiler **elide bounds checks** that indexing can't always prove away. Prefer
`for x in &v` / `.iter().map().filter()` over `for i in 0..v.len() { v[i] }`.

When a profiler proves a bounds check dominates a hot loop and you can't restructure to remove
it, `slice::get_unchecked` exists — but it's `unsafe` and a last resort (→ `rust-unsafe`); a
correct iterator almost always wins without it.

A few more iterator/collection wins the optimizer can't make for you:

- **Don't `collect` just to iterate again** — return `impl Iterator<Item = T>` and let the caller
  drive it, skipping an intermediate `Vec`. When you must `collect`, an accurate
  `Iterator::size_hint` lets it pre-size in one allocation.
- **`filter_map`** in one pass beats `filter().map()`; **`.copied()`** on small `Copy` items often
  codegens better than yielding `&T`.
- **`Vec::swap_remove`** is O(1) vs `remove`'s O(n) when order doesn't matter; **`retain`** drops
  many elements in a single pass instead of repeated `remove`.

## I/O: lock and buffer

I/O cost is usually syscall count, not CPU.

- **Buffer**: wrap files/sockets in `BufReader`/`BufWriter` so many small reads/writes collapse
  into few syscalls. `BufWriter` flushes on drop but *swallows the error* then — call `.flush()?`
  explicitly when it matters.
- **Lock once**: `println!` re-locks stdout on every call. In a hot output loop take the lock once
  — `let mut out = io::stdout().lock();` then `writeln!(out, …)` — and wrap it in a `BufWriter` for
  bulk output (CLI output conventions → `rust-cli`).
- **Skip UTF-8 validation** when you don't need it: `BufRead::read_until(b'\n', &mut buf)` reads raw
  bytes and avoids the `str` checks that `lines()`/`read_line` pay.

## Vectorization (SIMD)

On stable, the lever is **autovectorization** — LLVM turns a clean loop into SIMD for you. Help
it: iterate (don't index), process `chunks_exact(N)` so the bulk is a fixed width with a scalar
remainder, avoid early-exits and data dependencies inside the loop, and keep `f32`/`f64`
reductions associative-friendly (FP add/mul don't reassociate on their own, which blocks
reduction vectorization). Verify it actually vectorized (check the asm via `cargo-show-asm`) —
don't assume.

When autovectorization isn't enough and you need *explicit* SIMD, prefer a **safe portable**
layer over hand-written intrinsics:

- `std::simd` (`f32x8`, `slice::as_simd`) — portable and safe, but **nightly-only** today.
- On stable, crates like `wide` or `pulp` give portable SIMD types without `unsafe`.

Drop to architecture-specific intrinsics (`std::arch::x86_64`, `target_feature`) only when a
benchmark proves the portable path leaves speed on the table — that's `unsafe` and lives in
`rust-unsafe`.

## Inlining and code layout

Across crate boundaries the compiler can't inline by default. For small, hot, cross-crate
functions, `#[inline]` (or `#[inline(always)]` sparingly) can help — but don't sprinkle it
everywhere (it bloats compile time and binary), and enabling LTO removes much of the need.

The flip side is keeping cold code *out* of the hot path so it doesn't pollute the instruction
cache. Mark rarely-taken functions — error constructors, slow-path fallbacks — `#[cold]`, and
factor an unlikely branch's body into a `#[cold]` (often also `#[inline(never)]`) function so the
common path stays dense:

```rust
fn parse(input: &str) -> Result<Data, Error> {
    if input.is_empty() {
        return empty_err();   // cold path lives elsewhere
    }
    Ok(fast_parse(input))
}

#[cold]
#[inline(never)]
fn empty_err() -> Result<Data, Error> { Err(Error::Empty) }
```

`#[cold]` is stable; explicit `likely`/`unlikely` branch hints are still unstable intrinsics, so
the `#[cold]`-function idiom is how you express the same intent today. Like everything here:
measure — layout wins are real but small, and easy to talk yourself into without proof.

## Free in release: `debug_assert!`

For invariant checks on a hot path that aren't load-bearing for *safety*, use `debug_assert!` /
`debug_assert_eq!` instead of `assert!`: they run in debug and test builds but compile to nothing
in `--release`, so they cost zero in the shipped binary. (A check that upholds an `unsafe`
precondition must stay a real `assert!` → `rust-unsafe`.) Likewise, gate expensive logging or
debug-only computation behind the flag that enables it, so a disabled log does no work.

---

**Every change gets re-benchmarked.** A plausible optimization that doesn't move the number is
just added complexity — revert it.
