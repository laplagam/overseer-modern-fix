/*
 * focusfix - msvfw32.dll proxy for Tex Murphy: Overseer
 *
 * Problem: when the game is re-activated (WM_ACTIVATEAPP TRUE, e.g. after Alt+Tab) it reloads
 * the 3D world to restore its lost DirectDraw surfaces ("Returning to Tex's office..."). That is
 * fine in 3D, but if it happens while a cinematic plays, the reload clashes with the video and
 * once the video ends every texture is gone: the 3D view is solid white until the next focus
 * change. Sending WM_ACTIVATEAPP(TRUE) to the game window mid-cinematic reproduces it.
 *
 * Fix: hold activation changes back while a video plays and hand them to the game once the
 * video has finished, so the reload always happens in normal 3D.
 *
 * - The game plays every video with a DirectShow filter graph created by TexDll.dll; it calls
 *   IMediaControl::Run when a video starts and Pause (or Stop) when it ends. We hook TexDll's
 *   CoCreateInstance import and the graph's IMediaControl vtable to track that.
 * - The game's main window is subclassed to hold back WM_ACTIVATEAPP while a video runs.
 *
 * This DLL sits in the game folder as msvfw32.dll, which OVERSEER.EXE imports directly (and
 * which is not a KnownDLL, so the game folder copy wins). Every export is forwarded to the real
 * system msvfw32.dll. (dsound.dll does not work as the host: rsx.dll loads the system copy
 * through COM before the game ever asks for it.)
 *
 * Set FOCUSFIX_LOG=<file> to write a log of what it does.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include "exports.h"

#define GAME_WINDOW_CLASS "Tex Murphy: Overseer"

/* ---- msvfw32 forwarding --------------------------------------------------------------------- */

#define X(name) FARPROC g_##name;
MSVFW32_EXPORTS(X)
#undef X

#define X(name) { #name, &g_##name },
static const struct { const char *name; FARPROC *slot; } g_exports[] = { MSVFW32_EXPORTS(X) };
#undef X

static HMODULE g_real;

static LRESULT WINAPI Unavailable(void) { return 0; }

static void LoadRealMsvfw32(void)
{
    char path[MAX_PATH];
    UINT len = GetSystemDirectoryA(path, MAX_PATH);   /* SysWOW64 for this 32-bit process */
    unsigned i;
    if (len == 0 || len > MAX_PATH - 14) return;
    lstrcatA(path, "\\msvfw32.dll");
    g_real = LoadLibraryA(path);
    for (i = 0; i < sizeof(g_exports) / sizeof(g_exports[0]); i++) {
        FARPROC p = g_real ? GetProcAddress(g_real, g_exports[i].name) : NULL;
        *g_exports[i].slot = p ? p : (FARPROC)Unavailable;
    }
}

/* Each export jumps straight to the real function, so arguments and calling convention are
 * passed through untouched. */
#define X(name) __declspec(naked) void Proxy_##name(void) { __asm { jmp dword ptr [g_##name] } }
MSVFW32_EXPORTS(X)
#undef X

/* ---- Debug log ------------------------------------------------------------------------------ */

static char g_logPath[MAX_PATH];

static void Log(const char *fmt, ...)
{
    char buf[256];
    va_list ap;
    DWORD n;
    HANDLE f;
    if (!g_logPath[0]) return;
    n = (DWORD)wsprintfA(buf, "%lu ", GetTickCount());
    va_start(ap, fmt);
    n += (DWORD)wvsprintfA(buf + n, fmt, ap);
    va_end(ap);
    f = CreateFileA(g_logPath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                    OPEN_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    WriteFile(f, buf, n, &n, NULL);
    CloseHandle(f);
}

/* ---- Focus filter --------------------------------------------------------------------------- */

static WNDPROC g_origProc;
static HWND g_gameWnd;
static volatile LONG g_videoPlaying;
static BOOL g_heldBack;      /* an activation change arrived during the video */

static BOOL GameIsForeground(void)
{
    DWORD pid = 0;
    HWND fg = GetForegroundWindow();
    if (fg) GetWindowThreadProcessId(fg, &pid);
    return pid == GetCurrentProcessId();
}

static LRESULT CALLBACK FilterProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_ACTIVATEAPP && !wParam) {
        Log("dropped WM_ACTIVATEAPP(0)\r\n");
        return 0;
    }
    if (msg == WM_ACTIVATEAPP && g_videoPlaying) {
        Log("held back WM_ACTIVATEAPP(1) during video\r\n");
        g_heldBack = TRUE;
        return 0;
    }
    return CallWindowProcA(g_origProc, hwnd, msg, wParam, lParam);
}

static DWORD g_replayDelay = 1500;   /* ms; FOCUSFIX_DELAY overrides */

/* Replays the focus change a video missed. The deactivate/activate pair makes the game do its
 * usual surface reload. It has to wait until the game is back in 3D after the video: done right
 * at the end of the video, the reload is undone again and the view stays white. */
static DWORD WINAPI ReplayThread(LPVOID unused)
{
    (void)unused;
    Sleep(g_replayDelay);
    if (g_videoPlaying) { g_heldBack = TRUE; return 0; }   /* next video started; wait for it */
    Log("replaying focus change (foreground=%d)\r\n", GameIsForeground());
    if (GameIsForeground()) PostMessageA(g_gameWnd, WM_ACTIVATEAPP, TRUE, 0);
    return 0;
}

/* Called on the game's thread when a video stops. */
static void VideoEnded(void)
{
    HANDLE t;
    if (!InterlockedExchange(&g_videoPlaying, 0) || !g_heldBack || !g_gameWnd) return;
    g_heldBack = FALSE;
    Log("video ended after a held-back focus change\r\n");
    t = CreateThread(NULL, 0, ReplayThread, NULL, 0, NULL);
    if (t) CloseHandle(t);
}

/* ---- Video tracking ------------------------------------------------------------------------- */

static const GUID CLSID_FilterGraph_ = { 0xE436EBB3, 0x524F, 0x11CE, { 0x9F, 0x53, 0x00, 0x20, 0xAF, 0x0B, 0xA7, 0x70 } };
static const GUID IID_IMediaControl_ = { 0x56A868B1, 0x0AD4, 0x11CE, { 0xB0, 0x3A, 0x00, 0x20, 0xAF, 0x0B, 0xA7, 0x70 } };

/* IMediaControl vtable slots (after IUnknown + IDispatch): Run = 7, Pause = 8, Stop = 9 */
typedef HRESULT (WINAPI *MediaControlCall_t)(void *);
static MediaControlCall_t g_origRun, g_origPause, g_origStop;

/* Debug log only: the names of the filters in the graph. */
static const GUID IID_IFilterGraph_ = { 0x56A8689F, 0x0AD4, 0x11CE, { 0xB0, 0x3A, 0x00, 0x20, 0xAF, 0x0B, 0xA7, 0x70 } };
static void LogFilters(void *mediaControl)
{
    IUnknown *unk = (IUnknown *)mediaControl, *graph = NULL, *en = NULL, *filter = NULL;
    ULONG got;
    if (!g_logPath[0] || FAILED(unk->lpVtbl->QueryInterface(unk, &IID_IFilterGraph_, (void **)&graph))) return;
    /* IFilterGraph::EnumFilters = slot 5, IEnumFilters::Next = 3, IBaseFilter::QueryFilterInfo = 12 */
    if (SUCCEEDED(((HRESULT (WINAPI *)(void *, IUnknown **))(*(void ***)graph)[5])(graph, &en))) {
        while (((HRESULT (WINAPI *)(void *, ULONG, IUnknown **, ULONG *))(*(void ***)en)[3])(en, 1, &filter, &got) == S_OK) {
            struct { WCHAR name[128]; IUnknown *graph; } info;
            if (SUCCEEDED(((HRESULT (WINAPI *)(void *, void *))(*(void ***)filter)[12])(filter, &info))) {
                char name[128];
                WideCharToMultiByte(CP_ACP, 0, info.name, -1, name, sizeof(name), NULL, NULL);
                Log("  filter: %s\r\n", name);
                if (info.graph) info.graph->lpVtbl->Release(info.graph);
            }
            filter->lpVtbl->Release(filter);
        }
        en->lpVtbl->Release(en);
    }
    graph->lpVtbl->Release(graph);
}

static HRESULT WINAPI HookRun(void *self)
{
    HRESULT hr = g_origRun(self);
    if (SUCCEEDED(hr)) { InterlockedExchange(&g_videoPlaying, 1); Log("video started\r\n"); LogFilters(self); }
    return hr;
}

static HRESULT WINAPI HookPause(void *self)
{
    HRESULT hr = g_origPause(self);
    VideoEnded();
    return hr;
}

static HRESULT WINAPI HookStop(void *self)
{
    HRESULT hr = g_origStop(self);
    VideoEnded();
    return hr;
}

/* No CRT here, so no memcmp/IsEqualGUID. */
static BOOL SameGuid(const GUID *a, const GUID *b)
{
    const DWORD *x = (const DWORD *)a, *y = (const DWORD *)b;
    return x[0] == y[0] && x[1] == y[1] && x[2] == y[2] && x[3] == y[3];
}

static void *PatchVtable(void **vtbl, int slot, void *hook)
{
    DWORD old;
    void *prev = vtbl[slot];
    if (prev == hook || !VirtualProtect(&vtbl[slot], sizeof(void *), PAGE_READWRITE, &old)) return NULL;
    vtbl[slot] = hook;
    VirtualProtect(&vtbl[slot], sizeof(void *), old, &old);
    return prev;
}

/* The IMediaControl vtable lives in quartz.dll and is shared by every filter graph, so patching
 * it once (on the first graph TexDll creates) covers all videos. */
static void HookMediaControl(IUnknown *graph)
{
    IUnknown *mc = NULL;
    void **vtbl;
    if (g_origRun || FAILED(graph->lpVtbl->QueryInterface(graph, &IID_IMediaControl_, (void **)&mc)))
        return;
    vtbl = *(void ***)mc;
    g_origPause = (MediaControlCall_t)PatchVtable(vtbl, 8, (void *)HookPause);
    g_origStop = (MediaControlCall_t)PatchVtable(vtbl, 9, (void *)HookStop);
    if (g_origPause && g_origStop) g_origRun = (MediaControlCall_t)PatchVtable(vtbl, 7, (void *)HookRun);
    Log("IMediaControl hooked: %d\r\n", g_origRun != NULL);
    mc->lpVtbl->Release(mc);
}

typedef HRESULT (WINAPI *CoCreateInstance_t)(REFCLSID, LPUNKNOWN, DWORD, REFIID, LPVOID *);
static CoCreateInstance_t g_origCoCreate;

static HRESULT WINAPI HookCoCreate(REFCLSID clsid, LPUNKNOWN outer, DWORD ctx, REFIID iid, LPVOID *pv)
{
    HRESULT hr = g_origCoCreate(clsid, outer, ctx, iid, pv);
    if (SUCCEEDED(hr) && pv && *pv && SameGuid(clsid, &CLSID_FilterGraph_))
        HookMediaControl((IUnknown *)*pv);
    return hr;
}
/* Point module `mod`'s import of dll!func at `hook`; returns the previous target or NULL. */
static void *HookImport(HMODULE mod, const char *dll, const char *func, void *hook)
{
    BYTE *base = (BYTE *)mod;
    IMAGE_NT_HEADERS *nt;
    IMAGE_DATA_DIRECTORY *dir;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    if (!base) return NULL;
    nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir->VirtualAddress) return NULL;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir->VirtualAddress); imp->Name; imp++) {
        IMAGE_THUNK_DATA *names, *iat;
        if (lstrcmpiA((char *)(base + imp->Name), dll) != 0) continue;
        names = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        iat = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        for (; names->u1.AddressOfData; names++, iat++) {
            DWORD old;
            void *prev;
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            if (lstrcmpA((char *)((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name, func) != 0) continue;
            if (!VirtualProtect(&iat->u1.Function, sizeof(iat->u1.Function), PAGE_READWRITE, &old)) return NULL;
            prev = (void *)iat->u1.Function;
            iat->u1.Function = (DWORD_PTR)hook;
            VirtualProtect(&iat->u1.Function, sizeof(iat->u1.Function), old, &old);
            return prev;
        }
    }
    return NULL;
}

/* ---- Startup -------------------------------------------------------------------------------- */

static BOOL CALLBACK FindGameWindow(HWND hwnd, LPARAM lParam)
{
    char cls[64];
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId() && GetClassNameA(hwnd, cls, sizeof(cls)) &&
        lstrcmpA(cls, GAME_WINDOW_CLASS) == 0) {
        *(HWND *)lParam = hwnd;
        return FALSE;
    }
    return TRUE;
}

static DWORD WINAPI WatchThread(LPVOID unused)
{
    int tries;
    (void)unused;
    /* Runs after the loader has finished, so TexDll's imports are bound by now. */
    g_origCoCreate = (CoCreateInstance_t)HookImport(GetModuleHandleA("TexDll.dll"), "ole32.dll",
                                                    "CoCreateInstance", (void *)HookCoCreate);
    Log("TexDll CoCreateInstance hooked: %d\r\n", g_origCoCreate != NULL);
    /* The main window is created shortly after startup; poll for up to 10 minutes. */
    for (tries = 0; tries < 6000 && !g_gameWnd; tries++) {
        HWND found = NULL;
        EnumWindows(FindGameWindow, (LPARAM)&found);
        if (found) {
            g_origProc = (WNDPROC)SetWindowLongPtrA(found, GWLP_WNDPROC, (LONG_PTR)FilterProc);
            if (g_origProc) g_gameWnd = found;
            Log("game window subclassed: %d\r\n", g_gameWnd != NULL);
            break;
        }
        Sleep(100);
    }
    return 0;
}

/* Steam crash fix. When a video starts, DirectShow tries Windows' video renderers and decoders
 * as candidates, and they call Direct3DCreate9/Direct3DCreate9Ex. Under Steam those calls never
 * returned: the Steam overlay (injected even when it is switched off for the game) and Windows'
 * DWM8And16Bit compatibility hook both hooked them and called each other until the stack
 * overflowed. Having d3d9.dll loaded from the start, before either of them hooks it, avoids
 * that. */
static void PreloadD3d9(void)
{
    char path[MAX_PATH];
    UINT len = GetSystemDirectoryA(path, MAX_PATH);
    if (len == 0 || len > MAX_PATH - 12) return;
    lstrcatA(path, "\\d3d9.dll");
    LoadLibraryA(path);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        HANDLE t;
        DisableThreadLibraryCalls(inst);
        char delay[16];
        if (!GetEnvironmentVariableA("FOCUSFIX_LOG", g_logPath, MAX_PATH)) g_logPath[0] = 0;
        if (GetEnvironmentVariableA("FOCUSFIX_DELAY", delay, sizeof(delay))) {
            DWORD v = 0;
            char *p;
            for (p = delay; *p >= '0' && *p <= '9'; p++) v = v * 10 + (*p - '0');
            g_replayDelay = v;
        }
        LoadRealMsvfw32();
        PreloadD3d9();
        t = CreateThread(NULL, 0, WatchThread, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    return TRUE;
}
