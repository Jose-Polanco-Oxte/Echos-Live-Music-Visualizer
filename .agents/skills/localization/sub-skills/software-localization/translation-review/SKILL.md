---
name: translation-review
description: Review existing translations for quality, consistency, accuracy, and tone. Use when the user wants to audit translation quality, check for mistakes, or ensure consistency across languages.
user-invocable: true
argument-hint: "[language] [focus: tone, accuracy, consistency, length]"
allowed-tools: Read Grep Glob
---

# Translation Review

You are a translation quality reviewer. Analyze existing translations holistically — not just checking for missing keys, but evaluating whether translations are accurate, consistent, natural-sounding, and appropriate for the target audience.

## Arguments

- **Language**: `French`, `de`, `ja` — review a specific language (default: all).
- **Focus area**: `tone`, `accuracy`, `consistency`, `length`, `formality` — concentrate on a specific quality dimension.
- No arguments: comprehensive review of all languages.

---

## Step 1: Load Files

1. Read the config (`.translation-sync.json`) or discover files.
2. Read the source language file completely.
3. Read all target language files (or the specified language).

---

## Step 2: Quality Dimensions

Evaluate each target language across these dimensions:

### Accuracy
- Do translations convey the same meaning as the source?
- Are there mistranslations, false cognates, or semantic shifts?
- Are technical terms translated correctly (or left untranslated when appropriate)?

### Consistency
- Is the same source term translated the same way throughout the file?
  - e.g., "Save" should not be "Enregistrer" in one place and "Sauvegarder" in another (French).
- Are related keys (e.g., `nav_home`, `nav_settings`, `nav_profile`) stylistically consistent?
- Do module boundaries cause terminology drift?

### Tone & Formality
- Is the formality level consistent? (formal "Sie" vs informal "du" in German; "vous" vs "tu" in French; "usted" vs "tú" in Spanish)
- Does the tone match the UI context? (error messages should feel different from marketing copy)
- Is the tone appropriate for the target culture?

### Naturalness
- Do translations read like they were written by a native speaker?
- Are there awkward literal translations or unnatural word order?
- Are locale-specific conventions followed? (date formats, number separators, currency placement)

### Length & UI Fit
- Are translations significantly longer than the source? (German averages 30% longer than English)
- Flag translations that are > 50% longer than source — they may overflow UI containers.
- Flag translations that are suspiciously shorter than source — they may be truncated or incomplete.

### Variable Integrity
- Are all variables preserved correctly?
- Are variables positioned naturally in the target language's word order?

### Glossary Compliance (if config defines a glossary)
- Are `glossary.doNotTranslate` terms left verbatim in every translation that mentions them?
- Are `glossary.terms[lang]` mappings used consistently? Flag any translation that uses a different rendering for a mapped term.
- A glossary violation is a stronger signal than a generic terminology inconsistency, because the user has explicitly committed to that mapping in config.

---

## Step 3: Review Process

For each target language:

1. **Scan all translations** and evaluate against the quality dimensions above.
2. **Group findings** by severity:
   - **Error**: Mistranslation, wrong meaning, missing critical context.
   - **Warning**: Inconsistency, unnatural phrasing, formality mismatch.
   - **Suggestion**: Length concerns, minor style improvements, alternative wording.
3. **Provide specific fixes** for each finding — don't just flag problems, suggest the correction.

---

## Step 4: Report

```
Translation Review: French (fr.json)
═════════════════════════════════════

Overall Quality: ★★★★☆ (Good — 3 issues found)

Errors (1):
  ✗ "delete_confirm" → "Êtes-vous sûr de supprimer ?"
    Issue: Missing the subject context — should specify what is being deleted.
    Suggested: "Êtes-vous sûr de vouloir supprimer cet élément ?"

Warnings (1):
  ⚠ Inconsistent terminology for "Save":
    "save_button" → "Enregistrer"
    "save_draft" → "Sauvegarder le brouillon"
    Recommendation: Use "Enregistrer" consistently, or "Sauvegarder" consistently.

Suggestions (1):
  💡 "error_file_too_large" → "Le fichier est trop volumineux pour être téléchargé sur le serveur"
    Length: 71 chars vs source 42 chars (+69%) — may overflow in compact UI.
    Shorter alternative: "Fichier trop volumineux"

Consistency Summary:
  ✓ Formality: Consistent formal "vous" throughout
  ✓ Button labels: Consistent imperative mood
  ⚠ Error messages: Mixed passive/active voice (3 instances)
```

If reviewing all languages, end with a comparison:

```
Cross-Language Summary:
  Language     Quality   Errors   Warnings   Suggestions
  ───────────────────────────────────────────────────────
  French       ★★★★☆    1        1          1
  German       ★★★★★    0        0          2
  Spanish      ★★★☆☆    2        3          1
  Japanese     ★★★★☆    0        2          3
```

---

## Guidelines

- Be respectful of existing translations — assume they were done with intent.
- Provide alternatives, not just criticism.
- Acknowledge when translations are good — don't only flag negatives.
- For languages you're less confident about, note your confidence level.
- Consider cultural context: a casual app may intentionally use informal address.
- Do NOT modify any files. This skill is read-only. Suggest running `/translation-sync` to apply fixes.
