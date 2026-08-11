---
name: translation-guide
description: Generate or review a translation style guide based on existing translations. Use when setting up translation standards, onboarding translators, or ensuring consistency.
user-invocable: true
argument-hint: "[--generate | --check] [language]"
allowed-tools: Read Write Grep Glob
---

# Translation Style Guide

You are a translation style guide analyst. Analyze existing translations to discover implicit patterns and conventions, then generate an explicit style guide — or check translations against an existing guide.

## Arguments

- **`--generate`** (default): Analyze translations and produce a style guide.
- **`--check`**: Validate translations against an existing guide in `.translation-guide.md`.
- **Language**: Focus on a specific language.

---

## Mode 1: Generate Style Guide (`--generate`)

### Step 1: Analyze Existing Translations

Read source and all target language files. For each language, analyze:

**Formality Level**
- Detect pronoun usage: formal (Sie/vous/usted/あなた) vs informal (du/tu/tú/きみ).
- Check verb conjugation patterns for formality markers.
- Report: "German translations use **formal 'Sie'** consistently" or "Mixed: 'du' in UI labels, 'Sie' in legal text."

**Terminology Consistency**
- Build a term frequency table: how is each repeated English term translated?
- Flag inconsistencies: "Save" → "Enregistrer" (3 times) vs "Sauvegarder" (1 time).
- Identify the dominant translation for each term.

**Grammatical Patterns**
- Button labels: imperative ("Enregistrer") vs infinitive ("Enregistrer") vs noun ("Enregistrement").
- Error messages: passive ("Une erreur est survenue") vs active ("Nous avons rencontré une erreur").
- Placeholders/variables: position conventions.

**Brand & Proper Noun Handling**
- Which terms are left untranslated? (Product names, brand names, technical terms)
- Are there locale-specific adaptations?

**Punctuation & Formatting**
- Exclamation marks, question marks in UI strings.
- Quotation mark style (« » vs "" vs „" vs 「」).
- Number formatting (comma vs period for decimals).
- Date format conventions mentioned in strings.

### Step 2: Generate Guide

Write a `.translation-guide.md` file:

```markdown
# Translation Style Guide

Generated from existing translations on {date}.

## General Rules
- Source language: English (en)
- Formality: {detected level per language}

## Language-Specific Rules

### French (fr)
- **Formality**: Formal "vous" throughout
- **Button labels**: Infinitive form ("Enregistrer", "Annuler", "Supprimer")
- **Error messages**: Passive voice ("Une erreur est survenue")
- **Punctuation**: Space before colon, semicolon, question/exclamation marks
- **Quotation marks**: « guillemets »
- **Untranslated terms**: {list}

### German (de)
- **Formality**: Formal "Sie" throughout
- **Button labels**: Infinitive form ("Speichern", "Abbrechen")
- **Compound words**: Prefer hyphenated when very long
- **Untranslated terms**: {list}

## Terminology Glossary

| English | French | German | Spanish |
|---------|--------|--------|---------|
| Save | Enregistrer | Speichern | Guardar |
| Cancel | Annuler | Abbrechen | Cancelar |
| Delete | Supprimer | Löschen | Eliminar |
| Settings | Paramètres | Einstellungen | Configuración |
| ...     | ...    | ...    | ...     |

## Variable Rules
- Preserve all variables exactly: {name}, {{count}}, %s, etc.
- Variables may reorder for natural word order
- HTML tags must remain intact
```

### Step 3: Integrate with Config

If a `.translation-sync.json` exists, propose structured config additions based on what was detected — these are stronger than free-form `customInstructions` because the sync skill enforces them programmatically:

**Tone**: from the detected formality level per language, propose a `tone` field. Use a simple string if all languages agree, or a per-language object if they differ:
```json
"tone": { "default": "formal", "es": "informal" }
```

**Glossary**: from the dominant translation per repeated source term (the same data that built the Terminology Glossary table), propose a `glossary.terms` object. Include only terms that appeared 3+ times with a clear dominant rendering — single-occurrence terms aren't reliable. Also propose `doNotTranslate` for any term consistently left untranslated across all sampled languages.

Surface the proposal:
```
Generated .translation-guide.md with rules for 4 languages.

I also detected:
  • Tone: formal (de, fr); informal (es)
  • 12 glossary candidates (terms that appear 3+ times with consistent translation)
  • 4 do-not-translate candidates (terms left untranslated across all languages)

Would you like me to add these to your .translation-sync.json as structured `tone` and `glossary` fields?
This makes /translation-sync enforce them automatically — stronger than customInstructions guidance.
```

---

## Mode 2: Check Against Guide (`--check`)

### Step 1: Load Guide

Read `.translation-guide.md` from the project root.

### Step 2: Validate Translations

For each rule in the guide, check all translations:
- Formality violations (informal where formal is required)
- Terminology deviations (using a non-standard term)
- Grammatical pattern breaks (noun form where infinitive is the convention)
- Punctuation issues

### Step 3: Report

```
Style Guide Check
═════════════════

Checked 4 languages against .translation-guide.md

French (fr.json):
  ✓ Formality: Consistent (formal "vous")
  ⚠ Terminology: "save_draft" uses "Sauvegarder" — guide says "Enregistrer"
  ✓ Punctuation: Correct spacing before colons

German (de.json):
  ✓ All rules satisfied

Spanish (es.json):
  ⚠ Formality: "onboarding_greeting" uses informal "tú" — guide says "usted"
  ⚠ Terminology: "delete_button" uses "Borrar" — guide says "Eliminar"

Summary: 3 deviations found across 4 languages
```
