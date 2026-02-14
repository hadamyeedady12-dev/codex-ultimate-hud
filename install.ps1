#Requires -Version 5.1
<#
.SYNOPSIS
    codex-ultimate-hud Windows installer
.DESCRIPTION
    Installs codex-ultimate-hud for Windows (PowerShell).
    Usage: irm https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$HudDir = Join-Path $env:USERPROFILE '.codex\hud'
$Repo = 'https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main'

Write-Host '==> Installing codex-ultimate-hud (Windows)...' -ForegroundColor Cyan
Write-Host ''

# --- Dependency check ---
$missing = @()
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    $missing += 'codex (npm install -g @openai/codex)'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $missing += 'git (https://git-scm.com/)'
}
if ($missing.Count -gt 0) {
    Write-Host 'error: missing dependencies:' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# --- Create HUD directory ---
if (-not (Test-Path $HudDir)) {
    New-Item -ItemType Directory -Path $HudDir -Force | Out-Null
}

Write-Host '==> Downloading HUD files...'

$files = @('status.ps1', 'launch.ps1')
foreach ($f in $files) {
    $url = "$Repo/$f"
    $dest = Join-Path $HudDir $f
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Write-Host "    downloaded $f" -ForegroundColor Green
    }
    catch {
        Write-Host "error: failed to download $f from $url" -ForegroundColor Red
        exit 1
    }
}

# Also download the bash files for WSL users
$bashFiles = @('status.sh', 'launch.sh', 'tmux.conf')
foreach ($f in $bashFiles) {
    $url = "$Repo/$f"
    $dest = Join-Path $HudDir $f
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    catch {
        # Non-fatal for Windows-native users
    }
}

# --- Checksum verification (PowerShell files) ---
$sumsUrl = "$Repo/sha256sums.txt"
try {
    $sumsContent = (Invoke-WebRequest -Uri $sumsUrl -UseBasicParsing).Content
    Write-Host '==> Verifying file integrity...'
    $fail = $false
    foreach ($line in $sumsContent -split "`n") {
        $line = $line.Trim()
        if (-not $line) { continue }
        $parts = $line -split '\s+', 2
        $expectedHash = $parts[0]
        $fname = $parts[1]
        $filePath = Join-Path $HudDir $fname
        if (Test-Path $filePath) {
            $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -ne $expectedHash) {
                Write-Host "error: checksum mismatch for $fname" -ForegroundColor Red
                $fail = $true
            }
        }
    }
    if ($fail) {
        Write-Host 'error: integrity check failed. Files may have been tampered with.' -ForegroundColor Red
        exit 1
    }
    Write-Host '    checksums OK' -ForegroundColor Green
}
catch {
    Write-Host 'warning: could not fetch checksums, skipping verification' -ForegroundColor Yellow
}

# --- Add PowerShell function/alias ---
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$launchPath = Join-Path $HudDir 'launch.ps1'
$aliasLine = "function cxh { & '$launchPath' @args }"

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -and $profileContent -match 'function cxh') {
    Write-Host "==> 'cxh' function already exists in $PROFILE (not modified)"
}
else {
    Add-Content -Path $PROFILE -Value "`n# codex-ultimate-hud: one-command launcher"
    Add-Content -Path $PROFILE -Value $aliasLine
    Write-Host "==> Added 'cxh' function to $PROFILE" -ForegroundColor Green
}

Write-Host ''
Write-Host '  Done! Restart PowerShell or run: . $PROFILE' -ForegroundColor Green
Write-Host ''
Write-Host '  Usage:'
Write-Host '    cxh                       # Launch Codex with HUD'
Write-Host '    cxh -m gpt-5.3            # Pass any codex args'
Write-Host '    $env:CXH_FULL_AUTO=1; cxh # Enable full-auto mode'
Write-Host ''
Write-Host '  Made by AI영끌맨' -ForegroundColor Cyan
