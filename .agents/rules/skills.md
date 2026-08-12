# Skill Structure: Root Skills and Sub-skills

Some skills are *root* (grouping) skills. A root skill is a normal folder
under `.agents/skills/<name>/` with its own `SKILL.md`, written exactly like
any other skill (frontmatter `name`/`description` followed by instructions),
but its job is to group and route to related sub-skills.

## Layout

```text
.agents/skills/<root>/
├── SKILL.md                 # root skill: routes the agent to its sub-skills
└── sub-skills/              # sibling folder at the same level as SKILL.md
    ├── <sub-a>/
    │   └── SKILL.md         # a first-class skill
    └── <sub-b>/
        └── SKILL.md
```

## Rules

1. A root `SKILL.md` behaves like any other skill, but it functions as a
   **grouping / router**: it points the agent to the sub-skills underneath.
2. Every folder inside `sub-skills/` is itself a **skill**. Treat each one as a
   first-class skill: read its `SKILL.md`, follow its instructions, and honor
   its resources exactly as you would for a top-level skill.
3. The root `SKILL.md` must describe which sub-skills exist, when to descend
   into each, and give the relative path to every sub-skill
   (`sub-skills/<name>/SKILL.md`).
4. Load sub-skills **on demand**: only the one(s) the current task actually
   needs. Do not eagerly read every sub-skill (see
   `.agents/rules/general.md` → Context budget).
5. If the root skill triggers but a specific sub-skill is the real fit, load
   that sub-skill's `SKILL.md` and apply it instead of trying to handle the
   task with only the root router.
