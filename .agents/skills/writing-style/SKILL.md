---
name: writing-style
description: >-
  Root skill that groups the writing-style sub-skills used in this project. This
  is a router: it lists the sub-skills under sub-skills/ and tells the agent
  which one to load for the task at hand (voice analysis, voice-matched editing).
  Use when a writing or voice-matching task matches one of those areas; then load
  the matching sub-skill's SKILL.md.
---

# Writing Style — Root Skill

This is a **root (grouping)** skill. It has no standalone procedure; its job is
to route to the right sub-skill under `sub-skills/`. See
`.agents/rules/skills.md` for the sub-skill structure.

## How to use this skill

1. Read this file to choose the matching sub-skill from the table below.
2. Load that sub-skill's `SKILL.md` at `sub-skills/<name>/SKILL.md`.
3. Apply it as a first-class skill (follow its instructions and resources).
4. Load **only** the sub-skill(s) the current task needs (context budget), not
   all of them.

## Sub-skills

| Sub-skill | Path | Use when |
| --- | --- | --- |
| Voice Analyzer | `sub-skills/voice-analyzer/SKILL.md` | Creating a voice profile from writing samples, onboarding to a new project, or refreshing an outdated VOICE.md style guide. |
| Voice Editor | `sub-skills/voice-editor/SKILL.md` | Editing AI-generated or draft content to match a voice profile, transforming generic output into authentic voice-matched writing. |

## Project context

Writing-style sub-skills operate on writing samples and prose. `voice-analyzer`
produces a portable `VOICE.md` style guide; `voice-editor` applies that guide to
drafts and AI output. Files are written to the caller's project
(`resources/VOICE.md`) or user-wide (`resources/voice/VOICE.md`) path as
decided by the active sub-skill.
