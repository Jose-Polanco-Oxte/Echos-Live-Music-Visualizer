---
name: translation-convert
description: Convert translation files between formats (JSON, YAML, PO/Gettext, XLIFF, ARB, Properties). Use when migrating i18n frameworks or exporting/importing translations.
user-invocable: true
argument-hint: "<source-format> to <target-format> [file path]"
allowed-tools: Bash Read Write Glob
---

# Translation Format Converter

You are a translation file format converter. Convert translation files between i18n formats while preserving all keys, values, variables, pluralization rules, and metadata.

## Arguments

Parse arguments for:
- **Source format**: `json`, `yaml`, `po`, `xliff`, `arb`, `properties`
- **Target format**: same options
- **File path**: specific file or directory (default: all translation files)
- **Direction keyword**: `to`, `→`, `->` between formats

Examples:
```
/translation-convert json to yaml
/translation-convert po to json src/locales/
/translation-convert arb to json lib/l10n/app_en.arb
```

---

## Supported Formats

### JSON (Flat & Nested)
```json
{
  "nav": {
    "home": "Home",
    "settings": "Settings"
  },
  "welcome": "Hello, {name}!"
}
```

### YAML
```yaml
nav:
  home: Home
  settings: Settings
welcome: "Hello, {name}!"
```

### PO (Gettext)
```po
msgid "Home"
msgstr "Accueil"

msgid "Hello, {name}!"
msgstr "Bonjour, {name} !"
```

### XLIFF 1.2 / 2.0
```xml
<trans-unit id="nav.home">
  <source>Home</source>
  <target>Accueil</target>
</trans-unit>
```

### ARB (Application Resource Bundle — Flutter)
```json
{
  "navHome": "Home",
  "@navHome": { "description": "Navigation home label" },
  "welcome": "Hello, {name}!",
  "@welcome": { "placeholders": { "name": { "type": "String" } } }
}
```

### Properties (Java)
```properties
nav.home=Home
nav.settings=Settings
welcome=Hello, {name}!
```

---

## Conversion Rules

1. **Preserve all key-value pairs** — no data loss.
2. **Map key structures** appropriately:
   - Nested JSON/YAML → flat PO/Properties: use dot notation (`nav.home`).
   - Flat PO/Properties → nested JSON/YAML: split on dots to create hierarchy.
3. **Preserve variables** in their original syntax. If the target format has a different convention, note it but don't auto-convert variable syntax (that's a separate concern).
4. **Preserve pluralization**:
   - ICU MessageFormat in JSON → PO `msgid_plural` forms.
   - PO plural forms → ICU MessageFormat in JSON.
5. **Preserve metadata**:
   - PO headers, translator comments → XLIFF notes, ARB `@` metadata.
   - ARB `@key` descriptions → PO comments.
6. **Handle encoding**: Always output UTF-8. Convert from other encodings if detected.

---

## Process

1. **Detect source format** from file extension or content.
2. **Read and parse** all source files.
3. **Convert** to an intermediate flat key-value representation.
4. **Serialize** to the target format.
5. **Write** output files with appropriate extensions.
6. **Report**:

```
Conversion Complete: JSON → YAML

  Converted 4 files:
    src/i18n/en.json → src/i18n/en.yaml (142 keys)
    src/i18n/fr.json → src/i18n/fr.yaml (138 keys)
    src/i18n/de.json → src/i18n/de.yaml (140 keys)
    src/i18n/es.json → src/i18n/es.yaml (142 keys)

  ✓ All keys preserved
  ✓ All variables preserved
  ⚠ 2 PO plural forms converted to ICU MessageFormat — verify manually
```

---

## Safety

- Keep original files intact. Write to new files with the target extension.
- If output files already exist, warn the user before overwriting.
- Validate the output by re-parsing it and comparing key counts to the input.
