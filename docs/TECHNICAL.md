# Technical notes

Investigation done on Windows 11 Pro build 26300 (x64), GOG build 2.1.0.23, `OVERSEER.EXE` v1.04 b330
(SHA256 `5635781F…43CFC`, identical to the Steam release).

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
The fix only checks that this happened, and repairs it from GOG's copy if it didn't.

## 5. Graphics: dgVoodoo2

- **Required** with the `WIN7RTM` layer: without it the game quietly exits with code 0 after the System Checker.
- It also:
  - scales 800×600 to the native resolution at 4:3, instead of switching the monitor into 800×600;
  - fixes invisible or transparent textures in later scenes and on other GPUs (per community reports);
  - makes the output independent of the vendor's legacy DirectDraw support.

## 6. Video

FMV (`.VOB` MPEG-2) is played by `TexDll.dll`. For each video it creates a DirectShow filter graph (`CLSID_FilterGraph`), which decodes through GOG's patched `ffdshow.ax`.
It calls `IMediaControl::Run` when a video starts and `Pause` when it ends.
GOG registers ffdshow from the game folder. A system-wide ffdshow install can claim some of the same CLSIDs, and the fix warns if it finds one.

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
- *Debugging:* set `FOCUSFIX_LOG=<file>` to get a log. `FOCUSFIX_DELAY=<ms>` changes the re-post delay.
- *Build:* `src\focusfix\build.cmd` (Visual Studio Build Tools, x86) writes `bin\msvfw32.dll`.

## Test tooling

`tests/smoke-test.ps1` starts the game and checks:
- the process is **not** elevated (token check);
- it clicks the System Checker's *Continue* button;
- the game's audio is measured through the Windows audio session meter;
- screenshots of the game window are taken;
- the Application log has no new crash entries.

See [tests/TESTING.md](../tests/TESTING.md).
