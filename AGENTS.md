# Echo Agent Pipeline Bootstrap

This repository uses `.agents/` as its architectural and operational control
layer. This root file exists only to activate that layer through Codex's native
project-instruction discovery.


> Note: If the person taking over the repository needs to modify the entry point or specific rules, they should edit this file to reflect those changes.

## Mandatory Per-Request Activation

For **every user request while this repository is the active workspace**, before
substantive planning, analysis, repository inspection, tool use, editing, or a
final answer:

1. Read `.agents/AGENTS.md` completely, even if it was read earlier in the
   conversation.
2. Execute the mandatory pipeline defined there in its stated order.
3. Load only the task-relevant context, rules, skills, handoffs, specifications,
   roles, tools, and integrations selected by that pipeline.
4. Apply the resulting instruction set to the entire request.

This activation applies to read-only questions, reviews, planning, debugging,
implementation, testing, documentation, Git operations, builds, packaging, and
release work. A request being small or apparently self-contained does not skip
the bootstrap.

If `.agents/AGENTS.md` is missing or unreadable, stop before consequential work
and report that the project pipeline could not be activated.

System and developer instructions, followed by the user's explicit request,
remain higher priority than repository instructions.

## Context Verification Contract

Only when explicitly asked to verify project instructions, respond with:

CONTEXT_OK

PIPELINE=./scripts/Build-Distribution.ps1

RELEASE_BRANCH=main

INTEGRATION_BRANCH=dev

DIRECT_DEV_TO_MAIN=forbidden