#Requires -Version 5.1
<#
.SYNOPSIS
    Codex + HUD launcher for Windows
.DESCRIPTION
    Launches Codex CLI with a real-time HUD displayed in the terminal title bar.
    Usage: cxh [codex args...]
    Set $env:CXH_FULL_AUTO=1 to add --dangerously-bypass-approvals-and-sandbox
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs
)

$ErrorActionPreference = 'SilentlyContinue'

$CodexBin = if ($env:CODEX_BIN) { $env:CODEX_BIN } else { 'codex' }
$HudDir = Join-Path $env:USERPROFILE '.codex\hud'
$StatusScript = Join-Path $HudDir 'status.ps1'

# --- Dependency check ---
if (-not (Get-Command $CodexBin -ErrorAction SilentlyContinue)) {
    Write-Host "error: $CodexBin not found in PATH" -ForegroundColor Red
    exit 1
}

# --- Build codex command args ---
$allArgs = @()
if ($env:CXH_FULL_AUTO -eq '1') {
    $allArgs += '--dangerously-bypass-approvals-and-sandbox'
}
if ($CodexArgs) {
    $allArgs += $CodexArgs
}

# --- Clear HUD cache ---
$cachePath = Join-Path $HudDir '.cache'
if (Test-Path $cachePath) {
    Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
}

# --- Save original title ---
$originalTitle = $Host.UI.RawUI.WindowTitle

# --- Start HUD updater as background job ---
$hudJob = $null
if (Test-Path $StatusScript) {
    $hudJob = Start-Job -ScriptBlock {
        param($scriptPath, $originalTitle)
        while ($true) {
            try {
                $status = & $scriptPath 2>$null
                if ($status) {
                    $Host.UI.RawUI.WindowTitle = $status
                }
            }
            catch { }
            Start-Sleep -Seconds 5
        }
    } -ArgumentList $StatusScript, $originalTitle

    # Also update title in the main thread for immediate feedback
    $timer = New-Object System.Timers.Timer
    $timer.Interval = 5000
    $timer.AutoReset = $true

    $action = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        try {
            $s = & $using:StatusScript 2>$null
            if ($s) { $Host.UI.RawUI.WindowTitle = $s }
        }
        catch { }
    }
    $timer.Start()
}

# --- Run codex ---
try {
    & $CodexBin @allArgs
    $rc = $LASTEXITCODE
}
finally {
    # --- Cleanup ---
    if ($timer) {
        $timer.Stop()
        $timer.Dispose()
    }
    if ($action) {
        Unregister-Event -SourceIdentifier $action.Name -ErrorAction SilentlyContinue
    }
    if ($hudJob) {
        Stop-Job -Job $hudJob -ErrorAction SilentlyContinue
        Remove-Job -Job $hudJob -Force -ErrorAction SilentlyContinue
    }
    $Host.UI.RawUI.WindowTitle = $originalTitle
}

if ($null -ne $rc -and $rc -ne 0) {
    Write-Host "`n[codex exited (rc=$rc)]" -ForegroundColor Yellow
}
