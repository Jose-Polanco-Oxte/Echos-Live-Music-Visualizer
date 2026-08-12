---
name: rust-review
description: >-
  Rust code-review rubric — the cargo quality gate, a severity-tiered checklist (safety, error handling, ownership, concurrency, performance, API quality), a public-API pass against the Rust API Guidelines, the Approve/Warning/Block verdict, and how to dispatch the craft review agents. Use when reviewing Rust code or a diff, deciding if it's mergeable, or reviewing a public API. Triggers: code review, is this mergeable, dispatch reviewer, public API, what proves done.
---

# Rust Review

The rubric for reviewing Rust changes: run the mechanical gate first, then read the diff against the severity checklist, then issue a verdict. This is the knowledge; the `rust-reviewer` agent applies it to an actual diff and reports back.

**The review entry point is the `rust-review` workflow** (`workflows/rust-review.js`): it scout-scales
depth to the diff, fans out the lenses below, grounds findings in tool output, and adversarially
verifies each one. This skill is the rubric the workflow and the `rust-reviewer` lens worker apply.

## When to Use

- Reviewing a diff / PR of Rust code
- Deciding whether changes are safe to commit or merge
- A self-check before opening a PR

### Pre-PR gate

Self-review runs **before** the PR opens, not after. Before `gh pr create` on a Rust change, run
the `rust-review` (or generic `review`) workflow on the branch diff, then close the loop —
triage the findings (`triage-findings`), fix them (`addressing-findings`), and re-review until the
verdict is **Approve** (or **Warning** with each remaining item justified in the PR body). Only
then open the PR. A one-shot review whose findings never loop back into fixes is not a gate; the
PR isn't ready until the loop is green.

## Step 1 — Establish the gate (CI-aware)

The mechanical gate is non-negotiable: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, and (if installed) `cargo audit` / `cargo deny check` must be green before human-style review is worth doing. But **before running a check locally, ask whether CI already computed it on this PR; if a conclusive check covers it and is green, consume that result instead of recomputing.** Re-running a cold build the PR already ran in CI is slow, sometimes impossible (no toolchain/network), and redundant.

**Green does not have to be `required`.** Most repositories have no branch protection — `isRequired` is then null on every check and `gh api …/branches/<b>/protection` returns 404 — so a rule that only consumes *required* checks never fires and always falls through to a local build. Required-ness governs whether a **red** check blocks the merge upstream; it says nothing about whether a **green** one is trustworthy. A passing job ran the project's own command on a clean machine with a warm cache; that is better evidence than anything reproducible locally.

Establish each signal:

1. **Detect the PR's CI** for the current branch:
   ```bash
   gh pr checks --json name,state,bucket,link
   ```
   If `gh` is missing, unauthenticated, offline, or finds no PR → fall straight through to the local gate (never fail on detection).
2. **`fmt` / `clippy` / `test` / `build`** — if a check whose name matches the command (substring: `fmt`, `clippy`, `test`, `build`/`check`; match generously — `cargo nextest`, `just clippy`, `ci / test (stable)` all count) is conclusive — required or not:
   - green → treat that command as **PASSED**; record provenance `via CI · PR #N`;
   - failed → the gate is red: verdict **Block**, cite the failed check name + link, stop;
   - pending / absent / name unrecognized → run that command locally (the safe default is an extra run, never a skipped check):
     ```bash
     cargo fmt --check
     cargo clippy --all-targets -- -D warnings
     cargo test                         # or: cargo nextest run + cargo test --doc
     ```
3. **`audit` / `deny`** — always run locally if installed, regardless of CI (cheap, usually absent from CI):
   ```bash
   cargo audit                        # if cargo-audit present
   cargo deny check                   # if cargo-deny present
   ```
   Setting up / interpreting `cargo audit` + `cargo deny` → `rust-security`.

If any `fmt`/`clippy`/`test`/`build` signal is red (CI or local), stop and report — don't review further. A green gate is the floor, not the ceiling — whatever its provenance, it means the change is *reviewable*, not that it's good.

## Step 1.5 — Resolve dependency context

Review against the crate versions the project **actually pins**, not against crates-in-the-abstract.
A call that is idiomatic on `tokio 1.40` may be deprecated on the `1.20` this repo locks; a default
may have flipped between minor versions. Before judging dependency usage:

- Resolve the real versions — `cargo metadata --format-version 1` (or read `Cargo.lock`) — and match
  the external crates the changed files `use` to their **locked** versions.
- For any nontrivial dependency the diff touches, check the usage against **that** version's API:
  a since-deprecated/removed/renamed item, a changed default, a known footgun of that exact version.
  Consult live docs (context7, docs.rs for the pinned version) rather than memory — this ecosystem
  moves fast. Version-specific misuse is `DEP-001` (Medium).
- Known-*vulnerable* versions are a separate axis, caught by `cargo audit` / RUSTSEC (`DEP-002`,
  High) in Step 1 — don't duplicate them here.

Best-effort: skip if there are no external-crate changes. Choosing/pinning versions and MSRV is the
`rust-ecosystem` skill's domain; this step only *uses* the pinned set to ground the review.

## Step 2 — Severity checklist

Review the diff against these tiers. This skill owns only the review *process*; cite the owning skill for each fix. Each item has a stable ID in the [rules.md](rules.md) catalog — cite it in a finding (e.g. `CON-003`) so the finding is addressable and dedup-able; novel issues without a catalog ID are still welcome.

- Safety / injection / secrets / untrusted-input limits → `rust-security`
- `unsafe` / missing `// SAFETY:` → `rust-unsafe`
- Result-vs-panic, typed-error-vs-`anyhow` → `rust-errors`
- `.clone()` / `&str`-vs-`String` / lifetimes → `rust-ownership`
- Blocking-in-async / lock-across-`.await` / deadlock / `Send`+`Sync` → `rust-concurrency`
- Allocation / hot-path / N+1 → `rust-performance`
- Generic code smells / naming / wildcard-match / missing-`///` → `rust-idioms`
- Structural simplification / file decomposition / spaghetti branching → `refactoring`
- Missing tests → `rust-testing`

### CRITICAL — block on sight

**Safety**
- `unwrap()` / `expect()` / `panic!` / `todo!` / `unreachable!` on a reachable production path
- `unsafe` block without a `// SAFETY:` comment justifying every invariant (SAFETY-comment discipline & UB checklist → `rust-unsafe`)
- SQL/command built by string interpolation of untrusted input (injection)
- User-controlled path used without canonicalize + prefix check (traversal)
- Hardcoded secret / key / token / password in source
- Deserializing untrusted input without size/depth limits
- `debug_assert!` carrying a load-bearing invariant — an `unsafe` precondition, a bounds/length check, a trust-boundary validation. It compiles out in `--release`, so the shipped binary runs unguarded; a safety-critical check must be a real `assert!` (→ `rust-unsafe`; when `debug_assert!` *is* the right call → `rust-performance`)

**Error handling**
- Recoverable failure handled with `panic!`/`unwrap` instead of `Result`
- `let _ = result;` silently dropping a `#[must_use]` / error value

### HIGH — block unless justified

**Safety — build-profile divergence**
- Arithmetic on an untrusted-input path whose **outcome differs between the dev/test and the shipping profile**. `overflow-checks` is on in `dev`/`test` and off in `release` by default, so the same expression panics under review and wraps silently in production.

  Grade against the profile the project actually ships — read `[profile.release]` in the crate and workspace root before assuming, it may be re-enabled there. The profile-gated panic is the **floor of the impact, not the ceiling**: a panic that vanishes in release is not thereby harmless. Ask what the release build does *instead* — a silent wrap that truncates a length, misresolves an index, or corrupts state is worse than the panic precisely because nothing reports it. "Doesn't reproduce in release, moving on" is the reflex that misses it. Report both facets.

**Ownership & lifetimes**
- `.clone()` added to silence the borrow checker without understanding why
- Takes `String` where `&str`/`impl AsRef<str>` suffices; `Vec<T>` where `&[T]` suffices
- Explicit lifetimes where elision applies

**Concurrency**
- Blocking call (`std::thread::sleep`, `std::fs`, blocking I/O) inside an `async` fn
- Unbounded channel without justification (prefer bounded back-pressure)
- Lock held across an `.await`
- Inconsistent lock acquisition order (deadlock risk)
- Missing `Send`/`Sync` where the type crosses threads

**Test coverage** (cross-check with the `rust-testing` skill)
- New error path or branch with no test
- Bug fix landed without a regression test reproducing it

### MEDIUM — warn, may merge

**Performance**
- Allocation inside a hot loop; `to_string()`/`to_owned()` where a borrow works
- `Vec::new()` + push loop where the size is known (`with_capacity`)
- N+1 queries / repeated work in a loop

**API & quality**
- Library returning `Box<dyn Error>` / `anyhow::Error` instead of a typed error (API-design concern → `rust-errors`)
- Function > ~50 lines or nesting > 4 levels
- Wildcard `_ =>` on a business enum (hides new variants — prefer exhaustive)
- `pub` item without a `///` doc
- `#[allow(...)]` suppressing a lint without a justifying comment
- Crate-root `#![deny(warnings)]` (or other blanket lint-level attributes) — brittle: a new compiler/clippy lint becomes a hard build break for the crate and its dependents → move the denial to CI (`rust-idioms` anti-patterns)

**Maintainability & structural simplification** (fix → `refactoring`, `rust-idioms`)
- **Missed code judo** — a reframing that uses the existing architecture more effectively would make this change *dramatically* simpler or delete a whole category of complexity (a layer, a branch family). Don't flag hypothetical rewrites; flag a concrete, behavior-preserving restructuring the author could have taken.
- **File-size growth** — the diff pushes a file across ~700 lines (Rust files are dense; this is the decomposition smell, the per-function ~50-line rule above is separate) → split by responsibility.
- **Spaghetti branching** — a new ad-hoc conditional / one-off branch / scattered special-case spliced into an unrelated or shared flow, instead of behind a dedicated abstraction (→ `refactoring` "replace conditional with dispatch").
- **Needless optionality / casts** — superfluous `Option` wrapping where the value always exists, `as`-casts where `From`/`TryFrom` belongs, `Box<dyn Any>` / downcasting where a typed model fits.

### Maintainability bar — presumption of block (strict mode)

By default the maintainability items above are **MEDIUM** (warn, may merge). When the review is dispatched in **strict mode** (the `rust-review` workflow's `strict` flag, or an explicit "harsh maintainability review" request), they invert to a **presumption of block**: each is treated as a blocker *unless the author has clearly justified it in the diff or brief*. In strict mode, Approve additionally requires:

- no structural regression (a previously cohesive module didn't become more coupled or harder to scan);
- no obvious simplification missed (the code-judo check above came up empty);
- no unjustified file-size explosion;
- no spaghetti-growth from special-case branching;
- no hacky or magical abstraction obscuring the design.

Strict mode raises the bar; it does not invent findings — every item still goes through the verification protocol and a refuted item is dropped.

### Public-API diffs — the API-design pass

When the diff changes a **public API** (a library crate, a published `pub` surface), also run the
condensed Rust API Guidelines checklist → [api-design.md](api-design.md). It catches the
library-author concerns the general checklist above doesn't — missing common-trait impls,
`Deref`-as-inheritance, out-parameters, unsealed extensible traits, leaking unstable deps, absent
`CHANGELOG`/metadata. Each item points at the craft skill that owns the fix. Skip it for
application-internal code.

## Review lenses

The workflow fans the rubric out into independent lenses, each reviewing ONE slice blind to the
others (higher recall than one broad pass):

| Lens | Slice | Owning skill for the fix |
|---|---|---|
| safety | injection / secrets / unsafe / untrusted-input limits / build-profile-divergent arithmetic and guards | `rust-security`, `rust-unsafe` |
| errors | Result-vs-panic, dropped errors, typed-vs-anyhow | `rust-errors` |
| ownership | needless clone, `&str`/`&[T]`, lifetimes | `rust-ownership` |
| concurrency | blocking-in-async, lock-across-await, deadlock, Send/Sync | `rust-concurrency` |
| performance | hot-loop allocation, N+1, needless owning | `rust-performance` |
| api-idioms | typed errors, giant fns, wildcard match, missing docs, `#![deny(warnings)]` | `rust-idioms` |
| invariants | domain lifecycle/scope rules, derived/effective quantities, eligibility checks that **diverge from an existing sibling gate** (a new capacity/permission predicate dropping a fail-closed dimension), and the **mirror walk** on two-sided contracts (below) | `rust-architecture`, `rust-fintech` |
| compat | serialization / persistence / rolling-deploy compatibility — a changed serde/JSONB/wire representation vs data written by other code versions (rename with no `alias`, `alias` that only covers new-reads-old, unbackfilled migration) | `rust-ecosystem` |
| maintainability | structural simplification (code judo), file-size growth, spaghetti branching, needless optionality/casts | `refactoring`, `rust-idioms` |
| tests | test *quality* not just presence; missing regression/error-path tests | `rust-testing` |
| intent | does the change do what the brief/spec says? | `specs` |

The workflow runs additional context-dependent lenses the scout selects — `api-boundary` (error→HTTP-status
mapping, OpenAPI completeness), `reconciler` (controller idempotency), and `negative-space` (breakage the diff
enables in unchanged code); `workflows/review.js` is the authoritative lens set.

Each lens expands context (callers/impls/error paths via `rust-navigation`) and emits blast-radius
for changed public symbols.

## Confidence tiers — surface, don't censor

- **Confirmed** — located and survived verification; drives the verdict.
- **Suspected** — borderline or unverified; surfaced for the author, **never** changes the verdict.

Report everything you suspect. Borderline findings go to Suspected, not the bin.

## Tool grounding (seed findings)

Beyond the gate, the workflow runs real tools scoped to the diff and feeds their output in as seed
findings (each still verified): `cargo clippy -W clippy::pedantic -W clippy::nursery`; for
published libraries `cargo semver-checks check-release`; and `semgrep` as a SAST seed — in-repo
`./semgrep/` custom rules always when present, plus `p/rust`/`p/secrets` when the diff is
security-sensitive (auth, crypto, input parsing, unsafe, FFI, deps). semgrep results are seeds, never
gate failures: taint/secrets over-report, so the downstream verification refutes the false positives
(see `rust-security`). Optional tools degrade gracefully when absent.

## Severity magnitude — measure it, don't inherit it (`SAF-009`)

"Same class as that other finding" is a claim about **mechanism**, not about severity. A shared root
cause says nothing about shared magnitude, and the gap can be one or two orders of magnitude —
entirely invisible unless someone does the arithmetic.

For any resource-exhaustion or algorithmic-complexity finding, compute before you label:

- **Attack throughput vs a real-data baseline.** Measure the same code on *representative real
  input*, not only on the crafted PoC. "8× slower than normal traffic" and "50,000× slower" are
  different findings; a decoder still running at 10+ MB/s under attack is not a denial of service.
- **Attacker cost per unit of victim cost** — bytes (or requests) the attacker must send per second
  of victim CPU. This is the metric that ranks two exhaustion bugs against each other; when citing a
  prior finding as precedent, compare *this* number against that one's, not the mechanism.
- **State the units.** A severity backed by a measurement carries its numbers into the report.

Crashes have no throughput curve — a panic either fires or it doesn't. Rate those by convention
(malformed input causing a panic, no memory corruption, in a parsing library → Medium) and say
explicitly that it is a judgement call, so the label doesn't acquire false precision.

The check cuts both ways: run honestly, it demotes inflated findings and it *promotes* the ones that
turn out far worse than their class suggests.

## The mirror walk — enforcement asymmetry (`INV-005`)

For a protocol, state machine, codec, or any two-sided contract, bugs cluster where an invariant is
enforced in one place and **not at its mirror**. The asymmetry itself is the finding — you do not
need a crash, and a fuzzer has no oracle for it.

1. **Enumerate the invariants.** The **error enum is the index**: every variant names a rule someone
   decided to enforce. The spec/RFC and doc comments name the rest.
2. **Grep every enforcement site** for each invariant — the guard, the version check, the bounds or
   limit test, the capability predicate.
3. **Walk the four mirror axes.** For each site, where is the mirror and is it guarded the same?
   - **client ↔ server** — the server rejects X; does the client?
   - **send ↔ receive** — the outgoing value is filtered; is the incoming one re-validated?
   - **offered ↔ accepted** — we constrain what we offer; do we constrain what we accept back?
   - **one-param ↔ all-params** — one negotiated parameter is validated; are its siblings (version,
     algorithm, limit, scope)? Missing siblings travel in packs.
4. **Release-diff each candidate** — `git diff <last-tag> -- <file>`. A guard **present in the
   release and gone at HEAD** is a regression, not a long-standing gap; that changes its severity.

Report: the invariant · enforced-at `file:line` · missing-mirror-at `file:line` · which axis · what
the gap lets through (panic, silent drop, downgrade, accepted-but-should-be-rejected).

### Proving one — the control/attack differential

These findings have no crash to point at: the defect is that a value is *silently discarded* or a
message that should be rejected is *accepted*. Build the oracle as an A/B where **exactly one
variable changes**:

- **CONTROL** — the benign arrangement; the value must arrive / the message must be rejected.
- **ATTACK** — byte-for-byte the same construction with the one variable flipped; the loss or the
  wrong-accept must appear.

The oracle is the **delta**, not a panic. Assert both halves and exit non-zero unless CONTROL holds
*and* ATTACK reproduces — then the reproducer doubles as the regression test, and a fix that breaks
CONTROL cannot pass by making ATTACK stop firing.

Reach the state through the crate's **own test helpers** (its `tests/common`, an internal
`*-test` crate, a `#[cfg(feature = "test-util")]` surface) rather than hand-rolling the wire format
or mocking the protocol. A PoC over a mock measures the mock. Then state plainly what the harness
**demonstrated** versus what is **inferred** — "acceptance demonstrated at the API; on-path
reachability inferred, not exercised" is an honest and much stronger claim than blurring the two.

## Premise grounding — cite it or drop the claim

Most findings rest on a premise that is **not visible at the line they cite**: "the dependency
rejects this", "this is reachable from untrusted input", "no caller guards it", "the sibling path
does X". That off-site premise is the claim a review most reliably invents — and a second, smarter
reading does not catch it, because it reproduces the same assumption. Only opening the code does.

So every off-site premise is pinned to a `file:line` you **actually opened** — dependency sources
included (`~/.cargo/registry`, the vendored tree) — and reported in the finding's `whereChecked`.
A premise you did not open is not admissible: open it, or drop the claim and report only what the
cited line itself shows.

This binds **rejection** exactly as much as confirmation. "A caller already validates this," waved
through without opening the caller, is the same unfounded claim as the finding it dismisses — and
it discards a real bug silently. Uncertain and unable to check? That is Suspected, not a rejection.

An off-site premise nobody could pin costs a finding its Confirmed tier — it drops to Suspected,
never to refuted. Unsupported is not disproven, and burying it as "refuted" would keep a possibly
real defect out of every later round.

## Verification protocol

Every finding (lens or seed) is checked before it can be Confirmed:

- **Mechanical first:** if a tool can decide the finding (a clippy lint, semgrep rule,
  cargo-audit advisory), the verifier re-runs it scoped to the cited file and the tool's output
  overrides judgement in both directions. Tool-reported seeds can never be refuted on reasoning
  alone — only by the tool demonstrably no longer reporting them.
- **Adversarial:** skeptics try to REFUTE it (default to refuted when uncertain — except
  tool-reported seeds, per above). One skeptic by default; three-vote consensus for Critical/High.
- **Self-verification (anti-hallucination):** re-read the cited `file:line` — does the code
  actually say what the finding claims? A wrong citation drops the finding. A path that is
  test/example-only (not production-reachable) does NOT drop it — it demotes the confirmed
  severity one notch.
- **Exclusion catalog:** a rejection is a claim and carries the same burden as the finding. When
  one of the false-positive precedents in [fp-rules.md](fp-rules.md) fires, cite its ID
  (`refuted per FP-006`) — and run the trace that rule demands, not the shape it matches. That file
  also lists the `KEEP-*` non-reasons: dismissals that sound decisive and have repeatedly killed
  real defects.

## Step 3 — Verdict

| Verdict | When |
|---|---|
| **Approve** ✅ | gate green (CI or local), no **Confirmed** CRITICAL/HIGH/MEDIUM |
| **Warning** ⚠️ | gate green (CI or local), **Confirmed** MEDIUM only — Suspected items listed but don't block |
| **Block** ⛔ | gate red (CI or local), or any **Confirmed** CRITICAL/HIGH |

In **strict mode**, the maintainability bar applies: a Confirmed maintainability finding (code judo missed, file-size explosion, spaghetti branching, hacky abstraction) is a **presumptive Block** unless the author justified it — escalated from its default MEDIUM. Outside strict mode those findings stay MEDIUM (Warning at most).

Report findings as `severity · file:line · [rule-id] · what · why · fix`. Cite the [rules.md](rules.md) catalog ID when the finding maps to one (e.g. `CON-003`); novel findings need no ID. Be specific and cite the line; a finding without a location isn't actionable.

"Gate green / red" is read from Step 1 — the signal may come from a green CI check or a local run. Cite which in the `## Gate` line of the output.

## Requesting a review & acting on the verdict

Review early and often — small reviews catch issues while they're cheap; one giant review at the end catches them after they've compounded. Request after a feature or meaningful unit of work, before merging, when stuck, or after a complex bug fix.

Hand the reviewer a **crafted brief**, not your chat history:

- the **diff range** — `BASE..HEAD` (`git merge-base main HEAD` and `HEAD`); the agent derives the exact range itself via `git diff --merge-base main`, so the SHAs are just for your reference;
- **what it should do** — the requirement/spec it's meant to satisfy (→ `specs`);
- **what you built** — a one-paragraph summary.

In craft, dispatch the agents with that brief:

- **`rust-reviewer`** — runs the cargo gate + this rubric → Approve/Warning/Block.
- **`rust-security-scanner`** — security-sensitive changes (deps, `unsafe`, input handling) → `rust-security` verdict.
- **`rust-miri`** — when the change touches `unsafe` (→ `rust-unsafe`).

**Acting on the verdict** — working a set of findings to green (triage accept/reject/defer/needs-decision, order blocking → simple → complex, fix, verify, re-review, close the loop on GitHub) is its own discipline → `addressing-findings`; for a large batch it dispatches the `triage-findings` workflow.

## Proving a claim — what proves what

The Rust commands that actually prove each claim:

| Claim | Proof (run it) | Not proof |
|---|---|---|
| tests pass | `cargo test` / `cargo nextest run` → 0 failed | "should pass", an earlier run |
| doctests pass | `cargo test --doc` | unit tests passing |
| lint clean | `cargo clippy --all-targets -- -D warnings` → exit 0 | `cargo check` passing |
| formatted | `cargo fmt --check` | "I ran fmt earlier" |
| it builds | `cargo build --release` → exit 0 | clippy passing |
| bug fixed | re-run the case that reproduced it → passes | code changed, "looks right" |
| a panic is release-unreachable | re-run the repro under the shipping profile **and** state what release does instead (wrap? truncate? corrupt?) | `overflow-checks` is off in release |
| a silent-loss / wrong-accept bug is real | a control/attack pair differing in ONE variable: CONTROL correct **and** ATTACK reproducing (above) | no panic, "the code clearly drops it" |
| a defect is reachable from untrusted input | drive it through the real public entry point on crafted input | reproduced by constructing the state directly (builder/`new`/test fixture) |
| regression test works | saw it RED before the fix, GREEN after | it's green now |
| no vulns | `cargo audit` / `cargo deny check` clean | "deps look fine" |
| coverage target met | `cargo llvm-cov --fail-under-lines N` | tests pass |
| an agent finished | read the actual diff / its output | the agent said "success" |
| requirements met | check each one against the spec | tests pass |

A green **CI check** (required or not) for the same command is also valid proof of that command (see Step 1 — Establish the gate). The point of the table is that *some* fresh authoritative signal exists — CI or local — not that you must re-run it yourself.

State the claim **with** the evidence, or state the real status with the evidence. An earlier run, a "should pass", or a subagent's self-report is not evidence.

## Boundaries

- *How* to write the missing tests → `rust-testing` skill (this rubric only flags that they're missing).
- This skill judges; it does not rewrite. Propose the fix, let the author apply it.
