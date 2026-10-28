#Requires -Version 5.1
<#
.SYNOPSIS
    Automated smoke test: starts the game the way a player would and checks that it
    - starts without admin rights,
    - gets past the System Checker,
    - plays the opening video WITH sound,
    - reaches the main menu without crashing.
    Screenshots of the game window are saved to tests\logs\<timestamp>.

    The game takes over the screen for ~30 seconds. Don't touch mouse/keyboard while it runs.
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [int]$MenuWaitSeconds = 20,
    # For testing a copy that has no registry compat entry, e.g. 'WINXPSP3 RunAsInvoker'.
    [string]$CompatLayer
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\gamedriver.ps1')

$GameDir = Resolve-GameDir -GameDir $GameDir
$out = Join-Path $PSScriptRoot ("logs\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $out | Out-Null
$results = [ordered]@{}
$start = Get-Date

Write-Banner 'Overseer smoke test'
Write-Step "Game folder: $GameDir"
if ($CompatLayer) { $env:__COMPAT_LAYER = $CompatLayer }
$p = Start-Process -FilePath (Join-Path $GameDir 'OVERSEER.EXE') -WorkingDirectory $GameDir -PassThru
Remove-Item Env:__COMPAT_LAYER -ErrorAction SilentlyContinue

$results['Started without admin rights'] = -not (Test-ProcessElevated $p)
$results['System Checker passed'] = Wait-AndClick -Process $p -Button 'Continue' -Seconds 20

$peak = Measure-ProcessAudio -ProcessId $p.Id -Seconds 6
$results["Opening video has sound (peak $('{0:N3}' -f $peak))"] = $peak -gt 0.001
Save-GameShot -Process $p -Path (Join-Path $out '1-video.png') | Out-Null

Start-Sleep -Seconds $MenuWaitSeconds
Send-Key 0x20   # skip anything still playing
Start-Sleep -Seconds 3
$results['Game still running at main menu'] = -not $p.HasExited
$results['Main menu screenshot'] = Save-GameShot -Process $p -Path (Join-Path $out '2-menu.png')

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$crash = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $start } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'overseer' } | Select-Object -First 1
$results['No crash in Windows event log'] = -not $crash

Write-Host ''
$failed = 0
foreach ($r in $results.GetEnumerator()) {
    if ($r.Value) { Write-Ok $r.Key } else { Write-Fail $r.Key; $failed++ }
}
if ($crash) { Write-Host ($crash.Message -split "`n" | Select-Object -First 8 | Out-String) }
Write-Host ''
Write-Host "Screenshots: $out"
if ($failed) { Write-Fail "$failed check(s) failed."; exit 1 } else { Write-Ok 'All checks passed.'; exit 0 }
