#Requires -Version 5.1
<#
.SYNOPSIS
    Codex HUD Status Bar Generator for Windows
.DESCRIPTION
    Parses Codex CLI log files and outputs a formatted status string.
    Used by launch.ps1 to update the terminal title bar.
#>

$ErrorActionPreference = 'SilentlyContinue'

$Config = Join-Path $env:USERPROFILE '.codex\config.toml'
$Log = Join-Path $env:USERPROFILE '.codex\log\codex-tui.log'
$Cache = Join-Path $env:USERPROFILE '.codex\hud\.cache'
$SessDir = Join-Path $env:USERPROFILE '.codex\sessions'

$MAX_MODEL = 22
$MAX_BRANCH = 16

# --- Helper functions ---
function Truncate-String {
    param([string]$s, [int]$n)
    if ($s.Length -gt $n) {
        return $s.Substring(0, $n - 1) + '~'
    }
    return $s
}

function Parse-ConfigValue {
    param([string]$key)
    if (-not (Test-Path $Config)) { return '' }
    $content = Get-Content $Config -ErrorAction SilentlyContinue
    foreach ($line in $content) {
        if ($line -match "^\s*$key\s*=\s*`"?([^`"]*)`"?") {
            return $Matches[1].Trim()
        }
    }
    return ''
}

function Format-K {
    param([long]$n)
    if ($n -ge 1000000) {
        return '{0:F1}M' -f ($n / 1000000)
    }
    elseif ($n -ge 1000) {
        return '{0}K' -f [math]::Floor($n / 1000)
    }
    elseif ($n -gt 0) {
        return "$n"
    }
    return '0'
}

# --- Read model from config ---
$Model = Parse-ConfigValue 'model'
$Effort = Parse-ConfigValue 'model_reasoning_effort'
$Model = Truncate-String ($Model, '?')[0..0][0] $MAX_MODEL
if (-not $Model -or $Model -eq '') { $Model = '?' }
$Model = Truncate-String $Model $MAX_MODEL

# --- Cache check ---
$LogMtime = 0
if (Test-Path $Log) {
    $LogMtime = (Get-Item $Log).LastWriteTimeUtc.Ticks
}

$CacheHit = $false
$CachedLine = ''
if (Test-Path $Cache) {
    $cacheContent = Get-Content $Cache -ErrorAction SilentlyContinue
    if ($cacheContent -and $cacheContent.Count -ge 2) {
        $cachedMtime = $cacheContent[0].Trim()
        if ($cachedMtime -eq "$LogMtime") {
            $CachedLine = $cacheContent[1].Trim()
            $CacheHit = $true
        }
    }
}

$TotalTokens = 0; $EstTokens = 0; $CompactLimit = 244800
$ExecN = 0; $PatchN = 0; $ShellN = 0; $McpN = 0; $CompactCnt = 0

if ($CacheHit -and $CachedLine) {
    $parts = $CachedLine -split '\|'
    if ($parts.Count -ge 8) {
        $TotalTokens  = [long]$parts[0]
        $EstTokens    = [long]$parts[1]
        $CompactLimit = [long]$parts[2]
        $ExecN        = [int]$parts[3]
        $PatchN       = [int]$parts[4]
        $ShellN       = [int]$parts[5]
        $McpN         = [int]$parts[6]
        $CompactCnt   = [int]$parts[7]
    }
}
elseif (Test-Path $Log) {
    # Read last 5000 lines of log
    $logLines = Get-Content $Log -Tail 5000 -ErrorAction SilentlyContinue

    if ($logLines) {
        # Find last thread_id
        $lastTid = ''
        $tidLines = $logLines | Select-String -Pattern 'thread_id=([0-9a-f-]+)' | Select-Object -Last 1
        if ($tidLines) {
            $lastTid = $tidLines.Matches[0].Groups[1].Value
        }

        foreach ($line in $logLines) {
            # Parse token usage
            if ($line -match 'total_usage_tokens=(\d+)') {
                $TotalTokens = [long]$Matches[1]
            }
            if ($line -match 'estimated_token_count=Some\((\d+)\)') {
                $EstTokens = [long]$Matches[1]
            }
            if ($line -match 'auto_compact_limit=(\d+)') {
                $CompactLimit = [long]$Matches[1]
            }

            # Count compaction events
            if ($line -match 'ContextCompacted') {
                $CompactCnt++
            }

            # Count tool calls for current thread
            if ($lastTid -and $line -match [regex]::Escape($lastTid) -and $line -match 'ToolCall:') {
                if ($line -match 'ToolCall:\s*exec_command') { $ExecN++ }
                elseif ($line -match 'ToolCall:\s*apply_patch') { $PatchN++ }
                elseif ($line -match 'ToolCall:\s*shell_command') { $ShellN++ }
                elseif ($line -match 'ToolCall:\s*(mcp_|omx_)') { $McpN++ }
            }
        }
    }

    if ($CompactLimit -le 0) { $CompactLimit = 244800 }

    # Write cache
    $cacheDir = Split-Path $Cache -Parent
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    "$LogMtime" | Out-File -FilePath $Cache -Encoding utf8 -NoNewline
    "`n$TotalTokens|$EstTokens|$CompactLimit|$ExecN|$PatchN|$ShellN|$McpN|$CompactCnt" | Out-File -FilePath $Cache -Append -Encoding utf8 -NoNewline
}

# --- Format total tokens ---
if ($TotalTokens -ge 1000000) {
    $TokenFmt = '{0:F1}M' -f ($TotalTokens / 1000000)
}
elseif ($TotalTokens -ge 1000) {
    $TokenFmt = '{0}K' -f [math]::Floor($TotalTokens / 1000)
}
elseif ($TotalTokens -gt 0) {
    $TokenFmt = "$TotalTokens"
}
else {
    $TokenFmt = '--'
}

# --- Context window ---
$CtxUsed = Format-K $EstTokens
$CtxWindow = [long]($CompactLimit * 10 / 9)
$CtxLimit = Format-K $CtxWindow

if ($CtxWindow -gt 0) {
    $CtxPct = [int]($EstTokens * 100 / $CtxWindow)
}
else {
    $CtxPct = 0
}
if ($CtxPct -gt 100) { $CtxPct = 100 }

# --- Context bar (text-based for terminal title) ---
$W = 10
$F = [int]($CtxPct * $W / 100)
if ($CtxPct -gt 0 -and $F -eq 0) { $F = 1 }
$E = $W - $F

$filled = [string]::new([char]0x2588, $F)   # █
$empty  = [string]::new([char]0x2591, $E)    # ░
$bar = "$filled$empty"

# --- Git branch ---
$Branch = '?'
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitBranch = git branch --show-current 2>$null
    if ($gitBranch) { $Branch = $gitBranch.Trim() }
}
$Branch = Truncate-String $Branch $MAX_BRANCH

# --- Session duration ---
$Dur = '--'
if (Test-Path $SessDir) {
    $latestFile = Get-ChildItem -Path $SessDir -Recurse -Filter 'rollout*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestFile) {
        $fname = $latestFile.Name
        if ($fname -match '(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})') {
            $dtStr = "$($Matches[1]) $($Matches[2]):$($Matches[3]):$($Matches[4])"
            try {
                $startTime = [datetime]::ParseExact($dtStr, 'yyyy-MM-dd HH:mm:ss', $null)
                $elapsed = (Get-Date) - $startTime
                if ($elapsed.TotalSeconds -lt 60) {
                    $Dur = '<1m'
                }
                elseif ($elapsed.TotalSeconds -lt 3600) {
                    $Dur = '{0}m' -f [math]::Floor($elapsed.TotalMinutes)
                }
                else {
                    $Dur = '{0}h{1}m' -f [math]::Floor($elapsed.TotalHours), ($elapsed.Minutes)
                }
            }
            catch {
                # Fall back to file creation time
                $elapsed = (Get-Date) - $latestFile.CreationTime
                if ($elapsed.TotalSeconds -gt 0 -and $elapsed.TotalSeconds -lt 86400) {
                    if ($elapsed.TotalSeconds -lt 60) { $Dur = '<1m' }
                    elseif ($elapsed.TotalSeconds -lt 3600) { $Dur = '{0}m' -f [math]::Floor($elapsed.TotalMinutes) }
                    else { $Dur = '{0}h{1}m' -f [math]::Floor($elapsed.TotalHours), ($elapsed.Minutes) }
                }
            }
        }
    }
}

# --- Tool counts ---
$ToolTotal = $ExecN + $PatchN + $ShellN + $McpN
$Tools = ''
if ($ToolTotal -gt 0) {
    $toolParts = @()
    if ($ExecN -gt 0)  { $toolParts += "e$ExecN" }
    if ($PatchN -gt 0) { $toolParts += "p$PatchN" }
    if ($ShellN -gt 0) { $toolParts += "s$ShellN" }
    if ($McpN -gt 0)   { $toolParts += "m$McpN" }
    $Tools = $toolParts -join ' '
    if ($CompactCnt -gt 0) { $Tools += " c$CompactCnt" }
}

# --- Build output (plain text for terminal title) ---
$sep = ' | '
$output = "codex $Model"
if ($Effort) { $output += " $Effort" }
$output += "$sep$bar ${CtxUsed}/${CtxLimit} ${CtxPct}%"
$output += "$sep${TokenFmt} tok"
$output += "$sep$Branch"
$output += "$sep$Dur"
if ($Tools) { $output += "$sep$Tools" }

Write-Output $output
