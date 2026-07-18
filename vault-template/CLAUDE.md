# Vault — an LLM-maintained second brain

This vault is an LLM-maintained personal wiki for Claude Code. You (the human) curate sources,
ask questions, and direct analysis. Claude does ALL wiki writing, cross-referencing, and
maintenance. You browse the results (Obsidian, VS Code, any markdown viewer); you rarely edit
wiki pages by hand.

## Architecture — five layers

1. **`raw/`** — immutable source documents + auto-captured session transcripts. NEVER modify,
   move, or delete anything here except organising new arrivals out of `raw/inbox/`. This is the
   source of truth. **Nothing is ever deleted** — `wiki/` is a *derivative* of `raw/`, so burning
   the source destroys the only way to audit the derivation.
   - `raw/inbox/` — drop zone. New sources + captures land here. **After ingest they are filed to
     `raw/<year>/`** (`sessions/` for hook captures, `captures/` for curated ones). The inbox is
     meant to be empty; a file sitting in it means unfinished work.
   - `raw/inbox/sessions/` — auto-captures written by the SessionEnd hook. Raw material, not pages.
2. **`wiki/`** — LLM-generated pages. Claude owns this layer entirely.
3. **`KERNEL.md`** — the single memory entry point. Identity, standing instructions, recall +
   flush protocols. Loaded into EVERY session on EVERY device via one bootstrap import. **Keep it
   lean** — it costs context in every chat. Facts belong in `wiki/`, not here. It `@import`s
   `wiki/index.md` so the map (not the whole wiki) rides into every session.
4. **`state/`** — working state, human-editable. `state/<project>.md` holds one project's status /
   next actions; that project's folder imports it with a single `@` line, so it loads only inside
   that project. Working state is NOT durable knowledge; it churns, and does not belong in `wiki/`.
5. **`_system/`** — the automation: hooks, the skill library, and the installers. Not notes.
   Per-device install; the executable bit does not survive most sync engines, so the installer
   re-`chmod`s. **Install everything found here — never a hardcoded list.**

## Wiki structure

- `wiki/Overview.md` — the home page. High-level map. Keep current.
- `wiki/index.md` — content catalog. EVERY page listed with a wikilink + one-line summary,
  grouped by category. Read this FIRST when answering a query. Update on every ingest.
- `wiki/log.md` — append-only chronological record. `## [YYYY-MM-DD] ingest|query|lint | Title`.
  Never rewrite old entries.
- `wiki/people/` · `wiki/projects/` · `wiki/concepts/` · `wiki/sources/` · `wiki/syntheses/`
  — one page per person / project / topic / ingested source / durable analysis.

## Page conventions

- **Filenames**: Title Case, human-readable, so wikilinks read naturally.
- **Links**: `[[Page Name]]`. Link liberally — a red link marks a page worth creating. Orphans
  are a lint failure.
- **Citations**: cite sources inline as `([[source page]])`. Superseded claims stay visible,
  flagged `⚠️ superseded by [[newer source]]` — never silently deleted.
- **Frontmatter** on every wiki page: `type`, `tags`, `created`, `updated`, `sources`.
- **Dates**: always absolute (`2026-01-04`), never "recently".

## Operations

- **Ingest** — a source/capture arrives → read it fully → update every affected page (the core
  value) → note contradictions → update `index.md` + `Overview.md` → append a `log.md` entry.
- **Query** — read `index.md` → read the relevant pages → answer with citations. If the answer
  is durable, FILE IT as a `wiki/syntheses/` page and log it. Explorations must compound.
- **Lint** (on request, ~every 10 ingests) — contradictions, stale claims, orphans, red links,
  index/log drift. Report, propose, apply on approval, log the pass.

## Standing preferences

- **Wiki page writes/updates are pre-approved** — that's the whole system. Ask before creating
  exports (docx, zip, pdf, decks) or anything leaving the vault.
- Put YOUR own standing instructions and identity in `KERNEL.md`, not here. This file is schema.

## Session start ritual

Read `wiki/index.md` and the last ~5 log entries (`grep "^## \[" wiki/log.md | tail -5`) to load
current state. `KERNEL.md` imports `index.md`, so in Claude Code the map is already in context —
go straight to reading the pages it names. **Never preload the whole `wiki/`.**
