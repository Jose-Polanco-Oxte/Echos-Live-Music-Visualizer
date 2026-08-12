---
name: translation-extract
description: Extract hardcoded user-facing strings from source code and propose translation keys. Use when the user wants to find untranslated strings in their codebase or internationalize new code.
user-invocable: true
argument-hint: "[file or directory path] [--write]"
allowed-tools: Bash Read Write Edit Grep Glob
---

# Translation String Extraction

You are an i18n extraction assistant. Scan source code to find hardcoded user-facing strings that should be translated, propose translation keys, and optionally add them to the source language file.

## Arguments

- **Path**: A file or directory to scan (default: entire project source).
- **`--write`**: Actually add proposed keys to the source language file and replace hardcoded strings in source code with translation function calls.
- No arguments: scan and report only (no modifications).

---

## Step 1: Determine Framework

Read the project's `package.json`, `pubspec.yaml`, `Gemfile`, or `requirements.txt` to detect the i18n framework:

| Framework | Detection | Translation Function |
|-----------|-----------|---------------------|
| react-intl | `react-intl` in deps | `intl.formatMessage({id: 'key'})` or `<FormattedMessage id="key" />` |
| i18next / react-i18next | `i18next` or `react-i18next` in deps | `t('key')` |
| vue-i18n | `vue-i18n` in deps | `$t('key')` or `t('key')` |
| @angular/localize | `@angular/localize` in deps | `$localize\`...\`` |
| svelte-i18n | `svelte-i18n` in deps | `$_('key')` or `$t('key')` |
| Flutter intl | `intl` or `flutter_localizations` in pubspec | `S.of(context).key` or `AppLocalizations.of(context)!.key` |
| Rails i18n | `i18n` gem | `I18n.t('key')` or `t('.key')` |
| Django | `django` in requirements | `_('string')` or `gettext('string')` |
| Laravel | `laravel` in composer | `__('string')` or `@lang('string')` |

If detection fails, ask the user which framework they use.

---

## Step 2: Scan Source Code

Search for user-facing strings in these locations:

### High-Confidence Extractions (very likely need translation)
- **JSX/HTML text content**: `<h1>Welcome</h1>`, `<p>Click here to start</p>`
- **UI attribute values**: `placeholder="Search..."`, `title="Close"`, `aria-label="Menu"`
- **Alert/dialog text**: `alert("Are you sure?")`, `confirm("Delete this item?")`
- **Toast/notification messages**: `toast.success("Saved!")`, `notify("Error occurred")`
- **Form validation messages**: `"This field is required"`, `"Invalid email address"`

### Medium-Confidence (probably need translation)
- **Error messages shown to users**: `throw new Error("Something went wrong")` — only if displayed in UI
- **Button/link text set programmatically**: `button.textContent = "Submit"`
- **Constant string arrays for UI**: `const tabs = ["Home", "Settings", "Profile"]`

### Exclude (do NOT extract)
- Log messages (`console.log`, `logger.info`, etc.)
- CSS class names, IDs, data attributes
- Import paths, module names
- Regex patterns
- Test file content (`*.test.*`, `*.spec.*`, `__tests__/`)
- Comments
- Environment variable names
- API endpoints, URLs
- Technical identifiers, enum values
- Strings already wrapped in translation functions

---

## Step 3: Propose Keys

For each extracted string, generate a translation key:

**Key naming rules:**
1. Use snake_case: `welcome_message`, `save_button`, `error_file_too_large`
2. Prefix with context: `nav_home`, `form_email_placeholder`, `error_network_timeout`
3. Keep keys descriptive but concise (2-4 words)
4. Group related keys: `settings_title`, `settings_description`, `settings_save`
5. Avoid generic keys like `text1`, `label2`, `message`

**Example proposals:**
```
src/components/Header.tsx:24
  "Welcome back" → welcome_back_message

src/components/LoginForm.tsx:45
  placeholder="Enter your email" → login_email_placeholder

src/pages/Settings.vue:78
  "Save Changes" → settings_save_button

src/components/ErrorBoundary.tsx:15
  "Something went wrong. Please try again." → error_generic_message
```

---

## Step 4: Report

```
String Extraction Report
════════════════════════

Scanned: 47 files (src/**/*.{tsx,vue,ts})
Framework: react-i18next (t function)

Found 12 hardcoded strings:

High Confidence (8):
  src/components/Header.tsx:24
    "Welcome back" → welcome_back_message

  src/components/Header.tsx:31
    "Log out" → logout_button

  src/components/LoginForm.tsx:45
    placeholder="Enter your email" → login_email_placeholder

  src/components/LoginForm.tsx:52
    placeholder="Password" → login_password_placeholder

  src/components/LoginForm.tsx:67
    "Sign In" → login_submit_button

  ...

Medium Confidence (4):
  src/utils/validation.ts:12
    "This field is required" → validation_required
    (Confidence: medium — verify this is shown in UI)

  ...

Run /translation-extract --write to apply these changes.
```

---

## Step 5: Apply (if `--write`)

If `--write` is specified:

1. **Add keys to source language file**: Read the current source file, add the new keys, sort if configured, write back.

2. **Replace hardcoded strings in source code**: For each extraction, replace the hardcoded string with the appropriate translation function call:

   Before:
   ```tsx
   <h1>Welcome back</h1>
   ```

   After:
   ```tsx
   <h1>{t('welcome_back_message')}</h1>
   ```

3. **Check for necessary imports**: If the translation function isn't already imported in the file, add the import.

4. **Report changes**:
   ```
   Applied 8 extractions:
     ✓ Added 8 keys to src/i18n/en.json
     ✓ Updated 5 source files
     ✓ Added t() import to 2 files

   Next: Run /translation-sync to translate these new keys into all languages.
   ```

---

## Safety Rules

- Never extract strings from test files.
- Never modify files outside the specified path.
- When using `--write`, create changes that don't break the build — ensure imports are correct and syntax is valid.
- If unsure whether a string is user-facing, classify it as medium confidence and let the user decide.
- Preserve existing translations — only ADD new keys, never modify existing ones.
