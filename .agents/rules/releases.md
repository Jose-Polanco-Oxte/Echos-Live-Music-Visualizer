---
trigger: model_decision
description: when compile a new version
---

## 1. Purpose and Scope

This policy defines the official release management standards, versioning conventions, metrics, and distribution procedures for the **Echo Live Music Visualizer** project. 

It establishes a deterministic, metric-driven approach to version numbers based on solved errors, added features, and file modification metrics, ensuring full traceability across the Rust DSP core, WinUI 3 C# application, and MSIX packages.

### 1.1 Mandatory Explicit User Authorization

> [!IMPORTANT]
> **Strict User Authorization Requirement:** A release execution (including incrementing release version strings in `Package.appxmanifest` or `Cargo.toml`, generating distributable MSIX bundles via `Build-Distributions.ps1`, creating Git tags `vA.B.C.D`, or publishing release handoffs) **CAN ONLY be performed when explicitly and directly requested by the user**.  
> Release workflows must NEVER be triggered by indirect prompts, implicit context assumptions, automated sub-tasks, or autonomous background decisions.

### 1.2 Distinction Between Release Builds and Development Builds

To prevent premature version bumps and unauthorized package distribution, the project explicitly distinguishes between **Development Builds** and **Official Releases**:

| Criteria | Development Build (Local / Dev) | Official Release (Distributable) |
| :--- | :--- | :--- |
| **Purpose** | Local debugging, feature development, unit testing, and FFI integration. | Official distribution, production deployment, and public installation package. |
| **Version Change** | **No version bump required.** Retains current working baseline version. | **Requires metric-calculated version bump (`A.B.C.D`)** in `Package.appxmanifest` and `Cargo.toml`. |
| **Trigger Authorization** | Autonomous during local development and testing tasks. | **Requires explicit and direct user request.** |
| **Packaging & Signing** | Standard Visual Studio / `dotnet build` / `cargo build` outputs. Local unsigned/debug binaries. | Signed `.msixbundle` generated via `Build-Distributions.ps1`, with SHA-256 verification and checksum record. |
| **Git Governance** | Commits on dedicated working branches or `dev`. | Merged release commit tagged with `vA.B.C.D` and recorded in the local `.agents/state/PROJECT-HANDOFF.md`. |

---

## 2. Version Format ("0.0.0.0")

All releases must strictly adhere to the 4-digit version string format:

$$\text{Format: } \mathbf{MAJOR}.\mathbf{MINOR}.\mathbf{PATCH}.\mathbf{BUILD} \quad (0.0.0.0)$$

### 2.1 Component Definitions

1. **`MAJOR` (Digit 1 - `A`)**: **Architectural & Breaking Changes**
   - Incremented when major structural redesigns, breaking FFI ABI changes (e.g., ABI v1 $\rightarrow$ ABI v2 migration), or major milestone releases occur.
2. **`MINOR` (Digit 2 - `B`)**: **Features Added Metric**
   - Driven directly by the count of new user-facing or technical features implemented and verified.
3. **`PATCH` (Digit 3 - `C`)**: **Errors Solved Metric**
   - Driven directly by the count of resolved bugs, defects, memory leaks, or stability issues fixed.
4. **`BUILD` (Digit 4 - `D`)**: **File Impact & Build Velocity Metric**
   - Driven by the volume of modified files and sequential release build iterations.

---

## 3. Release Metric System & Calculation

To ensure version numbers directly reflect codebase evolution, versions are computed using the following metrics:

### 3.1 Metric Variables
- $F_{\text{added}}$: Total number of completed and verified features added in the release cycle.
- $E_{\text{fixed}}$: Total number of resolved errors, bug fixes, or QA issue closures.
- $M_{\text{files}}$: Total number of unique files modified across the repository in the release diff (`git diff --stat`).
- $B_{\text{seq}}$: Sequential build counter for package iterations.

### 3.2 Metric Calculation Rules

$$\begin{aligned}
\mathbf{MAJOR}_{new} &= \mathbf{MAJOR}_{old} + \Delta \text{Architectural Milestone} \\
\mathbf{MINOR}_{new} &= \mathbf{MINOR}_{old} + F_{\text{added}} \\
\mathbf{PATCH}_{new} &= \mathbf{PATCH}_{old} + E_{\text{fixed}} \\
\mathbf{BUILD}_{new} &= \mathbf{BUILD}_{old} + \max\left(1, \left\lfloor \frac{M_{\text{files}}}{10} \right\rfloor\right)
\end{aligned}$$

#### Metric Details:
- **Features Metric ($\text{MINOR}$)**: Each fully tested feature documented in
  the active project specification and verified with records under
  `docs/public/traceability/` increments $\text{MINOR}$ by $+1$.
- **Errors Solved Metric ($\text{PATCH}$)**: Each resolved defect (tracked in issue logs, QA incident reports, or bug fix commits) increments $\text{PATCH}$ by $+1$.
- **File Impact Metric ($\text{BUILD}$)**: The build number increases based on the number of modified files $M_{\text{files}}$, adding $+1$ base increment plus $+1$ additional unit for every 10 files modified in the release changeset.

---

## 4. Release Trigger Thresholds

### 4.1 Patch Release (`A.B.C+k.D+m`)
- **Trigger**: Solved errors ($E_{\text{fixed}} \ge 1$) without new features.
- **Action**: Increment $\text{PATCH}$ by $E_{\text{fixed}}$ and update $\text{BUILD}$ based on $M_{\text{files}}$.

### 4.2 Minor / Feature Release (`A.B+k.0.D+m`)
- **Trigger**: New features added ($F_{\text{added}} \ge 1$).
- **Action**: Increment $\text{MINOR}$ by $F_{\text{added}}$, reset $\text{PATCH}$ to $0$ (if all known issues are resolved), and update $\text{BUILD}$.

### 4.3 Major Release (`A+1.0.0.D+m`)
- **Trigger**: Major architectural changes or breaking FFI ABI shifts.
- **Action**: Increment $\text{MAJOR}$ by $+1$, reset $\text{MINOR}$ and $\text{PATCH}$ to $0$, and update $\text{BUILD}$.

---

## 5. Artifact Synchronization & Distribution Workflow

When a release version is determined via the metric system:

1. **Packaging Manifest (`src/ui/Package.appxmanifest`)**:
   - Update `<Identity Version="A.B.C.D" />`.
2. **Rust Cargo Manifest (`src/core/Cargo.toml`)**:
   - Sync `version = "A.B.C"` to align with the core engine binary (`EchoCore.dll`).
3. **Automated MSIX Packaging**:
   - Execute `scripts/Build-Distributions.ps1 -Profile Store` to produce and validate the package bundle (e.g., `EchoVisualizer_A.B.C.D_x64.msixbundle`).
4. **Validation Checklist**:
   - Rust formatting: `cargo fmt --check`
   - Rust linter: `cargo clippy -- -D warnings`
   - Rust tests: `cargo test`
   - .NET tests: `dotnet test`
5. **Git Tagging & Handoff**:
   - Tag the release commit in Git: `vA.B.C.D`.
   - Update the local `.agents/state/PROJECT-HANDOFF.md` with the new version
     string, MSIX SHA-256 hash, and release changelog.

---

## 6. Context Governance & Notification

Per `.agents/context/conventions.md`, any modification to release policies or versioning metrics must be explicitly reported to the user.

---

## 7. Microsoft Store Publishing Policy

The Microsoft Store is governed by the same strict user-authorization rules as
release tagging: do not publish, enable rollouts, or submit to the Store unless
the user explicitly requests it. The following rules apply to Store packages:

1. **Store version rule:** The package version must use revision zero
   (`A.B.C.0`), derived from the canonical product version's first three
   components. Never submit a package with a nonzero revision.
2. **Per-architecture packages:** Produce one unsigned, framework-dependent
   `.msix` per runtime identifier (x64 and ARM64). Never submit two
   `.msixbundle`/`.appxbundle` packages applicable to the same device set.
   The submission profile is `scripts/Build-Distributions.ps1 -Profile Store`.
3. **First submission is manual:** The Store Submission API can only update an
   existing app. The first submission must be created in Partner Center with:
   the reserved identity (`Tun4z.EchoVisualizer`), the public privacy-policy
   URL, justification for `runFullTrust` and `microphone`, age rating, listing,
   and testing notes.
4. **Continuous updates:** Use `.github/workflows/store-publish.yml` with
   GitHub Secrets `STORE_APP_ID`, `STORE_CLIENT_ID`, `STORE_CLIENT_SECRET`,
   `STORE_TENANT_ID`, plus the StoreBroker data in `docs/store/` (never commit
   credentials). Prefer `dry_run` before a live submission.
5. **Increasing Store versions:** The Store version must strictly increase
   across submissions. Pass `version_override` with an increased `A.B.C` when
   the derived `A.B.C.0` would repeat the previous submission.
   The canonical guidance is `docs/public/publishing/microsoft-store.md` and
   `docs/store/README.md`.
6. **Store release is independent from GitHub Releases:** Publishing to the
   Store does not create or push a Git tag, and a GitHub release does not submit
   to the Store.
