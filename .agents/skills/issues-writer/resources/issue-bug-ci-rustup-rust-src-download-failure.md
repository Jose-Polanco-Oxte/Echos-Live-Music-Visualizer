# Bug: Fallo intermitente de CI al descargar el componente `rust-src` de rustup

---

## Issue Metadata
* **Type:** Bug
* **Priority:** P1 - High
* **Target Component:** CI/CD Pipeline (`ci.yml`, `rust-toolchain.toml`)
* **Affected Workflow:** "Quality Gate (CI)" - step "Run Quality Gates and Validate Distribution Profiles"
* **Blocker:** Si, bloquea la release `v0.2.0.19` (PR #9 `dev -> main`)
* **Target Path:** .agents/skills/issues-writer/resources/issue-bug-ci-rustup-rust-src-download-failure.md

---

## Description

El pipeline de calidad en GitHub Actions falla de forma intermitente durante el
paso `dotnet test` a causa de que rustup no consigue descargar/instalar el
componente `rust-src` en el runner de `windows-latest`. El fallo NO está en el
código: los 77 tests de Rust y los 40 tests de .NET pasan antes del error. La
misma secuencia de comandos pasa localmente en ambas arquitecturas.

El paso que falla invoca `cargo build` a traves del target MSBuild
`BuildEchoCoreForFfiTests` (ver `EchoVisualizer.Tests.csproj`). Al ejecutar
cargo, rustup intenta sincronizar la toolchain y descargar `rust-src`, y esa
descarga falla con distintos errores transitorios segun el runner.

## Pasos para reproducir

1. Abrir o actualizar un PR contra `main` (p.ej. Release v0.2.0.19, PR #9).
2. El workflow "Quality Gate (CI)" ejecuta `Build-Distributions.ps1 -Profile Both`.
3. Observar el paso "Run Quality Gates and Validate Distribution Profiles":
   - `cargo fmt --check`, `cargo clippy` y `cargo test` pasan (77 tests OK).
   - `dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Release -p:Platform=x64` falla.
4. El log muestra un error de rustup al descargar `rust-src`.

### Log de fallo (muestras reales)

Primer fallo (descarga corrupta):

```text
info: downloading component rust-src
info: rolling back changes
EXEC : error : failed to extract package: lzma data error
    error: could not compile `quote` (build script)
```

Segundo fallo (conflicto de instalacion):

```text
EXEC : error : failed to install component: 'rust-src', detected conflict:
'lib\rustlib\src\rust\library\.cargo\config.toml'
```

Tercer fallo (rename fallido de descarga):

```text
EXEC : error : component download failed for rust-src: could not rename
'downloaded' file from 'C:\Users\runneradmin\.rustup\downloads\...\....partial'
to 'C:\Users\runneradmin\.rustup\downloads\...\...': The system cannot find
the file specified. (os error 2)
```

Linea final comun:

```text
tests/EchoVisualizer.Tests.csproj(51,5): error MSB3073: The command
""C:\Users\runneradmin\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe"
build --manifest-path "...\src\core\Cargo.toml" --release --target
x86_64-pc-windows-msvc" exited with code 101.
```

## Resultado esperado

El workflow "Quality Gate (CI)" completa sin fallos:
`cargo fmt`, `cargo clippy`, `cargo test` (77 tests) y `dotnet test` (40 tests)
terminan correctamente, y el PR queda `mergeable` y con checks en verde.

## Resultado actual

El workflow falla de forma intermitente en `dotnet test` por un error de red /
instalacion de rustup (`rust-src`), independiente del cambio de codigo. Se
observa en multiples runs consecutivos del mismo HEAD:

- Run `31334707547` (push a dev) y sus re-ejecuciones.
- Run `31334709612` (pull_request) y sus re-ejecuciones.
- Historial del workflow muestra que CI pasaba el 2026-08-08 (main) y falla el dia 2026-08-09 en dev.

## Entorno

- OS (runner): `windows-latest` (GitHub Actions).
- Toolchain declarada: `rust-toolchain.toml` con `channel = "1.97.1"`,
  `profile = "minimal"`, componentes `rustfmt`, `clippy` y targets
  `x86_64-pc-windows-msvc` y `aarch64-pc-windows-msvc`.
- CI setup: `dtolnay/rust-toolchain@stable` con los mismos targets/components.
- Reproduccion local: OK (77 Rust + 40 .NET, fmt/clippy en limpio, distribuciones
  x64 y ARM64 construidas y validadas).

---

## Causa raiz probada

No es el codigo del repositorio. Es un fallo transitorio del entorno de GitHub
Actions al descargar/instalar el componente `rust-src` de rustup durante la
invocacion de cargo disparada por `dotnet test` (MSBuild target
`BuildEchoCoreForFfiTests`). Los errores `lzma data error`, `detected conflict`
y `could not rename ... os error 2` son manifestaciones distintas del mismo
problema de descarga/extraccion en el runner.

---

## Soluciones potenciales (a validar)

- **Opcion A (recomendada):** Pre-instalar la toolchain y el componente
  `rust-src` de forma explicita y determinista en `ci.yml` (mismo canal
  `1.97.1`, profile minimal y `--component rust-src`), para que rustup no
  descargue componentes perezosamente durante `dotnet test`.
- **Opcion B:** Alinear `ci.yml` con el canal de `rust-toolchain.toml`
  (`dtolnay/rust-toolchain@1.97.1` en lugar de `@stable`) y anadir cache de
  `~/.rustup` / `Cargo` para evitar re-descargas entre runners.
- **Opcion C:** Anadir reintento (retry) al paso de calidad o ejecutar la
  descarga de componentes en un paso separado con `continue-on-error` / retry.
- **Opcion D:** Consumir el componente `rust-src` ya presente en la imagen del
  runner o pinar una versión de la imagen del runner.

## Definition of Done (DoD)

- [ ] Tres ejecuciones consecutivas del workflow "Quality Gate (CI)" pasan sin
      errores de `rust-src` en `dotnet test`.
- [ ] El PR de release queda `mergeable` con checks en verde.
- [ ] `cargo test` (77 tests) y `dotnet test` (40 tests) pasan en CI.
- [ ] No se introduce debilitamiento de pruebas ni flags de skip en la
      validacion final de la release.
- [ ] Los cambios de CI quedan documentados en `CHANGELOG.md` y, si aplica,
      una nota en `.agents/state/handoffs/intermittent-rust-ffi-test-failure-in-ci.md`.
