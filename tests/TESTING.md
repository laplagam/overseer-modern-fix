# Testing

## Automated smoke test

```powershell
powershell -ExecutionPolicy Bypass -File tests\smoke-test.ps1            # auto-detects the GOG install
powershell -ExecutionPolicy Bypass -File tests\smoke-test.ps1 -GameDir "D:\Games\Overseer"
```

The game takes over the screen for about 30 seconds; don't touch the mouse or keyboard while it runs.

It checks five things:
- the game starts without admin rights;
- it gets past the System Checker;
- the opening video has sound;
- it reaches the main menu;
- no crash is logged.

Screenshots are saved to `tests\logs\`.

Expected results:
- **Before the fix:** fails, either by elevating or crashing.
- **After the fix:** `All checks passed.`

## Manual checklist

Run through this after installing the fix. Note your Windows build, GPU and screen resolution in the bug report or PR.

- [ ] Access logo video plays with sound
- [ ] Main menu appears, scaled to the screen with black bars on the sides
- [ ] **New Game** → enter a name → **Begin** → choose play level → **OK**
- [ ] Intro video plays with sound and subtitles; Space skips
- [ ] Tex's office (3D):
  - [ ] walls, furniture and objects are all visible
  - [ ] no flicker when turning
  - [ ] music plays
- [ ] Look at an item and pick it up; the inventory exam video plays
- [ ] Talk to a character (dialogue choices appear)
- [ ] Travel to another location
- [ ] **Save**, quit, start again, **Load**
- [ ] Alt+Tab out and back in 3D: textures stay visible, music keeps playing
- [ ] Alt+Tab out and back **during a cinematic** (e.g. pick up the magazine by the office door): the video continues, and the office is textured (not white) afterwards
- [ ] **Exit Game** closes cleanly (no crash dialog)
