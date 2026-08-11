# Git Workflow

This rule defines the mandatory Git workflow for every repository in this
workspace. These instructions are prescriptive. Agents must preserve repository
history, branch boundaries, reviewability, and release traceability over
convenience.

The Agent must never infer permission to merge, release, tag, force-push, or
promote changes to a protected branch merely because implementation work is
complete.

## 1. Core Principles

* `main` represents released or release-ready production history.
* `dev` / `develop` represents integrated development when the repository uses
  that model.
* Feature, fix, refactor, documentation, and maintenance work should normally be
  performed on dedicated branches.
* One commit must represent one logical change.
* A completed implementation does **not** imply permission to:

  * merge into `main`;
  * push one branch directly into another;
  * create or push a version tag;
  * create a GitHub release;
  * force-push shared history.
* Releases are explicit operations and must follow the release procedure in
  Section 7.

Before modifying Git state, inspect the current branch and working tree when
needed:

```bash
git status
git branch --show-current
```

---

## 2. Commit Format — Conventional Commits

Every commit must follow:

```text
<type>(<optional-scope>): <imperative lowercase description>

<optional body: explain what and why, not implementation details>

<optional footer>
```

### Allowed Types

| Type       | Use for                                                       |
| ---------- | ------------------------------------------------------------- |
| `feat`     | New user-visible or API functionality.                        |
| `fix`      | Bug fixes.                                                    |
| `docs`     | Documentation-only changes.                                   |
| `style`    | Formatting or whitespace changes with no logic change.        |
| `refactor` | Internal code changes that neither add features nor fix bugs. |
| `perf`     | Performance improvements.                                     |
| `test`     | Test-only additions or corrections.                           |
| `build`    | Build system, packaging, dependencies, or build tooling.      |
| `ci`       | CI/CD configuration and automation.                           |
| `chore`    | Maintenance not covered by another type.                      |
| `revert`   | Reversion of an existing commit.                              |

### Format Rules

* Scope is optional, lowercase, and identifies the affected component:
  `fix(audio): ...`.
* Description uses imperative present tense: `add`, `fix`, `remove`, `prevent`.
* Do not use past or progressive tense such as `added`, `fixed`, `adding`.
* Keep the first line concise, preferably no more than ~72 characters.
* Do not end the description with a period.
* Breaking changes must use `!` and a footer:

```text
feat(api)!: change response contract

BREAKING CHANGE: clients must use the new response schema.
```

* `revert` commits must identify the reverted commit in the body.
* Never use meaningless messages such as `update`, `changes`, `misc`, `wip`,
  `fix stuff`, or equivalent.
* If multiple unrelated logical changes exist, create separate commits.

Examples:

```text
feat(catalog): add visual preset search
fix(audio): prevent wasapi initialization crash
docs(build): document release workflow
ci(release): validate arm64 distribution before publishing
refactor(renderer)!: replace legacy frame pipeline

BREAKING CHANGE: custom renderer integrations must use the new frame API.
```

---

## 3. Branch Creation

Create a new branch when **any** of the following applies:

1. The current branch is `main`, `master`, `dev`, `develop`, or another shared /
   protected integration branch and the task requires modifying repository files.
2. The requested work is logically different from the purpose of the current
   branch.
3. The user explicitly requests a branch, PR, isolated implementation, or review
   workflow.
4. The change is experimental, destructive, high-risk, or broadly cross-cutting.
5. A major dependency upgrade, migration, architecture change, or substantial
   refactor is required.

Do not modify shared/protected branches directly unless the user explicitly
instructs otherwise.

### Branch Naming

Use:

```text
<category>/<short-description-in-kebab-case>
```

Preferred categories:

```text
feature/
fix/
hotfix/
refactor/
docs/
test/
build/
ci/
chore/
```

Examples:

```text
feature/audio-device-selector
fix/arm64-github-build
ci/release-validation
docs/git-workflow
hotfix/startup-crash
```

If an issue identifier exists:

```text
fix/proj-123-audio-initialization
```

---

## 4. When to Continue on the Current Branch

Continue on the current branch when:

1. It was already created for the current task or directly related work.
2. The requested work is an incremental continuation of that branch's scope.
3. The change is trivial and low-risk **and** the branch is not shared/protected.
4. The user explicitly says to continue on the current branch.

When uncertain:

* on `main` / `master` / `dev` / `develop`: create a branch;
* on an existing task branch: remain on it if the work belongs to the same task.

Do not create unnecessary nested or replacement branches for work that clearly
belongs to the current task branch.

---

## 5. Before Every Commit

Before staging or committing:

```bash
git status
git diff
```

When staged changes exist, also inspect:

```bash
git diff --staged
```

The Agent must:

1. Understand every file being committed.
2. Exclude generated outputs, build artifacts, secrets, local configuration,
   temporary files, IDE state, and other files that should not be versioned.
3. Check whether suspicious files should instead be added to `.gitignore`.
4. Split unrelated modifications into separate logical commits.
5. Avoid blindly running:

```bash
git add .
```

when unrelated or unverified files exist.

Prefer explicit staging:

```bash
git add path/to/file1 path/to/file2
```

or carefully reviewed partial staging when appropriate.

Before committing, run the relevant tests, linters, builds, or validation
commands required by the repository when practical.

---

## 6. Push and Remote Branch Rules

### Normal task branches

For a newly created branch:

```bash
git push -u origin <branch>
```

For an already tracked branch:

```bash
git push
```

### Prohibited behavior

Never use:

```bash
git push --force
```

on shared branches.

`--force-with-lease` is allowed only on a personal/task branch when:

* the user explicitly requests history rewriting; or
* an explicitly requested rebase/amend operation requires it.

Never force-push:

```text
main
master
dev
develop
release/*
```

unless the user explicitly overrides this policy with full awareness of the
consequences.

### Branch promotion

Do **not** promote branches by directly pushing one local branch into another
remote branch, for example:

```bash
git push origin dev:main
git push origin feature/foo:main
```

unless the user explicitly requests that exact operation.

The normal integration path is:

```text
task branch
    ↓ Pull Request
dev / develop
    ↓ Pull Request
main
```

or, for repositories without an integration branch:

```text
task branch
    ↓ Pull Request
main
```

Use Pull Requests for promotion into `main` so CI, review history, branch
protection, and merge provenance remain intact.

---

## 7. Release Workflow

A release is a distinct operation from normal development.

The Agent must **never create or push a release tag unless the user explicitly
requests a release or explicitly authorizes creation of that version tag**.

For repositories using `dev` and `main`, the canonical release flow is:

```text
feature/fix branches
        ↓
       dev
        ↓
validation
        ↓
PR: dev → main
        ↓
      main
        ↓
final verification
        ↓
annotated version tag
        ↓
push tag
        ↓
release CI/CD
        ↓
published release
```

### 7.1 Prepare the development branch

Start from the integration branch:

```bash
git switch dev
git fetch origin --prune
git pull --ff-only origin dev
git status
```

The working tree must be understood before proceeding.

Any final release-preparation changes must be committed normally using
Conventional Commits.

Example:

```bash
git add <reviewed-files>
git commit -m "build(release): prepare v0.2.0.17"
git push origin dev
```

Do not create an empty `prepare release` commit merely to mark a release if no
repository changes are required.

### 7.2 Validate the release candidate

Before promoting `dev` to `main`, run the repository's complete applicable
release validation.

This should include, when available:

* unit/integration tests;
* lint/static analysis;
* release builds;
* packaging validation;
* supported architecture builds;
* version/metadata validation.

Do not intentionally use test-skipping flags for the final release validation
unless the user explicitly requests it or the skipped checks have already run
successfully for the exact release commit.

For Echo Visualizer, a GitHub release candidate should validate both supported
architectures:

```powershell
./scripts/Build-Distributions.ps1 `
  -Profile GitHub `
  -RuntimeIdentifiers win-x64,win-arm64 `
  -BuildVersion <A.B.C.D>
```

A successful local build does not replace CI, but it reduces the chance of
creating a tag that immediately fails the release pipeline.

### 7.3 Promote `dev` to `main`

Push `dev` normally:

```bash
git push origin dev
```

Then promote:

```text
dev → Pull Request → main
```

Do not substitute the PR with:

```bash
git push origin dev:main
```

unless explicitly instructed by the user.

The release tag must be created only **after** the intended release changes are
present on `main`.

### 7.4 Synchronize local `main`

After the PR has been merged:

```bash
git switch main
git fetch origin --prune
git pull --ff-only origin main
```

Then verify:

```bash
git status
git log -1 --oneline
```

Requirements before tagging:

* working tree is clean;
* local `main` is synchronized with `origin/main`;
* the current commit is the intended release commit;
* release version metadata is correct;
* required release validations passed.

When useful, verify synchronization explicitly:

```bash
git rev-parse HEAD
git rev-parse origin/main
```

Both hashes should match.

### 7.5 Verify the tag does not already exist

Before creating `<version>`:

```bash
git tag --list <version>
git ls-remote --tags origin refs/tags/<version>
```

If the tag already exists, **stop**.

Never silently delete, replace, move, or recreate an existing release tag.

Published/versioned tags are immutable unless the user explicitly requests a
tag repair and understands the consequences.

### 7.6 Create an annotated release tag

Release tags must be annotated:

```bash
git tag -a vA.B.C.D -m "<Product> vA.B.C.D"
```

Example:

```bash
git tag -a v0.2.0.17 -m "Echo Visualizer v0.2.0.17"
```

Do not create the tag on `dev`, an unmerged feature branch, or an arbitrary
detached commit during the normal release flow.

The tag must point to the intended `main` release commit.

Verify before pushing:

```bash
git show --no-patch --format=fuller v0.2.0.17
```

Optionally verify that the tag resolves to `HEAD`:

```bash
git rev-parse HEAD
git rev-parse v0.2.0.17^{}
```

The hashes must match for the normal release flow.

### 7.7 Push only the intended release tag

Once verified:

```bash
git push origin v0.2.0.17
```

Do not use:

```bash
git push --tags
```

for a normal release because it may publish unrelated local tags.

After pushing, verify the remote tag:

```bash
git ls-remote --tags origin \
  refs/tags/v0.2.0.17 \
  refs/tags/v0.2.0.17^{}
```

### 7.8 CI/CD owns release artifact publication

If pushing the tag triggers the repository's release workflow, allow CI/CD to
build and publish the official artifacts.

Do not manually create competing release artifacts or another release for the
same tag unless the workflow fails and the user explicitly requests recovery.

For Echo Visualizer, a tag matching:

```text
v*.*.*.*
```

is expected to trigger the official GitHub release workflow.

The intended release sequence is therefore:

```text
commit(s)
→ push dev
→ PR dev → main
→ merge
→ synchronize local main
→ verify main
→ create annotated tag
→ verify tag
→ push exact tag
→ CI builds x64 + ARM64
→ CI publishes GitHub Release
```

---

## 8. Release Safety Rules

The following actions require explicit user authorization:

* creating a release/version tag;
* pushing a release/version tag;
* deleting or moving an existing tag;
* publishing a release manually;
* merging a PR when the user has not already requested the merge;
* bypassing branch protection;
* force-pushing shared branches;
* rewriting published release history.

The Agent may prepare commands, validate the repository, or prepare a release
candidate without additional authorization, but must not cross these publication
boundaries implicitly.

If release validation fails:

1. Stop the release process.
2. Do not create or push the version tag.
3. Fix the failure on an appropriate task branch.
4. Commit and integrate the fix through the normal workflow.
5. Re-run release validation.
6. Only then proceed with tagging.

Never solve a failed release by weakening or removing a validation gate unless
that validation itself is demonstrably incorrect and changing it is part of the
requested work.

---

## 9. Hotfixes

Urgent production fixes should branch from the current production `main`:

```bash
git switch main
git fetch origin --prune
git pull --ff-only origin main
git switch -c hotfix/<description>
```

Apply, test, commit, and push the hotfix:

```bash
git push -u origin hotfix/<description>
```

Then use a PR:

```text
hotfix/* → main
```

After merging into `main`, propagate the fix back into `dev` through the
repository's normal merge/PR process so development history does not lose the
production fix.

If the hotfix requires a release, follow the complete Release Workflow after
the merge.

---

## 10. Forbidden Shortcuts

Unless explicitly requested, the Agent must not use shortcuts such as:

```bash
git push origin dev:main
git push origin HEAD:main
git push --force
git push --tags
git tag -f <version>
git push --force origin <version>
```

The Agent must not:

* tag uncommitted work;
* tag before release validation;
* tag `dev` when `main` is the release branch;
* silently overwrite an existing version tag;
* bypass a PR merely because direct push is technically possible;
* combine branch promotion, tagging, and release publication into an opaque
  command chain that prevents individual verification steps.

Release operations should remain explicit, observable, and independently
verifiable.
