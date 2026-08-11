# Development Conventions & Quality Standards

## 1. Coding & Naming Standards

### 1.1 Rust (`src/core/`)
- **Naming**: `snake_case` for functions/variables/modules, `PascalCase` for structs/enums/traits, `SCREAMING_SNAKE_CASE` for constants.
- **Safety**: No `panic!`, `unwrap()`, or `expect()` inside real-time DSP audio loops. Explicit error propagation via `Result<T, E>`.
- **Optimization**: Hot loops (`stft.rs`, `master_peak.rs`, `analysis.rs`) must use branchless math and pre-computed lookup tables where possible.
- **Linter & Formatting**: Zero warnings allowed under `cargo clippy -- -D warnings`. Code must pass `cargo fmt --check`.

### 1.2 C# / WinUI 3 (`src/ui/`)
- **Naming**: `PascalCase` for types/methods/properties, `camelCase` for local variables/parameters, `_camelCase` for private fields.
- **Zero GC Allocations per Render Tick**:
  - NEVER allocate objects (`new`), arrays, delegates, or strings inside the
    `CanvasControl.Draw` callback or other hot render callbacks.
  - Prefer resources owned by the active renderer and validate allocation claims
    against the current implementation; do not copy historical buffer type names
    into new documentation.
- **Dirty Checks**: Perform explicit property dirty checks on XAML and renderer elements before invoking redraws or GPU buffer updates.
- **UI String Throttling**: Throttle UI text string formatting (e.g., status labels, Hz indicators) to $\le 10\text{ Hz}$ to prevent UI thread overhead.

## 2. Agent Operations & Context Governance

- **Mandatory Notification on Context Changes**: Any required change, update, or proposal affecting project context (including files in `.agents/context/`, `.agents/rules/`, `.agents/state/`, or specification docs) **must always be explicitly reported to the user**, even when operating in an "always proceed", auto-approve, non-interactive, or similar continuous execution mode.

## 3. Product Configuration and Distribution Projections

- **Canonical metadata**: Official four-part version, package identity,
  publisher, display name, application ID, branding color, and Win32 manifest
  identity are defined in `build/Product.props`.
- **Validated projections**: `Package.appxmanifest`, Cargo semantic version,
  README badge, changelog, and Win32 manifest remain explicit formats but must
  pass `scripts/Test-ProductConfiguration.ps1`.
- **Generated branding**: Files under `src/ui/Assets/` are generated from
  `docs/public/Echo-Logo-Large.png` and `build/branding.json`. Change the source
  or recipe, run `scripts/Generate-BrandAssets.ps1`, and verify with `-Check`;
  do not hand-edit individual scale or target-size projections.
- **Common build entrypoint**: Local and CI distribution builds use
  `scripts/Build-Distributions.ps1`; direct publish commands are diagnostic
  only and are not distribution acceptance evidence.
