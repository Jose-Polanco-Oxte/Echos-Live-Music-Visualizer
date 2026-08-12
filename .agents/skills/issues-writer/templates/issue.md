---
name: issue-writer
description: Generate, document, and format structured issue reports (tasks, bug reports, feature requests, technical debt) for issue tracking systems like GitHub Issues or Jira. Saves finalized issue files in .agents/skills/issues-writer/resources/. Use this skill whenever the user asks to log a bug, create a ticket, document technical debt, or write an issue specification, even if they do not explicitly name the system.
license: MIT
compatibility: Requires standard Markdown support, shell access for execution scripts, and file system write access.
---

# Issue Writer Skill

## Overview
This skill provides instructions and standard templates to transform bug reports,
user feedback, technical debt, and feature ideas into concise, actionable, and
structured issue specifications. All generated issue documents are stored within
`.agents/skills/issues-writer/resources/`.

---

## Core Principles

* **Strict Actionability:** Every issue must define explicit reproduction steps, expected behavior, and acceptance criteria.
* **No Visual Embellishments:** Do not use emojis, icons, or decorative unicode characters in titles, bodies, or file names.
* **High Scannability:** Use standard Markdown headers (`##`, `###`), tables, concise bullet points, and code blocks for logs or code snippets.
* **File Directory Requirement:** Final output files must be written directly to `.agents/skills/issues-writer/resources/{ISSUE_TYPE}-{SHORT_NAME}.md`.

---

## Workflow Steps

1. **Categorize the Issue:** Determine the issue classification from the user request:
   * `bug`: Unexpected behavior, crash, memory leak, or functionality failure.
   * `feature`: New functional requirement or enhancement request.
   * `task` / `tech-debt`: Refactoring, testing additions, infrastructure updates, or documentation.
2. **Extract Essential Information:**
   * Bug: Environment, steps to reproduce, actual vs. expected results, log traces.
   * Feature/Task: User story, business rationale, technical scope, acceptance criteria.
3. **Format Output:** Populate the appropriate template matching the categorized issue type.
4. **Save File Output:** Write the final document to
   `.agents/skills/issues-writer/resources/` using the following naming
   convention:
   * Format: `.agents/skills/issues-writer/resources/issue-[type]-[short-slug].md`
   * Example: `.agents/skills/issues-writer/resources/issue-bug-auth-token-expiration.md`

---

## Auxiliary Scripts

When bulk issues need to be generated or validated against required schema fields prior to committing them to disk, run the bundled script:

```bash
No bundled issue validator is currently available; use the required-field and
acceptance-criteria checklist in this template before saving the issue.
