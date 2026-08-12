---
name: graphics
description: >-
  Root skill that groups the graphics sub-skills used in this project. This is a
  router: it lists the sub-skills under sub-skills/ and tells the agent which
  one to load for the task at hand (texture processing, GPU frame debugging).
  Use when a graphics/rendering task matches one of those areas; then load the
  matching sub-skill's SKILL.md.
---

# Graphics — Root Skill

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
| DirectXTex Usage | `sub-skills/directxtex-usage/SKILL.md` | Integrating or using the DirectXTex library: loading/saving textures, format conversion, mipmap generation, block compression, Direct3D resource creation. |
| RenderDoc GPU Debug | `sub-skills/renderdoc-gpu-debug/SKILL.md` | GPU frame capture and debugging with `rdc-cli`: shader issues, pipeline state, frame captures, pixel/shader debugging, rendering artifacts. |

## Project context

The graphics subsystem builds on the C++/WinUI rendering stack. Use
`directxtex-usage` when working with texture assets and processing, and
`renderdoc-gpu-debug` when investigating GPU rendering issues captured from the
running visualizer. See `.agents/context/architecture.md` for how the render
pipeline fits into the app.
