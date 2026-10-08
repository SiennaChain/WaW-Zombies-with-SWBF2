# Pointer scan: finds fixed places in BattlefrontII.exe that lead to a heap
# address (the unit's position moves every spawn, so the bridge needs a chain
# that starts somewhere fixed). Level 1 is a pointer in the exe image that
# points at most MaxOffset bytes before the target. Level 2 goes through one
# intermediate heap object.
param(
    [string]$ProcessName = 'BattlefrontII',
    [string]$TargetHex,            # address of the x coordinate, e.g. 09AE37B0
    [int]$MaxOffset = 0x1000,
    [string]$OutFile
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class PtrScan {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }

    public class Hit { public long Slot; public long Value; }

    // Every 4-byte-aligned slot in readable memory whose value lies in [lo, hi].
    public static List<Hit> FindPointers(IntPtr h, long lo, long hi) {
        var hits = new List<Hit>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && size <= (512L << 20)) {
                var buf = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got) && (long)got == size) {
                    for (int o = 0; o + 4 <= buf.Length; o += 4) {
                        long v = BitConverter.ToUInt32(buf, o);
                        if (v >= lo && v <= hi) hits.Add(new Hit { Slot = b + o, Value = v });
                    }
                }
            }
            addr = b + size;
        }
        return hits;
    }
}
'@

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$h = [PtrScan]::Open($proc.Id)
$imageBase = [int64]$proc.MainModule.BaseAddress
$imageEnd = $imageBase + $proc.MainModule.ModuleMemorySize
$target = [Convert]::ToInt64($TargetHex, 16)
function In-Image([long]$a) { $a -ge $imageBase -and $a -lt $imageEnd }

$l1 = [PtrScan]::FindPointers($h, $target - $MaxOffset, $target)
$static1 = @($l1 | Where-Object { In-Image $_.Slot })
"target 0x{0:X8}: {1} slots anywhere point within 0x{2:X} before it; {3} of those are in the exe image" -f $target, $l1.Count, $MaxOffset, $static1.Count
"--- level 1 (exe -> object) ---"
$chains = @()
foreach ($s in ($static1 | Sort-Object Slot)) {
    $chain = '{0}.exe+0x{1:X} > 0x{2:X}' -f $ProcessName, ($s.Slot - $imageBase), ($target - $s.Value)
    $chains += $chain; "  $chain      (object at 0x{0:X8})" -f $s.Value
}
"--- which object starts do the pointers agree on? ---"
$l1 | Group-Object Value | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "  0x{0:X8} (target is +0x{1:X}): {2} pointers, {3} in exe" -f [long]$_.Name, ($target - [long]$_.Name), $_.Count, @($_.Group | Where-Object { In-Image $_.Slot }).Count }

"--- level 2 (exe -> heap object -> object) ---"
$heap1 = @($l1 | Where-Object { -not (In-Image $_.Slot) } | Sort-Object Slot)
$shown = 0
foreach ($p in $heap1) {
    if ($shown -ge 40) { break }
    foreach ($s in ([PtrScan]::FindPointers($h, $p.Slot - $MaxOffset, $p.Slot) | Where-Object { In-Image $_.Slot })) {
        $chain = '{0}.exe+0x{1:X} > 0x{2:X} > 0x{3:X}' -f $ProcessName, ($s.Slot - $imageBase), ($p.Slot - $s.Value), ($target - $p.Value)
        $chains += $chain; "  $chain"; $shown++
    }
}
if ($OutFile) { @{ pid = $proc.Id; target = $target; chains = $chains } | ConvertTo-Json | Set-Content -Encoding utf8 $OutFile }
"total chains: $($chains.Count)"
