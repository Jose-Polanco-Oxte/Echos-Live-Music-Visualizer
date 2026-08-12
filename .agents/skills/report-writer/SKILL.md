---
name: report-writer
description: Generate comprehensive, well-structured, and formatted Markdown reports based on complex user data or analysis requests. Use this skill when the user asks for a formal report, summary analysis, technical findings, or structured documentation, even if they do not explicitly specify the format.
license: MIT
compatibility: Requires standard Markdown support. No external system packages needed.
---

# Structured Report Generator

## Overview
This skill guides the creation of professional, clear, and standardized technical or analytical reports. It enforces rigorous structure, scannability, and objectivity without relying on non-standard formatting or graphical embellishments like emojis.

---

## core Principles

* **Objective Tone:** Maintain a neutral, precise, and professional voice.
* **Scannability:** Rely on headers, clean Markdown tables, and structured bullet points to make information clear at a glance.
* **Prose Rules:** Do not use emojis, unicode symbols, or informal slang.
* **Data-Driven:** Support statements with explicit references to the input data or source context.

---

## Standard Report Structure

When requested to compile or write a report, organize the content according to the following layout:

### 1. Executive Summary
Provide a high-level overview of the findings, primary conclusion, and core key takeaways in 2–4 concise paragraphs.

### 2. Objectives and Scope
Clearly state the primary goals of the report, the boundaries of the analysis, and the data sources or methodology used.

### 3. Key Findings
Present the primary insights derived from the analysis. Use subsection headers (`###`) and bullet points to organize findings by category or theme.

### 4. Data Analysis & Evidence
Provide supporting data, metrics, or comparison tables. Use standard Markdown tables for structured data:

| Metric / Category | Observed Value | Target / Benchmark | Status |
| :--- | :--- | :--- | :--- |
| Metric A | Value A | Value B | Within Range |
| Metric B | Value C | Value D | Action Required |

### 5. Risk Assessment & Limitations
Highlight potential risks, edge cases, missing data, or constraints that could affect the conclusions or implementation.

### 6. Actionable Recommendations
List concrete, prioritized next steps or recommendations based on the findings. Organize them sequentially or by priority level (High, Medium, Low).

---

## Formatting Guidelines

* Use H2 (`##`) for major section boundaries and H3 (`###`) for subcategories.
* Separate major structural sections using horizontal rules (`---`).
* Use **bold text** to emphasize key terms or critical metrics sparingly.
* Ensure all code blocks, syntax references, or structured schemas use standard markdown syntax highlighting (e.g., ````json ... ````).