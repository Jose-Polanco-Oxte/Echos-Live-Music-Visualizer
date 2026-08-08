# Contribuir a Echo Visualizer

¡Gracias por tu interés en contribuir a Echo Visualizer! Este proyecto está estructurado como una aplicación de escritorio nativa para Windows con separación estricta entre el motor DSP en Rust (`src/core/`) y la interfaz de usuario WinUI 3 en C# (`src/ui/`).

---

## 🛠️ Configuración del Entorno de Desarrollo

### Requisitos Previos
1. **Windows 10 (1809+) o Windows 11** (x64 / ARM64).
2. **Visual Studio 2022 / 2026** con la carga de trabajo *Desarrollo de escritorio con .NET*.
3. **.NET 8 SDK** (definido en `global.json`).
4. **Toolchain de Rust (Stable)** con target `x86_64-pc-windows-msvc` (y opcionalmente `aarch64-pc-windows-msvc`).

---

## 🚀 Flujo de Trabajo y Ramas

1. Crea una rama descriptiva a partir de `dev`:
   ```bash
   git checkout -b feature/mi-nueva-funcionalidad
   ```
2. Realiza cambios enfocados y atómicos.
3. Ejecuta la suite de pruebas unitarias relevante antes de enviar un Pull Request:
   ```powershell
   # Pruebas de Rust Core
   cargo test --manifest-path src/core/Cargo.toml

   # Pruebas de C# UI & FFI
   dotnet test tests/EchoVisualizer.Tests/EchoVisualizer.Tests.csproj -c Release -p:Platform=x64
   ```
4. Abre un Pull Request dirigido a la rama `dev`.

---

## 🧹 Higiene del Repositorio

- **Archivos generados**: No commitees binarios compilados (`.dll`, `.exe`, `.msix`), carpetas de salida (`bin/`, `obj/`, `artifacts/`, `target/`), o archivos temporales del IDE (`.vs/`).
- **Secretos y Certificados**: Nunca almacenes claves privadas (`.pfx`), certificados de firma local (`.cer`), o tokens en el repositorio. Los workflows de CI/CD utilizan GitHub Actions Secrets de forma opcional.
- **Trazabilidad**: Si modificas algoritmos DSP o parámetros de escalado espectral, actualiza la documentación correspondiente en `docs/public/spec/` y añade la trazabilidad necesaria.

---

## 🏗️ Perfiles de Compilación Local

- **Publicación Unpackaged (GitHub Releases)**:
  ```powershell
  dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForGitHub=true
  ```
- **Empaquetado MSIX (Microsoft Store)**:
  ```powershell
  dotnet publish src/ui/EchoVisualizer.csproj -c Release -r win-x64 -p:BuildingForStore=true -p:Platform=x64
  ```
