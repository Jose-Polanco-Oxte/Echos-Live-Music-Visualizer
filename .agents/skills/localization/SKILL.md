---
name: localization
description: >-
  Root skill that groups the localization sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (software localization, translation linting).
  Use when an i18n/l10n task applies; then load the matching sub-skill's SKILL.md.
---

# Localization — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill under `sub-skills/`. See
`.agents/rules/skills.md` for the sub-skill structure.

The localization tree has **two levels of specificity**:

1. This root routes to the `software-localization` grouping skill.
2. `software-localization` is itself a router: it points to the task-specific
   `translation-*` skills.

`translint` is a standalone sub-skill at this same first level (a direct leaf,
not a group).

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at `sub-skills/<name>/SKILL.md`.
3. If the chosen sub-skill is `software-localization`, read its `SKILL.md` and
   descend to the matching `translation-*` skill (recursively, on demand).
4. Apply it as a first-class skill (follow its instructions and resources).
5. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| Software Localization (group) | `sub-skills/software-localization/SKILL.md` | Any translation workflow task: adding a language, syncing/translating, extracting strings, style guide, health check, review, or format conversion. Descend into its `translation-*` sub-skills from there. |
| Translint | `sub-skills/translint/SKILL.md` | Checking locale/i18n files for missing keys, extra keys, placeholder/interpolation mismatches, empty values, or untranslated strings after adding or editing locale files. |

## Project context

There is no localization content in this project itself; these skills are
generic i18n/l10n workflows. Apply them when the task involves translation,
locale, or i18n files in any codebase. Read the `translation-sync` config
(`.translation-sync.json` or `.claude/translation-sync.json`) when present, as
several sub-skills depend on its fields.