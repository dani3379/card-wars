[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    # One wall-clock budget for the pilot itself; the process timeout sits above
    # it so a genuine HANG is still distinguishable from a full budget.
    [ValidateRange(30, 3600)]
    [int]$Seconds = 400,
    [int]$Seed = 20260915,
    [int]$MaxNodes = 40,
    # Windowed is the honest run: three of the game's layout systems only settle
    # against a real display, and only windowed can save a PNG of a finding.
    [switch]$Windowed,
    [switch]$Shots,
    [switch]$Coach,
    [switch]$Slow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

function Resolve-GodotExecutable {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    foreach ($name in @(
        'godot4_console.exe', 'godot4.exe', 'godot.exe',
        'godot4_console', 'godot4', 'godot')) {
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $command -and
                -not [string]::IsNullOrWhiteSpace($command.Path)) {
            return $command.Path
        }
    }
    if (Test-Path 'D:\games\Godot_v4.6.2-stable_win64.exe') {
        return 'D:\games\Godot_v4.6.2-stable_win64.exe'
    }
    throw 'Godot was not found. Pass -GodotPath or set GODOT_BIN.'
}

$godot = Resolve-GodotExecutable -Requested $GodotPath

$godotArgs = @()
if (-not $Windowed) { $godotArgs += '--headless' }
$godotArgs += @('--path', $projectRoot, 'res://tools/_probe_pilot.tscn', '--')
$godotArgs += "--max-sec=$Seconds"
$godotArgs += "--seed=$Seed"
$godotArgs += "--max-nodes=$MaxNodes"
if ($Shots)  { $godotArgs += '--shots' }
if ($Coach)  { $godotArgs += '--coach' }
if ($Slow)   { $godotArgs += '--slow' }

Write-Host "[pilot] $godot $($godotArgs -join ' ')"
$outPath = Join-Path $scriptDir '_pilot_run.log'
$errPath = Join-Path $scriptDir '_pilot_run.err.log'

# Start-Process rather than `& $godot ... *> file`, for two PS 5.1 reasons:
# redirecting a native exe's stderr inline wraps every line in a NativeCommandError
# (and with $ErrorActionPreference='Stop' that THROWS on a clean exit code 0), and
# `*>` left the log empty here. Godot's SCRIPT ERROR lines go to stderr, so they
# must be captured - they are half of this runner's value.
$quoted = $godotArgs | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
}
Start-Process -FilePath $godot -ArgumentList $quoted -NoNewWindow -Wait `
    -RedirectStandardOutput $outPath -RedirectStandardError $errPath | Out-Null

# @(...) on every read: under `Set-StrictMode -Version Latest` a scalar has no
# .Count and a missing file reads as $null, so an unwrapped Get-Content throws
# "The property 'Count' cannot be found" instead of reporting the run.
# -Encoding UTF8 is not optional: Godot writes UTF-8 and PS 5.1's Get-Content
# defaults to the system ANSI codepage, which turns the report's box-drawing rules
# and the finding marker into mojibake.
$log = @()
if (Test-Path -LiteralPath $outPath) {
    $log += @(Get-Content -LiteralPath $outPath -Encoding UTF8)
}
if (Test-Path -LiteralPath $errPath) {
    $log += @(Get-Content -LiteralPath $errPath -Encoding UTF8)
}

$log | Write-Host

# -- THE SECOND ORACLE ----------------------------------------------------
# The pilot reports what it could not DO. This reports what the game said while
# it was doing it. A GDScript runtime error does not raise, does not stop the
# game and does not change the exit code - it prints and the function ABORTS
# where it stands, so an animation stops halfway with no other symptom. A long
# real play session is the only thing in this harness that surfaces them, and
# they are worth more than most of the pilot's own findings.
#
# Pilot-side frames are excluded on purpose: a bug in _probe_pilot.gd is not a
# bug in the game, and mixing them is how a harness starts accusing the product.
$gameErrors = @()
for ($i = 0; $i -lt $log.Count; $i++) {
    if ($log[$i] -notmatch 'SCRIPT ERROR') { continue }
    $where = ''
    for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $log.Count); $j++) {
        if ($log[$j] -match 'at:\s*(.+)$') { $where = $Matches[1].Trim(); break }
    }
    if ($where -match '_probe_pilot\.gd') { continue }
    $gameErrors += ("{0}  ||  {1}" -f $log[$i].Trim(), $where)
}

$summary = $log | Where-Object { $_ -match '^PILOT: ' } | Select-Object -Last 1

Write-Host ''
Write-Host '---------------- RUNNER VERDICT ----------------'
if ($null -eq $summary) {
    Write-Host '[pilot] NO REPORT - the pilot never finished. That is a HANG, not a' -ForegroundColor Red
    Write-Host '        pass: check the tail of the log above.' -ForegroundColor Red
    exit 2
}
Write-Host "[pilot] $summary"

if ($gameErrors.Count -gt 0) {
    $grouped = @($gameErrors | Group-Object | Sort-Object Count -Descending)
    $header = "[pilot] {0} GAME-SIDE SCRIPT ERRORS ({1} distinct):" -f $gameErrors.Count, $grouped.Count
    Write-Host $header -ForegroundColor Red
    foreach ($g in $grouped) {
        Write-Host ("   x{0,-4} {1}" -f $g.Count, $g.Name) -ForegroundColor Red
    }
} else {
    Write-Host '[pilot] no game-side script errors'
}

# Findings are LEADS, not gate failures - this is a bug finder, and a run that
# stops on budget has not proved anything about what it never reached. Exit 1
# only when the game actually threw.
if ($gameErrors.Count -gt 0) { exit 1 }
exit 0
