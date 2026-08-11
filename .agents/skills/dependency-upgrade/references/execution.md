# Dependency Upgrade — Execution

Use these steps when upgrading project dependencies on any stack — Composer (PHP), npm / pnpm / yarn (JS/TS), pip / poetry / uv (Python), go.mod (Go), Cargo (Rust), or any other language-level package manager.

**Do NOT use when:** installing new dependencies for the first time, or routine code changes unrelated to package versions.

## Procedure: Upgrade a dependency

### 1. Assess

Before upgrading:

- **Read the changelog** for every version between current and target.
- **Identify breaking changes** — look for "BREAKING", "BC break", major version bumps.
- **Check deprecation notices** — code using deprecated APIs needs updating.
- **Review upgrade guides** — many packages provide migration docs.
- **Check runtime version requirements** — does the new version need a newer PHP / Node / Python / Go / Rust toolchain?

### 2. Plan

Categorize changes needed:

| Category | Action |
|---|---|
| No breaking changes | Upgrade directly |
| Deprecation warnings | Upgrade, then fix deprecations |
| Breaking changes (small) | Fix code, then upgrade |
| Breaking changes (large) | Create a roadmap, upgrade in steps |
| Peer dependency conflicts | Resolve conflicts before upgrading |

### 3. Execute

#### Composer (PHP)

```bash
composer outdated                      # check outdated packages
composer update vendor/package         # upgrade a specific package
composer require vendor/package:^3.0   # upgrade with version constraint change
composer update vendor/package --dry-run   # dry-run to see what would change
```

#### npm (JavaScript/TypeScript)

```bash
npm outdated              # check outdated packages
npm update package-name   # upgrade a specific package
npm install package-name@latest   # upgrade to a new major version
npm audit                 # check for vulnerabilities
```

#### pip / poetry / uv (Python)

```bash
pip list --outdated         # pip
poetry show --outdated       # poetry
uv pip list --outdated       # uv

pip install --upgrade package-name
poetry update package-name
uv pip install --upgrade package-name

pip-audit                   # via pip-audit
safety check                # via safety
```

#### go.mod (Go)

```bash
go list -u -m all              # list available updates
go get example.com/pkg@latest  # upgrade a specific module
go get example.com/pkg@v1.2.3
go mod tidy                    # tidy after upgrade
govulncheck ./...
```

#### Cargo (Rust)

```bash
cargo outdated               # requires cargo-outdated
cargo update -p crate-name   # upgrade
cargo add crate-name@1.2     # edition-aware add
cargo audit                  # requires cargo-audit
```

### 4. Verify

After upgrading, run the project's full verification pipeline. The exact commands depend on the stack — resolve via the project's `Taskfile.yml`, `package.json scripts`, `composer.json scripts`, `Makefile`, or a `quality-tools` reference.

| Stack | Type-check | Lint / autofix | Tests |
|---|---|---|---|
| PHP / Laravel | `vendor/bin/phpstan analyse` | `vendor/bin/rector process` + `vendor/bin/ecs check --fix` | `php artisan test` (or `vendor/bin/pest`) |
| TypeScript | `tsc --noEmit` | `eslint --fix` + `prettier --write` | `pnpm test` (or `vitest run`, `jest`) |
| Python | `mypy` / `pyright` | `ruff check --fix` + `ruff format` | `pytest` |
| Go | `go vet ./...` | `golangci-lint run --fix` | `go test ./...` |
| Rust | `cargo check` | `cargo clippy --fix` + `cargo fmt` | `cargo test` |

Re-run the type-checker after any auto-fixer that can rewrite types (Rector for PHP, `eslint --fix` for TS). Always run the full suite after an upgrade, not just the affected tests.

### 5. Document

- Note the upgrade in the commit message: `chore: upgrade vendor/package from 2.x to 3.x`
- If breaking changes required code modifications, describe them in the PR body.

## Multi-package upgrades

- **Upgrade one at a time** — easier to identify which upgrade broke something.
- **Exception:** Tightly coupled packages can be upgraded together (e.g., `laravel/framework` + `laravel/*`; `@nestjs/core` + `@nestjs/*`; `react` + `react-dom`; `next` + `@next/*`).
- **Run tests after each upgrade** — don't batch upgrades and test once at the end.

## Common pitfalls

| Pitfall | Prevention |
|---|---|
| Upgrading without reading changelog | Always read the changelog first |
| Upgrading all packages at once | One package at a time (or tightly coupled groups) |
| Trusting `composer update` blindly | Use `--dry-run` first, review changes |
| Ignoring deprecation warnings | Fix deprecations before they become errors |
| Skipping tests after upgrade | Full test suite + type-checker after every upgrade |
| Lock file conflicts | Coordinate upgrades with the team |

## Version constraint guidelines

| Constraint | Meaning | When to use |
|---|---|---|
| `^2.0` | `>=2.0.0 <3.0.0` | Default — allows minor + patch updates |
| `~2.1` | `>=2.1.0 <2.2.0` | Strict — allows only patch updates |
| `2.1.*` | `>=2.1.0 <2.2.0` | Same as `~2.1` |
| `>=2.0 <2.5` | Explicit range | When you know specific versions work |
| `dev-main` | Latest commit | **Never in production** — only for development |

## Security upgrades

- **Prioritize** — security upgrades should be fast-tracked.
- **Check `composer audit`** / `npm audit` regularly.
- **Patch versions** (e.g., 2.1.3 → 2.1.4) are usually safe to apply immediately.
- **Still run tests** — even security patches can break things.

## Conflict detection

When `composer require` or `npm install` fails with conflicts:

1. **Read the error** — which versions conflict?
2. **Check if other packages need updating** — `composer why vendor/conflicting-pkg`.
3. **Use `--dry-run`** first — `composer require vendor/pkg --dry-run`.
4. **Never use `--ignore-platform-reqs`** in production — only for investigation.

## Output format

1. Updated dependency with version constraint change
2. Breaking changes addressed with code modifications
3. Test results confirming compatibility
4. Post-update audit result: capability delta old→new, purpose-vs-behavior verdict, provenance/advisory status — and any finding surfaced to the user for confirmation (see `security-and-audit.md`)

## Auto-trigger keywords

- dependency upgrade · package update · breaking changes · changelog review · malicious package · supply chain · compromised update

## Do NOT

- Do NOT manually edit `composer.lock` or `package-lock.json`.
- Do NOT upgrade to `dev-*` versions in production branches.
- Do NOT ignore failing tests after an upgrade — fix or revert.