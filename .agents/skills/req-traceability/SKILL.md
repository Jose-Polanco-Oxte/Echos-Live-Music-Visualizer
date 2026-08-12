---
name: req-traceability
description: Use this skill when a user requests changes, updates, or additions to project requirements, formulas, or specifications. It updates the corresponding specification documents in docs/public/spec/requirements-spec.md and automatically generates a structured traceability report in docs/public/traceability/.
---

# Requirements Traceability Skill

## Overview

This skill manages requirement modifications and maintains full traceability across project specifications and codebase implementations. Whenever a requirement, formula, or specification change occurs, this skill updates the source specification file under `docs/public/spec/requirements-spec.md` and produces a corresponding detailed traceability report inside `docs/public/traceability/`.

---

## Workflow Instructions

### 1. Identify Specification & Requirement Context
* Analyze the user input to extract feature increments, changed requirements, formulas, ranges, units, or acceptance criteria.
* Locate or create the target specification file under `docs/public/spec/requirements-spec.md`.

### 2. Update Specification File (`docs/public/spec/requirements-spec.md`)
* Edit or append the relevant specification document in `docs/public/spec/requirements-spec.md`.
* Record exact section references, updated requirement IDs (e.g., `RF6.2.2`), descriptions, formulas/rules, and acceptance criteria.

### 3. Generate Traceability Report (`docs/public/traceability/`)
* Create a dedicated traceability report file inside `docs/public/traceability/`.
* Use the following file naming format: `docs/public/traceability/traceability-report-<YYYYMMDD>-<feature-name>.md`.
* Ensure the report adheres strictly to the **Requirements and Formula Traceability Template** detailed below.

---

## Output Templates

```md
# Requirements and Formula Traceability Report

- **Feature / Increment:** [Name of the feature or increment]
- **Date:** [YYYY-MM-DD]
- **Responsible:** [Author / Agent / Contributor]
- **Status:** [IMPLEMENTED / PENDING VALIDATION / IN PROGRESS]

## Normative Source

| Requirement ID | Exact Section | Transcribed Formula, Range, Unit, or Rule | Acceptance Criteria |
|---|---|---|---|
| [REQ ID] | `[Spec File].md` §[Section] | [Exact formula or rule] | [Acceptance criterion] |

## Implementation Mapping

| Requirement | File and Symbol | Variables / Parameters and Units | Exact Relationship with Formula |
|---|---|---|---|
| [REQ ID] | `[path/to/file]` :: `[Symbol]` | [Variables and units] | [Explanation of implementation relation] |

## Verification

| Requirement | Automated Test / Manual Procedure | Edge Cases and Tolerance | Result |
|---|---|---|---|
| [REQ ID] | [Test or procedure description] | [Edge cases, ranges, or tolerances] | [Validation result] |

## Deviations or Decisions

[Detailed explanation of architectural decisions, platform limitations, or design choices made during implementation]
```