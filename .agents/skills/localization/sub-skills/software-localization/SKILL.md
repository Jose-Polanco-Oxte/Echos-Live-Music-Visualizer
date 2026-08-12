---
name: software-localization
description: >-
  Root skill that groups the software-localization (translation) sub-skills used
  in this project. This is a router at the second level of specificity of the
  localization skill: it lists the translation-* sub-skills directly under this
  folder and tells the agent which one to load for the task at hand (add
  language, sync, extract, guide, health, review, convert). Use when a
  translation/i18n task matches one of those areas; then load the matching
  sub-skill's SKILL.md.
---

# Software Localization — Root Skill (level 2)

This is a **root (grouping)** skill at the second level of the localization
skill tree. It has no standalone procedure; its job is to route to the
task-specific `translation-*` sub-skills that live alongside this file. See
`.agents/rules/skills.md` for the sub-skill structure. It is reached by loading
`../SKILL.md` (the `localization` root) and descending here; the translation
sub-skills are siblings of this file, not nested under a further `sub-skills/`.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at the path shown in the table below.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| Add Translation Language | `translation-add-language/SKILL.md` | Adding a new target language/locale: creating the translation file and populating translations. |
| Translation Convert | `translation-convert/SKILL.md` | Converting translation files between formats (JSON, YAML, PO, XLIFF, ARB, Properties). |
| Translation Extract | `translation-extract/SKILL.md` | Finding hardcoded user-facing strings in source code and proposing translation keys. |
| Translation Style Guide | `translation-guide/SKILL.md` | Generating or checking a translation style guide from existing translations. |
| Translation Health | `translation-health/SKILL.md` | Auditing translation coverage, dead keys, missing translations, and i18n health. |
| Translation Review | `translation-review/SKILL.md` | Reviewing translation quality, consistency, accuracy, and tone. |
| Translation Sync | `translation-sync/SKILL.md` | Synchronizing translation files across languages: translating only the delta, preserving variables and structure. |

## Project context

There is no localization content in this project itself; these are generic
i18n/l10n workflows. Several sub-skills depend on the project's
`.translation-sync.json` (or `.claude/translation-sync.json`) config — read it
first when present so its `sourceLanguage`, `targetLanguages`, `tone`, and
`glossary` fields are honored. For lint-level checks on locale files, see the
sibling `translint` skill at `../translint/SKILL.md`.