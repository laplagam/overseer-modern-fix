# Tex Murphy: Overseer — Modern Windows Fix (GOG and Steam)

The GOG and Steam versions of *Tex Murphy: Overseer* (1998) don't run properly on Windows 10/11.
They crash at startup, ask for admin rights, show invisible objects, and lose sound or music.

**This fix sorts all of that out in one go: download it, run `Install.cmd`, and play.**
It doesn't contain any game files, everything it changes is backed up, and `Uninstall.cmd` puts it all back.

## Quick start

1. **Steam users:** exit Steam completely (Steam menu → *Exit*).
2. Download this fix (green **Code → Download ZIP** button) and unzip it anywhere.
3. Double-click **`Install.cmd`** and click *Yes* on the admin prompt.
   It finds the game by itself. If you have both the GOG and the Steam version, it fixes both.
4. Start the game the way you normally would:
   - **GOG:** the desktop shortcut, GOG Galaxy, or `OVERSEER.EXE` in the game folder.
   - **Steam:** the normal **Play** button.

   When the *System Checker* window appears, click **Continue**.

## What it fixes

| If you see this... | ...the fix does this |
|---|---|
| The game closes right after the System Checker window | Replaces the *Windows 95* compatibility mode that GOG and Steam set (it breaks sound on today's Windows) with *Windows 7* mode |
| Windows asks for administrator rights every time | Lets the game run as a normal user. For Steam it also sets the game's *Launch Options*, because Steam would otherwise put its own admin setting back each time |
| **"ERROR: Error Code Does Not Indicate An Error"** when starting or loading a game | Points the game at the music device that actually exists on modern Windows |
| **"Digital Sound Initialization Error"** | Makes sure the game's 3D sound component (Intel RSX) is installed |
| Invisible or see-through objects, a tiny picture, the screen switching resolution | Adds [dgVoodoo2](https://dege.freeweb.hu/dgVoodoo2/), which draws the old graphics correctly and scales the game to your screen at 4:3 |
| Videos play without sound | Sets up the video decoder that comes with the game, and stops its hidden pop-up from switching itself off |
| Steam: crash when the first video starts | A small helper DLL from this fix stops the Steam overlay and Windows from clashing |
| The 3D view turns **all white** after a cinematic if you Alt+Tab during it (e.g. picking up the magazine in Tex's office) | The helper DLL holds the window switch back until the video has ended |
| The music stops after Alt+Tab | The helper DLL keeps the music playing |
| Crash at startup when the game is installed in a long folder path | Starts the game through a short link (`C:\TexOverseer`) |

The helper DLL is written for this fix; its source is in [`src/focusfix`](src/focusfix).
The full technical story behind each problem is in [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Good to know

- **After GOG Galaxy "Verify / Repair" or Steam "Verify integrity of game files"**, the original settings may come back. If the game crashes again, just run `Install.cmd` again.
- **Steam: forgot to exit Steam before installing?** The installer then shows a line to paste yourself. Right-click the game in Steam → *Properties* → *General* → *Launch Options*, and paste:
  ```
  "C:\TexOverseer-Steam\OVERSEER.EXE" %command%
  ```
- **Controls:** the arrow keys move and the mouse looks around. Move the mouse to the top of the screen for the menu. **Space** skips videos; **Esc** goes back to the main menu.
- If the 3D view is ever white anyway, Alt+Tab out and back once while in 3D. The game then reloads its textures.
- Picture scaling and filtering can be changed in `dgVoodoo.conf` in the game folder.

## Uninstall

Exit Steam if you use the Steam version, then double-click **`Uninstall.cmd`**. Every change is restored from the backup, for every copy of the game it finds.
To install or uninstall only one copy, give its folder from a command prompt, e.g. `Uninstall.cmd -GameDir "D:\SteamLibrary\steamapps\common\Overseer"`.

## Problems?

Run **`Diagnose.cmd`**. It saves `overseer-diagnostics-<date>.txt` on your Desktop. [Open an issue](../../issues) and attach that file.
Nothing is uploaded automatically.

## Tested on

- Windows 11 Pro build 26300 with an NVIDIA RTX 4070 Ti:
  - GOG build 2.1.0.23 (game v1.04 build 330);
  - Steam (app 302370; same game files as GOG).

Reports from other setups are welcome.

## Credits and licences

- The fix scripts, configuration and helper DLL are under the MIT licence (see [LICENSE](LICENSE)).
- dgVoodoo2 © Dege, redistributed unmodified under its terms. See [THIRD_PARTY.md](THIRD_PARTY.md).
- *Tex Murphy: Overseer* © Access Software / Big Finish Games. You need your own copy from [GOG](https://www.gog.com/game/tex_murphy_overseer) or [Steam](https://store.steampowered.com/app/302370/).

Technical details: [docs/TECHNICAL.md](docs/TECHNICAL.md) · Testing: [tests/TESTING.md](tests/TESTING.md)
