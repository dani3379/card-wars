[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    # Skip the three gates that need a real framebuffer (for CI / a headless box).
    [switch]$SkipWindowed
)

# run_ui_gates.ps1 — the UI / feel gate set (2026-09-02).
#
# Sibling to run_safe_probes.ps1, NOT an extension of it, for two reasons:
#
#   1. run_safe_probes is the FAST pre-commit set (three probes, seconds each).
#      These eight run for minutes and would wreck that loop.
#   2. Three of them MEASURE PIXELS and therefore cannot run --headless. A
#      "CI-safe" set that silently needs a display is not CI-safe, so the display
#      requirement is declared per gate here and `-SkipWindowed` drops exactly
#      those three.
#
# The set exists because a gate nobody runs is not a gate. Eight were written on
# 2026-09-02 and four of them lived in no runner at all.
#
# `uiscale` (C32) joined the same day, and it is the only gate that changes the
# VIEWPORT. Every other one runs at the 1600x900 project canvas; the player can
# set UI Scale 60-100%, which divides the logical canvas (2667x1500 at 60%), so
# anything placed from a constant is wrong at four of the five settings offered
# and no other gate can see it.
#
# `alignment` (C30) joined on 2026-09-03. Its three siblings here judge a control
# against ITSELF — does the text fit, is anything painted over it, can the click
# reach it. It is the only one that judges a control against the ones laid out
# BESIDE it, which is the only way "that looks off" becomes a measurement.

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
    throw 'Godot was not found. Pass -GodotPath or set GODOT_BIN.'
}

$godot = Resolve-GodotExecutable -Requested $GodotPath

# Target is either a scene (run directly) or a .gd driven with --script.
# Windowed = needs a framebuffer because the gate reads pixels.
$specs = @(
    [pscustomobject]@{ Name = 'occlusion';      Target = 'res://tools/_probe_occlusion.gd';             Script = $true;  Windowed = $false; Sentinel = 'NOTHING BURIED';          Timeout = 900 },
    [pscustomobject]@{ Name = 'cfg_diff';       Target = 'res://tools/_probe_settings_differential.gd'; Script = $true;  Windowed = $false; Sentinel = 'ALL AGREE';               Timeout = 900 },
    # The scene wipe parks a full-rect MOUSE_FILTER_STOP overlay at z_index 1000
    # over the entire game and is responsible for taking it away again. When that
    # has gone wrong before, the result was a black screen that ate every click
    # with no way out — the worst bug this codebase can ship, on its single most
    # travelled code path, and none of it judgeable by eye in CI. So the gate
    # asserts the state machine: the cover appears, the wipe claims the reveal,
    # a scene's own fade_in stands down instead of stacking a second cover, and
    # THE COVER ALWAYS LIFTS.
    [pscustomobject]@{ Name = 'transition';     Target = 'res://tools/_probe_transition.tscn';         Script = $false; Windowed = $false; Sentinel = 'THE COVER ALWAYS LIFTS';  Timeout = 300 },
    [pscustomobject]@{ Name = 'input_reach';    Target = 'res://tools/_probe_input_reach.gd';           Script = $true;  Windowed = $false; Sentinel = 'EVERY CONTROL REACHABLE'; Timeout = 900 },
    [pscustomobject]@{ Name = 'alignment';      Target = 'res://tools/_probe_alignment.gd';             Script = $true;  Windowed = $false; Sentinel = 'EVERYTHING LINES UP';     Timeout = 900 },
    [pscustomobject]@{ Name = 'uiscale';        Target = 'res://tools/_probe_uiscale.gd';               Script = $true;  Windowed = $false; Sentinel = 'EVERY SCALE AGREES';      Timeout = 900 },
    [pscustomobject]@{ Name = 'popup_layering'; Target = 'res://tools/_probe_popup_layering.gd';        Script = $true;  Windowed = $false; Sentinel = '[popup] PASS';            Timeout = 300 },
    [pscustomobject]@{ Name = 'spring';         Target = 'res://tools/_probe_spring.tscn';              Script = $false; Windowed = $false; Sentinel = '[spring] PASS';           Timeout = 300 },
    # card_pose (2026-09-17) is the only gate that asks whether a board token
    # comes back to REST. Every other feel gate here judges a settled screen or a
    # single beat in isolation; this one overlaps two beats on one card the way a
    # clash does and then checks the card's position, scale and tint against its
    # own rest. It found four defects on its first run, all of the same shape — a
    # beat sampling a property another beat was mid-way through writing — the
    # worst of which left a body struck four times at 1.405 x 0.729 of its size,
    # kept for the rest of the fight. Headless: it measures node state, not pixels.
    [pscustomobject]@{ Name = 'card_pose';      Target = 'res://tools/_probe_card_pose.tscn';           Script = $false; Windowed = $false; Sentinel = 'PROBE PASS: card_pose';   Timeout = 300 },
    [pscustomobject]@{ Name = 'boil';           Target = 'res://tools/_probe_boil.tscn';                Script = $false; Windowed = $true;  Sentinel = '[boil] PASS';             Timeout = 300 },
    [pscustomobject]@{ Name = 'smear';          Target = 'res://tools/_probe_smear.tscn';               Script = $false; Windowed = $true;  Sentinel = '[smear] PASS';            Timeout = 300 },
    [pscustomobject]@{ Name = 'modal_scrim';    Target = 'res://tools/_probe_modal_scrim.tscn';         Script = $false; Windowed = $true;  Sentinel = '[scrim] PASS';            Timeout = 300 }
)

# ERRORS PRINTED AFTER THE VERDICT ARE TEARDOWN NOISE.
#
# This replaced a hand-written list of benign strings, which was the wrong shape:
# the list has to be extended every time Godot finds a new way to complain on the
# way out, and it was already wrong once (a `Parse Error` raised while the engine
# reloaded the main scene at `cleanup` failed the smear gate, which had passed).
#
# The position of an error carries the information. Everything a gate says before
# its sentinel is the run; everything after is Godot shutting down. So the error
# scan is applied ONLY to the text preceding the sentinel — and when the sentinel
# is missing the whole log is scanned, because then there is no verdict to trust.

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$probeRoot = Join-Path $tempBase ('bm-ui-gates-' + [Guid]::NewGuid().ToString('N'))
# Same APPDATA isolation as run_safe_probes: Godot derives user:// from APPDATA
# on Windows and ignores GODOT_USER_HOME, so without this a gate run overwrites
# the player's real saves.
$userHome = Join-Path $probeRoot 'user-home'
$null = New-Item -ItemType Directory -Path $userHome -Force
$previousUserHome = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$env:APPDATA = $userHome
$failed = $false
$ran = 0
$skipped = 0

try {
    foreach ($spec in $specs) {
        if ($spec.Windowed -and $SkipWindowed) {
            Write-Host ('[ui-gates] SKIP  {0} (needs a display)' -f $spec.Name)
            $skipped = $skipped + 1
            continue
        }
        $stdoutPath = Join-Path $probeRoot ($spec.Name + '.stdout.log')
        $stderrPath = Join-Path $probeRoot ($spec.Name + '.stderr.log')

        $headlessFlag = ''
        if (-not $spec.Windowed) { $headlessFlag = '--headless ' }
        $scriptFlag = ''
        if ($spec.Script) { $scriptFlag = '--script ' }
        $argumentString = '{0}--path "{1}" {2}"{3}"' -f `
            $headlessFlag, $projectRoot, $scriptFlag, $spec.Target

        Write-Host ('[ui-gates] START {0}' -f $spec.Name)
        $process = Start-Process -FilePath $godot -ArgumentList $argumentString `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        # Cache the handle while the process lives, or ExitCode reads back empty
        # on PowerShell 5.1 — the same trap run_safe_probes documents.
        $null = $process.Handle
        if (-not $process.WaitForExit($spec.Timeout * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
            Write-Error ('[ui-gates] TIMEOUT {0} after {1}s' -f $spec.Name, $spec.Timeout) -ErrorAction Continue
            $failed = $true
            continue
        }
        $ran = $ran + 1

        $stdout = ''
        if (Test-Path -LiteralPath $stdoutPath) {
            $stdout = Get-Content -LiteralPath $stdoutPath -Raw
        }
        $stderr = ''
        if (Test-Path -LiteralPath $stderrPath) {
            $stderr = Get-Content -LiteralPath $stderrPath -Raw
        }
        if ($null -eq $stdout) { $stdout = '' }
        if ($null -eq $stderr) { $stderr = '' }
        $combined = $stdout + [Environment]::NewLine + $stderr

        # A NON-ZERO EXIT IS A FAILURE AGAIN, including a crash during teardown.
        #
        # Between 2026-09-02 and 2026-09-03 this block carried a "PASS*" status:
        # `_probe_occlusion`, `_probe_input_reach` and `_probe_settings_differential`
        # printed correct verdicts and then segfaulted in Godot's exit cleanup, so
        # a sentinel plus a known crash code was treated as a pass. That was a
        # workaround for a real bug and it has been removed with the bug.
        #
        # The cause was suspended coroutines. Every bake path parks on
        # `RenderingServer.frame_post_draw`, which never fires headless, so the
        # first bake held CardTextureCache's `_bake_busy` forever and each later
        # caller queued behind it: 143 leaked GDScriptFunctionStates that Godot
        # dereferenced after tearing down the script language. Fixed at the awaits
        # themselves (CardTextureCache._can_bake, MapTerrain._bake_via_clone) plus
        # a tween bound to a freed node in Event._shell_swap.
        #
        # Keep it strict. The crash was NOT reliably after the verdict —
        # `_probe_settings_differential` could die between its "64 screen state(s)"
        # line and the "ALL AGREE" on the next one, because redirected stdout is
        # block-buffered and a crash eats the tail. A tolerated crash code is
        # therefore a tolerated MISSING VERDICT, which is exactly what a gate must
        # never be green on.
        $hasSentinel = $combined.Contains([string]$spec.Sentinel)

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($process.ExitCode -ne 0) {
            $reasons.Add('exit code ' + $process.ExitCode)
        }
        if (-not $hasSentinel) {
            $reasons.Add('missing sentinel: ' + $spec.Sentinel)
        }
        $scanText = $combined
        if ($hasSentinel) {
            $scanText = $combined.Substring(0, $combined.IndexOf([string]$spec.Sentinel))
        }
        foreach ($line in ($scanText -split "`r?`n")) {
            if ($line -notmatch '(?i)^\s*(SCRIPT ERROR:|ERROR:|Parse Error:)') { continue }
            $reasons.Add('unexpected error before the verdict: ' + $line.Trim())
            break
        }
        if ($reasons.Count -gt 0) {
            $failed = $true
            Write-Host $combined
            Write-Error ('[ui-gates] FAIL {0}: {1}' -f $spec.Name, ($reasons -join '; ')) -ErrorAction Continue
        } else {
            Write-Host ('[ui-gates] PASS  {0}' -f $spec.Name)
        }
    }
} finally {
    if ($null -eq $previousUserHome) {
        Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
    } else {
        $env:APPDATA = $previousUserHome
    }
    $resolvedProbeRoot = [IO.Path]::GetFullPath($probeRoot)
    $safeLeaf = Split-Path -Leaf $resolvedProbeRoot
    $insideTemp = $resolvedProbeRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)
    if ($insideTemp -and $safeLeaf.StartsWith('bm-ui-gates-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedProbeRoot -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning ('Refusing to remove unexpected probe path: ' + $resolvedProbeRoot)
    }
}

Write-Host ('[ui-gates] {0} ran, {1} skipped' -f $ran, $skipped)
if ($failed) {
    exit 1
}
Write-Host '[ui-gates] ALL PASS'
exit 0
