[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateRange(5, 3600)]
    [int]$TimeoutSeconds = 180
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
    throw 'Godot was not found. Pass -GodotPath or set GODOT_BIN.'
}

$godot = Resolve-GodotExecutable -Requested $GodotPath
$specs = @(
    [pscustomobject]@{
        Name = 'parsecheck'
        Scene = 'res://tools/_probe_parsecheck.tscn'
        Sentinel = 'PROBE PASS: parsecheck'
    },
    [pscustomobject]@{
        Name = 'copy_lint'
        Scene = 'res://tools/_probe_copy_lint.tscn'
        Sentinel = 'PROBE PASS: copy_lint'
    },
    [pscustomobject]@{
        Name = 'event_art'
        Scene = 'res://tools/_probe_event_art.tscn'
        Sentinel = 'PROBE PASS: event_art'
    },
    # Cheap enough for the pre-commit loop (~2s, pure data + settings) and it
    # guards a failure mode nothing else can see: a lesson id quoted at a call
    # site but absent from TutorialDB does not error, does not warn, and reads as
    # "this player has already been taught it" forever. Its slower sibling,
    # _probe_tutorial_live, boots a real fight and belongs with the UI gates.
    [pscustomobject]@{
        Name = 'tutorial'
        Scene = 'res://tools/_probe_tutorial.tscn'
        Sentinel = 'PROBE PASS: tutorial'
    },
    # C34 (2026-09-19). Static, seconds, and it guards the failure mode that has
    # produced almost every red line in this suite's history: a probe pinning a
    # balance number as a literal. The 2026-09-19 sweep found 8 failing checks
    # across 4 gates and ALL 8 were this -- a rebalance moved five cards and the
    # mechanics were all correct. Cheap enough for the pre-commit loop, and the
    # thing it prevents is a red line nobody believes, which is what trains people
    # to stop running the suite at all.
    #
    # Runs with --script (it extends SceneTree, so it cannot be a scene root).
    [pscustomobject]@{
        Name = 'fixture_pins'
        Scene = 'res://tools/_probe_fixture_pins.gd'
        Script = $true
        Sentinel = '[pins] PASS'
    }
    # NOTE: `_probe_resolver_sweep` is deliberately NOT here, for a reason worth
    # stating. Its oracle is stderr, scored by tools/_score_resolver_sweep.sh --
    # the probe itself prints PASS even when the game is broken (proven by its
    # mutant run). Adding it to a SENTINEL-based runner would install exactly the
    # fake-green gate this session just removed from _probe_field_grants. It also
    # boots a real Combat scene 161 times, which is minutes, not seconds.
    # NOTE: `_probe_transition` is deliberately NOT here. It boots a real scene
    # and so emits Godot's usual exit-time noise ("resources still in use",
    # "ObjectDB instances leaked"), which this runner treats as a failure by
    # design — that strictness is what makes the pre-commit set trustworthy. It
    # lives in run_ui_gates.ps1, which tolerates exactly that named list for
    # exactly this reason: every gate there builds scenes.
)

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$probeRoot = Join-Path $tempBase (
    'burning-meadow-probes-' + [Guid]::NewGuid().ToString('N'))
# NOTE (2026-07-28): this used to set GODOT_USER_HOME, which Godot does NOT
# read on Windows — it derives user:// from %APPDATA%. The isolation was fake,
# and probe runs were writing the player's real run_*.save / meta.save. Proven
# empirically: the scratch dir stayed empty while the live saves changed.
$userHome = Join-Path $probeRoot 'user-home'
$null = New-Item -ItemType Directory -Path $userHome
$previousUserHome = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$env:APPDATA = $userHome
$failed = $false

try {
    foreach ($spec in $specs) {
        $stdoutPath = Join-Path $probeRoot ($spec.Name + '.stdout.log')
        $stderrPath = Join-Path $probeRoot ($spec.Name + '.stderr.log')
        # A .tscn runs as a SCENE (so autoload names resolve); a SceneTree-derived
        # .gd must be handed to --script, where it cannot be a scene root at all.
        $isScript = ($spec.PSObject.Properties.Name -contains 'Script') -and $spec.Script
        if ($isScript) {
            $argumentString = '--headless --path "{0}" --script "{1}"' -f $projectRoot, $spec.Scene
        } else {
            $argumentString = '--headless --path "{0}" "{1}"' -f $projectRoot, $spec.Scene
        }
        Write-Host ('[probe-runner] START {0}' -f $spec.Name)
        $process = Start-Process -FilePath $godot -ArgumentList $argumentString -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        # Touching .Handle caches the process handle while the process is still
        # alive. Without it, Windows PowerShell 5.1 returns a -PassThru object
        # whose .ExitCode reads back EMPTY after exit, so every probe was
        # reported as "FAIL: exit code " with no number — including probes that
        # had printed their PASS sentinel (found 2026-07-28).
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
            Write-Error ('[probe-runner] TIMEOUT {0} after {1}s' -f $spec.Name, $TimeoutSeconds) -ErrorAction Continue
            $failed = $true
            continue
        }
        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath -Raw
        } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw
        } else { '' }
        $combined = $stdout + [Environment]::NewLine + $stderr
        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($process.ExitCode -ne 0) {
            $reasons.Add('exit code ' + $process.ExitCode)
        }
        if (-not $combined.Contains([string]$spec.Sentinel)) {
            $reasons.Add('missing sentinel: ' + $spec.Sentinel)
        }
        if ($combined -match '(?im)^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:)') {
            $reasons.Add('Godot emitted an unexpected error')
        }
        if ($reasons.Count -gt 0) {
            $failed = $true
            Write-Host $combined
            Write-Error ('[probe-runner] FAIL {0}: {1}' -f $spec.Name, ($reasons -join '; ')) -ErrorAction Continue
        } else {
            Write-Host ('[probe-runner] PASS {0}' -f $spec.Name)
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
    $insideTemp = $resolvedProbeRoot.StartsWith(
        $tempBase, [StringComparison]::OrdinalIgnoreCase)
    if ($insideTemp -and $safeLeaf.StartsWith(
            'burning-meadow-probes-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedProbeRoot -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning (
            'Refusing to remove unexpected probe path: ' + $resolvedProbeRoot)
    }
}

if ($failed) {
    exit 1
}
Write-Host '[probe-runner] ALL PASS'
exit 0
