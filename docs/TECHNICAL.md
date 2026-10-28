# Technical notes

Investigation done on Windows 11 Pro build 26300 (x64), GOG build 2.1.0.23, `OVERSEER.EXE` v1.04 b330
(SHA256 `5635781F…43CFC`). The Steam release (app 302370) has a byte-identical `OVERSEER.EXE` and game DLLs.
Its differences are covered in [section 8](#8-steam).

## 1. Startup crash: the Windows 95 compatibility layer

GOG writes the following value under `HKLM` and `HKCU\…\AppCompatFlags\Layers`:

```
~WIN95 DISABLETHEMES DISABLECICERO RUNASADMIN
```

Clicking **Continue** in the System Checker then crashes the game:

```
overseer.exe  →  winmmbase.dll 10.0.26100.x  c0000005 @ +0x5ab3
```

Layer test matrix, run from a short path with only the layer varied via `__COMPAT_LAYER`:

| Layer | Needs admin rights? | Result |
|---|---|---|
| none | no | Game exits silently, code 0 (Windows version check) |
| WIN95 | **yes** | Crashes in winmmbase after the System Checker |
| WIN98, WINXPSP2, WINXPSP3 | **yes** | Main menu ✔ |
| WIN2000 | no | Stalls before the System Checker |
| NT4SP5, VISTASP2 | no | Main menu ✔ |
| **WIN7RTM** | no | Main menu ✔, 3D world ✔, music ✔ (chosen) |

"Needs admin rights" was checked by launching through `CreateProcess` in a debugger: the result is `ERROR_ELEVATION_REQUIRED` (740).

The Windows 9x and XP layers make Windows demand admin rights, and adding `RUNASINVOKER` to the registry value does not reliably override that.
Running the game as admin also breaks per-user audio-session tracking, and it isolates the game window from normal-user tools.
The fix therefore writes `~ WIN7RTM` to both `HKLM` and `HKCU`.

## 2. Long install path: stack buffer overflow

The game builds `<exe folder>\FONTS.LS` in an ~80 byte stack buffer.

In WinDbg, a copy at a ~130 character path crashed with `EIP = 0x3135612d`. Those bytes are the ASCII text `-a51` from the path.
The overwritten return address sits 88 bytes after the start of the string.

`install.ps1` therefore accepts folders of up to 60 characters (plain ASCII). Anything longer gets a junction at `C:\TexOverseer`, and the shortcuts are changed to use it.

## 3. "ERROR : Error Code Does Not Indicate An Error"

This appears when a game is started or loaded, right before the 3D world. The cause is that `Tex.ini [MIDI] DriverName=MIDI Mapper` does not match any device.

The 32-bit `midiOutGetDevCaps(MIDI_MAPPER)` reports `Microsoft MIDI Mapper`.
With the correct name the world loads, and the game's audio session shows MIDI music:

| MIDI setting | Audio peak in Tex's office |
|---|---|
| Unmuted | 0.031 |
| Muted | 0.000 |

The installer reads the name from 32-bit WinMM instead of hard-coding it, because the name can be localized.

## 4. Intel RSX 3D is required for all digital sound

Without a registered RSX COM server (`{E78F7620-96CB-11CF-A00B-444553540000}`), the game shows:

> Digital Sound Initialization Error — Another application is currently using the Sound Device or Intel RSX 3D drivers are not installed.

Setting `3DSound=0` does **not** avoid this. GOG Galaxy's support package installs `RSX.DLL`/`AAUDIO.DLL` into SysWOW64 and registers them.
Steam's install script does the same from `<game>\RSX`.
The fix only checks that this happened, and repairs it from the game's copy if it didn't.

## 5. Graphics: dgVoodoo2

- **Required** with the `WIN7RTM` layer: without it the game quietly exits with code 0 after the System Checker.
- It also:
  - scales 800×600 to the native resolution at 4:3, instead of switching the monitor into 800×600;
  - fixes invisible or transparent textures in later scenes and on other GPUs (per community reports);
  - makes the output independent of the vendor's legacy DirectDraw support.

## 6. Video

FMV (`.VOB` MPEG-2) is played by `TexDll.dll`. For each video it creates a DirectShow filter graph (`CLSID_FilterGraph`), which decodes through GOG's patched `ffdshow.ax`.
It calls `IMediaControl::Run` when a video starts and `Pause` when it ends.
GOG and Steam both register ffdshow from the game folder. A system-wide ffdshow install can claim some of the same CLSIDs, and the fix warns if it finds one.

The video graph contains:
- *Default DirectSound Device*
- *Mio Filtro* (the game's own renderer)
- *ffdshow Video Decoder* and *ffdshow Audio Decoder*
- *MPEG-2 Demultiplexer*
- the `.VOB` source

**ffdshow's compatibility manager.** When the process isn't on ffdshow's whitelist, ffdshow asks whether it should be used for that program.
The question opens *behind* the fullscreen game. After about 15 s it defaults to "don't use ffdshow", and the video then plays without sound.
The fix adds `overseer.exe;` to the `whitelist` value in both `HKCU\Software\GNU\ffdshow` and `HKCU\Software\GNU\ffdshow_audio`. The audio decoder keeps its own list.

## 7. White 3D view after Alt+Tab during a cinematic, and music stopping

**Symptom:** pick up the magazine in Tex's office and Alt+Tab while its cinematic plays.
- A "Returning to Tex's office..." loading box appears over the video.
- When the video ends, the whole 3D view is solid white.
- One more Alt+Tab in 3D brings the textures back.

Separately, any Alt+Tab stops the music for good.

**Cause:** the game reacts to `WM_ACTIVATEAPP`.
- On **TRUE** (activated) it reloads the 3D world, to restore DirectDraw surfaces lost while it was in the background. In 3D that's harmless and needed. During a cinematic it clashes with the video, and the textures end up empty.
  Sending `WM_ACTIVATEAPP(TRUE)` to the window mid-cinematic is enough to reproduce it.
- On **FALSE** (deactivated) it stops the music, and it never restarts it.

dgVoodoo's `FullscreenAttributes = fake` doesn't help: textures are lost on any focus change.

**Fix: `src/focusfix`**, a small C DLL installed as `msvfw32.dll` in the game folder.
- *Why msvfw32:* `OVERSEER.EXE` imports it directly and it isn't a KnownDLL, so the game folder copy is loaded first. All 47 exports are forwarded to the system copy.
  `dsound.dll` doesn't work here, because `rsx.dll` loads the system dsound through COM before the game asks for it.
- *What it does:*
  - hooks `TexDll.dll`'s `CoCreateInstance` import, and the shared quartz `IMediaControl` vtable (`Run`/`Pause`/`Stop`), to know when a video plays;
  - subclasses the game window (class `Tex Murphy: Overseer`);
  - drops `WM_ACTIVATEAPP(FALSE)`, so the music keeps going (it also plays while you're tabbed out);
  - holds back `WM_ACTIVATEAPP(TRUE)` while a video plays;
  - re-posts it 1.5 s after the video ends, if the game is in the foreground. Posting it right at the video's end is too early: the game is still leaving the video and the view stays white.
- *Also:* loads the system `d3d9.dll` at startup, for the Steam crash (see [section 8](#8-steam)).
- *Debugging:* set `FOCUSFIX_LOG=<file>` to get a log. `FOCUSFIX_DELAY=<ms>` changes the re-post delay.
- *Build:* `src\focusfix\build.cmd` (Visual Studio Build Tools, x86) writes `bin\msvfw32.dll`.

## 8. Steam

The game files are identical to GOG's. The differences are all in how Steam starts the game.

**Compatibility flags are re-applied on every launch.** Steam's signed install scripts (`overseer_installscript_one/two.vdf`) write
`WIN95 DISABLETHEMES DISABLECICERO DISABLETHEMES RUNASADMIN` to `HKCU\…\AppCompatFlags\Layers` for the game's path.
Steam runs these scripts again each time it starts the game. That overwrites the fix's value, so the game runs elevated with the crashing WIN95 layer.

The workaround uses the fact that the flags are stored per path:
1. The installer creates a junction `C:\TexOverseer-Steam` → game folder.
2. It gives *that* path the `~ WIN7RTM` value.
3. It sets the game's Steam launch options to:
   ```
   "C:\TexOverseer-Steam\OVERSEER.EXE" %command%
   ```

Steam then starts our path and passes its own command line as arguments, which the game ignores. Steam still sees the game as running, and the overlay still loads.

**Where Steam keeps launch options.** They are stored per Steam user in `<Steam>\userdata\<id>\config\localconfig.vdf`, under
`UserLocalConfigStore\Software\Valve\Steam\apps\302370\LaunchOptions`. The file is text VDF, UTF-8 without BOM, with `\\` and `\"` escapes.
- Steam keeps the file in memory and rewrites it when it exits. The installer therefore only edits it while `steam.exe` isn't running; otherwise it prints the line for the user to paste.
- The backup keeps the original value and a copy of the file. `uninstall.ps1` restores them.

**Crash when a video starts (stack overflow, `c00000fd`).** This only happens under Steam. The stack alternates endlessly between
`gameoverlayrenderer!OverlayHookD3D3` and `apphelp!DWM8AND16BitHook_Direct3DCreate9Ex`.
- When a video starts, DirectShow builds its graph by trying Windows' renderers and decoders as candidates: VMR-9 (`BasicHWCheck`), VMR-7 and `msmpeg2vdec`. These call `Direct3DCreate9`/`Direct3DCreate9Ex`.
- Steam injects its overlay DLL even when the overlay is disabled for the game, and that DLL hooks both functions.
- Windows' DWM8And16Bit mitigation hooks them too. It is applied to the process whatever the layer or exe name.
- Each hook ends up calling the other until the stack overflows.
- Blocking individual renderers only moved the problem to the next component that calls D3D9.

Fix: focusfix loads `%WINDIR%\SysWOW64\d3d9.dll` from its `DllMain`, before either hook is installed. After that, the calls return normally.
Verified with the overlay switched on (`gameoverlayrenderer.dll` loaded in the game) and off. GOG behaviour is unchanged.

## Test tooling

`tests/smoke-test.ps1` starts the game (through Steam for a Steam copy) and checks:
- the process is **not** elevated (token check);
- it clicks the System Checker's *Continue* button;
- the game's audio is measured through the Windows audio session meter;
- screenshots of the game window are taken;
- the Application log has no new crash entries.

See [tests/TESTING.md](../tests/TESTING.md).
