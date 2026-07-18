# KERNEL — the single entry point

> This file loads **in full, into every session, in every project folder**, on every device.
> Keep it lean — it costs context in every chat. Facts belong in `wiki/`; this holds only
> identity, standing rules, and the pointers below. Edit it to make the vault yours, then
> delete these quoted setup notes.

## Owner

> Replace with who you are and how you want Claude to work with you. Example:

- **Name / how to address me:** _<your name>_
- **Role / context:** _<what you do; the domains this vault covers>_
- **Defaults that matter:** _<currency, region, units, house style — anything a wrong default
  would get wrong>_

## Standing instructions

> Your working preferences. These load every session, so keep them tight. Example seeds:

- For complex or high-stakes requests, state what you understood in 1–3 lines first. For simple
  ones, answer directly.
- Accuracy > usefulness > brevity > formatting. Short sentences, no filler, answer first.
- If my idea is suboptimal, say so directly with reasoning. Distinguish fact / estimate / opinion.
- _<add your own>_

## RECALL protocol — how Claude gets context

**Never preload the wiki.** It grows without bound; loading it all costs thousands of tokens
before you type a word and buries the relevant page.

1. The vault map (`wiki/index.md`) is imported below — that is the table of contents.
2. When a question touches a person, project, or concept in the map, **read that page.** Claude
   has file tools; the vault is on disk. Reading is cheap; guessing is not.
3. Check `wiki/log.md` (last ~5 entries) for what changed recently before assuming state.
4. Cite the page used. If pages contradict, surface it rather than silently picking one.

## FLUSH protocol — how knowledge gets in

| What | Where |
|---|---|
| Durable knowledge — decisions + reasoning, analyses, facts, sources | `wiki/` (via `/ingest`) |
| Working state — current status, next actions | `state/<project>.md` |
| Raw, unprocessed capture | `raw/inbox/` (hook + `/capture`) |

- **SessionEnd hook** auto-captures every session to `raw/inbox/sessions/` — the hard guarantee.
- **`/capture`** — curated manual flush, mid-session, to `raw/inbox/`.
- **`/ingest`** — promotes `raw/inbox/` → `wiki/`, cross-references, flags contradictions.
  **Never ingest unprompted.** You decide when.

## Standing facts

> Locked decisions, naming conventions, anything Claude must not re-litigate. Add as you go.

- _<e.g. project priorities, naming locks, sensitive folders that need extra care>_

## The map

@wiki/index.md
