# Dependency Upgrade — Security and Supply-Chain Audit

Upgrade safely means running **two** security gates: (1) the known-vulnerability scan, and (2) the post-update malware/behavior audit for *compromised* updates that no CVE scanner will catch.

## Gate 1: Triaging Package-Manager Audit Results

The native package-manager audit (composer/npm/pip audit) reports known advisories; it does not prove a package is trustworthy or that vulnerable code is reachable.

```
The native package-manager audit reports a vulnerability
├── Severity: critical or high
│   ├── Is the vulnerable code reachable in runtime, build, test, or deployment paths?
│   │   ├── YES --> Fix immediately (update, patch, or replace the dependency)
│   │   └── NO (confirmed unused across those paths) --> Fix soon, but not a blocker
│   └── Is a fix available?
│       ├── YES --> Update to the patched version
│       └── NO --> Check for workarounds, consider replacing the dependency, or add to allowlist with a review date
├── Severity: moderate
│   ├── Reachable in production? --> Fix in the next release cycle
│   └── Dev-only? --> Fix when convenient, track in backlog
└── Severity: low
    └── Track and fix during regular dependency updates
```

**Key questions:**
- Is the vulnerable function actually called in your code path?
- Is the dependency a runtime dependency or dev-only?
- Is the vulnerability exploitable given your deployment context (e.g., a server-side vulnerability in a client-only app)?

When you defer a fix, document the reason and set a review date.

## Gate 2: Post-update Malware & Behavior Audit

CVE scanning catches *known-vulnerable* versions. It does **not** catch a **compromised update**: a trusted package with a legitimate history ships a normal-looking version bump that quietly adds data-exfiltration or other harmful behavior. This is how the biggest supply-chain attacks landed — event-stream (wallet stealer as a new transitive dep), ua-parser-js (`preinstall` miner + credential stealer), @solana/web3.js (key exfil hidden inside expected network calls), chalk/debug + 16 (browser crypto-drainer, 2B weekly downloads), xz-utils (backdoor in the released tarball, not the git repo). Routine updates slip through because the version looks normal and install runs scripts across the whole transitive tree silently.

**Run this audit during/after any add or upgrade, then surface findings to the user and hold pending confirmation** — a live supply-chain risk is surfaced, never silently accepted:

1. **Install without running scripts first** — `npm install --ignore-scripts` (npm v12 defaults to this), `composer install --no-scripts`, `pip install --only-binary :all:` (wheels only — no sdist build code) — so install-time code (the #1 RCE vector) cannot run before inspection.
2. **Diff the version delta old→new** — the `scripts` block (any newly-added `pre/post/install` hook), the dependency tree (any **new transitive dependency**), and — where feasible — the published tarball vs the git source (xz hid in the tarball).
3. **Capability / behavior diff** — did the new version add a capability its job doesn't need: network egress (`fetch`/`net`/`dns`/`http`), `child_process`/shell, env/secret/credential reads, filesystem writes, obfuscated/minified blobs, a `.github/workflows` file? Use `socket` / `guarddog <eco> scan <pkg>@<ver>` if available; else read the delta.
4. **Purpose-vs-behavior legitimacy check** — a Slack/HTTP client legitimately makes network calls; a date/string/color util does not. For each new capability ask: *does the package's stated purpose require this?* A network/secret capability with no purpose justification — or a **new outbound endpoint** even in a package that already uses the network — is high-risk.
5. **Provenance + advisory feeds** — `npm audit signatures` (flag a dep that *had* provenance and lost it — a hallmark of a token-theft publish); `osv-scanner --lockfile=…` and the GitHub Advisory / Socket / Snyk malware feeds against the newly-resolved versions.

**Surface to the user** any: new install script · new transitive dep · new network endpoint / secret read · obfuscated blob · lost provenance · advisory/malware hit — with the version delta and the purpose-vs-behavior verdict, and hold the update until they decide. Never auto-accept a bump that introduced an unexplained capability.

## Supply-Chain Hygiene Rules

- **Never apply forced audit remediation automatically** (`npm audit fix --force` or equivalent). Preview the remediation, read changelogs, and test each resulting upgrade; forced fixes may cross declared dependency ranges.
- **Verify registry signatures and provenance where supported** (`npm audit signatures`, `pnpm audit signatures`) and treat absence as a signal to investigate, not automatic proof of compromise.
- **Review new dependencies, lockfile diffs, and script-policy changes together** — ownership, maintenance, release age, provenance, transitive graph, and typosquats such as `cross-env` vs `crossenv`.
- **Block dependency scripts before first execution.** Bootstrap with scripts disabled or a documented fail-closed policy, inspect the pending script source, approve only the minimum required packages, commit the policy, then verify with a clean frozen/immutable install. Never blanket-approve scripts.
- **Find the installation boundary and manager.** Use the workspace root that owns the lockfile, or an independent nested project only when it is outside that workspace. Corroborate `packageManager` (when present), the lockfile, and CI; stop on disagreement or competing lockfiles. Pin the manager version.

## Security Review Checklist (supply chain items)

- [ ] One authoritative lockfile committed; CI uses that manager's frozen/immutable install
- [ ] Native audit triaged by reachability and fix risk; dependency install scripts blocked unless explicitly approved
- [ ] New dependencies reviewed (ownership, provenance, release age, transitive graph)
- [ ] No secrets committed; no forced audit remediation applied automatically

## Gotchas

- **A trusted package is not a safe version.** Every major supply-chain attack (event-stream, ua-parser-js, chalk/debug, xz) shipped through a *legitimate* package's normal-looking bump — maintainer-authored ≠ safe. Run the post-update behavior audit, not just `audit` for CVEs.
- **`audit` (CVE) ≠ malware scan.** `npm/composer audit` only knows *published* vulnerabilities; a fresh compromised version has no CVE yet. The capability/behavior diff + purpose-vs-behavior check is what catches zero-hour malware.
- **When adding a new dependency** (not upgrading), also run a security audit first and re-check after install: known CVEs, maintenance status, dependency tree, license compatibility, and bundle size (npm).