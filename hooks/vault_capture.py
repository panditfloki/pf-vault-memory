#!/usr/bin/env python3
"""
vault_capture.py — SessionEnd hook for pf-vault-memory.

The guaranteed-capture layer. Fires when any Claude Code session under WORKSPACE ends and
writes ONE lean markdown note into the vault inbox. It does NOT synthesise — that is the
`/ingest` step's job, run by a human. This script only guarantees nothing is lost.

Contract:
  - reads hook JSON on stdin (session_id, transcript_path, cwd, reason)
  - NEVER fails the session: any error is logged and we exit 0
  - idempotent: re-firing for the same session_id updates the same note, wherever it lives
  - NEVER un-ingests a note that has no new material (the "resurrection bug", below)

Why the watermark (the single most important design choice here):
  `/ingest` records `status: ingested` INSIDE the note. This hook owns that file and rewrites
  it whole on every session end. A naive rewrite hardcodes `status: unprocessed`, so any long
  or *resumed* session un-ingests itself — captures you already promoted flood back into the
  queue. But naively carrying `status: ingested` forward is also wrong: a session ingested at
  turn 4 that later runs to turn 9 has five turns of NEW material you'd bury.

  So the flag is a WATERMARK, not a boolean. `/ingest` stamps `ingested_at_turns: N`. On rewrite:
      turns_now <= watermark  -> nothing new, stay `ingested`
      turns_now >  watermark  -> new material, back to `unprocessed`
  Sessions can live for days and be resumed repeatedly, so there is no "old enough to ignore"
  cutoff — the watermark is the only safe way to tell promoted turns from fresh ones.

Configuration (set by install.sh / install.ps1 into ~/.claude/settings.json → env):
  VAULT_PATH        absolute path to the vault folder
  VAULT_WORKSPACE   the root you work under; sessions anywhere below it get captured
"""

from __future__ import annotations  # keep annotations lazy: runs on Python 3.9+

import glob
import json
import os
import re
import sys
import traceback
from datetime import datetime
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
VAULT = Path(os.environ.get("VAULT_PATH", Path.home() / "second-brain"))
WORKSPACE = Path(os.environ.get("VAULT_WORKSPACE", VAULT.parent))
RAW = VAULT / "raw"
INBOX = RAW / "inbox" / "sessions"   # where NEW captures land; /ingest files them to raw/<year>/
ERRLOG = Path.home() / ".claude" / "hooks" / "vault_capture.error.log"

# Folders (relative to WORKSPACE) whose sessions are NEVER captured. Empty by default —
# capture everything. Add a folder here to sandbox it, e.g. EXCLUDE_DIRS = ["secrets", "client-x"].
EXCLUDE_DIRS: list[str] = []

# Grouping folders that are NOT projects themselves — used only as a fallback when no CLAUDE.md
# marks the project root. Empty by default. If you nest projects under a category folder
# (e.g. work/, personal/), list those folders here so the capture is labelled by project,
# not by the category.
CONTAINER_DIRS: set[str] = set()

MAX_PROMPT_CHARS = 1500
MAX_CLOSING_CHARS = 2000
MAX_PROMPTS = 40
MAX_FILES = 60

# Strip harness-injected noise from user text blocks. `local-command-stdout` is the harness
# echoing a slash command's own output back into the turn — not something the user typed.
NOISE_RE = re.compile(
    r"<system-reminder>.*?</system-reminder>"
    r"|<ide_selection>.*?</ide_selection>"
    r"|<local-command-stdout>.*?</local-command-stdout>",
    re.DOTALL,
)
WRITE_TOOLS = {"Write", "Edit", "NotebookEdit", "MultiEdit"}


def log_error(msg: str) -> None:
    try:
        ERRLOG.parent.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().astimezone().isoformat(timespec="seconds")
        with ERRLOG.open("a") as fh:
            fh.write(f"[{stamp}] {msg}\n")
    except Exception:
        pass


def find_transcript(session_id: str, given: str | None) -> Path | None:
    if given and Path(given).is_file():
        return Path(given)
    if not session_id:
        return None
    hits = glob.glob(
        str(Path.home() / ".claude" / "projects" / "*" / f"{session_id}.jsonl")
    )
    return Path(hits[0]) if hits else None


def text_blocks(content) -> list[str]:
    """Every human-authored text in a message, whichever shape the harness used.

    Claude Code stores a message's `content` as a bare string OR as a list of typed blocks,
    depending on whether the turn carried attachments/tool results. Both are normal; assuming
    either one alone loses turns. Anything else (None, dict) yields nothing.
    """
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        return [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    return []


def clean(text: str) -> str:
    return NOISE_RE.sub("", text).strip()


def truncate(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[:limit].rstrip() + " …[truncated]"


def parse_transcript(path: Path) -> dict:
    prompts, files, closing, stamps = [], [], "", []

    # encoding is explicit: on Windows, Python defaults to the locale codepage (cp1252) and
    # mis-decodes UTF-8 transcripts — it silently mangles any non-ASCII text (₹, é, 你好, emoji).
    with path.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue

            if e.get("isSidechain"):  # subagent chatter, not the main thread
                continue
            if ts := e.get("timestamp"):
                stamps.append(ts)

            etype = e.get("type")
            content = (e.get("message") or {}).get("content")

            if etype == "user" and "toolUseResult" not in e:
                # A plainly typed prompt is a BARE STRING; a block list only appears when the
                # turn carries an attachment/image/tool-result. Reading lists only would drop
                # every string-shaped prompt — silently, since empty `prompts` makes the hook
                # exit 0 writing nothing. Accept both shapes; never assume one.
                for text in text_blocks(content):
                    if txt := clean(text):
                        prompts.append(truncate(txt, MAX_PROMPT_CHARS))

            elif etype == "assistant" and isinstance(content, list):
                for block in content:
                    btype = block.get("type")
                    if btype == "text" and block.get("text", "").strip():
                        closing = block["text"].strip()  # keep the last one
                    elif btype == "tool_use" and block.get("name") in WRITE_TOOLS:
                        fp = (block.get("input") or {}).get("file_path")
                        if fp and fp not in files:
                            files.append(fp)

    return {
        "prompts": prompts[:MAX_PROMPTS],
        "files": files[:MAX_FILES],
        "closing": truncate(closing, MAX_CLOSING_CHARS),
        "started": stamps[0] if stamps else "",
        "ended": stamps[-1] if stamps else "",
    }


def existing_note(sid8: str) -> Path | None:
    """Find this session's note ANYWHERE under raw/ — /ingest may have archived it.

    Sessions live for days, not minutes, and can be resumed long after being ingested and filed
    out of inbox/. A lookup limited to inbox/ would miss the archived note, write a NEW one, and
    resurrect the capture as a watermark-less duplicate — the exact bug the watermark exists to
    kill. So search raw/ whole and update the note in place, wherever it lives.
    """
    hits = sorted(glob.glob(str(RAW / "**" / f"*_{sid8}.md"), recursive=True))
    return Path(hits[0]) if hits else None


def read_frontmatter(path: Path | None) -> dict:
    """Minimal YAML-frontmatter reader. No deps; scalar values kept as raw strings.

    Any parse failure returns {} — the caller then treats the note as fresh, which is the safe
    direction: a capture may be re-ingested, never silently dropped.
    """
    if not path or not path.is_file():
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {}
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    fm = {}
    for line in text[3:end].splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm


def as_int(value, default: int = -1) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def carry_forward(prev: dict, turns_now: int) -> tuple[str, str, int]:
    """Decide this note's status from the previous note and the turn watermark.

    Returns (status, ingested_date, watermark). Empty date / -1 watermark mean "never ingested".
    """
    was_ingested = prev.get("status") == "ingested"
    ingested_date = prev.get("ingested", "")
    # Legacy notes promoted before watermarking: their `turns` at ingest is the best mark.
    watermark = as_int(prev.get("ingested_at_turns"), as_int(prev.get("turns"), -1) if was_ingested else -1)

    if was_ingested and turns_now <= watermark:
        return "ingested", ingested_date, watermark
    return "unprocessed", ingested_date, watermark


def yaml_str(v: str) -> str:
    return json.dumps(v)  # safe quoting for paths/reasons


def project_name(cwd: Path, rel: str) -> str:
    """Name the project this session belongs to.

    Primary rule: the nearest ancestor holding a CLAUDE.md IS the project root — Claude Code's
    own convention, so it self-corrects when folders are reorganised. Fallback: the first path
    segment that isn't a grouping folder (see CONTAINER_DIRS).
    """
    p = cwd
    while p != WORKSPACE and WORKSPACE in p.parents:
        if (p / "CLAUDE.md").is_file():
            return p.name
        p = p.parent
    for seg in rel.split("/"):
        if seg and seg not in CONTAINER_DIRS:
            return seg
    return WORKSPACE.name


def main() -> None:
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}

    cwd = Path(data.get("cwd") or os.getcwd()).resolve()
    session_id = data.get("session_id", "")
    reason = data.get("reason", "unknown")

    # Guard 1: only capture work inside the workspace.
    if not (cwd == WORKSPACE or WORKSPACE in cwd.parents):
        return
    # Guard 2: honour the exclusion list.
    rel = cwd.relative_to(WORKSPACE).as_posix() if cwd != WORKSPACE else ""
    if any(rel == d or rel.startswith(d + "/") for d in EXCLUDE_DIRS):
        return

    transcript = find_transcript(session_id, data.get("transcript_path"))
    if not transcript:
        log_error(f"no transcript for session {session_id} (cwd={cwd})")
        return

    t = parse_transcript(transcript)
    if not t["prompts"]:  # empty session — nothing worth capturing
        return

    project = project_name(cwd, rel)
    sid8 = (session_id or "unknown")[:8]
    now = datetime.now().astimezone()

    prior = existing_note(sid8)
    note = prior or INBOX / f"{now:%Y-%m-%d}_{project}_{sid8}.md"
    INBOX.mkdir(parents=True, exist_ok=True)

    # Never clobber what /ingest recorded. See the module docstring.
    prev = read_frontmatter(prior)
    turns_now = len(t["prompts"])
    status, ingested_date, watermark = carry_forward(prev, turns_now)
    created = prev.get("created") or f"{now:%Y-%m-%d}"

    fm = [
        "---",
        "type: session-capture",
        f"status: {status}",
        f"created: {created}",
    ]
    if ingested_date:
        fm.append(f"ingested: {ingested_date}")
    if watermark >= 0:
        fm.append(f"ingested_at_turns: {watermark}")
    fm += [
        f"project: {yaml_str(project)}",
        f"cwd: {yaml_str(str(cwd))}",
        f"session_id: {yaml_str(session_id)}",
        f"started: {yaml_str(t['started'])}",
        f"ended: {yaml_str(t['ended'])}",
        f"end_reason: {yaml_str(reason)}",
        f"turns: {turns_now}",
        f"transcript: {yaml_str(str(transcript))}",
        f"tags: [session-capture, {status}]",
        "---",
        "",
        f"# Session — {project} — {now:%Y-%m-%d %H:%M}",
        "",
        "> Auto-captured by the SessionEnd hook. Raw material for the `/ingest` sweep.",
        "> Not a wiki page. Promote what is durable, then set `status: ingested`",
        "> and `ingested_at_turns: <turns>`.",
        "",
    ]

    fm.append("## Prompts")
    fm.append("")
    if status == "unprocessed" and watermark >= 0:
        # Partially promoted already: tell the next ingest exactly what it has not seen.
        fm.append(
            f"> ⚠️ Turns 1–{watermark} were ingested on {ingested_date}. "
            f"**Only turns {watermark + 1}–{turns_now} are new.**"
        )
        fm.append("")
    for i, p in enumerate(t["prompts"], 1):
        fm.append(f"{i}. {p}\n")

    if t["files"]:
        fm += ["## Files touched", ""]
        fm += [f"- `{f}`" for f in t["files"]]
        fm.append("")

    if t["closing"]:
        fm += ["## Closing assistant message", "", t["closing"], ""]

    note.write_text("\n".join(fm), encoding="utf-8")
    print(json.dumps({"suppressOutput": True}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log_error(traceback.format_exc())
    sys.exit(0)  # never break the session
