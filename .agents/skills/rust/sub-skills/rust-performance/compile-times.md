# Cutting compile times

The counterpart to [optimizing.md](optimizing.md). That file tunes the build to make the **binary
faster at runtime**; this one tunes it to make the **edit→compile→run loop faster**. The two axes
pull in opposite directions on several knobs — `codegen-units`, `lto`, `opt-level` — so keep the
axis you're on explicit. Same measure-first ethos: profile the build before tuning it.

## Measure first — where the time goes

- `cargo build --timings` — writes an HTML report under `target/cargo-timings/` showing each
  crate's compile time and the critical path. Read it before changing anything; the bottleneck is
  usually a handful of crates, not "Rust is slow".
- `cargo llvm-lines` — ranks functions by how much LLVM IR they generate; the top of the list is
  your monomorphization bloat (generic functions instantiated many times).
- `cargo +nightly rustc -- -Z self-profile` — deeper per-pass rustc profiling when `--timings`
  isn't enough.

## Faster linker — the cheapest big win

Linking is serial and often dominates incremental builds (you relink on every change). Switching
linkers needs no source changes:

```toml
# .cargo/config.toml
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]   # mold: fastest on Linux (install: apt / brew `mold`)
```

- **Linux:** `mold` is fastest; `lld` is a solid second.
- **macOS:** recent Xcode toolchains ship a fast default linker, so the old advice to bolt on
  `zld`/`lld` is mostly obsolete — measure before adding one.
- **Cross-platform fallback:** `lld` via `rustflags = ["-C", "link-arg=-fuse-ld=lld"]`.

## Dev profile tuning

The dev profile drives your inner loop. Tune it for rebuild speed:

```toml
# Cargo.toml
[profile.dev]
opt-level = 0                 # default; raise to 1 only if the dev loop is itself CPU-bound
debug = "line-tables-only"    # enough for backtraces, far less debuginfo to emit
split-debuginfo = "unpacked"  # macOS: keeps debuginfo out of the link step
incremental = true            # the dev default — keep it; recompiles only changed units

[profile.dev.package."*"]
opt-level = 2                 # optimize dependencies once; your own crate stays cheap to rebuild
```

When the loop only needs a type-check (not a run), `cargo check` skips codegen and is several
times faster than `cargo build`.

## `codegen-units` — calibration

A common reflex is to raise `codegen-units` "for parallelism". For **compile speed** this rarely
helps: the dev default is already 256, which saturates parallelism, and pushing higher buys
nothing. The levers that actually move compile time are the linker and crate granularity, not this
knob.

The opposite move — `codegen-units = 1` — is a **runtime** optimization (see
[optimizing.md](optimizing.md)): it lets the optimizer see a whole crate at once and **costs**
compile time. Set it on `[profile.release]` for the shipped binary, never on the dev loop.

## Crate splitting — parallelism and incrementality

`rustc` parallelizes at *crate* granularity and the incremental cache is per crate. A single giant
crate therefore serializes compilation and forces a full recompile on any change. Splitting a
monolith into a workspace of focused crates lets cores work in parallel and confines a rebuild to
the crate you touched (and its dependents).

- Split along seams you already have — a library core, separate adapters, a thin binary. Workspace
  layout and dependency-weight tradeoffs live in `rust-ecosystem`.
- **Caveat:** each crate boundary adds (de)serialization + linking cost, so over-splitting *raises*
  total time. Split where there's a real dependency seam; don't chase a thousand crates. (The
  widely-cited result behind this lever came from machine-generated code with hundreds of
  independent operators — a niche the lever generalizes from, not a target to copy.)

## Monomorphization is a compile-time cost

Every generic function is recompiled for each concrete type it's instantiated with. Heavy generics
and deep generic call trees multiply codegen and LLVM work — visible at the top of
`cargo llvm-lines`. To cut it:

- **Fewer instantiations:** prefer `&dyn Trait` at API boundaries that aren't hot — one compiled
  copy instead of N. The dispatch tradeoff (static vs `dyn` vs enum), including this compile-time
  dimension, is owned by `rust-traits`.
- **Thin generic shell, non-generic inner fn:** keep the generic surface tiny and forward to a
  single non-generic inner function, so only the small shell is monomorphized:

```rust
pub fn load<P: AsRef<Path>>(path: P) -> io::Result<Vec<u8>> {
    fn inner(path: &Path) -> io::Result<Vec<u8>> {
        // the real work — compiled once, not per P
        std::fs::read(path)
    }
    inner(path.as_ref())
}
```

Honest tradeoff: `dyn` adds an indirect call, and the inner-fn split is a touch more code — you
trade a little runtime for compile speed. Worth it on cold paths; measure on hot ones.

## Caching

- **`sccache`** caches compiled artifacts across builds and machines — most valuable in CI and when
  switching branches. Set `RUSTC_WRAPPER=sccache` (env or `.cargo/config.toml`).
- Trust the incremental cache; **don't `cargo clean` reflexively** — it throws away exactly the
  work you're trying to save.

## Trim dependencies and features

Every dependency and every enabled feature is more code to compile. The compile graph shrinks when
you:

- Disable defaults you don't use:
  `foo = { version = "1", default-features = false, features = [...] }`.
- Audit what you actually pull in with `cargo tree` (and `cargo tree -e features` for feature
  edges). Dependency weight as a selection criterion lives in `rust-ecosystem`.

## Boundaries

- Tuning the build for a **faster runtime binary** (LTO, `codegen-units = 1`, `target-cpu`, PGO) →
  [optimizing.md](optimizing.md). This file is its counterpart; where a knob appears in both, the
  effect is opposite.
- Workspace structure, dependency selection, and feature design → `rust-ecosystem`.
- Static vs `dyn` vs enum dispatch (the runtime side of the monomorphization tradeoff) →
  `rust-traits`.
