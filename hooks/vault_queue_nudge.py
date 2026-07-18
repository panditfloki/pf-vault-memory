#!/usr/bin/env python3
"""
vault_queue_nudge.py — SessionStart hook for pf-vault-memory.

The human-in-the-loop half of the flush protocol. The SessionEnd hook captures; this tells you
what is waiting. It READS ONLY — it never writes to the vault and never synthesises.

On session start it surfaces two things, then stays silent:
  1. unprocessed captures waiting in the vault — so the queue can never silently grow;
  2. INSTALLER DRIFT — hooks or skills the vault carries but this machine does not run — so
     "the vault syncs, the reflexes do not" can never strand a fix or a skill unnoticed.

Contract:
  - reads hook JSON on stdin (cwd, session_id, source)
  - NEVER fails the session: any error is swallowed and we exit 0
  - READS ONLY — reports drift, never repairs it (that would mean rewriting installed code,
    including this file, mid-run, unasked)
  - silent when the queue is empty AND nothing has drifted
"""

from __future__ import annotations  # keep annotations lazy: runs on Python 3.9+

import hashlib
import json
import os
import re
import sys
from pathlib import Path

VAULT = Path(os.environ.get("VAULT_PATH", Path.home() / "second-brain"))
WORKSPACE = Path(os.environ.get("VAULT_WORKSPACE", VAULT.parent))
RAW = VAULT / "raw"

VAULT_HOOKS = VAULT / "_system" / "hooks"
LIVE_HOOKS = Path.home() / ".claude" / "hooks"
# HOOKS is a CURATED list, not a disk scan: `_system/hooks/` may hold helper scripts that are
# deliberately NOT wired as hooks. Enumerating the dir would flag those as permanently "missing".
HOOKS = ("vault_capture.py", "vault_queue_nudge.py")

VAULT_SKILLS = VAULT / "_system" / "skills"
LIVE_SKILLS = Path.home() / ".claude" / "skills"

# Large historical import dirs are never capture notes. Skipped for speed only; adding a dir here
# can never hide a real capture, because captures never land in them.
SKIP_DIRS = {"assets"}

UNPROCESSED = re.compile(r"^status:\s*unprocessed\s*$", re.MULTILINE)
MAX_LISTED = 6


def queue() -> list[Path]:
    """Every capture still marked unprocessed, ANYWHERE under raw/.

    Not just inbox/: an archived note reverts to `unprocessed` the moment its session grows past
    its watermark, and scanning only inbox/ would make that re-queue invisible. Scoped to capture
    notes by frontmatter, so large import dirs cost almost nothing.
    """
    if not RAW.is_dir():
        return []
    hits = []
    for p in sorted(RAW.rglob("*.md")):
        if any(d in SKIP_DIRS for d in p.parts):
            continue
        try:
            # frontmatter lives in the first ~1KB; don't slurp big notes
            if UNPROCESSED.search(p.read_text(errors="replace")[:1024]):
                hits.append(p)
        except OSError:
            continue
    return hits


def hook_drift() -> list[str]:
    """Hooks whose installed copy differs from the vault's — i.e. fixes that never took effect.

    **The vault syncs; the reflexes do not.** A sync engine delivers a corrected hook into
    `_system/hooks/`, but the copy that actually RUNS lives in `~/.claude/hooks/` and only the
    installer refreshes it. So a fully-synced machine can carry a fix in the vault and still be
    executing the bug. Reported, never auto-repaired: silently rewriting hook code — including
    this very file, mid-execution — is not a thing a SessionStart hook should do unasked.
    """
    stale = []
    for name in HOOKS:
        src, dst = VAULT_HOOKS / name, LIVE_HOOKS / name
        if not src.is_file():
            continue  # vault copy absent (sync still running) — nothing to compare against
        try:
            live = hashlib.md5(dst.read_bytes()).digest() if dst.is_file() else None
            if live != hashlib.md5(src.read_bytes()).digest():
                stale.append(name)
        except OSError:
            continue
    return stale


def skill_drift() -> list[str]:
    """Skills present in the vault but NOT installed here.

    The installer copies every skill dir from `_system/skills/` into `~/.claude/skills/`. A skill
    added later syncs into the vault but stays uninstalled until the installer is re-run: present
    on disk, invisible to Claude, no error raised. This closes that gap. It detects STRANDED
    skills (in vault, not installed); it deliberately does NOT byte-compare each SKILL.md.
    """
    if not VAULT_SKILLS.is_dir():
        return []  # vault copy absent (sync still running)
    missing = []
    try:
        for d in sorted(VAULT_SKILLS.iterdir()):
            if not (d / "SKILL.md").is_file():
                continue  # not a skill dir
            if not (LIVE_SKILLS / d.name / "SKILL.md").is_file():
                missing.append(d.name)
    except OSError:
        return []
    return missing


def main() -> None:
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}

    cwd = Path(data.get("cwd") or os.getcwd()).resolve()
    if not (cwd == WORKSPACE or WORKSPACE in cwd.parents):
        return  # not our workspace

    stale_hooks = hook_drift()
    stranded_skills = skill_drift()
    pending = queue()
    if not stale_hooks and not stranded_skills and not pending:
        return  # nothing to say — stay silent

    banners, contexts = [], []

    # Installer drift first: a stale capture hook means THIS session may not be captured at all,
    # and a stranded skill is silently absent — both outrank a queue that is merely waiting, and
    # both are fixed by the same one command, so they share a single banner.
    if stale_hooks or stranded_skills:
        installer = "_system/install.sh" if os.name != "nt" else "_system\\install.ps1"
        parts = []
        if stale_hooks:
            parts.append(f"hooks stale ({', '.join(stale_hooks)})")
        if stranded_skills:
            parts.append(f"{len(stranded_skills)} skill(s) not installed ({', '.join(stranded_skills)})")
        banners.append(f"vault: {'; '.join(parts)} — re-run {installer}.")

        ctx = (
            "VAULT — INSTALLER DRIFT: what the vault carries and what this machine actually runs "
            "have diverged. The vault syncs; the reflexes do not — only the installer refreshes "
            "`~/.claude/`.\n\n"
        )
        if stale_hooks:
            ctx += (
                f"• HOOKS out of date: {', '.join(stale_hooks)}. If vault_capture.py is among them, "
                "sessions here may be captured incompletely or not at all, silently.\n"
            )
        if stranded_skills:
            ctx += (
                f"• SKILLS synced but not installed: {', '.join(stranded_skills)}. They exist in the "
                "vault and stay invisible to Claude until installed — no error is raised.\n"
            )
        ctx += (
            f"\nTell the user in ONE line and offer to run `{installer}` (idempotent; preserves "
            "existing settings). Do not run it without their say-so, and do not repeat this later "
            "in the session."
        )
        contexts.append(ctx)

    if pending:
        n = len(pending)
        names = [p.name for p in pending[:MAX_LISTED]]
        listing = "\n".join(f"  - {name}" for name in names)
        if n > MAX_LISTED:
            listing += f"\n  - …and {n - MAX_LISTED} more"

        noun = "capture" if n == 1 else "captures"
        banners.append(f"vault: {n} unprocessed {noun} waiting — run /ingest to promote.")
        contexts.append(
            f"VAULT — {n} unprocessed {noun} waiting in raw/:\n{listing}\n\n"
            "These are raw session captures that have not yet been promoted into wiki/. "
            "Mention this to the user once, early, in one line — then continue with whatever "
            "they actually asked. If they want them promoted, run the /ingest skill. Do not "
            "ingest unprompted, and do not repeat this notice later in the session."
        )

    print(
        json.dumps(
            {
                "systemMessage": "\n".join(banners),
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": "\n\n".join(contexts),
                },
            }
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # a nudge is never worth breaking a session over
    sys.exit(0)
