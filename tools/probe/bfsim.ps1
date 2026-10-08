# Read-only. Answers "is the Battlefront II match actually playing?" by
# counting how many soldiers changed position between two looks.
#
# Use this, not memory activity, to judge whether the game is paused: a paused
# match still redraws and changes hundreds of thousands of memory words a
# second, but nobody moves.
param(
    [string]$ProcessName = 'BattlefrontII',
    [long]$SoldierType = 0x39D114,   # first word of a soldier object, exe-relative
    [int]$GapMs = 1500,
    [int]$Repeats = 1
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfSim {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    // address -> x, y, z of every heap object whose first word is `type` (position at +0x120).
    public static Dictionary<long, float[]> Soldiers(IntPtr h, long type, long imageLo, long imageHi) {
        var r = new Dictionary<long, float[]>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (!(b >= imageLo && b < imageHi) && m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var d = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, d, (IntPtr)size, out got) && (long)got == size) {
                    for (int o = 0; o + 0x12C <= d.Length; o += 4) {
                        if (BitConverter.ToUInt32(d, o) != (uint)type) continue;
                        float x = BitConverter.ToSingle(d, o + 0x120), y = BitConverter.ToSingle(d, o + 0x124), z = BitConverter.ToSingle(d, o + 0x128);
                        if (!(Math.Abs(x) < 5000f && Math.Abs(y) < 2000f && Math.Abs(z) < 5000f)) continue;
                        r[b + o] = new float[] { x, y, z };
                    }
                }
            }
            addr = b + size;
        }
        return r;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [BfSim]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$end = $base + $proc.MainModule.ModuleMemorySize
for ($i = 0; $i -lt $Repeats; $i++) {
    $fp = 0; [void][BfSim]::GetWindowThreadProcessId([BfSim]::GetForegroundWindow(), [ref]$fp)
    $a = [BfSim]::Soldiers($h, $base + $SoldierType, $base, $end)
    Start-Sleep -Milliseconds $GapMs
    $b = [BfSim]::Soldiers($h, $base + $SoldierType, $base, $end)
    $moved = 0
    foreach ($k in $a.Keys) {
        if (-not $b.ContainsKey($k)) { continue }
        $p = $a[$k]; $q = $b[$k]
        if ([Math]::Abs($p[0] - $q[0]) + [Math]::Abs($p[1] - $q[1]) + [Math]::Abs($p[2] - $q[2]) -gt 0.05) { $moved++ }
    }
    "{0}  game focused={1,-5}  soldiers={2,3}  moved in {3} ms: {4,3}  ->  {5}" -f (Get-Date -Format 'HH:mm:ss'), ($fp -eq $proc.Id), $a.Count, $GapMs, $moved, $(if ($a.Count -eq 0) { 'not in a match' } elseif ($moved -ge 2) { 'PLAYING' } else { 'PAUSED (or everyone is standing still)' })
}
