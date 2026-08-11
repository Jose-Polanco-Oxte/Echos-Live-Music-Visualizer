# Tooling: snapshots, runner, coverage, CI

## Snapshot testing (`insta`)

For output too large or structured to hand-write assertions for — serialized structs, rendered text, ASTs. `insta` stores the expected value in a `.snap` file; on change it shows a diff you accept or reject.

```toml
[dev-dependencies]
insta = { version = "1.47", features = ["json"] } # json/yaml/redactions optional
```

```rust
#[test]
fn renders_invoice() {
    let invoice = Invoice::sample();
    insta::assert_debug_snapshot!(invoice);        // Debug repr
    // insta::assert_json_snapshot!(invoice);      // serde_json (needs Serialize)
    // insta::assert_snapshot!(render(&invoice));  // a String
}
```

Workflow:

```bash
cargo install cargo-insta     # one-time
cargo test                    # first run writes .snap.new and fails
cargo insta review            # interactively accept/reject changes
```

Commit `.snap` files — they are the assertions. Use redactions to mask volatile fields (timestamps, ids) so snapshots stay stable.

## Test runner (`cargo nextest`)

A faster runner with clearer output: runs each test in its own process (better isolation), parallelizes harder, and prints a concise summary. It does **not** run doc tests — keep `cargo test --doc` for those.

```bash
cargo install cargo-nextest   # or via taiki-e/install-action in CI

cargo nextest run             # all tests
cargo nextest run -E 'test(parse)'   # filter by expression
cargo nextest run --no-capture
cargo test --doc              # doc tests separately
```

## Coverage (`cargo llvm-cov`)

Source-based coverage via LLVM instrumentation.

```bash
cargo install cargo-llvm-cov          # one-time (or taiki-e/install-action)

cargo llvm-cov                        # summary table
cargo llvm-cov --html                 # open target/llvm-cov/html/index.html
cargo llvm-cov --lcov --output-path lcov.info   # for CI uploaders
cargo llvm-cov nextest                # run coverage through nextest
cargo llvm-cov --fail-under-lines 80  # gate in CI
```

### Targets — treat as guidance, not a fetish

| Code | Line target |
|---|---|
| Critical business logic | ~100% |
| Public API | 90%+ |
| General code | 80%+ |
| Generated / FFI bindings | exclude |

High coverage of weak assertions proves nothing. Coverage tells you what was *executed*, not what was *checked*.

### Find risky code: `cargo-crap`

Coverage alone doesn't tell you *where* low coverage matters most. The CRAP metric (Change Risk
Anti-Patterns) combines cyclomatic **complexity** with **coverage** — high-complexity,
low-coverage functions score worst and are where bugs hide. `cargo-crap` reads the lcov file
`cargo llvm-cov` produces:

```bash
cargo binstall cargo-crap                        # or: cargo install cargo-crap
cargo llvm-cov --lcov --output-path lcov.info
cargo crap --lcov lcov.info                       # report the worst offenders
cargo crap --lcov lcov.info --fail-above --threshold 30   # gate in CI
cargo crap --lcov lcov.info --format github               # CI annotations
cargo crap --lcov lcov.info --format pr-comment           # PR comment
```

For a mature codebase prefer **baseline mode** over an absolute threshold — fail only on
*regression*, so quality ratchets up without a big-bang cleanup:

```bash
cargo crap --lcov lcov.info --format json --output baseline.json   # capture once
cargo crap --lcov lcov.info --baseline baseline.json --fail-regression
```

This aims your testing effort at the functions that combine risk and neglect — better signal
than chasing a uniform coverage percentage.

## Mutation testing (`cargo-mutants`)

Coverage proves a line *ran*; it can't prove a test would *notice* if that line were wrong.
Mutation testing does: `cargo-mutants` makes small edits to your code — delete a function body,
flip `<` to `>`, replace a return with a default — rebuilds, and reruns the suite for each. A
mutant that *survives* (tests still pass) is a hole in your assertions.

```bash
cargo install cargo-mutants
cargo mutants                       # mutate the whole crate, report survivors
cargo mutants --in-diff git.diff    # only lines changed in a diff (fast, CI-friendly)
cargo mutants -f src/parser.rs      # scope to one file
```

Each mutant lands in a bucket: **caught** (a test failed — good), **missed** (survived — write a
test that kills it), **unviable** (didn't compile), or **timeout**. Aim it at critical logic, not
the whole tree — it rebuilds per mutant, so it's much slower than coverage. Run `--help` for
baseline and CI options.

## CI (GitHub Actions)

Format and lint gate first (cheap, fail fast), then tests, then coverage.

```yaml
name: ci
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt

      - name: Format
        run: cargo fmt --check
      - name: Clippy
        run: cargo clippy --all-targets -- -D warnings

      - uses: taiki-e/install-action@v2
        with:
          tool: cargo-nextest,cargo-llvm-cov

      - name: Tests
        run: cargo llvm-cov nextest --lcov --output-path lcov.info --fail-under-lines 80
      - name: Doc tests
        run: cargo test --doc
```

`cargo llvm-cov nextest` runs the suite once and produces coverage in the same pass; doc tests run separately because nextest doesn't cover them.
