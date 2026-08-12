---
name: translation-health
description: Check translation coverage, find dead keys, detect missing translations, and report project i18n health. Use when the user wants to audit or check the status of their translation files.
user-invocable: true
argument-hint: "[--deep] [language]"
allowed-tools: Bash Read Grep Glob
---

# Translation Health Check

You are a translation health auditor. Analyze the project's translation files and report on coverage, consistency, and issues — without modifying any files.

## Arguments

- **`--deep`** or **`deep`**: Also scan source code for dead keys and hardcoded strings (slower but thorough).
- **Language filter**: `fr`, `German`, etc. — focus on a specific language.
- No arguments: standard health check across all languages.

---

## Step 1: Load Config & Discover Files

1. Check for `.translation-sync.json` or `.claude/translation-sync.json`.
2. If no config, auto-discover translation files using the same patterns as `/translation-sync`.
3. Read the source language file and all target language files.
4. Flatten all files to key sets.

---

## Step 2: Coverage Analysis

For each target language, compute:

| Metric | Calculation |
|--------|-------------|
| **Total keys** | Number of keys in source |
| **Translated** | Keys present in target with non-empty, non-TODO values |
| **Missing** | Keys in source but not in target |
| **Extra** | Keys in target but not in source (orphaned) |
| **TODO markers** | Keys with values starting with `TODO:` |
| **Empty values** | Keys present but with empty string values |
| **Coverage %** | `(translated / total) * 100` |

---

## Step 3: Variable Integrity Check

For every translated key, extract variables from both source and target:
- Compare variable sets.
- Flag any key where the target is missing a variable from the source.
- Flag any key where the target has a variable NOT in the source (likely a typo).

---

## Step 3b: Glossary Compliance (if a glossary is configured)

If `glossary` is set in config (inline or external file), check every translated key for glossary integrity:

- For each key, find glossary terms (`doNotTranslate` and `terms`) that appear in the SOURCE string.
- For `doNotTranslate` terms: verify the same term appears verbatim in the target. Skip occurrences inside `{variables}` or `<tags>`.
- For `terms[lang]` mappings: verify the mapped translation appears in the target (case-insensitive, word-boundary).
- Aggregate by language. Report:
  - Total glossary checks per language
  - Number of violations
  - Sample of up to 5 violating keys with expected vs actual

A glossary violation is classified as a **warning** in the severity table — high enough to fix, not a blocker.

---

## Step 4: Structural Consistency

Check for:
- **Key ordering mismatch**: Are target file keys in the same order as source?
- **Nesting mismatch**: Does target have flat keys where source has nested (or vice versa)?
- **Format differences**: JSON vs YAML inconsistencies across language files.
- **Encoding issues**: Non-UTF-8 files, BOM markers.
- **Trailing whitespace or newline differences**.

---

## Step 5: Deep Analysis (if `--deep`)

If the user requested deep analysis, scan the source code:

### 5a: Dead Key Detection

Production codebases routinely build translation keys at runtime — error-code maps, badge labels, API status mappers — so naive grep-based dead-key detection produces high false-positive rates. Detection MUST be aware of dynamic key families before classifying anything as dead.

**Step 1 — Load exemption rules from config:**
- `dynamicKeyPrefixes: string[]` — any source key starting with one of these prefixes is exempt (e.g., `"Api."` exempts `Api.users`, `Api.orders.create`, etc.).
- `dynamicKeyPatterns: string[]` — glob patterns for advanced cases (e.g., `"Errors.*.message"`, `"toast.{success,error,warning}.*"`).

Both fields are optional. The two lists are unioned.

**Step 2 — Auto-infer dynamic families from source code:**

Grep the codebase for template-literal and concatenation patterns that build keys at runtime. Look for these forms:

| Pattern | Example | Inferred prefix |
|---------|---------|----------------|
| Template literal in t-call | `` t(`Api.${endpoint}`) `` | `Api.` |
| Template literal, nested | `` $t(`Badge.${status}.label`) `` | `Badge.` |
| String concatenation | `t('Errors.' + code)` | `Errors.` |
| Computed object access | `messages['toast.' + kind]` | `toast.` |

Recommended grep patterns (run across `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`, `.svelte`, `.dart`, `.kt`, `.swift`, `.py`, `.rb`, `.php`):
- ``[\$\.]?t\(\s*[`'"]([\w.]+\.)\$?\{`` — template literal with literal prefix segment
- `[\$\.]?t\(\s*['"]([\w.]+\.)['"\s]*\+` — concatenation with literal prefix
- `formatMessage\(\s*\{\s*id:\s*[`'"]([\w.]+\.)\$?\{` — React Intl pattern

For each match, extract the static prefix segment (everything up to and including the last `.` before the dynamic part) and record the file:line where it was found. These become **inferred prefixes**.

If a pattern has no static prefix (e.g., `` t(`${kind}.error`) ``), do NOT infer anything — note it as "ambiguous dynamic key construction" and surface it in the report so the user can decide.

**Step 3 — Collect and classify:**

For each key in the source translation file, classify in this order:
1. **Exempt (config)** — matches `dynamicKeyPrefixes` or `dynamicKeyPatterns`.
2. **Exempt (inferred)** — matches an auto-inferred prefix.
3. **Live** — found via Grep in source code, matched as `t('key')`, `$t('key')`, `i18n.t('key')`, `translate('key')`, `messages.key`, `I18n.t(:key)`, `useTranslation()...t('key')`, `formatMessage({id: 'key'})`, etc.
4. **Dead** — none of the above.

Only keys in category 4 are reported as dead.

**Step 4 — Report transparency:**

Always report which keys were suppressed and why, so users can audit and tighten rules. Group exempt keys by family rather than listing them individually.

### 5b: Hardcoded String Detection
1. Search source code for user-visible strings that should probably be translated:
   - String literals inside JSX/HTML text nodes
   - `placeholder="..."`, `title="..."`, `aria-label="..."` attributes
   - `alert("...")`, `confirm("...")` calls
   - String arguments to toast/notification functions
2. Exclude: log messages, error codes, CSS classes, import paths, test files, comments.
3. Report as suggestions, not errors.

---

## Step 6: Report

Output a structured health report:

```
Translation Health Report
═════════════════════════

Source: src/i18n/en.json (142 keys)

Coverage Summary:
  Language        Coverage    Missing   Extra   TODO   Issues
  ─────────────────────────────────────────────────────────
  French (fr)     97.2%       4         0       2      1 variable mismatch
  German (de)     95.1%       7         3       0      0
  Spanish (es)    100%        0         0       0      0
  Japanese (ja)   88.0%       17        0       5      2 variable mismatches

Variable Mismatches:
  ⚠ de.json → "welcome_user": missing {name} variable
  ⚠ ja.json → "file_count": missing {count} variable
  ⚠ ja.json → "upload_status": has extra {size} not in source

Extra Keys (not in source — consider removing):
  de.json → "old_feature_title", "deprecated_label", "legacy_help"

TODO Markers (incomplete translations):
  fr.json → "payment_error", "subscription_renewal"
  ja.json → "nav_settings", "nav_profile", "nav_billing", "nav_help", "nav_logout"

Glossary Compliance (if configured):
  fr.json — 47 checks, 2 violations:
    ⚠ "inbox_header"  → expected "Boîte de réception", got "Boîte de courrier"
    ⚠ "premium_cta"   → expected "Premium" verbatim (do-not-translate), got "Premium plan" → "Plan Premium"
  de.json — 47 checks, 0 violations
  es.json — 47 checks, 0 violations
```

If `--deep` was used, append:

```
Dynamic Key Families (excluded from dead-key check):
  Api.*     — 47 keys (configured via dynamicKeyPrefixes)
  Badge.*   — 23 keys (configured via dynamicKeyPrefixes)
  Errors.*  — 32 keys (inferred from src/utils/errors.ts:42)
  toast.*   — 18 keys (inferred from src/components/Toast.tsx:15)

Ambiguous dynamic constructions (review manually):
  src/i18n/helpers.ts:88 → t(`${kind}.error`)  — no static prefix to infer

Dead Keys (in translation files but not referenced in code):
  ⚠ "onboarding_step_3" — not found in any source file
  ⚠ "beta_banner" — not found in any source file

Hardcoded Strings (consider extracting to translation files):
  src/components/Header.tsx:24 → "Welcome back"
  src/components/ErrorBoundary.tsx:15 → "Something went wrong"
  src/pages/Settings.vue:42 → "Save Changes"
```

---

## Severity Classification

Classify each finding:
- **Error** (must fix): Variable mismatches, missing keys in languages marked as required.
- **Warning** (should fix): TODO markers, extra/orphaned keys, dead keys.
- **Info** (nice to fix): Key ordering differences, hardcoded string suggestions.

End the report with a one-line summary:
```
Health: 3 errors, 8 warnings, 5 info — run /translation-sync to fix missing translations
```
