#Requires -Version 5.1
<#
.SYNOPSIS
    Collects the information needed for a bug report into a .txt file on your Desktop.
    Nothing is uploaded; attach the file to a GitHub issue yourself.
#>
[CmdletBinding()]
param([string]$GameDir, [switch]$NoPause)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$report = New-Object System.Text.StringBuilder
function Add([string]$Title, $Body) {
    [void]$report.AppendLine("==== $Title ====")
    [void]$report.AppendLine(($Body | Out-String -Width 250).TrimEnd())
    [void]$report.AppendLine('')
}

Write-Banner 'Tex Murphy: Overseer - Diagnostics'
try { $GameDir = Resolve-GameDir -GameDir $GameDir } catch { $GameDir = $null }

$os = Get-CimInstance Win32_OperatingSystem
Add 'Windows' ("{0} {1} build {2} ({3})" -f $os.Caption, $os.Version, $os.BuildNumber, $os.OSArchitecture)
Add 'GPU' (Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize)
Add 'Sound devices' (Get-CimInstance Win32_SoundDevice | Select-Object Name, Status | Format-Table -AutoSize)
Add 'Game folder' ("$GameDir (length $($GameDir.Length))")

if ($GameDir) {
    $exe = Join-Path $GameDir 'OVERSEER.EXE'
    if (Test-Path $exe) { Add 'OVERSEER.EXE SHA256' (Get-FileHash $exe).Hash }
    Add 'Game folder files' (Get-ChildItem $GameDir -File | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize)
    foreach ($f in 'Tex.ini', 'dgVoodoo.conf') {
        $p = Join-Path $GameDir $f
        if (Test-Path $p) { Add $f ((Get-Content $p | Where-Object { $_ -notmatch '^\s*;' -and $_.Trim() }) -join "`n") }
    }
    Add 'Fix installed' (Test-Path (Join-Path $GameDir $script:BackupFolder))
}

$layers = foreach ($k in $script:LayersPaths) {
    $i = Get-Item $k -ErrorAction SilentlyContinue
    if ($i) { $i.GetValueNames() | Where-Object { $_ -match '(?i)overseer' } | ForEach-Object { "$k :: $_ = $($i.GetValue($_))" } }
}
Add 'Compatibility flags' $layers
Add 'Intel RSX registered' (Test-Rsx)
Add 'MIDI Mapper name (32-bit)' (Get-MidiMapperName)
$d32 = Get-Item 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Drivers32' -ErrorAction SilentlyContinue
if ($d32) { Add 'Drivers32 (midi/wave)' ($d32.GetValueNames() | Where-Object { $_ -match '^(midi|wave)' } | ForEach-Object { "$_ = $($d32.GetValue($_))" }) }
$ff = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{04FE9017-F873-410E-871E-AB91661A4EF7}\InprocServer32' -ErrorAction SilentlyContinue).'(default)'
Add 'ffdshow video decoder registered at' $ff
Add 'Recent Overseer crashes (Application log, 14 days)' (
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match '(?i)overseer' } | Select-Object -First 5 |
        ForEach-Object { "$($_.TimeCreated)`n" + (($_.Message -split "`n" | Select-Object -First 7) -join "`n") })

$file = Join-Path ([Environment]::GetFolderPath('Desktop')) ("overseer-diagnostics-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report.ToString() | Set-Content $file -Encoding UTF8
Write-Ok "Saved: $file"
Write-Host '  Attach this file when reporting a problem.'
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
