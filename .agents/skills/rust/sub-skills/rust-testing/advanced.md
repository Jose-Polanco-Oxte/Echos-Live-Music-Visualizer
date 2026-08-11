# Advanced: async, table-driven, property, and mocks

Adds four crates. All go in `[dev-dependencies]`:

```toml
[dev-dependencies]
tokio    = { version = "1.52", features = ["macros", "rt-multi-thread", "test-util"] }
rstest   = "0.26"
proptest = "1.11"
mockall  = "0.14"
```

## Async tests (`tokio`)

`#[tokio::test]` spins up a runtime per test.

```rust
#[tokio::test]
async fn fetches_data() {
    let client = TestClient::new().await;
    let items = client.get("/data").await.unwrap();
    assert_eq!(items.len(), 3);
}
```

### Timeouts without wall-clock waiting

The `test-util` feature lets you control time, so "timeout" tests run instantly and deterministically.

```rust
#[tokio::test(start_paused = true)] // clock starts frozen
async fn times_out() {
    use std::time::Duration;
    let result = tokio::time::timeout(Duration::from_secs(30), slow_op()).await;
    // No real 30s wait — paused time auto-advances when all tasks are idle.
    assert!(result.is_err(), "should have timed out");
}
```

Never `std::thread::sleep` in async tests — it blocks the runtime. Use `tokio::time::sleep`, `pause`/`advance`, or a channel/`Notify` to synchronize.

## Table-driven tests (`rstest`)

### Cases — one test body, many input/output rows

```rust
use rstest::rstest;

#[rstest]
#[case("hello", 5)]
#[case("", 0)]
#[case("über", 5)] // 4 chars, 5 bytes — proves we mean bytes
fn byte_length(#[case] input: &str, #[case] expected: usize) {
    assert_eq!(input.len(), expected);
}
```

Each case is reported as its own test, so a single failing row is easy to spot.

### Fixtures — shared setup injected by argument name

```rust
use rstest::{fixture, rstest};

#[fixture]
fn db() -> TestDb {
    TestDb::new_in_memory()
}

#[rstest]
fn insert_then_get(db: TestDb) {
    db.insert("k", "v");
    assert_eq!(db.get("k"), Some("v".into()));
}
```

`rstest` also composes with async: `#[rstest] #[tokio::test] async fn ...` and async fixtures.

## Property-based tests (`proptest`)

Instead of fixed inputs, assert an invariant over *generated* inputs; proptest shrinks any failure to a minimal counterexample.

```rust
use proptest::prelude::*;

proptest! {
    // round-trip: decode(encode(x)) == x for any string
    #[test]
    fn encode_decode_roundtrip(input in ".*") {
        let decoded = decode(&encode(&input)).unwrap();
        prop_assert_eq!(input, decoded);
    }

    // metamorphic: sorting never changes length, and output is ordered
    #[test]
    fn sort_is_well_behaved(mut v in prop::collection::vec(any::<i32>(), 0..100)) {
        let len = v.len();
        v.sort();
        prop_assert_eq!(v.len(), len);
        prop_assert!(v.windows(2).all(|w| w[0] <= w[1]));
    }
}
```

### Custom strategies

Build generators for your own valid inputs:

```rust
use proptest::prelude::*;

fn valid_email() -> impl Strategy<Value = String> {
    ("[a-z]{1,10}", "[a-z]{1,5}").prop_map(|(u, d)| format!("{u}@{d}.com"))
}

proptest! {
    #[test]
    fn accepts_valid_emails(email in valid_email()) {
        prop_assert!(User::new("Test", &email).is_ok());
    }
}
```

Use `prop_assert!`/`prop_assert_eq!` inside `proptest!` (not `assert!`) so shrinking reports cleanly.

## Fuzzing (`cargo-fuzz`)

Property tests assert an invariant over *structured* inputs; fuzzing throws *adversarial bytes* at code and watches for panics, crashes, or sanitizer-detected memory errors. Reach for it on anything that eats untrusted input — parsers, decoders, deserializers, `unsafe`/FFI. `cargo-fuzz` drives libFuzzer and needs the **nightly** toolchain (it uses `-Z` flags for sanitizers).

```bash
cargo install cargo-fuzz
cargo +nightly fuzz init            # create the fuzz/ crate + a first target
cargo +nightly fuzz add parse_url   # add another target
cargo +nightly fuzz list
cargo +nightly fuzz run parse_url   # fuzz until a crash (Ctrl-C to stop)
```

A target is a function fed pseudo-random bytes; keep it total (don't `unwrap` the *input* itself) so only real bugs trip it:

```rust
// fuzz/fuzz_targets/parse_url.rs
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        let _ = url::Url::parse(s);   // a panic in here = a found bug
    }
});
```

For non-byte inputs, derive `Arbitrary` and take a typed argument — libFuzzer builds the value from the raw bytes (structure-aware fuzzing):

```rust
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct Cmd { name: String, args: Vec<u32> }

fuzz_target!(|cmd: Cmd| { let _ = run(&cmd); });
```

A crash is written to `fuzz/artifacts/<target>/`; reproduce it, then shrink it:

```bash
cargo +nightly fuzz run  parse_url fuzz/artifacts/parse_url/crash-<hash>   # reproduce
cargo +nightly fuzz tmin parse_url fuzz/artifacts/parse_url/crash-<hash>   # minimize
```

Commit the corpus and crash artifacts as regression seeds. Full guide: the [Rust Fuzz Book](https://rust-fuzz.github.io/book/). Fuzzing `unsafe`/FFI for undefined behavior pairs naturally with Miri → `rust-unsafe`.

## Mocking (`mockall`)

When a unit depends on a trait you can't (or don't want to) run for real — network, clock, payment gateway — generate a mock with `#[automock]` and program expectations.

```rust
use mockall::{automock, predicate::eq};

#[automock]
trait UserRepository {
    fn find_by_id(&self, id: u64) -> Option<User>;
}

#[test]
fn service_returns_user_when_found() {
    let mut repo = MockUserRepository::new();
    repo.expect_find_by_id()
        .with(eq(42))                  // arg matcher
        .times(1)                      // call-count expectation
        .returning(|_| Some(User { id: 42, name: "Alice".into() }));

    let service = UserService::new(Box::new(repo));
    assert_eq!(service.get_user(42).unwrap().name, "Alice");
}
```

Mock at the boundary, not everywhere: over-mocking tests your mocks instead of your code. If an in-memory fake is simple, prefer it.

## BDD: behavior as executable spec

BDD is specification by example: each rule is a `Given` (context) → `When` (action) →
`Then` (outcome) scenario. The acceptance criteria you write while planning a feature *are*
these scenarios — BDD just makes them executable, so the spec and the test are the same
artifact ("living documentation"). Two levels, pick by audience.

> The *process* — deriving scenarios from requirements, choosing examples, driving outside-in —
> is the `specs` skill. This section is the Rust mechanics for running them.

### Lightweight — Given/When/Then, no crate

Structure an ordinary test along the three beats. Costs nothing, reads as a spec, and is the
right default for developer-facing behavior:

```rust
#[test]
fn withdrawing_more_than_balance_is_rejected() {
    // given
    let mut account = Account::with_balance(100);
    // when
    let result = account.withdraw(150);
    // then
    assert_eq!(result, Err(AccountError::Insufficient { available: 100 }));
    assert_eq!(account.balance(), 100); // and: balance unchanged
}
```

The test *name* is the spec sentence; the three blocks are the scenario. Most BDD value comes
from this discipline alone — no framework required.

### Full Gherkin — `cucumber`

When non-developers (product, QA) should read or write the specs, use `.feature` files in
Gherkin and bind steps in Rust with [`cucumber`](https://github.com/cucumber-rs/cucumber):

```toml
[dev-dependencies]
cucumber = "0.23"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }

[[test]]
name = "cucumber"
harness = false        # cucumber ships its own runner
```

```gherkin
# tests/features/account.feature
Feature: Withdrawals
  Scenario: rejecting an overdraft
    Given an account with balance 100
    When I withdraw 150
    Then the withdrawal is rejected
    And the balance is still 100
```

```rust
// tests/cucumber.rs
use cucumber::{given, when, then, World};

#[derive(Debug, Default, World)]
struct AccountWorld { account: Account, last: Option<Result<(), AccountError>> }

#[given(regex = r"^an account with balance (\d+)$")]
async fn given_balance(w: &mut AccountWorld, n: u64) {
    w.account = Account::with_balance(n);
}

#[when(regex = r"^I withdraw (\d+)$")]
async fn when_withdraw(w: &mut AccountWorld, n: u64) {
    w.last = Some(w.account.withdraw(n));
}

#[then("the withdrawal is rejected")]
async fn then_rejected(w: &mut AccountWorld) {
    assert!(matches!(w.last, Some(Err(_))));
}

#[then(regex = r"^the balance is still (\d+)$")]
async fn then_balance(w: &mut AccountWorld, n: u64) {
    assert_eq!(w.account.balance(), n);
}

#[tokio::main]
async fn main() {
    AccountWorld::run("tests/features").await;
}
```

Run with `cargo test --test cucumber`. The `World` is the per-scenario state; steps match by
regex (or cucumber expressions) and mutate it.

**Choose deliberately:** Gherkin adds a parsing/indirection layer and a separate runner — worth
it only when the `.feature` files are genuinely read by non-developers. For developer-only
behavior, the lightweight Given/When/Then test is clearer and cheaper.
