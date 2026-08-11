---
name: incident-writer
description: Generate standard, objective, and structured IT or operational incident reports based on log data, system metrics, outage details, or user descriptions. Saves generated reports into .agents/skills/incident-writer/resources/. Use this skill whenever the user requests an incident report, post-mortem summary, outage breakdown, or root-cause document, even if they do not explicitly name the format.
license: MIT
compatibility: Requires standard Markdown support and file system write access.
---

# Incident Report Generator

## Overview
This skill provides instructions and templates to transform operational outage data,
error logs, metrics, or verbal incident summaries into precise, standardized
IT/Engineering incident reports. It enforces objectivity, conciseness, and
scannability without relying on emojis or informal phrasing. Generated report
files are stored in `.agents/skills/incident-writer/resources/`.

---

## Core Principles

* **Strict Objectivity:** State factual data (timestamps, metrics, observed behavior). Avoid speculation unless explicitly categorized under hypotheses.
* **No Visual Embellishments:** Do not use emojis, icons, or unicode decoration symbols.
* **High Scannability:** Use standard Markdown headers (`##`, `###`), tables, horizontal dividers (`---`), and concise bullet points.
* **Timeline Clarity:** Always normalize timestamps into a single baseline timezone (preferably UTC).
* **Target Output Directory:** All finalized incident report files must be saved under the `.agents/skills/incident-writer/resources/` directory.

---

## Workflow Steps

1. **Information Extraction:** Identify the incident summary, start time, end time/status, affected services, impact metrics, root cause, and remediation steps from the user's input.
2. **Severity Classification:** Assign a severity level based on the following threshold reference:
   * **SEV-1 (Critical):** Core system complete outage, active data loss, or high security breach affecting all or most users.
   * **SEV-2 (High):** Major feature degraded or unavailable with no immediate workaround; broad user impact.
   * **SEV-3 (Medium):** Minor feature failure or degraded performance with an available workaround.
   * **SEV-4 (Low):** Internal tool issue, cosmetic fault, or minor glitch with minimal user impact.
3. **Structure Mapping:** Populate the output strictly adhering to the standard template below.
4. **File Output Destination:** Write the resulting Markdown file directly to `.agents/skills/incident-writer/resources/{INCIDENT_ID}.md` (e.g., `.agents/skills/incident-writer/resources/INC-2026-8941.md`).

---

## Standard Incident Report Template

When generating an incident report, strictly apply this format and save it to `.agents/skills/incident-writer/resources/`:

```markdown
# Incident Report: [Brief Descriptive Title]

---

## Summary Information

| Parameter | Details |
| :--- | :--- |
| **Incident ID** | [e.g., INC-2026-8941] |
| **Severity Level** | [SEV-1 / SEV-2 / SEV-3 / SEV-4] |
| **Status** | [Investigating / Identified / Monitoring / Resolved] |
| **Affected Service(s)** | [e.g., Auth API, Payment Gateway] |
| **Incident Commander** | [Name or Role / Unassigned] |
| **Start Time (UTC)** | [YYYY-MM-DD HH:MM:SS] |
| **Resolution Time (UTC)**| [YYYY-MM-DD HH:MM:SS / Ongoing] |
| **Total Downtime** | [X hours Y minutes / N/A] |

---

## Executive Summary
Provide a concise 2–3 sentence overview detailing what occurred, the primary impact on users or business logic, and how the incident was ultimately mitigated or contained.

---

## User Impact & Metrics
* **User Reach:** [Percentage or estimated number of affected users]
* **Error Rate / Degradation:** [e.g., HTTP 500 errors increased by 45%]
* **Financial / Data Impact:** [Details regarding data integrity loss, transaction failures, or state N/A]

---

## Chronological Timeline (UTC)

* **HH:MM:** Alert triggered or initial issue reported by telemetry/users.
* **HH:MM:** Incident response initiated; triage begins.
* **HH:MM:** Root cause or contributing factor identified.
* **HH:MM:** Mitigation deployed or temporary workaround implemented.
* **HH:MM:** System metrics normalized and incident marked as resolved.

---

## Root Cause Analysis (RCA)
Explain the precise technical underlying cause. Distinguish clearly between the trigger event (e.g., a bad code deployment) and the systemic vulnerability (e.g., missing automated test suite or resource limit ceiling).

---

## Corrective & Preventative Actions

### Immediate Action Items Taken
* Applied hotfix patch or restored prior state version.
* Rerouted service traffic or scaled instance memory capacity.

### Long-Term Preventative Measures
* [ ] Task 1: Update automated regression test suites to catch similar regressions.
* [ ] Task 2: Implement circuit breakers or retry logic for dependent sub-systems.
* [ ] Task 3: Revise alerting thresholds for telemetry services.
