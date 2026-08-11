---
name: automation-oportunity-detection
description: >-
  Detect automation opportunities by mining conversation transcripts, compacting
  recurring workflow patterns into weighted knowledge, and recommending skills,
  hooks, or agents to automate repetitive work. Wraps a vendored agent-sh plugin
  and bridges its recommendations to the script-development skill for authoring.
  Use when asked to analyze past sessions, find what to automate, or build
  automations from observed patterns.
---

# Automation Opportunity Detection

This skill wraps a **vendored third-party plugin** (`agent-sh/skillers`) that
learns from past AI conversations and proposes automation for recurring work.

It answers questions like:

* "What should I automate?"
* "Which tasks do I repeat all the time?"
* "Could a script, hook, or agent save me this work?"

It does **not** write the final artifact directly. It detects patterns, produces
ranked recommendations, and hands the accepted ones to the
`script-development` skill (see [Bridging to script-development](#bridging-to-script-development)).

## How the plugin works together

The vendored plugin is a pipeline of four cooperating pieces. Everything below
`agent-sh/skillers/` is upstream code — keep the layout intact.

```text
Conversation transcripts
  (any installed AI tool: this project's opencode DB, plus Claude Code / Codex
   if present — auto-detected)
        ↓  1. COMPACT  (analyze, extract observations, cluster by theme)
Knowledge themes  (weighted JSON: frequency + recency + cross-session + pain)
        ↓  2. RECOMMEND  (apply evidence thresholds, classify primitive, check
                          what already exists in this repo)
Ranked recommendations (skill | hook | agent) + scaffold specs
        ↓  3. USER PICKS + SCAFFOLD
Accepted idea → author with script-development → place in `.agents/`
```

### The pieces

| Piece | Path (under `agent-sh/skillers/`) | Role |
| --- | --- | --- |
| Command | `commands/skillers.md` | Orchestrates `show` / `compact` / `recommend`; presents choices. The `$ARGUMENTS`/slash-command framing is a CLI convenience — run the same logic by following this file's steps. |
| Compactor agent | `agents/skillers-compactor.md` | Runs **compact**: reads transcripts, redacts secrets, extracts observations, clusters into themes, writes `knowledge/*.json`. |
| Compact skill | `skills/skillers-compact/SKILL.md` | The authoritative compact algorithm (sources, extraction criteria, clustering, weighting, pruning). |
| Recommender agent | `agents/skillers-recommender.md` | Runs **recommend**: loads themes, applies evidence thresholds, classifies skill/hook/agent, checks the ecosystem, returns ranked JSON. |
| Recommend skill | `skills/recommend/SKILL.md` | The authoritative recommend algorithm (thresholds, classification ratios, scaffold specs, sanitization). |
| Sanitizer | `lib/sanitize.js` | **Mandatory** redaction of API keys/tokens/high-entropy secrets before transcripts enter context or knowledge files. |
| Inventory | `components.json` | Declares the plugin's agents/skills/commands. |

## Project context

* **Data source:** this environment writes transcripts to
  `~/.local/share/opencode/opencode.db` (SQLite). The plugin auto-detects that
  and also reads Claude Code / Codex stores when present, so it is not tied to
  one tool.
* **State directory:** knowledge is written under `{stateDir}/skillers/`.
  Default is `.claude` (Claude Code convention). For this repository, run with
  `AI_STATE_DIR=.agents/state` (repo scope) or pass `--state-dir` so knowledge
  persists under the project's own state area and is not stored in a `.claude`
  folder.
* **Ecosystem check:** the recommender scans the repo for existing capabilities
  before suggesting anything. That scan maps to this project's structure:
  `.agents/skills/` (skills), `.agents/roles/` (agents), `.agents/rules/` and
  `.agents/integrations/` (policy/hooks). It will not propose something that
  already exists here.

## Workflow

Run these steps in order. All paths are relative to
`.agents/skills/scripting/sub-skills/automation-oportunity-detection/`.

### 1. Show status (optional)

```text
Read agent-sh/skillers/commands/skillers.md  → subcommand: show
```

Report active scope, state dir, transcript count, themes and weights, last
compaction time. Warn if knowledge is empty or stale.

### 2. Compact

```text
Read agent-sh/skillers/skills/skillers-compact/SKILL.md   (algorithm)
Read agent-sh/skillers/agents/skillers-compactor.md       (role)
```

Then execute:

1. Detect available transcript sources (auto-detect; use opencode DB for this
   project, plus any Claude/Codex stores found).
2. For every transcript line / message row, run
   `agent-sh/skillers/lib/sanitize.js::redact()` **before** parsing or passing
   to context. Never skip redaction.
3. Extract observations (`pain | repeat | task | wish | workflow`), cluster by
   shared tokens, compute weights, merge with existing `knowledge/*.json`,
   prune stale entries, update `lastCompactedAt`.
4. Output the JSON summary (sources, totals, themes updated/created).

### 3. Recommend

```text
Read agent-sh/skillers/skills/recommend/SKILL.md  (algorithm)
Read agent-sh/skillers/agents/skillers-recommender.md  (role)
```

Then execute:

1. Load `knowledge/*.json`, sort by weight.
2. Keep only themes meeting evidence: **5+ occurrences, 3+ sessions, weight ≥ 0.2**.
3. Classify each into **hook / skill / agent** using the type-ratio rules.
4. Check the existing repo ecosystem; mark anything already covered as
   `existing` instead of recommending it.
5. Return ≤ 5 ranked recommendations with evidence, rationale, estimated
   savings, and scaffold specs. Sanitize observation text — never embed raw
   observation data into scaffold commands.

### 4. Present and scaffold

Present the ranked list and let the user choose (never auto-create anything).
For each accepted recommendation, follow
[Bridging to script-development](#bridging-to-script-development).

## Bridging to script-development

`automation-oportunity-detection` decides **what** to automate; it relies on the
sibling **`script-development`** skill to produce the working artifact. After a
recommendation is accepted:

```text
Accepted recommendation + scaffold spec
        ↓ load
script-development  (../script-development/SKILL.md)
        ↓
author the script / skill / helper with real code
        ↓
place in the repo: .agents/skills/<group>/SKILL.md or scripts/ under the project
```

How to use it together, by primitive:

* **Skill recommendation** → scaffold the new skill with
  `script-development`'s PowerShell/scripting references, then register it under
  `.agents/skills/` following `.agents/rules/skills.md` (root-router pattern for
  grouping, or a standalone leaf skill).
* **Hook recommendation** → author the trigger logic as a script with
  `script-development`, then wire the hook under `.agents/integrations/` or a
  hooks mechanism the project already uses.
* **Agent recommendation** → draft the role definition
  (`.agents/roles/` descriptor) and, where it automates shell behavior, back it
  with a `script-development` reference.

In short: this skill detects and proposes; `script-development` builds. Always
hand the user a concrete, tested artifact (with `-WhatIf` / dry-run conventions
from `script-development`) rather than a bare scaffold.

## Constraints

* **Redaction is mandatory**: every raw transcript line must pass through
  `lib/sanitize.js::redact()` before analysis. Never write credentials to
  knowledge files.
* **Evidence before recommending**: never suggest below 5 occurrences / 3
  sessions / weight 0.2; never suggest what already exists in the repo.
* **No auto-creation**: get explicit user approval before generating anything.
* **Cap output**: at most 5 recommendations; keep output plain-text and terse.
* **Respect scope**: honor the requested scope (`repo` / `global` / `both`);
  for this repository prefer repo scope with `AI_STATE_DIR=.agents/state`.

## Vendored plugin notes (what to ignore)

* `agent-sh/skillers/.claude-plugin/`, `marketplace.json`, `CLAUDE.md`, and the
  `AGENTS.md` model-selection table are the upstream author's packaging/dev
  conventions. They are not part of this project's runtime; do not copy their
  CLI/model framing into generated files.
* `agent-sh/skillers/.github/` and its CI are upstream and out of scope.
* Keep the vendored tree read-only. Local adaptations live in this entry
  `SKILL.md` and in the `script-development` skill, not inside the vendored
  plugin.
