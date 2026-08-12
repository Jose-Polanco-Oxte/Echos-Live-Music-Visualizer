---
name: translation-sync
description: Synchronize translation files across languages. Use when the user wants to sync, translate, or update i18n/l10n files. Detects changed keys, translates only the delta, preserves variables and structure.
user-invocable: true
argument-hint: "[languages] [options: dry-run, formal/informal, staged-only]"
allowed-tools: Bash Read Write Edit Grep Glob Agent
---

# Translation Sync

You are a translation synchronization engine. Your job is to keep a project's translation files in sync with the source language file — translating only what changed, preserving everything else.

## Arguments

The user may provide arguments after `/translation-sync`. Parse them for:
- **Language filter**: `only French and German`, `fr, de`, `just Spanish`
- **Tone**: `formal`, `informal`, `casual`
- **Dry-run**: `dry-run`, `preview`, `--dry-run`
- **Git scope**: `staged only`, `staged changes`, `last commit`, `last 3 commits`
- **Source file override**: a file path ending in `.json`, `.yaml`, `.yml`, `.po`, `.xliff`, `.arb`, `.properties`

If no arguments are given, sync all configured languages with default settings.

---

## Step 1: Load and Validate Configuration

Check for a project config file in this order:
1. `.translation-sync.json` in the project root
2. `.claude/translation-sync.json`

If a config file exists, read and parse it. The expected shape:
```json
{
  "sourceLanguage": "en",
  "sourceFile": "src/i18n/en.json",
  "targetLanguages": ["fr", "de", "es", "ja", "zh"],
  "format": "json",
  "keySort": "asc",
  "variablePatterns": "auto",
  "customInstructions": "",
  "tone": "formal",
  "glossary": {
    "doNotTranslate": [],
    "terms": {}
  },
  "dynamicKeyPrefixes": [],
  "dynamicKeyPatterns": [],
  "modules": {}
}
```

### 1a: Validate the Config

Silent ignore of typos or wrong types is the single biggest cause of "the skill ignored my setting" confusion. Always validate and surface findings at the START of the run, before any translation work.

**Known top-level fields** (the canonical schema):

| Field | Type | Required | Allowed values / notes |
|-------|------|----------|------------------------|
| `sourceLanguage` | string | yes | BCP-47 code (e.g., `en`, `pt-BR`) |
| `sourceFile` | string | no (auto-detected) | Path relative to project root |
| `targetLanguages` | string[] | no | BCP-47 codes; if omitted/empty, runs language discovery |
| `format` | string | no | One of: `json`, `yaml`, `yml`, `po`, `xliff`, `arb`, `properties`, `auto` |
| `keySort` | string | no | One of: `asc`, `desc`, `none` |
| `variablePatterns` | string \| string[] | no | `"auto"` or explicit pattern list |
| `customInstructions` | string | no | Free-form translation guidance |
| `tone` | string \| object | no | `"formal"` / `"informal"` / `"neutral"`, or per-language object: `{ "default": "formal", "es": "informal" }` |
| `glossary` | object \| string | no | Inline glossary object (`doNotTranslate`, `terms`) OR a path string to an external glossary file |
| `dynamicKeyPrefixes` | string[] | no | See `/translation-health` for usage |
| `dynamicKeyPatterns` | string[] | no | Glob patterns; see `/translation-health` |
| `modules` | object | no | Module-based file patterns with `{lang}` placeholder |

**Validation behavior:**
- **Unknown top-level field**: log a WARNING. If a known field is within edit-distance 2, suggest it (e.g., `Unknown field "languageNames" — did you mean "targetLanguages"? Ignoring.`). Continue.
- **Wrong type on a required field** (`sourceLanguage`): ABORT with a clear error and the expected type.
- **Wrong type on an optional field**: log a WARNING and fall back to the default.
- **Invalid enum value** (`format`, `keySort`): log a WARNING, fall back to `auto` / `asc`.
- **Empty / null config file**: log a WARNING and treat as "no config" (proceed to discovery).

Print a single grouped block at the start of the run, e.g.:
```
Config validation:
  ⚠ Unknown field "languageNames" — did you mean "targetLanguages"? Ignoring.
  ⚠ format: "yml" is valid; "yamll" is not. Falling back to auto-detection.
  ✓ All other fields valid.
```

If there were no findings, do not print this block.

### 1b: Decide What to Do Next

Based on what was found, pick one path:

| State | Action |
|-------|--------|
| No config file | Proceed to **Step 2: Discovery** (full discovery — files, source, targets). Offer to create a config at the end. |
| Config exists, `targetLanguages` is a non-empty array | Skip to **Step 3**. Use the configured languages exactly; do NOT discover new ones. |
| Config exists, `targetLanguages` is missing or `[]` | Run **Step 2** in *language-only mode*: discover existing target files, but use all OTHER fields from config as-is. Log a notice: `No targetLanguages in config — discovered: fr, de, es. Pin these in config to lock the set.` |

### 1c: Resolve the Glossary

The `glossary` field accepts two forms — auto-detect which is in use:

- **Inline object** with `doNotTranslate` and/or `terms` keys → use as-is.
- **String** → treat as a path relative to the project root (or absolute), read the JSON, and use its content as the glossary. If the file is missing or unparseable, log a WARNING and continue with an empty glossary.

The resolved glossary shape:
```json
{
  "doNotTranslate": ["Premium", "Pro", "Acme Corp"],
  "terms": {
    "Inbox":    { "es": "Bandeja de entrada", "fr": "Boîte de réception", "de": "Posteingang" },
    "Settings": { "es": "Configuración",       "fr": "Paramètres",         "de": "Einstellungen" }
  }
}
```

Both sub-fields are optional. If neither is set, glossary enforcement is a no-op.

If the user has not set a glossary at all, skip this step silently — glossary is optional.

---

## Step 2: Discovery

This step runs in two modes:
- **Full discovery** (no config exists): find source file, target files, propose creating a config.
- **Language-only discovery** (config exists but `targetLanguages` is missing/empty): use the configured `sourceFile` and `format`; only auto-detect which target language files exist.

In language-only mode, run substep 1 below ONLY (glob) but scope it to the directory of the configured `sourceFile`. Skip substeps 2–4 — you already have the source from config and don't need to propose a new config. Use the discovered target files as the language list, then continue to **Step 3**.

For full discovery, run all four substeps:

1. Use Glob to find files matching common i18n patterns:
   - `**/{locale,locales,i18n,lang,languages,translations}/**/*.{json,yaml,yml}`
   - `**/{en,fr,de,es,ja,zh,ko,pt,it,ru,ar,hi,nl,sv,pl,tr,th,vi,id,cs,ro,hu,uk,da,fi,no,el,he,bg,hr,sk,sl,lt,lv,et,mt,ga,ca,eu,gl}.{json,yaml,yml}`
   - `**/messages.*.{json,yaml,yml}`
   - `**/*.po`, `**/*.xliff`, `**/*.arb`, `**/*.properties`
   - Exclude: `node_modules`, `dist`, `build`, `.next`, `.nuxt`, `vendor`, `coverage`, `.git`

2. Group the discovered files by directory and identify the source language file (typically `en.json` or the file matching the most common language code).

3. Present findings to the user:
   ```
   Found translation files:
     Source: src/i18n/en.json (English, 142 keys)
     Targets:
       - src/i18n/fr.json (French, 138 keys — 4 missing)
       - src/i18n/de.json (German, 140 keys — 2 missing)
       - src/i18n/es.json (Spanish, 142 keys — up to date)

   Shall I create a .translation-sync.json config file? (Recommended for consistent behavior)
   ```

4. If the user confirms, write the config file. If not, proceed with discovered settings.

---

## Step 3: Read Source

1. Read the source language file entirely.
2. Parse it according to its format (JSON, YAML, PO, etc.).
3. Flatten nested keys using dot notation: `{"nav": {"home": "Home"}}` → `nav.home = "Home"`
4. Count total keys and note the key ordering.

Report: `Source: {file} — {count} keys`

---

## Step 4: Detect Changes (Git-Aware)

If the project is a git repository AND the user hasn't specified `--all` or `--force`:

1. Run `git status` to check if the source file has changes.
2. Determine changed keys using the appropriate strategy:
   - **Default (head-vs-working)**: `git diff HEAD -- {sourceFile}`
   - **Staged only** (if user said "staged"): `git diff --cached -- {sourceFile}`
   - **Last commit**: `git diff HEAD~1 -- {sourceFile}`
   - **Last N commits**: `git diff HEAD~{N} -- {sourceFile}`

3. Parse the diff to extract which keys were added, modified, or removed.
4. Report: `Detected {n} changed keys since last commit`

If not a git repo or user specified `--all`, treat ALL keys as candidates for translation check.

---

## Step 5: Process Each Target Language

For each target language file (filtered by user's language selection if provided):

### Pre: Tone Calibration

Before classifying keys, calibrate the tone for this language. The goal is to catch the case where the config says one register but the existing translations use another — silently picking either side is the wrong default.

**Resolve the configured tone:**
- If `tone` is a string → applies to all languages.
- If `tone` is an object → use `tone[lang]` if set, else `tone.default`, else unset.
- If unset → no expectation from config; skip directly to **5a**.

**Sample existing translations** (only if a target file already has translations):
- Pick up to 10 existing translated strings that are likely to expose register: those containing second-person pronouns (you, vous, du, usted, tu, あなた), imperatives, or polite request patterns.
- If fewer than 5 candidate strings exist, **skip the check** — too little signal to act on.

**Classify the sample** for the language's relevant register dimension:
- German: Sie vs du
- French: vous vs tu
- Spanish: usted vs tú/vos
- Italian: Lei vs tu
- Portuguese: você vs tu
- Russian: вы vs ты
- Japanese: keigo (敬語/丁寧語) vs casual
- Korean: tiered honorifics
- Languages without a T-V or honorific distinction (English, Mandarin, etc.): skip — no actionable conflict.

**Decide the outcome:**
- If ≥ 7/10 sample strings agree AND the agreed register matches `tone` → all good, log a one-liner and proceed.
- If ≥ 7/10 agree AND the agreed register conflicts with `tone` → **conflict detected**.
- If the sample is mixed (no clear majority) → log an advisory ("`{lang}.json` appears mixed-tone") and use the config tone.

**Conflict resolution:**

In interactive runs, ask the user:
```
Tone conflict for es.json:
  Config says: formal
  Existing translations sampled (10): 8/10 use informal "tú"

How should I resolve?
  1) Match existing (informal) — recommended for consistency
  2) Match config (formal) — re-translate inconsistent existing keys, mark with [REVIEW]
  3) Abort — let me edit config first
```

In non-interactive runs (CI, scripted), use the `--tone-conflict` flag (`existing` | `config` | `abort`). Default: **`existing`** — preserve existing tone, log loudly. Never silently reconcile.

The chosen tone for this language is then used as the binding tone in **5d** for any translations produced.

### 5a: Read Target File
Read the existing translation file and flatten its keys.

### 5b: Classify Each Key

For every key in the source file, classify it:

| Classification | Condition | Action |
|---------------|-----------|--------|
| **Reuse** | Key exists in target, source value unchanged (or not in git diff), translation is valid, all variables present | Keep existing translation |
| **Translate** | Key is new, or source value changed, or translation is empty/TODO | Translate |
| **Remove** | Key exists in target but NOT in source | Remove from target |

**"Valid" means**: not empty, not prefixed with `TODO:`, and contains all variables from the source string.

### 5c: Variable Detection

Before translating, identify all variables in each source string. Detect these patterns:
- `{name}` — i18next, React Intl, Java MessageFormat
- `{{name}}` — Angular, Handlebars, Mustache, Laravel
- `${name}` — ES6 template literals, Kotlin
- `%s`, `%d`, `%f` — C-style printf
- `%(name)s` — Python named format
- `%{name}` — Ruby, Elixir Gettext
- `$t(key)` — i18next nested references
- `@:key` — Vue i18n linked messages
- `{0}`, `{1}` — Positional (Java, C#, Flutter)
- `%1$s`, `%2$d` — Android positional printf
- HTML tags: `<b>`, `<a href="...">`, `<br/>`, etc.

Record the set of variables for each key. After translation, verify every variable from the source appears in the translation.

### 5d: Translate

Translate all keys classified as **Translate** for this language. Follow these rules precisely:

**Translation Rules:**
1. Translate to natural, fluent {target language} — not word-for-word.
2. Preserve ALL variables exactly as they appear in the source. Do not translate variable names inside `{}`, `${}`, `%s`, etc.
3. Variables may change position to produce natural word order in the target language — this is correct and expected.
4. For positional variables (`%1$s`, `{0}`), ensure they map to the same semantic argument.
5. Preserve HTML tags and their attributes exactly. Only translate the text content between tags.
6. Match the formality level: use the tone resolved in the **Pre: Tone Calibration** step. If no config tone exists and calibration was skipped, match the register of existing translations in the same file.
7. Keep translations concise — UI strings should be similar length to the source when possible.
8. Do NOT translate:
   - Brand names, product names, proper nouns (unless locale convention requires it)
   - Technical identifiers, code references
   - URLs, email addresses
   - Emoji (keep as-is)
   - Any term in `glossary.doNotTranslate` — these MUST appear verbatim in the translation.
9. **Glossary terms are binding.** For each glossary term in `glossary.terms` that appears in the source string, the translation MUST use the exact mapped value for the target language. Example: `glossary.terms.Inbox.es = "Bandeja de entrada"` → every Spanish translation that contains "Inbox" in the source must contain "Bandeja de entrada" in the target. If a term has no mapping for the current target language, fall back to normal translation (or treat as do-not-translate if it also appears in `doNotTranslate`).
10. For pluralization with ICU MessageFormat, generate language-appropriate plural forms.
11. If `customInstructions` exist in the config, follow them as highest-priority guidance — but glossary mappings and do-not-translate terms still take precedence over free-form instructions.

**Prompting guidance**: when sending a batch of strings to translate, include only the glossary entries whose source term actually appears in the batch. Don't bloat the prompt with the full glossary.

### 5e: Assemble Output

1. Start with the reused translations.
2. Merge in the new translations.
3. Remove keys that no longer exist in source.
4. Apply key sorting if configured (default: match source key order).
5. Unflatten dot-notation keys back to nested structure.

### 5f: Output Validation

Before writing, validate every translated string in two passes:

**Variable integrity:**
- Extract variables from the translation.
- Compare against the source string's variable set.
- If ANY variable is missing or altered: flag it, and prepend `TODO:` to that translation.

**Glossary integrity** (only if a glossary is configured):
- For each glossary term that appears in the source string, verify the corresponding requirement in the target:
  - **`doNotTranslate`** terms: the target must contain the same term verbatim (case-sensitive, word-boundary matched). If the term sits inside a `{variable}` or `<tag>` in the source, skip enforcement for that occurrence.
  - **`terms[targetLang]`** mappings: the target must contain the mapped translation (case-insensitive presence check, word-boundary matched).
- On miss: prepend `[GLOSSARY: expected "<expected>" for "<source-term>"]` to the translation, leaving the rest of the translated text intact so the user can review and edit.
- A single key may have BOTH a variable mismatch and a glossary mismatch — surface both prefixes in that order: `TODO: [GLOSSARY: ...] <translation>`.

Report all mismatches in a single grouped block at the end of the per-language pass:
```
fr.json validation:
  ⚠ welcome_user — missing {name} variable (added TODO marker)
  ⚠ inbox_header — glossary expected "Boîte de réception" for "Inbox" (added [GLOSSARY] marker)
```

---

## Step 6: Write or Preview

### Dry-Run Mode
If `dry-run` was specified, do NOT write files. Instead, report:

```
Dry Run Summary for {language}:
  ✓ {n} keys reused (unchanged)
  + {n} keys translated (new/updated)
  − {n} keys removed
  ⚠ {n} variable mismatches (marked TODO)

  Sample translations:
    "welcome_message": "Bienvenue, {name} !" (was: "Welcome, {name}!")
    "items_count": "{count} éléments" (new)
```

### Write Mode

Writes MUST be atomic per-file: a crash, parse failure, or interruption must NEVER leave a translation file half-written or corrupted. Use a write-then-rename pattern so the original file is replaced as a single filesystem operation.

For each target file:

1. **Write to a temporary path**: use the Write tool to write the new content to `<target>.tmp` (e.g., `src/i18n/fr.json.tmp`). If a stale `<target>.tmp` exists from a prior crashed run, overwriting it is fine.
2. **Validate the temp file**: re-read `<target>.tmp` and parse it according to its format (JSON.parse, YAML parse, etc.). If parsing fails, abort this file: delete the `.tmp`, report the error, and move on to the next target — DO NOT touch the original file.
3. **Atomic rename**: replace the original with the temp file as a single operation:
   - **POSIX (Bash)**: `mv -f <target>.tmp <target>`
   - **Windows (PowerShell)**: `Move-Item -Force <target>.tmp <target>`
   Pick the command based on the current platform. The rename is atomic on the same filesystem on all major OSes.
4. **On any failure between steps 1–3**: ensure `<target>.tmp` is removed and the original is untouched. Never leave orphaned `.tmp` files behind on success.

Formatting rules (apply when generating the content in step 1):

1. Preserve the original file's formatting (indentation, trailing newlines).
2. For JSON: use 2-space indentation and a trailing newline.
3. For JSON: locale-specific quotation marks (`„"`, `«»`, `「」`) MUST be Unicode-escaped (`\u201E`, `\u201C`, `\u00AB`, `\u00BB`, etc.) to avoid breaking JSON syntax. The `"` character inside a JSON string value must ALWAYS be escaped as `\"`.
4. For YAML: preserve the existing style.

---

## Step 7: Summary Report

After all files are processed, output a summary:

```
Translation Sync Complete

Source: src/i18n/en.json (142 keys)

  French (fr.json):    ✓ 138 reused  + 4 translated  − 0 removed
  German (de.json):    ✓ 130 reused  + 10 translated  − 2 removed
  Spanish (es.json):   ✓ 142 reused  + 0 translated  − 0 removed
  Japanese (ja.json):  ✓ 135 reused  + 7 translated  − 0 removed

  Total: 4 files synced, 21 translations added, 2 keys removed
  ⚠ 0 variable mismatches
```

If there were any issues (variable mismatches, parse errors, etc.), list them at the end with actionable guidance.

---

## Error Handling

- **File not found**: Report which file is missing and suggest running `/translation-sync` with discovery.
- **Invalid JSON/YAML**: Report the parse error with file path and line number. Do not partially process broken files.
- **Variable mismatch after translation**: Mark the key with `TODO:` prefix, report it, and continue with other keys.
- **Glossary mismatch after translation**: Mark the key with `[GLOSSARY: expected "X" for "Y"]` prefix, report it, and continue. Do NOT block the run — the user reviews the marker and edits.
- **Tone conflict in a target file**: never resolve silently. In interactive runs, prompt; in non-interactive runs, follow `--tone-conflict` flag (default `existing`) and log the decision prominently.
- **Git not available**: Skip change detection, process all keys.
- **Empty source file**: Report and stop — do not overwrite targets with empty content.
- **Write/validation failure on a target**: per Step 6 atomic-write rules, the original file is never touched until the `.tmp` parses cleanly. Delete the orphaned `.tmp`, report which file failed, and continue with the remaining targets. The user can safely re-run `/translation-sync` — already-completed files won't be re-translated thanks to the reuse classification in Step 5b.

---

## Multi-Module Support

If the config has `modules` defined, process each module independently:
- Each module has its own source and target file pattern.
- The `{lang}` placeholder in the path is replaced with the target language code.
- Report results per-module in the summary.

---

## Performance Guidelines

- For files with < 200 keys: process the entire file in one pass.
- For files with 200-1000 keys: process in chunks of ~100 keys, translating each chunk and assembling results.
- For files with > 1000 keys: use the Agent tool to spawn a sub-agent per target language for parallel processing.
- Always process the reuse classification first — most keys in a mature project will be reused, minimizing actual translation work.
