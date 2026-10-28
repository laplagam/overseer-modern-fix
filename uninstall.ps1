#Requires -Version 5.1
<#
.SYNOPSIS
    Reverts everything install.ps1 changed, using the backup in <game>\_overseerfix_backup.
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$NoPause,
    # Testing only: skip the admin prompt (works when nothing machine-wide needs restoring).
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner 'Tex Murphy: Overseer - Remove Modern Windows Fix'

if (-not $NoElevate -and -not (Test-IsAdmin)) {
    Write-Step 'Requesting administrator rights...'
    Restart-Elevated -ScriptPath $PSCommandPath -Arguments $PSBoundParameters
    return
}

function Uninstall-Fix([string]$GameDir) {
    $dir = Join-Path $GameDir $script:BackupFolder
    $stateFile = Join-Path $dir 'state.json'
    Write-Host ''
    Write-Host "--- $GameDir ---" -ForegroundColor Cyan
    if (-not (Test-Path $stateFile)) { Write-Step 'The fix is not installed here.'; return $false }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    Restore-SteamLaunchOptions $state.SteamLaunch   # first: stops here if Steam is running

    foreach ($p in $state.Files.PSObject.Properties) {
        $target = Join-Path $GameDir $p.Name
        if ($p.Value) { Copy-Item (Join-Path $dir $p.Name) $target -Force; Write-Ok "Restored $($p.Name)" }
        elseif (Test-Path $target) { Remove-Item $target -Force; Write-Ok "Removed $($p.Name)" }
    }

    foreach ($p in $state.Registry.PSObject.Properties) {
        $key, $name = $p.Name -split '\|', 2
        if ($null -eq $p.Value) { Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue }
        else {
            if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
            Set-ItemProperty -Path $key -Name $name -Value $p.Value
        }
    }
    Write-Ok 'Restored registry settings.'

    foreach ($c in @($state.Created)) {
        if (-not $c -or -not (Test-Path $c)) { continue }
        $item = Get-Item $c -Force
        if ($item.LinkType -eq 'Junction') { $item.Delete(); Write-Ok "Removed short path $c" }
        elseif ($c -like "$env:WINDIR\*") {
            # RSX was installed by the fix: unregister and remove it again.
            & "$env:WINDIR\SysWOW64\regsvr32.exe" /s /u $c
            Remove-Item $c -Force -ErrorAction SilentlyContinue
            Write-Ok "Removed $c"
        }
    }

    Remove-Item $dir -Recurse -Force
    Write-Ok 'The fix has been removed. The game is back to how it was installed.'
    $true
}

try {
    $removed = @(foreach ($d in (Resolve-GameDirs -GameDir $GameDir)) { Uninstall-Fix -GameDir $d }) -contains $true
    if (-not $removed) { throw 'No backup found - the fix does not seem to be installed.' }
}
catch {
    Write-Fail "Uninstall failed: $($_.Exception.Message)"
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
