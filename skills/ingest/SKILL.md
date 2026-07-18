---
name: ingest
description: Promote unprocessed captures from the vault inbox into the wiki — the synthesis half of the second brain. Use when the user says /ingest, "process the inbox", "promote my captures", "sweep the vault", or when a SessionStart notice reports unprocessed captures and the user asks to clear them. Also fires when a new source (article, PDF, export) is dropped into raw/ and needs ingesting. Do NOT run unprompted.
---

# /ingest — Promote raw/inbox → wiki

The synthesis pass of the second brain. Captures are cheap and noisy; the wiki is curated and
cross-referenced. This skill turns the former into the latter, with the human present.

**Vault:** the folder at `$VAULT_PATH`.
**Schema (authoritative — read it first, obey it exactly):** `<vault>/CLAUDE.md`

## Load state before touching anything

1. Read `<vault>/CLAUDE.md` — the schema governs every write below.
2. Read `wiki/index.md` (the content catalog) and the last 5 log entries:
   `grep "^## \[" wiki/log.md | tail -5`.
3. Do not re-ingest a source the log says is already ingested.

## Find the queue

Every file under `raw/inbox/` whose frontmatter has `status: unprocessed`. Two kinds:

- `raw/inbox/sessions/*.md` — auto-captured by the SessionEnd hook. Dumb transcripts of prompts
  + files touched. Mostly noise; mine them for the signal.
- `raw/inbox/*.md` — curated captures from `/capture`, or sources the user dropped in.

## Ingest each one

1. **Extract only what is durable.** Decisions *and the reasoning behind them*; new facts about
   people, projects, or concepts; analyses; sources worth keeping; changed project status.
   **Discard:** chatter, debugging noise, one-off commands, anything the repo/git already
   records, anything true only inside that one conversation.
2. **Update every affected page** in `wiki/`. *This cross-referencing is the core value* — a
   single capture may touch 5–15 pages. A capture that updates nothing should not become a page.
3. **Flag contradictions explicitly.** If a capture conflicts with an existing claim, record the
   disagreement — newer supersedes older, but the conflict stays visible
   (`⚠️ superseded by [[newer source]]`). **Never silently overwrite.**
4. **File durable analyses** as `wiki/syntheses/` pages. Explorations must compound.
5. **If a capture contains nothing durable, invent nothing.** Mark it done and move on.
6. **Mark it processed:** set `status: ingested`, add `ingested: YYYY-MM-DD`, and **copy the
   note's current `turns:` value into `ingested_at_turns:`**. Then file it out of `raw/inbox/`
   into `raw/<year>/` (`sessions/` for hook captures, `captures/` for curated ones).

   The watermark is not optional. `SessionEnd` owns these files and rewrites them whole; it
   keeps `status: ingested` only while `turns <= ingested_at_turns`. Omit it and a long or
   resumed session either resurrects itself (old bug) or buries its own tail. Curated captures
   from `/capture` have no `turns:` — they need no watermark.

   A note that comes back `unprocessed` carrying an `ingested:` date is **partially promoted**.
   It says so above its prompts: *"Turns 1–N were ingested on DATE."* Promote only the tail.

## Close the loop

7. Update `wiki/index.md` (every page listed, with a one-line summary) and `wiki/Overview.md`
   if the map changed.
8. Append **one** `wiki/log.md` entry: `## [YYYY-MM-DD] ingest | <title>` — what was promoted,
   which pages changed, which contradictions were flagged. Never rewrite old entries.
9. Report in a short table: items processed · pages created · pages updated · contradictions
   flagged · items skipped as non-durable.

## Rules

- Wiki and inbox writes are **pre-approved** — that is the whole system. Anything **leaving**
  the vault (docx, pdf, zip, decks) needs explicit approval first.
- `raw/` is immutable apart from the `status:` flag above and filing new arrivals out of
  `raw/inbox/`. **Nothing is ever deleted** — `wiki/` is a derivative of `raw/`.
- Dates absolute (`2026-01-09`), never "recently".
- Batch large queues: if more than ~8 items are pending, delegate the reading to parallel
  sub-agents, then do the cross-referencing yourself in one pass so the links stay coherent.
