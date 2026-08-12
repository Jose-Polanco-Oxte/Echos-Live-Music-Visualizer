---
trigger: always_on
---

# Testing and Validation Rules

## Required validation by change type

- Product Rust/C# changes require the relevant unit, FFI and integration tests
  before completion.
- Agent, documentation, rule, skill or script changes require targeted contract
  validation, PowerShell/Python parsing where applicable, local-link/reference
  checks and `git diff --check`.
- A plan may require both categories; the active plan is authoritative about
  the final gate.
- A skipped check is recorded as `SKIPPED` with its reason and is never reported
  as a pass.

## Project commands

From the repository root, use the quality gate when its prerequisites are
available:

```powershell
.\.agents\tools\scripts\Invoke-QualityGate.ps1 -Configuration Debug
```

Targeted Rust validation:

```powershell
cargo fmt --manifest-path src\core\Cargo.toml -- --check
cargo clippy --manifest-path src\core\Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path src\core\Cargo.toml
```

Targeted .NET validation:

```powershell
dotnet test tests\EchoVisualizer.Tests\EchoVisualizer.Tests.csproj --configuration Debug --no-restore -p:Platform=x64
```

The repository quality-gate script restores and builds the explicit UI and test
projects rather than the aggregate solution, because the solution also
contains versioned skill fixtures that are not product projects. Do not add
`--no-restore` unless restore has already been validated for the current
dependency state.

## Agent-contract validation

For `.agents/` changes, run the architecture validator and inspect:

- required stable paths exist;
- local/generated paths remain ignored;
- active references resolve to existing files;
- role definitions have valid frontmatter and scope;
- zero, single and multiple role selection behave correctly;
- task-local role context can run without a catalog file;
- `AGENTS.md` is not discovered as a role;
- PowerShell scripts parse successfully.

## Environment limits

Full runtime validation may require a physical active WASAPI device, GPU and
Windows UI environment. Offline DSP benchmarks do not prove hardware, GPU,
endurance or real audio acceptance. Record those limitations explicitly.
