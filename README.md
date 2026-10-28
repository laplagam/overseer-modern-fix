# Tex Murphy: Overseer — Modern Windows Fix (GOG and Steam)

Makes the **GOG and Steam releases** of *Tex Murphy: Overseer* (1998) start and play on current Windows 10/11.
It doesn't ship any game files, and you can fully undo it.

## The problem

A fresh GOG or Steam install on Windows 11 closes right after the "System Checker" window (crash in `winmmbase.dll`).
If you get past that, entering the 3D world fails with **"ERROR: Error Code Does Not Indicate An Error"**.

## What the fix does

| Problem | Cause | Fix |
|---|---|---|
| Crash right after the System Checker | GOG and Steam set the *Windows 95* compatibility mode, which breaks Windows' audio/MIDI layer on current Windows | Uses *Windows 7* mode instead (the game still needs a compatibility mode to pass its Windows version check) |
| Always asks for admin rights | GOG and Steam add *Run as administrator*, and the Windows 95/98/XP modes also demand admin rights | Runs as a normal user. Steam re-applies its settings every time it starts the game, so for Steam the fix sets the game's **Launch Options** to start it through a link (`C:\TexOverseer-Steam`) that Steam's settings don't apply to |
| "Error Code Does Not Indicate An Error" when a game starts or loads | GOG's `Tex.ini` names the MIDI device `MIDI Mapper`, which doesn't exist on modern Windows | Sets the real name (`Microsoft MIDI Mapper`, read from Windows) |
| "Digital Sound Initialization Error" | Intel RSX 3D audio is missing or not registered | Checks RSX and, if needed, registers it from the game's own files |
| Crash at startup when installed in a long folder path | The game overflows an ~80 byte buffer when building `<folder>\FONTS.LS` | Detects long or non-English paths and starts the game through a short link (`C:\TexOverseer`) |
| Invisible/transparent objects, tiny 800×600 picture, mode switching | 1998 DirectDraw/Direct3D on modern GPUs | Bundles [dgVoodoo2](https://dege.freeweb.hu/dgVoodoo2/), which scales the game to your screen at the correct 4:3 aspect ratio |
| FMV videos | Need the ffdshow decoder bundled with the game | Makes sure it's registered from the game folder, and allows it for the game so ffdshow's "use ffdshow?" question (which pops up *behind* the game and silently answers "no") doesn't take the video sound away |
| Steam only: crash when the first video starts | The Steam overlay and a Windows compatibility hook both intercept Direct3D 9 and call each other forever | The same small DLL as below loads Direct3D 9 before either of them hooks it. Works with the overlay on or off |
| 3D view turns **all white** after a cinematic (e.g. picking up the magazine in Tex's office) | Alt+Tab (or anything stealing focus) during a cinematic makes the game reload its 3D world in the middle of the video | A small DLL (`msvfw32.dll`, source in [`src/focusfix`](src/focusfix)) holds the focus change back until the video ends |
| Music stops after Alt+Tab | The game stops the music when it loses focus and never restarts it | The same DLL keeps the game from seeing focus loss, so the music keeps playing (also while you're tabbed out) |

## Install

1. Install the game from GOG (Galaxy or the offline installer) or Steam. Starting it once is fine; expect it to crash.
2. **Steam users: exit Steam completely** (Steam menu → *Exit*). Steam overwrites its settings file while it runs, so the fix can only set the game's launch options while Steam is closed.
3. Download this fix (green **Code → Download ZIP** button, or a release zip) and unzip it anywhere.
4. Double-click **`Install.cmd`** and accept the admin prompt.
   The game folder is detected automatically; if you have both the GOG and the Steam version, both are fixed. If none is found, you'll be asked to select it.
5. Start the game as usual (from Steam for the Steam version).

On the System Checker window, click **Continue**.

> **GOG Galaxy "Verify / Repair"** or **Steam "Verify integrity of game files"** may put back the original files. If the game crashes again after that, just run `Install.cmd` again.

> **Steam: forgot to exit Steam?** The installer then shows the launch options to paste yourself: right-click the game in Steam → *Properties* → *General* → *Launch Options*:
> ```
> "C:\TexOverseer-Steam\OVERSEER.EXE" %command%
> ```
> Without them Steam starts the game with its own Windows 95 / admin settings and it crashes as before.

## Uninstall

Double-click **`Uninstall.cmd`**. Every file and registry value the fix changed is restored from the backup in `<game folder>\_overseerfix_backup`.
For the Steam version, exit Steam first so the original launch options can be put back.

## Problems?

Run **`Diagnose.cmd`**. It writes `overseer-diagnostics-<date>.txt` to your Desktop. Open an issue and attach that file.
Nothing is uploaded automatically.

## Tips

- **Controls:** arrow keys move, the mouse looks around. Move the mouse to the top of the screen to open the menu.
- **Space** skips videos; **Esc** goes back to the main menu.
- If the 3D view is ever white anyway, Alt+Tab out and back once while in 3D: the game then reloads its textures.
- dgVoodoo2's scaling and filtering can be adjusted in `dgVoodoo.conf` in the game folder.
  You can also use dgVoodoo's own control panel, from the [official package](https://dege.freeweb.hu/dgVoodoo2/).

## Tested on

- Windows 11 Pro build 26300 with an NVIDIA RTX 4070 Ti:
  - GOG build 2.1.0.23 (game v1.04 build 330);
  - Steam (app 302370; same game files as GOG).

Reports from other setups are welcome.

## Credits and licences

- The fix scripts, configuration and `focusfix` DLL are under the MIT licence (see [LICENSE](LICENSE)).
- dgVoodoo2 © Dege, redistributed unmodified under its terms. See [THIRD_PARTY.md](THIRD_PARTY.md).
- *Tex Murphy: Overseer* © Access Software / Big Finish Games. You need your own copy from [GOG](https://www.gog.com/game/tex_murphy_overseer) or [Steam](https://store.steampowered.com/app/302370/).

Technical details: [docs/TECHNICAL.md](docs/TECHNICAL.md) · Testing: [tests/TESTING.md](tests/TESTING.md)
