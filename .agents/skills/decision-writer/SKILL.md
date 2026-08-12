---
name: decision-writer
description: Generate and document structured decision records, architecture decision records (ADRs), and rationale analysis. Triggers when asked to document a decision, create an ADR, or record decision outcomes.
---

# Decision Record Generator

This skill guides the creation of standardized, structured Decision Records
(Architecture Decision Records / Business Decision Log) and saves them to
`docs/public/decisions/`.

## Workflow

1. Gather key input parameters: Title, Context, Decision Drivers, Options Considered, Decision Outcome, and Consequences.
2. Format the decision record using the provided markdown template.
3. Save the resulting document in `docs/public/decisions/` using the naming
   convention `YYYY-MM-DD-<short-title>.md`.

## Output Location

All generated decision records MUST be written to:
`docs/public/decisions/`

## Decision Record Template

Use the following template for all decision documentation outputs:

```markdown
# [Short Title of Decision]

* Status: [Proposed | Accepted | Rejected | Deprecated | Superseded]
* Date: YYYY-MM-DD
* Decision Makers: [Names/Roles]
* Path: docs/public/decisions/YYYY-MM-DD-[short-title].md

## Context and Problem Statement
[Describe the context, problem, or driver prompting this decision in 2-4 sentences.]

## Decision Drivers
* [Driver 1]
* [Driver 2]

## Options Considered
* Option 1: [Short summary]
* Option 2: [Short summary]

## Decision Outcome
Chosen Option: [Selected Option], because [justification/rationale].

### Positive Consequences
* [Positive impact 1]
* [Positive impact 2]

### Negative Consequences / Trade-offs
* [Trade-off / risk 1]
* [Trade-off / risk 2]

## Pros and Cons of Options

### Option 1
* Good, because [argument]
* Bad, because [argument]

### Option 2
* Good, because [argument]
* Bad, because [argument]
