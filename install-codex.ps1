#!/usr/bin/env pwsh
# Add Codex support to a pf-vault-memory installation on Windows.
# Run install.ps1 first so the vault and its _system directory exist.

$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Vault = if ($env:VAULT_PATH) { $env:VAULT_PATH } else { Join-Path $env:USERPROFILE 'second-brain' }
$Vault = [System.IO.Path]::GetFullPath($Vault)
$Workspace = if ($env:VAULT_WORKSPACE) { $env:VAULT_WORKSPACE } else { Split-Path -Parent $Vault }
$Workspace = [System.IO.Path]::GetFullPath($Workspace)
$SourceRoot = Join-Path $Vault '_system\skills'
$HookSource = Join-Path $Vault '_system\hooks\vault_capture.py'
$Template = Join-Path $Here 'codex-AGENTS.md.tmpl'
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$CodexHooksDir = Join-Path $CodexHome 'hooks'
$UserAgentsDir = Join-Path $env:USERPROFILE '.agents'
$UserSkillsDir = Join-Path $UserAgentsDir 'skills'
$MarkersDir = Join-Path $UserAgentsDir '.pf-vault-memory-installed'
$WorkspaceAgentsDir = Join-Path $Workspace '.agents'
$WorkspaceSkills = Join-Path $WorkspaceAgentsDir 'skills'
$WorkspaceMarker = Join-Path $WorkspaceAgentsDir '.pf-vault-memory-skills-target'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Find-RealPython {
    $Candidates = @()
    $Launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($Launcher) {
        try {
            $Resolved = & $Launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $Resolved) { $Candidates += $Resolved.Trim() }
        } catch { }
    }
    foreach ($Name in @('python', 'python3')) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not $Candidate -or $Candidate -match '\\WindowsApps\\') { continue }
        try {
            $Probe = & $Candidate -c "print('ok')" 2>$null
            if ($LASTEXITCODE -eq 0 -and $Probe -eq 'ok') { return $Candidate }
        } catch { }
    }
    return $null
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Read-Marker {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
}

function Test-ReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $Item = Get-Item -LiteralPath $Path -Force
    return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Ensure-Junction {
    param([string]$Path, [string]$Target, [string]$Marker)
    $Target = (Resolve-Path -LiteralPath $Target).Path
    $Recorded = Read-Marker $Marker
    if ((Test-ReparsePoint $Path) -and $Recorded -eq $Target) { return 'existing' }

    if (Test-Path -LiteralPath $Path) {
        if ((Test-ReparsePoint $Path) -and $Recorded) {
            [System.IO.Directory]::Delete($Path)
        } else {
            $AsideRoot = Join-Path (Split-Path -Parent $Path) "_superseded-$RunStamp"
            New-Item -ItemType Directory -Force -Path $AsideRoot | Out-Null
            $Aside = Join-Path $AsideRoot (Split-Path -Leaf $Path)
            Move-Item -LiteralPath $Path -Destination $Aside
            Write-Warning "Existing unmanaged path moved aside: $Aside"
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Marker) | Out-Null
    Write-Utf8NoBom $Marker $Target
    return 'created'
}

foreach ($Required in @($Vault, $SourceRoot, $HookSource, $Template)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Missing $Required. Run install.ps1 first, then rerun install-codex.ps1."
    }
}

$PyExe = Find-RealPython
if (-not $PyExe) { throw 'A real Python 3 installation is required.' }

Write-Host "vault     : $Vault"
Write-Host "workspace : $Workspace"
Write-Host "python    : $PyExe"
Write-Host ""

# Codex discovers user skills from ~/.agents/skills. Junctions keep the vault canonical.
New-Item -ItemType Directory -Force -Path $UserSkillsDir, $MarkersDir | Out-Null
$Installed = 0
foreach ($SkillDir in Get-ChildItem -LiteralPath $SourceRoot -Directory | Sort-Object Name) {
    if (-not (Test-Path -LiteralPath (Join-Path $SkillDir.FullName 'SKILL.md') -PathType Leaf)) { continue }
    $Name = $SkillDir.Name
    $Result = Ensure-Junction -Path (Join-Path $UserSkillsDir $Name) `
                              -Target $SkillDir.FullName `
                              -Marker (Join-Path $MarkersDir $Name)
    Write-Host "[ok] /$Name ($Result)"
    $Installed++
}

# Prune only junctions previously managed here when a skill disappears from the vault.
foreach ($MarkerFile in Get-ChildItem -LiteralPath $MarkersDir -File -ErrorAction SilentlyContinue) {
    $Name = $MarkerFile.Name
    if (Test-Path -LiteralPath (Join-Path $SourceRoot $Name) -PathType Container) { continue }
    $Destination = Join-Path $UserSkillsDir $Name
    if (Test-ReparsePoint $Destination) { [System.IO.Directory]::Delete($Destination) }
    Remove-Item -LiteralPath $MarkerFile.FullName -Force
    Write-Host "[ok] /$Name unlinked; no longer present in the vault"
}

# Also expose the library when Codex is launched from the workspace root.
New-Item -ItemType Directory -Force -Path $WorkspaceAgentsDir | Out-Null
$WorkspaceResult = Ensure-Junction -Path $WorkspaceSkills -Target $SourceRoot -Marker $WorkspaceMarker
Write-Host "[ok] workspace .agents\skills ($WorkspaceResult)"

# Render global instructions because Codex does not expand Claude Code @imports.
New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null
$AgentsFile = Join-Path $CodexHome 'AGENTS.md'
if ((Test-Path -LiteralPath $AgentsFile -PathType Leaf) -and
    -not (Select-String -LiteralPath $AgentsFile -Pattern 'GENERATED by the pf-vault-memory installer' -Quiet)) {
    $Backup = "$AgentsFile.pre-pf-vault-memory-$RunStamp"
    Copy-Item -LiteralPath $AgentsFile -Destination $Backup
    Write-Warning "Existing AGENTS.md backed up: $Backup"
}
$Rendered = Get-Content -LiteralPath $Template -Raw -Encoding UTF8
$Rendered = $Rendered.Replace('{{VAULT}}', ($Vault -replace '\\', '/'))
$Rendered = $Rendered.Replace('{{WORKSPACE}}', ($Workspace -replace '\\', '/'))
Write-Utf8NoBom $AgentsFile $Rendered
Write-Host '[ok] Codex AGENTS.md generated'

# Install capture hook and a Windows wrapper that supplies paths while preserving stdin.
New-Item -ItemType Directory -Force -Path $CodexHooksDir | Out-Null
$HookScript = Join-Path $CodexHooksDir 'vault_capture.py'
$HookWrapper = Join-Path $CodexHooksDir 'vault_capture.cmd'
Copy-Item -LiteralPath $HookSource -Destination $HookScript -Force
$BatchVault = $Vault -replace '%', '%%'
$BatchWorkspace = $Workspace -replace '%', '%%'
$BatchPython = $PyExe -replace '%', '%%'
$BatchHook = $HookScript -replace '%', '%%'
$WrapperText = "@echo off`r`nset `"VAULT_PATH=$BatchVault`"`r`nset `"VAULT_WORKSPACE=$BatchWorkspace`"`r`n`"$BatchPython`" `"$BatchHook`"`r`n"
Write-Utf8NoBom $HookWrapper $WrapperText

$HooksJson = Join-Path $CodexHome 'hooks.json'
$MergeScript = Join-Path $env:TEMP 'pf-vault-memory-merge-codex-hooks.py'
$MergeCode = @'
import json, os, sys

path = os.environ["CODEX_HOOKS"]
wrapper = os.environ["CODEX_HOOK_WRAPPER"].replace("\\", "/")
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except FileNotFoundError:
    cfg = {}
except json.JSONDecodeError:
    sys.exit(f"{path} is not valid JSON; refusing to overwrite it")

command = f'cmd.exe /d /s /c ""{wrapper}""'
entry = {"type": "command", "command": command, "commandWindows": command, "timeout": 3}
groups = cfg.setdefault("hooks", {}).setdefault("SessionEnd", [])
for group in groups:
    group["hooks"] = [hook for hook in group.get("hooks", [])
                      if "vault_capture.py" not in hook.get("command", "")
                      and "vault_capture.cmd" not in hook.get("command", "")]
groups[:] = [group for group in groups if group.get("hooks")]
groups.append({"hooks": [entry]})
with open(path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
'@
Write-Utf8NoBom $MergeScript $MergeCode
$env:CODEX_HOOKS = $HooksJson
$env:CODEX_HOOK_WRAPPER = $HookWrapper
try {
    & $PyExe $MergeScript
    if ($LASTEXITCODE -ne 0) { throw 'Could not merge Codex hooks.json' }
} finally {
    Remove-Item -LiteralPath $MergeScript -Force -ErrorAction SilentlyContinue
}

Write-Host '[ok] Codex SessionEnd capture merged'
Write-Host ""
Write-Host "Installed $Installed Vault Memory skill(s)."
Write-Host 'Open Codex, run /hooks once, trust the SessionEnd hook, then restart Codex.'
