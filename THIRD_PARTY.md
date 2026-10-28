# Third-party components

## Bundled

### dgVoodoo2 v2.87.5 — `third_party/dgVoodoo2/`
- Author: Dege — https://dege.freeweb.hu/dgVoodoo2/ · https://github.com/dege-diosg/dgVoodoo2
- Source: `dgVoodoo2_87_5.zip` from https://github.com/dege-diosg/dgVoodoo2/releases/tag/v2.87.5
  (SHA256 `5ffde6927f7355ca3fdd5d785b581256a8e6539fa13e395a891ade6ba1040850`)
- Files: `MS/x86/DDraw.dll`, `MS/x86/D3DImm.dll`, unmodified.

| File | SHA256 |
|---|---|
| DDraw.dll | `612a24408a090a3c6f3886557fa18034ee742e94ad0a40ebdf854d2816176c2e` |
| D3DImm.dll | `93c534f2d17419ea78f15551f7e0aac78b3c503733a840914fa063708a5afe8e` |

- Licence: the dgVoodoo2 readme, section "Redistribution rights", says:
  *"You can freely ship your game or game mod with unmodified individual dgVoodoo components (files) included."*
  This fix applies only to *Tex Murphy: Overseer*. It is not a general-purpose launcher or framework.
- `config/dgVoodoo.conf` is dgVoodoo's default configuration with these changes:
  - `ScalingMode = stretched_ar`
  - `dgVoodooWatermark = false`
  - `3DfxWatermark = false`
  - `ForceVerticalSync = false` (DirectX)

## Used from the game install (not shipped here)

| Component | Where it comes from |
|---|---|
| Intel RSX 3D (`RSX.DLL`, `AAUDIO.DLL`) | GOG installs it. If its registration is missing, the fix re-registers GOG's copy from `%ProgramData%\GOG.com\Galaxy\support\1207658769\…\dll` or `<game>\__support\…\dll`. |
| ffdshow (`ffdshow.ax`, `libavcodec.dll`, `libmplayer.dll`) | Shipped by GOG in the game folder. |
