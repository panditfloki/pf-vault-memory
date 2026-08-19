---
name: newproject
description: Wire a new (or existing) project folder into the vault memory system, so its working state lives in the synced vault and loads automatically inside that folder — in Claude Code, Codex, and Gemini/Antigravity alike. Use when the user says /newproject, "add this project to memory", "set up memory for this folder", "wire this into the vault", or when they create a project folder they want remembered across sessions and devices. Also use to retrofit an existing folder missing CLAUDE.md, AGENTS.md, or GEMINI.md.
---

# /newproject — wire a project into the vault

Four files. The project's **working state** goes in the vault (so it syncs across devices and
stays editable in your notes app); the project folder gets three tiny platform adapters —
`CLAUDE.md` for Claude Code, `AGENTS.md` for Codex, and `GEMINI.md` for Gemini/Antigravity — all
three pointing at the same state file. No adapter stores project facts itself.

Write all three even if you only use one tool today. They are each other's cheapest insurance:
an adapter that doesn't exist fails **silently**, and you find out only when a session works
without the project's state and you can't tell why.

**Vault:** the folder at `$VAULT_PATH` (set in `~/.claude/settings.json`).
**Schema:** `<vault>/CLAUDE.md`.

## Before you write anything

1. **Get the folder path.** Default to the current working directory if the user doesn't say.
2. **Pick the project name.** Use it consistently for both the state filename and any future wiki page.
   **No spaces in the state filename** — `@import` is not documented to tolerate them, and a
   space-bearing basename also collides with `wiki/projects/<same name>.md`. Use hyphens
   (`My-Project.md`, not `My Project.md`).
3. **Count the import depth — on THIS machine, by looking, not from memory.** The pointer's `@` path is
   relative to the project's `CLAUDE.md`. Count the directory segments from the project folder up to the
   folder that *contains* the vault, then use that many `../`. Example: if the vault is `~/second-brain`
   and the project is `~/work/acme/`, the pointer needs `@../second-brain/state/Acme.md` — but a nested
   `~/work/clients/acme/` needs one more `../`. **Layouts differ; always look at the actual tree.**
   ⚠️ **A wrong depth fails SILENTLY** — the import loads nothing, with no error, forever. **Always
   `test -f` (or `Test-Path`) the resolved target before you finish.**
4. **Check it doesn't already exist.** If `state/<name>.md`, the project `CLAUDE.md`, `AGENTS.md`,
   or `GEMINI.md` is already there, read it and *extend* — never clobber working state or custom
   project instructions.

## Write file 1 — the state, in the vault

`<vault>/state/<Project-Name>.md`

```markdown
---
type: state
project: <Project Name>
tags: [state, <domain tag from the schema>]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active | dormant | paused
---

# <Project Name> — Working State

Working state, not durable knowledge. Syncs across devices; editable in your notes app.
Durable knowledge lives in `wiki/`. See [[<Project Name>]] and [[index]].

## Status
<one line: what phase, what's live, what's blocked>

## Current decisions
- <decision + one-line why>

## Next actions
- [ ] <action>

## Log (append-only)
- YYYY-MM-DD — <what changed>
```

Keep it **short** — it loads into every session inside that folder. Facts, analyses, and reasoning
belong in `wiki/` (via `/ingest`), not here.

## Write file 2 — the pointer, in the project folder

`<project folder>/CLAUDE.md`

```markdown
# <Project Name>

Working state lives in the vault, so it syncs across devices and stays editable in your notes app.
This file is just the pointer.

@../<vault-dirname>/state/<Project-Name>.md

Durable knowledge is not here — it's in the vault's `wiki/`. Read `wiki/index.md`, then fetch the
page you need.
```

Adjust `../` to the depth you counted in step 3. Nothing else goes in this file — no rules, no facts.
Any workspace-root `CLAUDE.md` and the `KERNEL.md` are inherited automatically (Claude Code walks up
the directory tree), so never re-paste them here.

## Write file 3 — the Codex adapter, in the project folder

`<project folder>/AGENTS.md`

```markdown
# <Project Name> — Codex project pointer

Before working on this project:

1. Read `<same relative path as above>/<vault-dirname>/state/<Project-Name>.md` for current
   working state.
2. Read `<relative path>/<vault-dirname>/CLAUDE.md` (or `KERNEL.md`, if your vault has one) for
   standing rules.
3. Read `<relative path>/<vault-dirname>/wiki/index.md`, then only the relevant wiki pages.
4. Check the last five entries of `<relative path>/<vault-dirname>/wiki/log.md` when recency matters.

The vault is the source of truth. Do not copy project state or durable knowledge into this file.
```

**Why this file exists separately from `CLAUDE.md`:** Codex officially discovers `AGENTS.md`; it
does not automatically expand Claude Code's `@` imports. Keep this adapter explicit and short, using
the exact same verified relative depth as `CLAUDE.md` — both point at the same target, just by
different mechanisms.

## Write file 4 — the Gemini / Antigravity adapter, in the project folder

`<project folder>/GEMINI.md`

```markdown
# <Project Name> — Gemini / Antigravity project pointer

Before working on this project:

1. Read `<same relative path as above>/<vault-dirname>/state/<Project-Name>.md` for current
   working state.
2. Read `<relative path>/<vault-dirname>/CLAUDE.md` (or `KERNEL.md`, if your vault has one) for
   standing rules.
3. Read `<relative path>/<vault-dirname>/wiki/index.md`, then only the relevant wiki pages.
4. Check the last five entries of `<relative path>/<vault-dirname>/wiki/log.md` when recency matters.

The vault is the source of truth. Do not copy project state or durable knowledge into this file.
```

**Why a third near-identical file, and not a symlink.** Only the title line differs from
`AGENTS.md` — but a Gemini/Antigravity session loads `GEMINI.md` **and** `AGENTS.md` as two
separate files rather than treating one as covering the other, so each needs its own real copy.
A symlink is also the wrong tool here: it does not survive a Windows checkout the way a plain
file does. Use the same verified relative depth as the other two adapters.

## Then

5. **Verify all three adapters resolve.** Confirm the state and (if present) KERNEL/index/log targets
   exist from the project directory. A broken path fails silently — check it, don't assume.
6. **Wiki page:** if `wiki/projects/<Project Name>.md` doesn't exist, **don't hand-write it.** Say so —
   it gets created by `/ingest` once the project has captures, per the schema.
7. **Nothing else to register.** The SessionEnd hook already covers every folder under the workspace —
   no config change, no settings edit.
8. **Report briefly:** the four files written or preserved (state + `CLAUDE.md` + `AGENTS.md` +
   `GEMINI.md`), the verified paths, and whether a wiki page exists yet.

## Rules

- Never put durable knowledge in `state/`. Never put working state in `wiki/`.
- Never restate standing rules/identity in a project `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md` —
  they're pointers and loading instructions only.
- Dates absolute (`2026-01-09`), never "today"/"recently".
- If the project is sensitive, follow whatever capture policy the vault's `KERNEL.md`/schema sets —
  don't invent an exclusion on your own; ask the user if it isn't already decided.
