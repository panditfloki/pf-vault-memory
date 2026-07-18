---
name: capture
description: Flush durable knowledge from the current session into the vault (your Claude Code second brain). Use when the user says /capture, "save this", "remember this", "put this in the vault", or when a session has produced a decision, analysis, or fact worth keeping. Writes a curated capture note to raw/inbox/ per the vault schema. Do NOT use for trivial chatter or for reading the vault (that is a normal query).
---

# /capture — Flush to the vault

Write the durable knowledge from this session into the vault so it compounds instead of
evaporating when the session ends.

**Vault:** the folder at `$VAULT_PATH` (set in `~/.claude/settings.json`).
**Schema (authoritative, read it):** `<vault>/CLAUDE.md`

## What counts as durable

Capture: decisions + the reasoning behind them · analyses and comparisons · new facts about
people, projects, or concepts · contradictions with what the vault already claims · sources
worth ingesting · changed status of a project.

Skip: chatter, one-off commands, debugging noise, anything already in the repo or git history,
anything true only inside this conversation.

If nothing durable happened, **say so and write nothing.** A capture note that records nothing
is worse than no note — it pollutes the ingest queue.

## Procedure

1. **Read `<vault>/CLAUDE.md`** — the schema governs everything below. Never write outside it.
2. **Decide the takeaways.** If the user passed arguments to `/capture`, that text is the
   instruction for *what* to capture. Otherwise infer from the session.
3. **Check for conflicts.** Read `wiki/index.md` and any page the takeaway touches. If a
   takeaway contradicts an existing claim, say so explicitly in the note — do not silently
   overwrite. Newer supersedes older, but the disagreement is recorded.
4. **Write the capture note** to `<vault>/raw/inbox/YYYY-MM-DD_<short-slug>.md` using the
   frontmatter below.
5. **Do NOT write into `wiki/` unless the user asks.** `/capture` feeds the queue; `/ingest`
   does the synthesis. Exception: if the user says "capture and file it", perform a full
   Ingest per the schema, including `index.md` + `log.md` updates.
6. **Report in one line** what you wrote and where. No preamble.

## Capture note format

```markdown
---
type: capture
status: unprocessed
created: YYYY-MM-DD
project: <project this came from>
session_id: <if known>
tags: [capture, unprocessed, <domain tags from schema>]
touches: ["[[Page A]]", "[[Page B]]"]   # wiki pages this likely updates
---

# <Title — the takeaway, not the topic>

## Takeaways
- <durable fact / decision, stated flatly>

## Reasoning
<why — the part that is expensive to reconstruct later>

## Contradictions
- ⚠️ <existing claim> on [[Page]] conflicts with <new claim>. Newer wins; flagged for lint.

## Open threads
- <what is still undecided, and what data would settle it>
```

## Rules

- Dates absolute (`2026-01-08`), never "today" or "recently".
- Wikilinks liberally in `touches:` — a red link marks a page worth creating.
- Wiki/inbox writes are pre-approved. Anything **leaving** the vault (exports, decks, PDFs,
  zips) needs explicit approval first.
- Never modify anything already inside `raw/` other than adding new files.
- Respect any exclusions in the schema: if a session is about a sandboxed/sensitive folder,
  ask before writing rather than assuming.
