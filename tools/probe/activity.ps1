# Prints how many 4-byte words of a game's writable memory change per second,
# with whether the game is the foreground window at the time. A game that is
# idling shows a small fraction of the figure it shows while running.
param([string]$ProcessName = 'BattlefrontII', [int]$Samples = 3, [int]$GapMs = 1000)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Activity {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }

    public static Dictionary<long, byte[]> Take(IntPtr h) {
        var s = new Dictionary<long, byte[]>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var buf = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got) && (long)got == size) s[b] = buf;
            }
            addr = b + size;
        }
        return s;
    }

    public static long CountChanged(Dictionary<long, byte[]> a, Dictionary<long, byte[]> b) {
        long n = 0;
        foreach (var kv in a) {
            byte[] db;
            if (!b.TryGetValue(kv.Key, out db) || db.Length != kv.Value.Length) continue;
            byte[] da = kv.Value;
            for (int o = 0; o + 4 <= da.Length; o += 4) if (BitConverter.ToInt32(da, o) != BitConverter.ToInt32(db, o)) n++;
        }
        return n;
    }
}
'@

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$h = [Activity]::Open($proc.Id)
for ($i = 0; $i -lt $Samples; $i++) {
    $fp = 0; [void][Activity]::GetWindowThreadProcessId([Activity]::GetForegroundWindow(), [ref]$fp)
    $proc.Refresh()
    $a = [Activity]::Take($h); Start-Sleep -Milliseconds $GapMs; $b = [Activity]::Take($h)
    $rate = [Activity]::CountChanged($a, $b) * 1000 / $GapMs
    "{0}  focused={1,-5} minimised={2,-5} words changing/sec = {3,9:N0}" -f (Get-Date -Format 'HH:mm:ss'), ($fp -eq $proc.Id), [Activity]::IsIconic($proc.MainWindowHandle), $rate
    $a = $null; $b = $null; [GC]::Collect()
}
$r = New-Object Activity+RECT; [void][Activity]::GetWindowRect($proc.MainWindowHandle, [ref]$r)
$style = [Activity]::GetWindowLong($proc.MainWindowHandle, -16)
"window: {0}x{1} at ({2},{3}); title bar = {4}" -f ($r.R - $r.L), ($r.B - $r.T), $r.L, $r.T, (($style -band 0x00C00000) -eq 0x00C00000)
