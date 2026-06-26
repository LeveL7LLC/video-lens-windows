<#
.SYNOPSIS
    Install video-lens (Windows-native) as a global agent skill.

.DESCRIPTION
    One-shot installer for Windows. It:
      1. Finds your Python 3 and ensures a working `python3` command exists
         (the skill's scripts and serve_report.sh invoke `python3`; many Windows
         Python installs only expose `python`). If missing, a tiny `python3.exe`
         shim is created and added to your User PATH.
      2. Installs the Python dependencies (youtube-transcript-api, yt-dlp).
      3. Copies the `video-lens` and `video-lens-gallery` skills into your
         agent's global skills directory (default: Claude Code at ~/.claude/skills).

    No `PYTHONUTF8` or yt-dlp-on-PATH tweaks are needed — the scripts handle
    UTF-8 output and invoke yt-dlp as a module themselves.

.PARAMETER Agent
    Which agent to install for: claude (default), agents, gemini, opencode,
    cursor, copilot, codex, windsurf. Controls the target ~/.<agent>/skills dir.

.EXAMPLE
    pwsh -File install.ps1

.EXAMPLE
    pwsh -File install.ps1 -Agent gemini
#>
[CmdletBinding()]
param(
    [ValidateSet('claude', 'agents', 'gemini', 'opencode', 'cursor', 'copilot', 'codex', 'windsurf')]
    [string]$Agent = 'claude'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# 1. Resolve a Python 3 interpreter ------------------------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $py) {
    throw "Python 3 not found on PATH. Install it from https://www.python.org/downloads/ and re-run."
}
Write-Step "Using Python: $py"

# 2. Ensure a working `python3` command --------------------------------------
$python3Works = $false
try {
    $null = & python3 --version 2>$null
    if ($LASTEXITCODE -eq 0) { $python3Works = $true }
} catch { }

if ($python3Works) {
    Write-Step "'python3' already works — no shim needed."
} else {
    Write-Step "Creating a 'python3' shim (this Python only exposes 'python')."
    $shimDir = Join-Path $env:LOCALAPPDATA 'Programs\video-lens\bin'
    New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
    Copy-Item $py (Join-Path $shimDir 'python3.exe') -Force
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if ($userPath -notlike "*$shimDir*") {
        $newPath = ($userPath.TrimEnd(';') + ';' + $shimDir).TrimStart(';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "    Added $shimDir to your User PATH."
        Write-Host "    Restart your terminal / agent so the new PATH takes effect." -ForegroundColor Yellow
    }
    # Make python3 usable for the remainder of this process too.
    $env:Path = "$shimDir;$env:Path"
}

# 3. Install Python dependencies ---------------------------------------------
Write-Step "Installing Python dependencies (youtube-transcript-api, yt-dlp)."
& $py -m pip install --upgrade youtube-transcript-api yt-dlp
if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)." }

# 4. Copy the skills into the agent's global skills dir ----------------------
$skillsRoot = if ($Agent -eq 'agents') {
    Join-Path $HOME '.agents\skills'
} else {
    Join-Path $HOME ".$Agent\skills"
}
New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null

foreach ($s in 'video-lens', 'video-lens-gallery') {
    $srcDir = Join-Path $repo "skills\$s"
    $dstDir = Join-Path $skillsRoot $s
    if (-not (Test-Path $srcDir)) { throw "Source skill not found: $srcDir" }
    if (Test-Path $dstDir) { Remove-Item $dstDir -Recurse -Force }
    Copy-Item $srcDir $dstDir -Recurse -Force
    Get-ChildItem $dstDir -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force
    Write-Step "Installed $s -> $dstDir"
}

Write-Host ""
Write-Step "Done. In your agent, run:  /video-lens <youtube-url>"
if (-not $python3Works) {
    Write-Host "Note: a 'python3' shim was just created — restart your agent first." -ForegroundColor Yellow
}
