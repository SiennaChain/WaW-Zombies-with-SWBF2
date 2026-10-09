# Read-only. How loud each game's sound is right now, as Windows' mixer has
# it: the loudest moment over a few seconds, with the volume and mute the
# mixer holds for the program.
#
# Battlefront II under World at War is never the window in front, and was
# silent for it until the bridge changed how its sounds are made
# (docs/PHASE3.md, "Sound"). This is how that was seen, and how each
# character's weapon was measured: hold its trigger through the bridge
# ([debug] force_functions = 1) and run this. A rifle reads about 0.2 of 1.
param([double]$Seconds = 4, [string[]]$Names = @('BattlefrontII', 'CoDWaW'))
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class AudioPeak {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device); }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface); }
  [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionManager2 { int NotImpl1(); int NotImpl2(); [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions); }
  [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int count); [PreserveSig] int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session); }
  [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionControl2 {
    int NotImpl0(); int NotImpl1(); int NotImpl2(); int NotImpl3(); int NotImpl4(); int NotImpl5(); int NotImpl6(); int NotImpl7(); int NotImpl8(); int NotImpl9(); int NotImpl10();
    [PreserveSig] int GetProcessId(out uint pid); }
  [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float peak); }
  [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ISimpleAudioVolume { int NotImpl0(); [PreserveSig] int GetMasterVolume(out float level); int NotImpl2(); [PreserveSig] int GetMute(out bool mute); }
  public static List<string> Listen(int[] pids, string[] names, double seconds) { var res = new List<string>();
    var en = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev); Guid iid = typeof(IAudioSessionManager2).GUID; object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    var mgr = (IAudioSessionManager2)o; IAudioSessionEnumerator sessions; mgr.GetSessionEnumerator(out sessions); int count; sessions.GetCount(out count);
    var meters = new List<IAudioMeterInformation>(); var whose = new List<string>(); var loudest = new List<float>();
    for (int i = 0; i < count; i++) { object s; sessions.GetSession(i, out s); uint pid; ((IAudioSessionControl2)s).GetProcessId(out pid); int at = Array.IndexOf(pids, (int)pid); if (at < 0) continue;
      float level; bool mute; var vol = (ISimpleAudioVolume)s; vol.GetMasterVolume(out level); vol.GetMute(out mute);
      meters.Add((IAudioMeterInformation)s); whose.Add(string.Format("{0} (mixer volume {1:N0}%{2})", names[at], level * 100, mute ? ", MUTED" : "")); loudest.Add(0); }
    if (meters.Count == 0) { res.Add("none of them has a sound session open"); return res; }
    var sw = System.Diagnostics.Stopwatch.StartNew(); while (sw.Elapsed.TotalSeconds < seconds) { for (int i = 0; i < meters.Count; i++) { float p; meters[i].GetPeakValue(out p); if (p > loudest[i]) loudest[i] = p; } System.Threading.Thread.Sleep(15); }
    for (int i = 0; i < meters.Count; i++) res.Add(string.Format("{0}: loudest {1:N3} of 1 over {2:N0} s", whose[i], loudest[i], seconds));
    return res; } }
'@
$procs = @(); foreach ($n in $Names) { $p = Get-Process $n -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { $procs += $p } }
if (-not $procs.Count) { 'neither game is running'; return }
[AudioPeak]::Listen([int[]]($procs | ForEach-Object { $_.Id }), [string[]]($procs | ForEach-Object { $_.ProcessName }), $Seconds)
