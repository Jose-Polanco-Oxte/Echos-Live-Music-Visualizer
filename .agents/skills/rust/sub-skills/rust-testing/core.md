# Core: unit, integration, and doc tests

The standard-library testing surface — no extra crates needed.

## Unit tests

Live in the same file as the code, in a `#[cfg(test)]` module so they're compiled only for `cargo test`.

```rust
// src/user.rs
pub struct User {
    pub name: String,
    pub email: String,
}

impl User {
    pub fn new(name: impl Into<String>, email: impl Into<String>) -> Result<Self, String> {
        let email = email.into();
        if !email.contains('@') {
            return Err(format!("invalid email: {email}"));
        }
        Ok(Self { name: name.into(), email })
    }
}

#[cfg(test)]
mod tests {
    use super::*; // bring the parent module (incl. private items) into scope

    #[test]
    fn creates_user_with_valid_email() {
        let user = User::new("Alice", "alice@example.com").unwrap();
        assert_eq!(user.name, "Alice");
    }

    #[test]
    fn rejects_invalid_email() {
        let err = User::new("Bob", "not-an-email").unwrap_err();
        assert!(err.contains("invalid email"));
    }
}
```

Unit tests can reach **private** items — that's their advantage over integration tests.

### Assertions

```rust
assert_eq!(a, b);                              // equality (preferred — prints both sides)
assert_ne!(a, b);                              // inequality
assert!(cond);                                 // boolean
assert_eq!(got, 42, "context: {got}");         // custom message
assert!((x - y).abs() < f64::EPSILON);         // float comparison — never == on floats
assert!(matches!(val, Foo::Bar(_)));           // shape match without full PartialEq
```

## Testing `Result` and panics

### Result-returning code

```rust
#[test]
fn parse_rejects_garbage() {
    let result = parse_config("}{");
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), ConfigError::Parse(_))); // assert the variant
}

// Let the test itself return Result and use `?` — failure prints the full error.
#[test]
fn parse_accepts_valid() -> Result<(), Box<dyn std::error::Error>> {
    let config = parse_config(r#"port = 8080"#)?;
    assert_eq!(config.port, 8080);
    Ok(())
}
```

### Panics

```rust
#[test]
#[should_panic]
fn panics_on_empty() {
    process(&[]);
}

#[test]
#[should_panic(expected = "index out of bounds")] // substring of the panic message
fn panics_with_message() {
    let v: Vec<i32> = vec![];
    let _ = v[0];
}
```

Prefer `is_err()` over `#[should_panic]` when the code returns `Result` — a panic test can pass for an unrelated panic.

## Integration tests

Each file in `tests/` is compiled as a **separate crate** that links your library like a real user — so it sees only the public API.

```text
my_crate/
├── src/
│   └── lib.rs
└── tests/
    ├── api.rs          # `cargo test --test api`
    ├── db.rs
    └── common/
        └── mod.rs      # shared helpers (a subdir avoids it becoming its own test binary)
```

```rust
// tests/api.rs
use my_crate::{App, Config};

mod common; // tests/common/mod.rs

#[test]
fn health_endpoint_returns_ok() {
    let app = App::new(Config::test_default());
    let response = app.handle("/health");
    assert_eq!(response.status, 200);
}
```

Put a helper in `tests/common/mod.rs` (not `tests/common.rs`) so the test harness doesn't treat it as a standalone test binary.

### Real dependencies with `testcontainers`

For an adapter that talks to a real database/queue (the part fakes can't prove — your actual
SQL), spin the dependency up in a throwaway Docker container per test run instead of mocking it.
This is the integration layer above the fake-port unit tests (→ `rust-architecture`).

```toml
[dev-dependencies]
testcontainers = "0.27"
testcontainers-modules = { version = "0.15", features = ["postgres"] }
```

```rust
use testcontainers_modules::{postgres::Postgres, testcontainers::runners::AsyncRunner};

#[tokio::test]
async fn repo_persists_author() {
    let pg = Postgres::default().start().await.unwrap();      // ephemeral container
    let url = format!("postgres://postgres:postgres@127.0.0.1:{}/postgres",
                      pg.get_host_port_ipv4(5432).await.unwrap());
    let pool = sqlx::PgPool::connect(&url).await.unwrap();
    sqlx::migrate!().run(&pool).await.unwrap();               // real schema

    let repo = Sqlite::new(pool);                             // the real outbound adapter
    let saved = repo.create_author(&req()).await.unwrap();
    assert_eq!(repo.get(saved.id).await.unwrap(), Some(saved));
    // container is torn down when `pg` drops
}
```

Use a real container over a mock when the thing under test *is* the integration (queries,
migrations, transactions). Keep these tests separate from fast unit tests (a `--ignored` flag or
a separate target) so the suite stays quick when Docker isn't around — and note when they're
skipped (don't let "no Docker" silently pass as "covered").

## Doc tests

Code blocks in `///` docs are compiled and run by `cargo test --doc`. They keep your examples from rotting.

```rust
/// Adds two numbers.
///
/// ```
/// use my_crate::add;
/// assert_eq!(add(2, 3), 5);
/// ```
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

/// Parses a config string.
///
/// ```
/// # use my_crate::parse_config;
/// let cfg = parse_config("port = 8080").unwrap();
/// assert_eq!(cfg.port, 8080);
/// ```
///
/// Lines starting with `#` are hidden from rendered docs but still compiled.
pub fn parse_config(input: &str) -> Result<Config, ParseError> {
    let _ = input;
    Ok(Config { port: 8080 })
}

pub struct Config {
    pub port: u16,
}

#[derive(Debug)]
pub struct ParseError;
```

Block annotations: ` ```no_run ` compiles but doesn't execute; ` ```ignore ` skips compilation; ` ```should_panic ` expects a panic; ` ```compile_fail ` asserts it must *not* compile.
