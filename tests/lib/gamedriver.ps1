# Helpers to drive the game from tests: find windows, click dialog buttons, send input,
# take screenshots of the game window and measure the game's audio output.

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public static class GameWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, int f, IntPtr e);
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("advapi32.dll")] public static extern bool OpenProcessToken(IntPtr p, int access, out IntPtr t);
  [DllImport("advapi32.dll")] public static extern bool GetTokenInformation(IntPtr t, int cls, out int info, int len, out int ret);

  // TokenElevation = 20. Returns 1 if elevated, 0 if not, -1 if unknown.
  public static int IsElevated(int pid) {
    IntPtr p = OpenProcess(0x1000, false, pid); if (p == IntPtr.Zero) return -1;
    IntPtr t; if (!OpenProcessToken(p, 0x8, out t)) { CloseHandle(p); return -1; }
    int e, r; bool ok = GetTokenInformation(t, 20, out e, 4, out r); CloseHandle(t); CloseHandle(p);
    return ok ? (e != 0 ? 1 : 0) : -1;
  }

  public static List<IntPtr> TopWindows(int pid) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => { int w; GetWindowThreadProcessId(h, out w); if (w == pid && IsWindowVisible(h)) res.Add(h); return true; }, IntPtr.Zero);
    return res;
  }

  public static bool ClickButton(int pid, string text) {
    bool hit = false;
    foreach (var top in TopWindows(pid)) {
      EnumChildWindows(top, (c, l) => {
        var sb = new StringBuilder(128); GetWindowText(c, sb, 128);
        if (sb.ToString() == text) { SendMessage(c, 0xF5, IntPtr.Zero, IntPtr.Zero); hit = true; }
        return true; }, IntPtr.Zero);
      if (hit) return true;
    }
    return false;
  }

  public static string ClassOf(IntPtr h) { var sb = new StringBuilder(128); GetClassName(h, sb, 128); return sb.ToString(); }
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface); }
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 { int NotImpl1(); int NotImpl2(); [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e); }
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int n); [PreserveSig] int GetSession(int i, out IAudioSessionControl2 s); }
[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
  int NotImpl0(); int GetDisplayName(out IntPtr p); int SetDisplayName(); int GetIconPath(out IntPtr p); int SetIconPath();
  int GetGroupingParam(out Guid g); int SetGroupingParam(); int RegisterAudioSessionNotification(); int UnregisterAudioSessionNotification();
  int GetSessionIdentifier(out IntPtr p); int GetSessionInstanceIdentifier(out IntPtr p); [PreserveSig] int GetProcessId(out uint pid); }
[Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float peak); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
public static class GameAudio {
  // Highest current peak level among the audio sessions owned by the given process.
  public static float Peak(uint pid) {
    float best = 0;
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCom());
    IMMDevice dev; if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) return 0;
    Guid iid = typeof(IAudioSessionManager2).GUID; object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    IAudioSessionEnumerator se; ((IAudioSessionManager2)o).GetSessionEnumerator(out se);
    int n; se.GetCount(out n);
    for (int i = 0; i < n; i++) {
      IAudioSessionControl2 s; se.GetSession(i, out s); uint p; s.GetProcessId(out p);
      if (p != pid) continue;
      float v; ((IAudioMeterInformation)s).GetPeakValue(out v); if (v > best) best = v;
    }
    return best;
  }
}
'@

function Test-ProcessElevated($Process) { [GameWin]::IsElevated($Process.Id) -ne 0 }

function Wait-AndClick($Process, [string]$Button, [int]$Seconds = 15) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline -and -not $Process.HasExited) {
        if ([GameWin]::ClickButton($Process.Id, $Button)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    $false
}

function Send-Key([int]$VirtualKey) {
    [GameWin]::keybd_event([byte]$VirtualKey, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 80
    [GameWin]::keybd_event([byte]$VirtualKey, 0, 2, [IntPtr]::Zero)
}

function Measure-ProcessAudio([int]$ProcessId, [int]$Seconds = 5) {
    $max = 0; $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        $v = [GameAudio]::Peak([uint32]$ProcessId); if ($v -gt $max) { $max = $v }
        Start-Sleep -Milliseconds 200
    }
    $max
}

function Save-GameShot($Process, [string]$Path) {
    if ($Process.HasExited) { return $false }
    $h = [GameWin]::TopWindows($Process.Id) | Where-Object { [GameWin]::ClassOf($_) -eq 'Tex Murphy: Overseer' } | Select-Object -First 1
    if (-not $h) { $h = [GameWin]::TopWindows($Process.Id) | Select-Object -First 1 }
    if (-not $h) { return $false }
    $r = New-Object GameWin+RECT; [void][GameWin]::GetWindowRect($h, [ref]$r)
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    if ($w -le 0 -or $ht -le 0) { return $false }
    $bmp = New-Object Drawing.Bitmap $w, $ht; $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object Drawing.Size $w, $ht))
    $bmp.Save($Path); $g.Dispose(); $bmp.Dispose()
    $true
}
