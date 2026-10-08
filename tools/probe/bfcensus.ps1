# Read-only. Works out which fixed pointers in BattlefrontII.exe always lead to
# the player's own soldier, by watching across several lives.
#
# Ground truth needs no pointer: soldiers are the heap objects whose first
# word is the soldier class (exe+SoldierType) and the player's is the one the
# camera sits a few metres behind. Each time that object changes (a new life),
# the exe image is searched for every slot pointing into it, and only slots
# seen for every life are kept.
param(
    [string]$ProcessName = 'BattlefrontII',
    [long]$SoldierType = 0x39D114,
    [long]$CameraOffset = 0x3DE3A8,
    [int]$Seconds = 150,
    [double]$MaxFromCamera = 12,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Census {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    public static float[] F3(IntPtr h, long addr) {
        var b = new byte[12]; IntPtr n;
        if (addr <= 0x10000 || !ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) return null;
        return new float[] { BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 4), BitConverter.ToSingle(b, 8) };
    }

    // Heap objects whose first word is `type`; returns address, x, y, z (position at +0x120) flattened.
    public static List<double> Soldiers(IntPtr h, long type, long imageLo, long imageHi) {
        var r = new List<double>();
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
                        r.Add(b + o); r.Add(x); r.Add(y); r.Add(z);
                    }
                }
            }
            addr = b + size;
        }
        return r;
    }

    public static long U32(IntPtr h, long addr) {
        var b = new byte[4]; IntPtr n;
        return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? (long)BitConverter.ToUInt32(b, 0) : -1;
    }

    // Two-step chains: exe slot -> some heap object -> the soldier. First collects every heap slot
    // holding a pointer into [unit, unit+span], then every exe slot pointing at most maxOff bytes
    // before one of those. Each result is "exeSlot > offsetInMiddleObject > offsetOfX".
    public static List<string> TwoStep(IntPtr h, long imageLo, long imageHi, long unit, int span, int maxOff) {
        var slots = new List<long>(); var vals = new List<long>();
        var image = new List<KeyValuePair<long, byte[]>>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && size <= (512L << 20)) {
                var d = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, d, (IntPtr)size, out got) && (long)got == size) {
                    if (b >= imageLo && b < imageHi) image.Add(new KeyValuePair<long, byte[]>(b, d));
                    else for (int o = 0; o + 4 <= d.Length; o += 4) {
                        long v = BitConverter.ToUInt32(d, o);
                        if (v >= unit && v <= unit + span) { slots.Add(b + o); vals.Add(v); }
                    }
                }
            }
            addr = b + size;
        }
        var result = new List<string>();   // slots is already in ascending order
        foreach (var kv in image) {
            byte[] d = kv.Value;
            for (int o = 0; o + 4 <= d.Length; o += 4) {
                long v = BitConverter.ToUInt32(d, o);
                if (v < 0x10000) continue;
                int i = slots.BinarySearch(v);
                if (i < 0) i = ~i;
                for (; i < slots.Count && slots[i] <= v + maxOff; i++)
                    result.Add(string.Format("0x{0:X} > 0x{1:X} > 0x{2:X}", kv.Key + o - imageLo, slots[i] - v, 0x120 - (vals[i] - unit)));
            }
        }
        return result;
    }

    // Slots inside the exe image holding a value in [lo, hi]; returns slot address, value pairs flattened.
    public static List<long> StaticPointers(IntPtr h, long imageLo, long imageHi, long lo, long hi) {
        var r = new List<long>();
        long addr = imageLo;
        while (addr < imageHi) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0) {
                var d = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, d, (IntPtr)size, out got) && (long)got == size) {
                    for (int o = 0; o + 4 <= d.Length; o += 4) {
                        long v = BitConverter.ToUInt32(d, o);
                        if (v >= lo && v <= hi) { r.Add(b + o); r.Add(v); }
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
$h = [Census]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$end = $base + $proc.MainModule.ModuleMemorySize

$current = $null; $stableCount = 0; $lives = @(); $common = $null; $common2 = $null
$cameraSlot = 0x1A296B0; $camAgree = 0; $camDisagree = 0   # the 3-of-4 slot from the first census
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $cam = [Census]::F3($h, $base + $CameraOffset)
    $flat = [Census]::Soldiers($h, $base + $SoldierType, $base, $end)
    $best = $null; $bestDist = [double]::MaxValue
    for ($i = 0; $i -lt $flat.Count; $i += 4) {
        $d = [Math]::Sqrt([Math]::Pow($flat[$i + 1] - $cam[0], 2) + [Math]::Pow($flat[$i + 2] - $cam[1], 2) + [Math]::Pow($flat[$i + 3] - $cam[2], 2))
        if ($d -lt $bestDist) { $bestDist = $d; $best = [long]$flat[$i] }
    }
    if ($bestDist -gt $MaxFromCamera) { $best = $null }
    if ($best) { if ([Census]::U32($h, $base + $cameraSlot) -eq $best + 0x120) { $camAgree++ } else { $camDisagree++ } }

    if ($best -ne $current) {
        "t+{0,3:N0}s  {1}" -f $sw.Elapsed.TotalSeconds, $(if ($best) { 'camera is now following soldier 0x{0:X8} ({1:N1} m away; {2} soldiers alive)' -f $best, $bestDist, ($flat.Count / 4) } else { 'camera is not following a soldier (dead, spawn screen or vehicle)' })
        $current = $best; $stableCount = 0
    } elseif ($best) {
        $stableCount++
        # Same soldier for three samples running: treat it as a life and record what points at it.
        if ($stableCount -eq 3) {
            $p = [Census]::StaticPointers($h, $base, $end, $best, $best + 0x200)
            $slots = @{}
            for ($i = 0; $i -lt $p.Count; $i += 2) { $slots['0x{0:X} > 0x{1:X}' -f ($p[$i] - $base), (0x120 - ($p[$i + 1] - $best))] = $true }
            $lives += , @{ Soldier = $best; Slots = $slots }
            if ($null -eq $common) { $common = @($slots.Keys) } else { $common = @($common | Where-Object { $slots.ContainsKey($_) }) }
            "t+{0,3:N0}s    life {1}: {2} fixed slots point into this soldier; {3} have done so for every life so far" -f $sw.Elapsed.TotalSeconds, $lives.Count, $slots.Count, $common.Count
            $two = @{}; foreach ($c in [Census]::TwoStep($h, $base, $end, $best, 0x200, 0x1000)) { $two[$c] = $true }
            if ($null -eq $common2) { $common2 = @($two.Keys) } else { $common2 = @($common2 | Where-Object { $two.ContainsKey($_) }) }
            "t+{0,3:N0}s    life {1}: {2:N0} two-step chains reach this soldier; {3:N0} have done so for every life so far" -f $sw.Elapsed.TotalSeconds, $lives.Count, $two.Count, $common2.Count
        }
    }
    Start-Sleep -Milliseconds 700
}
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)

"--- {0} lives seen ---" -f $lives.Count
"--- chains (exe-relative slot > offset of x) that pointed into the player's soldier in every life ---"
$common | Sort-Object | ForEach-Object { "  {0}.exe+{1}" -f $ProcessName, $_ }
if ($lives.Count) {
    "--- for comparison, slots seen in only some lives ---"
    $all = @{}; foreach ($l in $lives) { foreach ($k in $l.Slots.Keys) { $all[$k] = 1 + [int]$all[$k] } }
    $all.GetEnumerator() | Where-Object { $_.Value -lt $lives.Count } | Sort-Object Name | Select-Object -First 15 | ForEach-Object { "  {0}.exe+{1}   ({2} of {3} lives)" -f $ProcessName, $_.Name, $_.Value, $lives.Count }
}
if ($OutFile) { @{ lives = $lives.Count; common = @($common); common2 = @($common2) } | ConvertTo-Json | Set-Content -Encoding utf8 $OutFile }
"--- two-step chains (exe slot > offset in the middle object > offset of x) that reached the player's soldier in every life: {0} ---" -f @($common2).Count
$common2 | Sort-Object | Select-Object -First 60 | ForEach-Object { "  {0}.exe+{1}" -f $ProcessName, $_ }
"--- camera-target slot exe+0x{0:X}: pointed at the followed soldier's position in {1} of {2} samples ---" -f $cameraSlot, $camAgree, ($camAgree + $camDisagree)
