<#
  install.ps1 — set up pf-vault-memory on THIS machine (Windows).

  The vault (your notes) syncs across devices however you like. The REFLEXES (hooks + skills)
  do not sync; they live in ~/.claude/ and must be installed per-device. Run once per machine.

      $env:VAULT_PATH = "$HOME\second-brain"; powershell -ExecutionPolicy Bypass -File install.ps1

  Idempotent: safe to re-run after every change to the hooks or skills. Never clobbers
  unrelated settings. Note: on locked-down machines the PowerShell *console* may be restricted,
  but a script file on disk runs with full language — which is why this lives in a .ps1.
#>

$ErrorActionPreference = "Stop"

$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Vault     = if ($env:VAULT_PATH) { $env:VAULT_PATH } else { Join-Path $HOME "second-brain" }
$Workspace = if ($env:VAULT_WORKSPACE) { $env:VAULT_WORKSPACE } else { Split-Path -Parent $Vault }
$ClaudeDir = Join-Path $HOME ".claude"
$Settings  = Join-Path $ClaudeDir "settings.json"

$py = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { Write-Error "need python3 on PATH"; exit 1 }

Write-Host "vault     : $Vault"
Write-Host "workspace : $Workspace"
Write-Host "python    : $($py.Source)`n"

# ── 0. scaffold the vault from the template if it doesn't exist ─────────────────
if (-not (Test-Path $Vault)) {
  Write-Host "→ vault not found; scaffolding from vault-template/"
  New-Item -ItemType Directory -Force -Path $Vault | Out-Null
  Copy-Item -Recurse -Force (Join-Path $Here "vault-template\*") $Vault
  New-Item -ItemType Directory -Force -Path (Join-Path $Vault "raw\inbox\sessions") | Out-Null
  Write-Host "✓ vault created at $Vault  (edit KERNEL.md to make it yours)"
}
New-Item -ItemType Directory -Force -Path (Join-Path $Vault "_system\hooks"), (Join-Path $Vault "_system\skills") | Out-Null
Copy-Item -Force (Join-Path $Here "hooks\*.py") (Join-Path $Vault "_system\hooks")
Copy-Item -Recurse -Force (Join-Path $Here "skills\*") (Join-Path $Vault "_system\skills")

# ── 1. hooks ──────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir "hooks") | Out-Null
foreach ($h in "vault_capture.py", "vault_queue_nudge.py") {
  Copy-Item -Force (Join-Path $Vault "_system\hooks\$h") (Join-Path $ClaudeDir "hooks\$h")
  Write-Host "✓ hook   $h"
}

# ── 2. skills ─────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir "skills") | Out-Null
Get-ChildItem -Directory (Join-Path $Vault "_system\skills") | ForEach-Object {
  if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { Write-Host "⚠ skip   $($_.Name) — no SKILL.md"; return }
  $dest = Join-Path $ClaudeDir "skills\$($_.Name)"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force (Join-Path $_.FullName "*") $dest
  Write-Host "✓ skill  /$($_.Name)"
}

# ── 3. settings.json: merge, never clobber (delegated to python for a real JSON merge) ──
if (-not (Test-Path $Settings)) { "{}" | Set-Content $Settings }
$env:SETTINGS = $Settings; $env:V = $Vault; $env:W = $Workspace
& $py.Source - @"
import json, os, sys
sp = os.environ['SETTINGS']
try:
    cfg = json.load(open(sp, encoding='utf-8'))
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit('settings.json is not valid JSON — fix it first, refusing to overwrite')
cfg.setdefault('env', {})
cfg['env']['VAULT_PATH'] = os.environ['V']
cfg['env']['VAULT_WORKSPACE'] = os.environ['W']
cmd = '/usr/bin/env python3 "\$HOME/.claude/hooks/%s"'
wanted = {'SessionStart': (cmd % 'vault_queue_nudge.py', 15, None),
          'SessionEnd':   (cmd % 'vault_capture.py', 20, 'Capturing session to vault...')}
hooks = cfg.setdefault('hooks', {})
for ev,(c,t,s) in wanted.items():
    e = {'type':'command','command':c,'timeout':t}
    if s: e['statusMessage']=s
    g = hooks.setdefault(ev, [])
    for grp in g:
        grp['hooks'] = [h for h in grp.get('hooks',[]) if 'vault_capture.py' not in h.get('command','') and 'vault_queue_nudge.py' not in h.get('command','')]
    g[:] = [grp for grp in g if grp.get('hooks')]
    g.append({'hooks':[e]})
json.dump(cfg, open(sp,'w',encoding='utf-8'), indent=2); open(sp,'a',encoding='utf-8').write('\n')
print('settings.json merged (hooks + VAULT_PATH), existing keys preserved')
"@

Write-Host @"

----------------------------------------------------------------
Done. One manual step remains — the only per-device configuration:

  Add this line to  $ClaudeDir\CLAUDE.md   (create it if missing)

      @$Vault\KERNEL.md

That loads your identity, laws, and the vault map into every session
on this machine, in every project folder under $Workspace.
----------------------------------------------------------------
"@
