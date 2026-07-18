#!/usr/bin/env bash
# install.sh — set up pf-vault-memory on THIS machine (macOS / Linux).
#
# The vault (your notes) syncs across devices however you like — git, Dropbox, Syncthing,
# Obsidian Sync, iCloud. The REFLEXES (hooks + skills) do not sync; they live in ~/.claude/
# and must be installed per-device. Run this once per machine, after the vault folder exists.
#
#   VAULT_PATH=~/second-brain bash install.sh
#
# Idempotent: safe to re-run after every change to the hooks or skills. Never clobbers
# unrelated settings.
#
# What it does:
#   1. copies hooks   → ~/.claude/hooks/        (and re-chmods; sync engines drop the exec bit)
#   2. copies skills  → ~/.claude/skills/       (every skill in ./skills/)
#   3. merges hooks + VAULT_PATH into ~/.claude/settings.json (preserving what's there)
#   4. scaffolds the vault folder from ./vault-template/ if it does not exist yet
#   5. prints the one bootstrap line you still add by hand

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="$(cd "${VAULT_PATH:-$HOME/second-brain}" 2>/dev/null && pwd || echo "${VAULT_PATH:-$HOME/second-brain}")"
WORKSPACE="${VAULT_WORKSPACE:-$(dirname "$VAULT")}"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

PY=$(command -v python3 || command -v python) || { echo "✗ need python3 on PATH"; exit 1; }

echo "vault     : $VAULT"
echo "workspace : $WORKSPACE"
echo "python    : $PY"
echo

# ── 0. scaffold the vault from the template if it doesn't exist ─────────────────
if [ ! -d "$VAULT" ]; then
  echo "→ vault not found; scaffolding from vault-template/"
  mkdir -p "$VAULT"
  cp -R "$HERE/vault-template/." "$VAULT/"
  mkdir -p "$VAULT/raw/inbox/sessions"
  echo "✓ vault created at $VAULT  (edit KERNEL.md to make it yours)"
fi
mkdir -p "$VAULT/_system/hooks" "$VAULT/_system/skills"
cp "$HERE"/hooks/*.py "$VAULT/_system/hooks/"
cp -R "$HERE"/skills/. "$VAULT/_system/skills/"

# ── 1. hooks ──────────────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR/hooks"
for h in vault_capture.py vault_queue_nudge.py; do
  cp "$VAULT/_system/hooks/$h" "$CLAUDE_DIR/hooks/$h"
  chmod +x "$CLAUDE_DIR/hooks/$h"          # sync engines drop the exec bit
  echo "✓ hook   $h"
done

# ── 2. skills ─────────────────────────────────────────────────────────────────
# Install EVERY skill in _system/skills/ — never a hardcoded list. A hardcoded list silently
# strands any newly-added skill: it lands on disk and stays invisible to Claude, no error raised.
mkdir -p "$CLAUDE_DIR/skills"
for d in "$VAULT"/_system/skills/*/; do
  [ -f "$d/SKILL.md" ] || { echo "⚠ skip   $(basename "$d") — no SKILL.md"; continue; }
  s="$(basename "$d")"
  rm -rf "$CLAUDE_DIR/skills/$s"
  mkdir -p "$CLAUDE_DIR/skills/$s"
  cp -R "$d". "$CLAUDE_DIR/skills/$s/"
  echo "✓ skill  /$s"
done

# ── 3. settings.json: merge, never clobber ────────────────────────────────────
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

VAULT="$VAULT" WORKSPACE="$WORKSPACE" SETTINGS="$SETTINGS" "$PY" - <<'PYEOF'
import json, os, sys

settings_path = os.environ["SETTINGS"]
vault, workspace = os.environ["VAULT"], os.environ["WORKSPACE"]

try:
    with open(settings_path) as fh:
        cfg = json.load(fh)
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(f"✗ {settings_path} is not valid JSON — fix it first, refusing to overwrite")

cfg.setdefault("env", {})
cfg["env"]["VAULT_PATH"] = vault
cfg["env"]["VAULT_WORKSPACE"] = workspace

cmd = '/usr/bin/env python3 "$HOME/.claude/hooks/%s"'
wanted = {
    "SessionStart": (cmd % "vault_queue_nudge.py", 15, None),
    "SessionEnd":   (cmd % "vault_capture.py", 20, "Capturing session to vault..."),
}

hooks = cfg.setdefault("hooks", {})
for event, (command, timeout, status) in wanted.items():
    entry = {"type": "command", "command": command, "timeout": timeout}
    if status:
        entry["statusMessage"] = status
    groups = hooks.setdefault(event, [])
    # drop any prior copy of our hook so re-running doesn't stack duplicates
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if "vault_capture.py" not in h.get("command", "")
                      and "vault_queue_nudge.py" not in h.get("command", "")]
    groups[:] = [g for g in groups if g.get("hooks")]
    groups.append({"hooks": [entry]})

with open(settings_path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print("✓ settings.json merged (hooks + VAULT_PATH), existing keys preserved")
PYEOF

# ── 4. the one manual step ────────────────────────────────────────────────────
cat <<EOF

────────────────────────────────────────────────────────────────
Done. One manual step remains — the only per-device configuration:

  Add this line to  $CLAUDE_DIR/CLAUDE.md   (create it if missing)

      @$VAULT/KERNEL.md

That loads your identity, laws, and the vault map into every session
on this machine, in every project folder under $WORKSPACE.

Verify:  grep KERNEL $CLAUDE_DIR/CLAUDE.md
────────────────────────────────────────────────────────────────
EOF
