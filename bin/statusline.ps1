#requires -Version 5.1
# Windows PowerShell port of statusline.sh — see that file for the reference behavior.

# Claude Code invokes this script with stdout piped (not a real console), so the
# encoding that matters is $OutputEncoding, not [Console]::OutputEncoding — Windows
# PowerShell 5.1 defaults $OutputEncoding to the legacy OEM/ASCII codepage, which
# silently mangles the Unicode glyphs below (│ ✍️ ◑ ● ○ ⟳ ⏱ ⚡) into "?" once piped.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8NoBom
try { [Console]::OutputEncoding = $utf8NoBom } catch { }
try {
    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    $stdout.AutoFlush = $true
    [Console]::SetOut($stdout)
} catch { }

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output "Claude"
    exit 0
}

try {
    $data = $rawInput | ConvertFrom-Json
} catch {
    Write-Output "Claude"
    exit 0
}

# ── Colors ──────────────────────────────────────────────
$esc = [char]27
$blue = "$esc[38;2;0;153;255m"
$orange = "$esc[38;2;255;176;85m"
$green = "$esc[38;2;0;175;80m"
$cyan = "$esc[38;2;86;182;194m"
$red = "$esc[38;2;255;85;85m"
$yellow = "$esc[38;2;230;200;0m"
$white = "$esc[38;2;220;220;220m"
$magenta = "$esc[38;2;180;140;255m"
$dim = "$esc[2m"
$reset = "$esc[0m"

$sep = " ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
function Get-ColorForPct {
    param([double]$Pct)
    if ($Pct -ge 90) { return $red }
    elseif ($Pct -ge 70) { return $yellow }
    elseif ($Pct -ge 50) { return $orange }
    else { return $green }
}

function Build-Bar {
    param([double]$Pct, [int]$Width)
    if ($Pct -lt 0) { $Pct = 0 }
    if ($Pct -gt 100) { $Pct = 100 }

    $filled = [math]::Floor($Pct * $Width / 100)
    $empty = $Width - $filled
    $barColor = Get-ColorForPct -Pct $Pct

    $filledStr = "".PadRight($filled, [char]0x25CF)
    $emptyStr = "".PadRight($empty, [char]0x25CB)

    return "${barColor}${filledStr}${dim}${emptyStr}${reset}"
}

function Format-EpochTime {
    param([Nullable[long]]$Epoch, [string]$Style)
    if (-not $Epoch -or $Epoch -eq 0) { return "" }

    try {
        $local = [DateTimeOffset]::FromUnixTimeSeconds($Epoch).ToLocalTime()
    } catch {
        return ""
    }

    switch ($Style) {
        "time" {
            return ($local.ToString("h:mmtt", [Globalization.CultureInfo]::InvariantCulture)).ToLower()
        }
        "datetime" {
            $datePart = $local.ToString("MMM d,", [Globalization.CultureInfo]::InvariantCulture).ToLower()
            $timePart = ($local.ToString("h:mmtt", [Globalization.CultureInfo]::InvariantCulture)).ToLower()
            return "$datePart $timePart"
        }
        default {
            return $local.ToString("MMM d", [Globalization.CultureInfo]::InvariantCulture).ToLower()
        }
    }
}

function ConvertFrom-Iso8601 {
    param([string]$IsoStr)
    if ([string]::IsNullOrWhiteSpace($IsoStr)) { return $null }

    try {
        $dto = [DateTimeOffset]::Parse(
            $IsoStr,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        )
        return $dto.ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

# ── Extract JSON data ───────────────────────────────────
$modelName = $data.model.display_name
if (-not $modelName) { $modelName = "Claude" }

$size = $data.context_window.context_window_size
if (-not $size -or $size -eq 0) { $size = 200000 }

$inputTokens = 0; if ($data.context_window.current_usage.input_tokens) { $inputTokens = $data.context_window.current_usage.input_tokens }
$cacheCreate = 0; if ($data.context_window.current_usage.cache_creation_input_tokens) { $cacheCreate = $data.context_window.current_usage.cache_creation_input_tokens }
$cacheRead = 0; if ($data.context_window.current_usage.cache_read_input_tokens) { $cacheRead = $data.context_window.current_usage.cache_read_input_tokens }
$current = $inputTokens + $cacheCreate + $cacheRead

$pctUsed = 0
if ($size -gt 0) { $pctUsed = [math]::Floor($current * 100 / $size) }

$effort = "default"
$settingsPath = Join-Path $HOME ".claude/settings.json"
if (Test-Path $settingsPath) {
    try {
        $settingsJson = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settingsJson.effortLevel) { $effort = $settingsJson.effortLevel }
    } catch { }
}

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Effort ──
$pctColor = Get-ColorForPct -Pct $pctUsed
$cwd = $data.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$dirName = Split-Path $cwd -Leaf

$gitBranch = ""
$gitDirty = ""
if (Get-Command git -ErrorAction SilentlyContinue) {
    git -C $cwd rev-parse --is-inside-work-tree *>$null
    if ($LASTEXITCODE -eq 0) {
        $gitBranch = (git -C $cwd symbolic-ref --short HEAD 2>$null)
        $statusOutput = git -C $cwd --no-optional-locks status --porcelain 2>$null
        if ($statusOutput) { $gitDirty = "*" }
    }
}

$sessionDuration = ""
$sessionStart = $data.session.start_time
if ($sessionStart) {
    $startEpoch = ConvertFrom-Iso8601 -IsoStr $sessionStart
    if ($startEpoch) {
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $elapsed = $nowEpoch - $startEpoch
        if ($elapsed -ge 3600) {
            $sessionDuration = "$([math]::Floor($elapsed / 3600))h$([math]::Floor(($elapsed % 3600) / 60))m"
        } elseif ($elapsed -ge 60) {
            $sessionDuration = "$([math]::Floor($elapsed / 60))m"
        } else {
            $sessionDuration = "${elapsed}s"
        }
    }
}

$skipPerms = ""
try {
    $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
    $parentCmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$parentId" -ErrorAction Stop).CommandLine
    if ($parentCmd -and $parentCmd -like "*--dangerously-skip-permissions*") { $skipPerms = "⚡  " }
} catch { }

$line1 = "${blue}${modelName}${reset}"
$line1 += $sep
$line1 += "✍️ ${pctColor}${pctUsed}%${reset}"
$line1 += $sep
$line1 += "${skipPerms}${cyan}${dirName}${reset}"
if ($gitBranch) {
    $line1 += " ${green}(${gitBranch}${red}${gitDirty}${green})${reset}"
}
if ($sessionDuration) {
    $line1 += $sep
    $line1 += "${dim}⏱ ${reset}${white}${sessionDuration}${reset}"
}
$line1 += $sep
switch ($effort) {
    "high" { $line1 += "${magenta}● ${effort}${reset}" }
    "medium" { $line1 += "${dim}◑ ${effort}${reset}" }
    "low" { $line1 += "${dim}◔ ${effort}${reset}" }
    default { $line1 += "${dim}◑ ${effort}${reset}" }
}

# ── Rate limits from stdin (primary) ───────────────────
$hasStdinRates = $false
$fiveHourPct = $null
$fiveHourResetEpoch = $null
$sevenDayPct = $null
$sevenDayResetEpoch = $null

if ($null -ne $data.rate_limits.five_hour.used_percentage) {
    $hasStdinRates = $true
    $fiveHourPct = [math]::Round([double]$data.rate_limits.five_hour.used_percentage)
    $fiveHourResetEpoch = $data.rate_limits.five_hour.resets_at
    if ($null -ne $data.rate_limits.seven_day.used_percentage) {
        $sevenDayPct = [math]::Round([double]$data.rate_limits.seven_day.used_percentage)
    }
    $sevenDayResetEpoch = $data.rate_limits.seven_day.resets_at
}

# ── Fallback: API call (cached) ────────────────────────
$tempRoot = $env:TEMP
if (-not $tempRoot) { $tempRoot = [System.IO.Path]::GetTempPath() }
$cacheDir = Join-Path $tempRoot "claude"
$cacheFile = Join-Path $cacheDir "statusline-usage-cache.json"
$cacheMaxAge = 60
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$usageData = $null
$extraEnabled = $false

if (-not $hasStdinRates) {
    $needsRefresh = $true

    if (Test-Path $cacheFile) {
        $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($cacheAge.TotalSeconds -lt $cacheMaxAge) {
            $needsRefresh = $false
            try { $usageData = Get-Content $cacheFile -Raw | ConvertFrom-Json } catch { }
        }
    }

    if ($needsRefresh) {
        $token = $env:CLAUDE_CODE_OAUTH_TOKEN
        if (-not $token) {
            $credsFile = Join-Path $HOME ".claude/.credentials.json"
            if (Test-Path $credsFile) {
                try {
                    $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
                    $token = $creds.claudeAiOauth.accessToken
                } catch { }
            }
        }

        if ($token) {
            try {
                $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -TimeoutSec 5 -Headers @{
                    "Accept"           = "application/json"
                    "Content-Type"     = "application/json"
                    "Authorization"    = "Bearer $token"
                    "anthropic-beta"   = "oauth-2025-04-20"
                    "User-Agent"       = "claude-code/2.1.34"
                }
                if ($response -and $response.five_hour) {
                    $usageData = $response
                    $response | ConvertTo-Json -Depth 10 | Set-Content $cacheFile
                }
            } catch { }
        }

        if (-not $usageData -and (Test-Path $cacheFile)) {
            try { $usageData = Get-Content $cacheFile -Raw | ConvertFrom-Json } catch { }
        }
    }

    if ($usageData) {
        if ($null -ne $usageData.five_hour.utilization) { $fiveHourPct = [math]::Round([double]$usageData.five_hour.utilization) }
        $fiveHourResetEpoch = ConvertFrom-Iso8601 -IsoStr $usageData.five_hour.resets_at
        if ($null -ne $usageData.seven_day.utilization) { $sevenDayPct = [math]::Round([double]$usageData.seven_day.utilization) }
        $sevenDayResetEpoch = ConvertFrom-Iso8601 -IsoStr $usageData.seven_day.resets_at
        $extraEnabled = [bool]$usageData.extra_usage.is_enabled
    }
} else {
    if (Test-Path $cacheFile) {
        try {
            $usageData = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $extraEnabled = [bool]$usageData.extra_usage.is_enabled
        } catch { }
    }
}

# ── Rate limit lines ────────────────────────────────────
$rateLines = ""
$barWidth = 10

if ($null -ne $fiveHourPct) {
    $fiveHourReset = Format-EpochTime -Epoch $fiveHourResetEpoch -Style "time"
    $fiveHourBar = Build-Bar -Pct $fiveHourPct -Width $barWidth
    $fiveHourPctColor = Get-ColorForPct -Pct $fiveHourPct
    $fiveHourPctFmt = "{0,3}" -f [int]$fiveHourPct

    $rateLines += "${white}current${reset} ${fiveHourBar} ${fiveHourPctColor}${fiveHourPctFmt}%${reset}"
    if ($fiveHourReset) { $rateLines += " ${dim}⟳${reset} ${white}${fiveHourReset}${reset}" }
}

if ($null -ne $sevenDayPct) {
    $sevenDayReset = Format-EpochTime -Epoch $sevenDayResetEpoch -Style "datetime"
    $sevenDayBar = Build-Bar -Pct $sevenDayPct -Width $barWidth
    $sevenDayPctColor = Get-ColorForPct -Pct $sevenDayPct
    $sevenDayPctFmt = "{0,3}" -f [int]$sevenDayPct

    if ($rateLines) { $rateLines += "`n" }
    $rateLines += "${white}weekly${reset}  ${sevenDayBar} ${sevenDayPctColor}${sevenDayPctFmt}%${reset}"
    if ($sevenDayReset) { $rateLines += " ${dim}⟳${reset} ${white}${sevenDayReset}${reset}" }
}

if ($extraEnabled -and $usageData) {
    $extraPct = 0; if ($usageData.extra_usage.utilization) { $extraPct = [math]::Round([double]$usageData.extra_usage.utilization) }
    $extraUsed = 0.0; if ($usageData.extra_usage.used_credits) { $extraUsed = [double]$usageData.extra_usage.used_credits / 100 }
    $extraLimit = 0.0; if ($usageData.extra_usage.monthly_limit) { $extraLimit = [double]$usageData.extra_usage.monthly_limit / 100 }
    $extraBar = Build-Bar -Pct $extraPct -Width $barWidth
    $extraPctColor = Get-ColorForPct -Pct $extraPct

    $today = Get-Date
    $nextMonth = (Get-Date -Year $today.Year -Month $today.Month -Day 1).AddMonths(1)
    $extraReset = $nextMonth.ToString("MMM d", [Globalization.CultureInfo]::InvariantCulture).ToLower()

    $extraUsedFmt = "{0:F2}" -f $extraUsed
    $extraLimitFmt = "{0:F2}" -f $extraLimit

    if ($rateLines) { $rateLines += "`n" }
    $rateLines += "${white}extra${reset}   ${extraBar} ${extraPctColor}`$${extraUsedFmt}${dim}/${reset}${white}`$${extraLimitFmt}${reset} ${dim}⟳${reset} ${white}${extraReset}${reset}"
}

# ── Output ──────────────────────────────────────────────
Write-Output $line1
if ($rateLines) {
    Write-Output ""
    Write-Output $rateLines
}
