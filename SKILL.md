---
name: pf-vault-memory
description: A persistent, cross-device second brain for Claude Code — an LLM-maintained wiki you query, not a context blob you preload. Use when the user asks to recall past decisions/context ("what did we decide about X", "check the vault", "what does memory say"), to save durable knowledge (see /capture), or to promote captures into the wiki (see /ingest). Backed by a SessionEnd auto-capture hook and a SessionStart queue nudge. Do NOT preload the whole wiki; read the map, then the page.
---

# pf-vault-memory — operate the second brain

A vault of markdown that persists across sessions and devices. The engine is two hooks + two
skills; this file is how Claude *operates* it. Full architecture: the repo README. Schema:
`<vault>/CLAUDE.md`. Vault path: `$VAULT_PATH` in `~/.claude/settings.json`.

## The one idea

**Context is not storage. Mount the brain, don't ship it.** Every session starts empty. Do not
preload the wiki — load only the *map* (`wiki/index.md`, already imported by `KERNEL.md`), then
read the specific page on demand. Preloading everything costs thousands of tokens and buries the
relevant page; reading on demand is cheap and precise.

## Recall (answering from memory)

1. Read `wiki/index.md` → find the relevant page(s).
2. Read those pages → answer **with citations** (`[[Page]]`).
3. Check `wiki/log.md` (last ~5 entries) before assuming current state.
4. If pages contradict, surface it — never silently pick one.
5. If the answer is durable (a comparison, analysis, decision), FILE IT as a `wiki/syntheses/`
   page and log it. Explorations must compound.

## Flush (getting knowledge in) — two loops

- **Capture** (cheap, noisy, automatic): the SessionEnd hook writes every session to
  `raw/inbox/sessions/`. For a curated mid-session flush, use the **`/capture`** skill.
- **Ingest** (curated, human-gated): the **`/ingest`** skill promotes `raw/inbox/` → `wiki/`,
  cross-references, and flags contradictions. **Never run it unprompted** — the SessionStart
  nudge reports the queue; the user decides when to promote.

## Non-negotiables

- **Never delete anything in `raw/`.** `wiki/` is a derivative of `raw/`; the source is the audit
  trail. Supersede with a flag (`⚠️ superseded by [[newer]]`), never overwrite.
- **Wiki/inbox writes are pre-approved.** Anything *leaving* the vault (exports, decks, pushes)
  needs explicit approval.
- **The vault syncs; the reflexes do not.** If the SessionStart nudge reports installer drift,
  tell the user in one line and offer to re-run the installer — do not run it unasked.

## Setup (once per machine)

`bash install.sh` (macOS/Linux) or `install.ps1` (Windows), then add `@<vault>/KERNEL.md` to
`~/.claude/CLAUDE.md`. The vault folder itself syncs however the user prefers (git, Dropbox,
Syncthing, Obsidian Sync, iCloud). See the README.
