---
name: translation-add-language
description: Add a new target language to the project. Creates the translation file and populates it with translations. Use when the user wants to support a new language/locale.
user-invocable: true
argument-hint: "<language code or name> [--empty]"
allowed-tools: Read Write Edit Glob
---

# Add Translation Language

You are a language onboarding assistant. Add a new target language to the project by creating the translation file, translating all keys from the source, and updating the config.

## Arguments

- **Language** (required): A BCP-47 code (`fr`, `de`, `ja`, `pt-BR`, `zh-Hans`) or full name (`French`, `German`, `Japanese`, `Brazilian Portuguese`, `Simplified Chinese`).
- **`--empty`**: Create the file with empty values (for human translators to fill in) instead of AI-translating.

---

## Step 1: Validate Language

1. Parse the language argument. If a full name was given, resolve to its BCP-47 code.
2. Validate the code is a recognized BCP-47 language tag.
3. Check if this language already exists in the project:
   - If a translation file already exists for this language, inform the user and suggest `/translation-sync` instead.

Common language codes for reference:
```
ar (Arabic), bg (Bulgarian), bn (Bengali), ca (Catalan), cs (Czech),
da (Danish), de (German), el (Greek), en (English), es (Spanish),
et (Estonian), fa (Persian), fi (Finnish), fr (French), ga (Irish),
he (Hebrew), hi (Hindi), hr (Croatian), hu (Hungarian), id (Indonesian),
it (Italian), ja (Japanese), ko (Korean), lt (Lithuanian), lv (Latvian),
ms (Malay), nl (Dutch), no (Norwegian), pl (Polish), pt (Portuguese),
pt-BR (Brazilian Portuguese), ro (Romanian), ru (Russian), sk (Slovak),
sl (Slovenian), sr (Serbian), sv (Swedish), th (Thai), tr (Turkish),
uk (Ukrainian), vi (Vietnamese), zh-Hans (Simplified Chinese),
zh-Hant (Traditional Chinese)
```

---

## Step 2: Determine File Location

Based on existing translation files, determine where the new file should be created:

- If files follow `{dir}/{lang}.json` pattern → create `{dir}/{newLang}.json`
- If files follow `{dir}/{lang}/messages.json` pattern → create `{dir}/{newLang}/messages.json`
- If using module pattern `{dir}/{module}/{lang}.json` → create one file per module
- Match the format of existing files (JSON, YAML, PO, etc.)

Report:
```
Adding: Japanese (ja)
File: src/i18n/ja.json
Source: src/i18n/en.json (142 keys)
```

---

## Step 3: Create Translation File

### If `--empty`:
Create the file with all source keys but empty string values:
```json
{
  "nav": {
    "home": "",
    "settings": ""
  },
  "welcome": ""
}
```

### If not `--empty` (default):
Translate all keys from the source language file into the new target language. Follow the same translation rules as `/translation-sync`:
- Natural, fluent translation
- Preserve all variables
- Respect `customInstructions` from config
- Match formality from style guide if it exists (`.translation-guide.md`)

---

## Step 4: Update Config

If `.translation-sync.json` exists, add the new language to `targetLanguages`:

```json
{
  "targetLanguages": ["fr", "de", "es", "ja"]  // ← added "ja"
}
```

If module-based, add the file pattern for the new language.

---

## Step 5: Report

```
Language Added: Japanese (ja)
════════════════════════════

  Created: src/i18n/ja.json
  Keys: 142 translated
  Variables: ✓ All preserved
  Config: Updated .translation-sync.json

  Next steps:
  - Review translations: /translation-review ja
  - Check health: /translation-health ja
  - Generate style guide: /translation-guide --generate
```
