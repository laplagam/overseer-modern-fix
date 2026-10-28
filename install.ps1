#Requires -Version 5.1
<#
.SYNOPSIS
    Makes the GOG release of Tex Murphy: Overseer run on modern Windows (10/11).

.DESCRIPTION
    - Replaces GOG's broken "Windows 95 + Run as admin" compatibility flags.
    - Installs dgVoodoo2 (DirectDraw/Direct3D wrapper) with a tuned config.
    - Installs focusfix (msvfw32.dll) so Alt+Tab doesn't break textures or music.
    - Handles install paths that are too long for the game's internal buffers.
    - Makes sure GOG's ffdshow video decoder is registered from the game folder.
    Everything changed is backed up; run uninstall.ps1 to revert.

.PARAMETER GameDir
    Game folder. If omitted, every GOG and Steam copy found is fixed (falling back to the script
    location or a folder picker).
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner 'Tex Murphy: Overseer - Modern Windows Fix'

if (-not (Test-IsAdmin)) {
    Write-Step 'Requesting administrator rights (needed to fix machine-wide compatibility flags)...'
    Restart-Elevated -ScriptPath $PSCommandPath -Arguments $PSBoundParameters
    return
}

function Install-Fix([string]$GameDir) {
    $steam = Test-IsSteamCopy $GameDir
    Write-Host ''
    Write-Host "--- $(if ($steam) { 'Steam' } else { 'GOG' }) copy: $GameDir ---" -ForegroundColor Cyan
    Test-GameFiles -GameDir $GameDir

    $backup = Initialize-Backup -GameDir $GameDir

    # 1. Short launch path (game crashes when its folder path is long).
    $launchDir = Get-LaunchDir -GameDir $GameDir -Backup $backup

    # 2. Compatibility flags.
    Set-CompatFlags -GameDir $GameDir -LaunchDir $launchDir -Backup $backup

    # 3. dgVoodoo2 wrapper.
    Install-DgVoodoo -GameDir $GameDir -Backup $backup

    # 3b. Alt+Tab fix (our msvfw32.dll proxy).
    Install-FocusFix -GameDir $GameDir -Backup $backup

    # 4. Game settings (Tex.ini).
    Set-GameSettings -GameDir $GameDir -Backup $backup

    # 5. Intel RSX 3D audio (required for any digital sound).
    Install-Rsx -GameDir $GameDir -Backup $backup

    # 6. ffdshow (FMV decoder shipped with the game).
    Register-Ffdshow -GameDir $GameDir -Backup $backup

    # 7. Shortcuts.
    Set-Shortcuts -GameDir $GameDir -LaunchDir $launchDir -Backup $backup

    Save-Backup $backup
    if ($steam) { Write-Ok 'Done! Start the game from Steam as usual.' }
    else { Write-Ok 'Done! Start the game from the GOG shortcut, GOG Galaxy, or OVERSEER.EXE.' }
    if ($launchDir -ne $GameDir) {
        Write-Warn2 "Your game folder path is long, so the game is started through: $launchDir"
    }
}

try {
    foreach ($dir in (Resolve-GameDirs -GameDir $GameDir)) { Install-Fix -GameDir $dir }
}
catch {
    Write-Host ''
    Write-Fail "Installation failed: $($_.Exception.Message)"
    Write-Host 'Nothing is lost: run uninstall.ps1 to restore any files that were already changed.'
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
