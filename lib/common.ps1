# Shared helpers for install.ps1 / uninstall.ps1 / diagnose.ps1.

$script:GogGameId    = '1207658769'
$script:SteamAppId   = '302370'
$script:BackupFolder = '_overseerfix_backup'
# WIN95/WIN98/WINXP* layers make Windows demand admin rights for the game; WIN7RTM passes the
# game's Windows version check without that. See docs/TECHNICAL.md.
$script:CompatValue  = '~ WIN7RTM'
$script:LayersPaths  = @(
    'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
    'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
)
# OVERSEER.EXE v1.04 build 330 as shipped by GOG (identical in the Steam release).
$script:KnownExeHashes = @('5635781F506E953B06DF0E28AAD2C810BB02D2D64470A158614CBED927E43CFC')
# The game copies "<folder>\FONTS.LS" into an ~80 byte stack buffer and overflows it on
# longer paths. Keep a safety margin below that.
$script:MaxGameDirLength = 60
$script:ShortLaunchDir   = Join-Path $env:SystemDrive 'TexOverseer'

#region Output
function Write-Banner([string]$Text) { Write-Host ''; Write-Host "=== $Text ===" -ForegroundColor Cyan; Write-Host '' }
function Write-Step([string]$Text)   { Write-Host "  > $Text" }
function Write-Ok([string]$Text)     { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text)  { Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text)   { Write-Host "  [X] $Text" -ForegroundColor Red }
#endregion

#region Elevation
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated([string]$ScriptPath, [System.Collections.IDictionary]$Arguments) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"")
    foreach ($k in $Arguments.Keys) {
        $v = $Arguments[$k]
        if ($v -is [switch] -or $v -is [bool]) { if ($v) { $argList += "-$k" } }
        else { $argList += "-$k"; $argList += "`"$v`"" }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
}
#endregion

#region Game folder
# Steam: the game's install folder is <library>\steamapps\common\<installdir from appmanifest>.
function Get-SteamGameDir {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }
    if (-not $steam) { return $null }
    $libraries = @($steam -replace '/', '\')
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $libraries += Select-String -Path $vdf -Pattern '^\s*"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $acf = Join-Path $lib "steamapps\appmanifest_$script:SteamAppId.acf"
        if (-not (Test-Path $acf)) { continue }
        $m = Select-String -Path $acf -Pattern '^\s*"installdir"\s+"(.+)"' | Select-Object -First 1
        if ($m) { return Join-Path $lib ("steamapps\common\" + $m.Matches[0].Groups[1].Value) }
    }
    $null
}

function Test-IsSteamCopy([string]$GameDir) {
    (Test-Path (Join-Path $GameDir 'overseer_installscript_one.vdf')) -or ($GameDir -match '(?i)\\steamapps\\common\\')
}

function Resolve-GameDir([string]$GameDir) {
    $candidates = @()
    if ($GameDir) { $candidates += $GameDir }
    else {
        $gog = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$script:GogGameId" -ErrorAction SilentlyContinue
        if ($gog -and $gog.PATH) { $candidates += $gog.PATH }
        $candidates += Get-SteamGameDir
        $candidates += (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)   # fix unpacked inside the game folder
        $candidates += (Get-Location).Path
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'OVERSEER.EXE'))) { return (Resolve-Path $c).Path.TrimEnd('\') }
    }
    if ($GameDir) { throw "OVERSEER.EXE was not found in '$GameDir'." }

    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select your Tex Murphy: Overseer folder (the one containing OVERSEER.EXE)'
    if ($dlg.ShowDialog() -eq 'OK' -and (Test-Path (Join-Path $dlg.SelectedPath 'OVERSEER.EXE'))) {
        return $dlg.SelectedPath.TrimEnd('\')
    }
    throw 'Could not find the game folder. Run install.ps1 -GameDir "<path to game>".'
}

# All installs to work on: the given folder, else every GOG and Steam copy found, else whatever
# Resolve-GameDir finds (script location, current folder, folder picker).
function Resolve-GameDirs([string]$GameDir) {
    if ($GameDir) { return @(Resolve-GameDir -GameDir $GameDir) }
    $gog = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$script:GogGameId" -ErrorAction SilentlyContinue).PATH
    $found = @($gog, (Get-SteamGameDir)) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ 'OVERSEER.EXE')) } |
        ForEach-Object { (Resolve-Path $_).Path.TrimEnd('\') } | Select-Object -Unique
    if ($found) { return @($found) }
    @(Resolve-GameDir)
}

function Test-GameFiles([string]$GameDir) {
    $exe = Join-Path $GameDir 'OVERSEER.EXE'
    $hash = (Get-FileHash $exe -Algorithm SHA256).Hash
    if ($script:KnownExeHashes -notcontains $hash) {
        Write-Warn2 "OVERSEER.EXE is not the known GOG/Steam v1.04 version (SHA256 $hash). Continuing, but this is untested."
    } else { Write-Ok "OVERSEER.EXE is the known v1.04 build ($(if (Test-IsSteamCopy $GameDir) { 'Steam' } else { 'GOG' }))." }
    foreach ($f in 'TexDll.dll', 'SOS9505.DLL', 'SMACKW32.DLL', 'ffdshow.ax') {
        if (-not (Test-Path (Join-Path $GameDir $f))) { Write-Warn2 "$f is missing from the game folder." }
    }
}
#endregion

#region Backup
function Initialize-Backup([string]$GameDir) {
    $dir = Join-Path $GameDir $script:BackupFolder
    New-Item -ItemType Directory -Force $dir | Out-Null
    $stateFile = Join-Path $dir 'state.json'
    $state = if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { $null }
    $backup = [ordered]@{
        Dir      = $dir
        GameDir  = $GameDir
        Files    = @{}   # relative file name -> $true (original backed up) / $false (did not exist)
        Registry = @{}   # "<key>|<name>" -> original value or $null
        Created  = @()   # paths created by the fix (junctions, shortcuts)
        SteamLaunch = @{}   # localconfig.vdf path -> original LaunchOptions or $null
    }
    if ($state) {   # Re-install: keep the ORIGINAL backup, never overwrite it.
        foreach ($p in $state.Files.PSObject.Properties)    { $backup.Files[$p.Name] = $p.Value }
        foreach ($p in $state.Registry.PSObject.Properties) { $backup.Registry[$p.Name] = $p.Value }
        if ($state.SteamLaunch) { foreach ($p in $state.SteamLaunch.PSObject.Properties) { $backup.SteamLaunch[$p.Name] = $p.Value } }
        $backup.Created = @($state.Created)
    }
    $backup
}

function Backup-File($Backup, [string]$Name) {
    if ($Backup.Files.ContainsKey($Name)) { return }
    $src = Join-Path $Backup.GameDir $Name
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $Backup.Dir $Name) -Force
        $Backup.Files[$Name] = $true
    } else { $Backup.Files[$Name] = $false }
}

function Backup-RegValue($Backup, [string]$Key, [string]$Name) {
    $id = "$Key|$Name"
    if ($Backup.Registry.ContainsKey($id)) { return }
    $item = Get-Item $Key -ErrorAction SilentlyContinue
    $Backup.Registry[$id] = if ($item) { $item.GetValue($Name, $null) } else { $null }
}

function Save-Backup($Backup) {
    $Backup | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Backup.Dir 'state.json') -Encoding UTF8
}
#endregion

#region Fix steps
function Get-LaunchDir([string]$GameDir, $Backup) {
    if (Test-IsSteamCopy $GameDir) {
        # Always use a link for Steam, see "Steam launch options" below.
        $link = "$script:ShortLaunchDir-Steam"
        Write-Step 'Steam copy: the game will be started through a short link that Steam''s own compatibility settings don''t touch.'
    } else {
        $nonAscii = $GameDir -match '[^\x20-\x7E]'
        if ($GameDir.Length -le $script:MaxGameDirLength -and -not $nonAscii) {
            Write-Ok "Game folder path length is fine ($($GameDir.Length) characters)."
            return $GameDir
        }
        $why = if ($nonAscii) { 'contains non-English characters' } else { "is too long ($($GameDir.Length) characters)" }
        Write-Warn2 "The game folder path $why; the game would crash at startup."
        $link = $script:ShortLaunchDir
    }
    if (Test-Path $link) {
        $existing = (Get-Item $link).Target
        if ($existing -and ((@($existing)[0]).TrimEnd('\') -ieq $GameDir)) { Write-Ok "Using existing short path $link"; return $link }
        throw "$link already exists and is not a link to the game. Remove it or move the game to a shorter path."
    }
    New-Item -ItemType Junction -Path $link -Target $GameDir | Out-Null
    $Backup.Created += $link
    Write-Ok "Created short path $link -> $GameDir"
    $link
}

function Set-CompatFlags([string]$GameDir, [string]$LaunchDir, $Backup) {
    $exeNames = @((Join-Path $GameDir 'overseer.exe'))
    if ($LaunchDir -ne $GameDir) { $exeNames += (Join-Path $LaunchDir 'overseer.exe') }
    foreach ($key in $script:LayersPaths) {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        $item = Get-Item $key
        # Remove any existing entries for the game (GOG writes "~WIN95 ... RUNASADMIN"), whatever their case.
        foreach ($name in $item.GetValueNames()) {
            if ($name -ieq (Join-Path $GameDir 'overseer.exe') -or ($LaunchDir -ne $GameDir -and $name -ieq (Join-Path $LaunchDir 'overseer.exe'))) {
                Backup-RegValue $Backup $key $name
                Remove-ItemProperty -Path $key -Name $name
            }
        }
        foreach ($exe in $exeNames) {
            Backup-RegValue $Backup $key $exe
            Set-ItemProperty -Path $key -Name $exe -Value $script:CompatValue
        }
    }
    Write-Ok "Compatibility mode set to Windows 7, no admin rights ($script:CompatValue)."
}

function Install-DgVoodoo([string]$GameDir, $Backup) {
    $src = Join-Path $PSScriptRoot '..\third_party\dgVoodoo2'
    foreach ($f in 'DDraw.dll', 'D3DImm.dll') {
        Backup-File $Backup $f
        Copy-Item (Join-Path $src $f) (Join-Path $GameDir $f) -Force
    }
    Backup-File $Backup 'dgVoodoo.conf'
    Copy-Item (Join-Path $PSScriptRoot '..\config\dgVoodoo.conf') (Join-Path $GameDir 'dgVoodoo.conf') -Force
    Write-Ok 'Installed dgVoodoo2 (DirectDraw/Direct3D wrapper) and its configuration.'
}

# focusfix (src/focusfix): keeps Alt+Tab during a cinematic from turning the 3D view white, and
# keeps the music playing after Alt+Tab. Loaded by the game as msvfw32.dll from its own folder.
function Install-FocusFix([string]$GameDir, $Backup) {
    Backup-File $Backup 'msvfw32.dll'
    Copy-Item (Join-Path $PSScriptRoot '..\bin\msvfw32.dll') (Join-Path $GameDir 'msvfw32.dll') -Force
    Write-Ok 'Installed the Alt+Tab fix (msvfw32.dll).'
}

function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $lines = [System.Collections.Generic.List[string]]@(if (Test-Path $Path) { Get-Content $Path })
    $inSection = $false; $sectionEnd = -1; $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+)\]\s*$') {
            if ($inSection) { $sectionEnd = $i; break }
            $inSection = ($Matches[1] -ieq $Section)
            continue
        }
        if ($inSection -and $lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $lines[$i] = "$Key=$Value"; $done = $true; break }
    }
    if (-not $done) {
        if ($inSection -and $sectionEnd -lt 0) { $lines.Add("$Key=$Value") }
        elseif ($sectionEnd -ge 0) { $lines.Insert($sectionEnd, "$Key=$Value") }
        else { $lines.Add("[$Section]"); $lines.Add("$Key=$Value") }
    }
    Set-Content -Path $Path -Value $lines -Encoding Ascii
}

function Set-GameSettings([string]$GameDir, $Backup) {
    $ini = Join-Path $GameDir 'Tex.ini'
    Backup-File $Backup 'Tex.ini'
    # GOG ships "MIDI Mapper", which matches no device on modern Windows. Entering the 3D world
    # then fails with "ERROR: Error Code Does Not Indicate An Error".
    $mapper = Get-MidiMapperName
    Set-IniValue $ini 'MIDI' 'DriverName' $mapper
    Write-Ok "Music device set to '$mapper' (Tex.ini)."
}

function Get-MidiMapperName {
    # Ask 32-bit WinMM (what the game sees) for the MIDI Mapper's name; it can be localized.
    $code = @'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices;
public static class M { [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct C { public ushort a, b; public uint v; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string n; public ushort t, vo, no, ch; public uint s; }
[DllImport("winmm.dll", CharSet=CharSet.Unicode)] public static extern int midiOutGetDevCapsW(IntPtr id, ref C c, int size); }'
$c = New-Object M+C; if ([M]::midiOutGetDevCapsW([IntPtr](-1), [ref]$c, [Runtime.InteropServices.Marshal]::SizeOf($c)) -eq 0) { $c.n }
'@
    $ps32 = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    try {
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $name = (& $ps32 -NoProfile -NonInteractive -EncodedCommand $enc 2>$null | Select-Object -Last 1)
        if ($name -and $name.Trim()) { return $name.Trim() }
    } catch { }
    'Microsoft MIDI Mapper'
}

# Intel RSX 3D audio. The game routes ALL digital sound through RSX and refuses to start sound
# without it ("Digital Sound Initialization Error"). GOG's installer normally provides it; we only
# repair a missing registration using GOG's own copy of the files.
$script:RsxClsid = '{E78F7620-96CB-11CF-A00B-444553540000}'

function Test-Rsx {
    $srv = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$script:RsxClsid\InprocServer32" -ErrorAction SilentlyContinue).'(default)'
    $srv -and (Test-Path ([Environment]::ExpandEnvironmentVariables($srv)))
}

function Install-Rsx([string]$GameDir, $Backup) {
    if (Test-Rsx) { Write-Ok 'Intel RSX 3D audio is installed.'; return }
    $sources = @(
        "$env:ProgramData\GOG.com\Galaxy\support\$script:GogGameId\$script:GogGameId\dll",
        (Join-Path $GameDir "__support\$script:GogGameId\dll"),
        (Join-Path $GameDir 'RSX'),
        $GameDir
    )
    $src = $sources | Where-Object { (Test-Path (Join-Path $_ 'RSX.DLL')) -and (Test-Path (Join-Path $_ 'AAUDIO.DLL')) } | Select-Object -First 1
    if (-not $src) {
        throw ('Intel RSX 3D audio (RSX.DLL/AAUDIO.DLL) is not installed and the copy shipped with the game was not found. ' +
               'Reinstall the game (GOG Galaxy, the GOG offline installer, or Steam), then run this fix again.')
    }
    $sysDir = "$env:WINDIR\SysWOW64"
    foreach ($f in 'AAUDIO.DLL', 'RSX.DLL') {
        $dst = Join-Path $sysDir $f
        if (-not (Test-Path $dst)) { Copy-Item (Join-Path $src $f) $dst; $Backup.Created += $dst }
        & "$sysDir\regsvr32.exe" /s $dst
    }
    if (-not (Test-Rsx)) { throw 'Registering Intel RSX 3D audio failed.' }
    Write-Ok "Installed Intel RSX 3D audio from the game's files ($src)."
}

function Register-Ffdshow([string]$GameDir, $Backup) {
    $ax = Join-Path $GameDir 'ffdshow.ax'
    if (-not (Test-Path $ax)) { Write-Warn2 'ffdshow.ax not found; videos may not play.'; return }
    # ffdshow video decoder CLSID
    $clsid = 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{04FE9017-F873-410E-871E-AB91661A4EF7}\InprocServer32'
    $current = (Get-ItemProperty $clsid -ErrorAction SilentlyContinue).'(default)'
    $sameFile = $current -and (Test-Path $current) -and ((Get-FileHash $current).Hash -eq (Get-FileHash $ax).Hash)
    if ($current -ieq $ax -or $sameFile) { Write-Ok "The game's ffdshow video decoder is registered ($current)." }
    else {
        & "$env:WINDIR\SysWOW64\regsvr32.exe" /s $ax
        Write-Ok 'Registered the GOG ffdshow video decoder.'
    }
    $key = 'HKCU:\Software\GNU\ffdshow'
    if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
    foreach ($v in @(@('trayIcon', 0), @('trayIconExt', 0), @('fvfw', 1), @('mpg2', 1), @('supDVDdec', 1), @('isBlacklist', 1))) {
        Backup-RegValue $Backup $key $v[0]
        Set-ItemProperty -Path $key -Name $v[0] -Value $v[1] -Type DWord
    }
    # Without this, ffdshow's "compatibility manager" asks whether OVERSEER.EXE may use it (the
    # dialog hides behind the game), and after 15 seconds picks "don't use": videos lose their sound.
    foreach ($k in 'HKCU:\Software\GNU\ffdshow', 'HKCU:\Software\GNU\ffdshow_audio') {
        if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
        Backup-RegValue $Backup $k 'whitelist'
        $list = [string](Get-Item $k).GetValue('whitelist', '')
        if (($list -split ';') -notcontains 'overseer.exe') {
            Set-ItemProperty -Path $k -Name 'whitelist' -Value (($list.TrimEnd(';') + ';overseer.exe;').TrimStart(';')) -Type String
        }
    }
    $sys = "${env:ProgramFiles(x86)}\ffdshow\ffdshow.ax"
    if (Test-Path $sys) { Write-Warn2 "A separate ffdshow is installed system-wide ($sys). If videos misbehave, uninstall it." }
}

#region Steam launch options
# Steam re-applies its install script's registry entries every time it starts the game, which
# puts "WIN95 ... RUNASADMIN" back on <steam folder>\OVERSEER.EXE. So under Steam the game is
# started through a link instead (C:\TexOverseer-Steam\OVERSEER.EXE), which has our flags, using
# the launch options: whatever comes before %command% is what Steam runs.
# Launch options live in Steam\userdata\<account>\config\localconfig.vdf under
# ...\apps\<appid>\LaunchOptions. Steam rewrites that file while it runs, so it is only edited
# while Steam is closed.

function Get-SteamLocalConfigs {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return @() }
    @(Get-ChildItem (Join-Path ($steam -replace '/', '\') 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue | ForEach-Object FullName)
}

function ConvertTo-VdfString([string]$s)   { $s.Replace('\', '\\').Replace('"', '\"') }
function ConvertFrom-VdfString([string]$s) { $s.Replace('\"', '"').Replace('\\', '\') }

# Sets (or with $null removes) apps\<appid>\LaunchOptions in one localconfig.vdf. Returns the
# previous value ($null if there was none), or the string '<no-app>' if the game has no entry
# in that file (that Steam account never started it).
function Set-VdfLaunchOptions([string]$File, $Value) {   # untyped: [string] would turn $null into ''
    $text = [IO.File]::ReadAllText($File)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]($text -split "`r?`n")
    $stack = New-Object Collections.Generic.List[string]; $pending = $null
    $start = -1; $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^"([^"]*)"$') { $pending = $Matches[1]; continue }
        if ($t -eq '{') {
            $stack.Add($pending); $pending = $null
            # The file also has a top-level apps\<appid> block (overlay settings); only this one counts.
            if ($start -lt 0 -and ($stack -join '\') -ieq "UserLocalConfigStore\Software\Valve\Steam\apps\$script:SteamAppId") { $start = $i; $depth = $stack.Count }
            continue
        }
        if ($t -eq '}') {
            if ($start -ge 0 -and $stack.Count -eq $depth) { $end = $i; break }
            if ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
        }
    }
    if ($start -lt 0 -or $end -lt 0) { return '<no-app>' }
    $old = $null; $at = -1
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match '^\s*"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"\s*$') { $old = ConvertFrom-VdfString $Matches[1]; $at = $i; break }
    }
    $indent = ($lines[$start] -replace '\S.*$', '') + "`t"
    $entry = "$indent`"LaunchOptions`"`t`t`"$(ConvertTo-VdfString $Value)`""
    if ($null -eq $Value) { if ($at -ge 0) { $lines.RemoveAt($at) } }
    elseif ($at -ge 0) { $lines[$at] = $entry }
    else { $lines.Insert($start + 1, $entry) }
    [IO.File]::WriteAllText($File, ($lines -join $nl), (New-Object Text.UTF8Encoding $false))
    $old
}

function Get-SteamLaunchOptionsText([string]$LaunchDir) { "`"$(Join-Path $LaunchDir 'OVERSEER.EXE')`" %command%" }

function Write-SteamLaunchHelp([string]$LaunchDir) {
    Write-Warn2 'Set this in Steam: right-click the game > Properties > General > Launch Options:'
    Write-Host ''
    Write-Host "      $(Get-SteamLaunchOptionsText $LaunchDir)" -ForegroundColor White
    Write-Host ''
}

function Set-SteamLaunchOptions([string]$LaunchDir, $Backup) {
    $value = Get-SteamLaunchOptionsText $LaunchDir
    if (Get-Process steam -ErrorAction SilentlyContinue) {
        Write-Warn2 'Steam is running, so its launch options for the game could not be set automatically.'
        Write-Warn2 'Either exit Steam completely and run Install.cmd again, or:'
        Write-SteamLaunchHelp $LaunchDir
        return
    }
    $done = $false
    foreach ($f in Get-SteamLocalConfigs) {
        $copy = Join-Path $Backup.Dir ("localconfig-{0}.vdf" -f (Split-Path (Split-Path (Split-Path $f -Parent) -Parent) -Leaf))
        if (-not (Test-Path $copy)) { Copy-Item $f $copy }
        $old = Set-VdfLaunchOptions -File $f -Value $value
        if ($old -eq '<no-app>') { continue }
        if (-not $Backup.SteamLaunch.ContainsKey($f)) { $Backup.SteamLaunch[$f] = $old }
        $done = $true
    }
    if ($done) { Write-Ok "Steam launch options set to: $value" }
    else {
        Write-Warn2 'Steam has no settings for the game yet (start it once from Steam first), so:'
        Write-SteamLaunchHelp $LaunchDir
    }
}

function Restore-SteamLaunchOptions($SteamLaunch) {
    $files = @(if ($SteamLaunch) { $SteamLaunch.PSObject.Properties })
    if (-not $files) { return }
    if (Get-Process steam -ErrorAction SilentlyContinue) {
        # Without the launch options reset, Steam would keep starting the game through the link
        # that is about to be removed.
        throw 'Steam is running. Exit Steam completely (Steam menu > Exit) and run Uninstall.cmd again.'
    }
    foreach ($p in $files) { if (Test-Path $p.Name) { [void](Set-VdfLaunchOptions -File $p.Name -Value $p.Value) } }
    Write-Ok 'Restored the Steam launch options.'
}
#endregion

function Set-Shortcuts([string]$GameDir, [string]$LaunchDir, $Backup) {
    if ($LaunchDir -eq $GameDir) { return }
    if (Test-IsSteamCopy $GameDir) { Set-SteamLaunchOptions -LaunchDir $LaunchDir -Backup $Backup; return }
    # Point the GOG shortcuts at the short path so the game never sees the long one.
    $shell = New-Object -ComObject WScript.Shell
    $links = @(Join-Path $GameDir 'Launch Tex Murphy - Overseer.lnk')
    $links += Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", ([Environment]::GetFolderPath('CommonDesktopDirectory')), ([Environment]::GetFolderPath('Desktop')) -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Overseer' } | ForEach-Object FullName
    foreach ($l in ($links | Where-Object { Test-Path $_ } | Select-Object -Unique)) {
        $sc = $shell.CreateShortcut($l)
        if ($sc.TargetPath -match '(?i)overseer\.exe$') {
            $sc.TargetPath = Join-Path $LaunchDir 'OVERSEER.EXE'
            $sc.WorkingDirectory = $LaunchDir
            $sc.Save()
            Write-Ok "Updated shortcut: $l"
        }
    }
    Write-Warn2 'GOG Galaxy launches the long path directly; use the updated shortcut instead.'
}
#endregion
