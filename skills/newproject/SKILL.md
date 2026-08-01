---
name: newproject
description: Wire a new (or existing) project folder into the vault memory system, so its working state lives in the synced vault and loads automatically inside that folder. Use when the user says /newproject, "add this project to memory", "set up memory for this folder", "wire this into the vault", or when they create a project folder they want remembered across sessions and devices. Also use to retrofit an existing folder that has no CLAUDE.md.
---

# /newproject — wire a project into the vault

Two files. That's the whole job. The project's **working state** goes in the vault (so it syncs
across devices and stays editable in your notes app); the project folder gets a **one-line pointer**
so Claude Code loads that state automatically — but only inside that folder.

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
4. **Check it doesn't already exist.** If `state/<name>.md` or the project `CLAUDE.md` is already there,
   read them and *extend* — never clobber working state.

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

## Then

5. **Verify the import resolves.** Confirm the target file exists at the path the `@` line points to.
   A broken import fails silently — check it, don't assume.
6. **Wiki page:** if `wiki/projects/<Project Name>.md` doesn't exist, **don't hand-write it.** Say so —
   it gets created by `/ingest` once the project has captures, per the schema.
7. **Nothing else to register.** The SessionEnd hook already covers every folder under the workspace —
   no config change, no settings edit.
8. **Report in three lines:** the two files written, the import path, and whether a wiki page exists yet.

## Rules

- Never put durable knowledge in `state/`. Never put working state in `wiki/`.
- Never restate standing rules/identity in a project `CLAUDE.md` — they're inherited.
- Dates absolute (`2026-01-09`), never "today"/"recently".
- If the project is sensitive, follow whatever capture policy the vault's `KERNEL.md`/schema sets —
  don't invent an exclusion on your own; ask the user if it isn't already decided.
