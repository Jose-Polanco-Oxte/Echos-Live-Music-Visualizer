# Dependency Upgrade — Planning

Turn "bump the version and hope" into a sequenced, evidence-backed upgrade plan. The skill establishes the exact current → target version gap, reads the CHANGELOG and migration guide for **every** major in between, then greps the codebase for the dependency's imported symbols so the breaking-change list is narrowed to the call sites that actually exist here. It checks the target's peer-dependency and runtime requirements, orders the work (codemods first, one major at a time for big jumps, behind tests), and writes down a rollback before anything is touched.

## When to plan

- A key dependency, framework, or runtime is several majors behind and you need a path forward, not a single `npm install pkg@latest`.
- A security advisory (CVE, `npm audit`, Dependabot) forces an upgrade and you need to know the blast radius before merging.
- You are scoping a framework or runtime migration (React, Next.js, Django, Rails, Node, Python) and want to know what breaks before committing the sprint.

> [!WARNING]
> Jumping several majors in one `install` hides which version broke what. Breaking changes compound: v3's removal of an API plus v4's renamed option plus v5's changed default land as one undebuggable wall of errors. For a gap of two or more majors, upgrade **one major at a time**, landing each behind a green build/test run, so every failure maps to exactly one version's changes.

## Plan steps

1. **Pin the exact current and target versions.** Read the lockfile (`package-lock.json`/`pnpm-lock.yaml`/`yarn.lock`, `poetry.lock`, `go.sum`, `Cargo.lock`) for the version actually installed — not the loose range in the manifest, which lies about what resolved. Confirm the target: `npm view <pkg> versions --json`, `pip index versions <pkg>`, `go list -m -versions <mod>`, or the registry page. Record the full hop list, e.g. `4.2.1 → 5.x → 6.x → 7.0.3`.
2. **Read the migration guide for every major in between — don't skip the intermediate notes.** A jump from v4 to v7 means reading the v5, v6, **and** v7 breaking-change sections, not just v7's. Pull the CHANGELOG / UPGRADING / migration doc (`gh release view`, the repo's `CHANGELOG.md`, the docs site) and extract every entry under "Breaking", "Removed", "Renamed", "Default changed", and "Deprecated → removed".
3. **Inventory your actual usage so you only care about breaks that hit you.** Grep the codebase for the dependency's imported symbols and entry points — `grep -rIn "from 'pkg'"`, `grep -rIn "require('pkg')"`, `import pkg`, the specific class/function/option names called out in the breaking-change list. A breaking change to an API you never call is noise; a one-line default change to a function on 40 call sites is the real work. Map each relevant breaking change to its call sites.
4. **Check transitive/peer-dep and runtime requirements of the target.** The target may demand a newer peer (`react@>=19`, a `@types/*` bump) or a higher minimum runtime (Node, Python, Go, the language edition). Run `npm info <pkg>@<target> peerDependencies engines` (or read `requires-python` / `go.mod` `go` directive / `rust-version`). Cross-check against your other dependencies' peer ranges and your CI/Dockerfile/`.nvmrc`/`engines` runtime — a conflict here blocks the install before any code change.
5. **Sequence the work: codemods → one major at a time → behind tests.** Run the official codemod first if one exists (`npx <pkg>-codemod`, `npx @next/codemod`, framework migration CLIs) — they do the mechanical renames so you review semantics, not churn. For multi-major gaps, do one major per commit/PR; for each step, apply the codemod, hand-fix the mapped call sites, then run the **real** build and test commands as a checkpoint before the next hop.
6. **Write the rollback before touching anything.** Commit the current lockfile, branch the work, and record the revert: restore the pinned versions in the manifest **and** the lockfile (a manifest-only revert re-resolves to something new), then reinstall from the lockfile (`npm ci`, `pnpm install --frozen-lockfile`, `poetry install`). For a forced security upgrade with no safe target yet, note the interim mitigation (override/resolution pin, patch backport) as the fallback.

> [!WARNING]
> Peer-dependency conflicts and a bumped minimum runtime are the upgrades that silently break the build — not the API renames you can see in a diff. `npm install` may resolve a peer with a warning (or fail under strict/`pnpm`), and a target that requires Node 22 will install fine locally then explode in CI on Node 20. Verify both **before** writing code, in step 4.

> [!NOTE]
> Land the upgrade on its own branch with one commit per major hop and the codemod output as a separate commit from your hand-fixes. If a regression only shows up in CI or staging, granular history makes `git revert` of a single version trivial instead of unpicking a tangled bump.

## Planning output

A concrete upgrade plan, reproducible from the evidence gathered:

- **Version path** — the exact hop list from the lockfile to the target (`4.2.1 → 5.18.0 → 6.4.2 → 7.0.3`), one line per major.
- **Breaking changes that affect THIS codebase** — a table of `change → version → call sites`, with the file:line locations grep found; changes that touch no call site are explicitly listed as not-applicable so the reader trusts the filter.
- **Peer-dep & runtime gate** — required peer ranges and minimum runtime of the target vs. what the repo and CI currently pin, with conflicts flagged as blockers.
- **Steps in order** — codemod commands first, then per-major manual fixes, each with its test/build checkpoint command.
- **Rollback plan** — the exact manifest + lockfile revert and reinstall command, plus any interim mitigation for a forced upgrade.