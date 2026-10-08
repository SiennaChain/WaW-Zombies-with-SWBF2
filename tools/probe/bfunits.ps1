# Read-only. Finds every soldier object in Battlefront II by its shape in
# memory, then says which one the camera is following (the player's).
#
# Shape, learned from the unit the lift test confirmed: the position (x, y, z)
# is at +0x120 and the same x and z are repeated at +0x18 and +0x7C.
# The camera is the 4x4 matrix at exe+0x3DE378; its position is the last row.
param(
    [string]$ProcessName = 'BattlefrontII',
    [int]$Repeats = 1,
    [int]$GapMs = 1500,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfUnits {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    public class Unit { public long Address; public long VTable; public float X, Y, Z; }

    public static float[] F3(IntPtr h, long addr) {
        var b = new byte[12]; IntPtr n;
        if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) return null;
        return new float[] { BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 4), BitConverter.ToSingle(b, 8) };
    }

    static bool Same(float a, float b) { return Math.Abs(a - b) <= 0.001f; }

    public static List<Unit> Find(IntPtr h, long skipLo, long skipHi) {
        var units = new List<Unit>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            bool inImage = b >= skipLo && b < skipHi;
            if (!inImage && m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var d = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, d, (IntPtr)size, out got) && (long)got == size) {
                    for (int o = 0; o + 0x12C <= d.Length; o += 4) {
                        float x = BitConverter.ToSingle(d, o + 0x120);
                        float ax = Math.Abs(x);
                        if (!(ax > 0.01f && ax < 5000f)) continue;
                        if (!Same(BitConverter.ToSingle(d, o + 0x7C), x) || !Same(BitConverter.ToSingle(d, o + 0x18), x)) continue;
                        float z = BitConverter.ToSingle(d, o + 0x128);
                        float az = Math.Abs(z);
                        if (!(az > 0.01f && az < 5000f)) continue;
                        if (!Same(BitConverter.ToSingle(d, o + 0x84), z) || !Same(BitConverter.ToSingle(d, o + 0x20), z)) continue;
                        float y = BitConverter.ToSingle(d, o + 0x124);
                        if (!(Math.Abs(y) < 2000f)) continue;
                        units.Add(new Unit { Address = b + o, VTable = BitConverter.ToUInt32(d, o), X = x, Y = y, Z = z });
                    }
                }
            }
            addr = b + size;
        }
        return units;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [BfUnits]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$end = $base + $proc.MainModule.ModuleMemorySize

for ($i = 0; $i -lt $Repeats; $i++) {
    $cam = [BfUnits]::F3($h, $base + 0x3DE3A8)
    $units = [BfUnits]::Find($h, $base, $end)
    $rows = foreach ($u in $units) {
        [pscustomobject]@{ Address = $u.Address; VTable = $u.VTable; X = $u.X; Y = $u.Y; Z = $u.Z
            FromCamera = [Math]::Sqrt([Math]::Pow($u.X - $cam[0], 2) + [Math]::Pow($u.Y - $cam[1], 2) + [Math]::Pow($u.Z - $cam[2], 2)) }
    }
    $rows = @($rows | Sort-Object FromCamera)
    "{0}  camera ({1,8:N1}, {2,6:N1}, {3,8:N1})   objects with the soldier shape: {4}" -f (Get-Date -Format 'HH:mm:ss'), $cam[0], $cam[1], $cam[2], $rows.Count
    if (-not $Quiet) {
        "  by type: " + (($rows | Group-Object VTable | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { 'exe+0x{0:X} x{1}' -f ($_.Name - $base), $_.Count }) -join ', ')
        $rows | Select-Object -First 6 | ForEach-Object { "    0x{0:X8}  type exe+0x{1:X}  ({2,8:N1}, {3,6:N1}, {4,8:N1})  {5,6:N1} m from camera" -f $_.Address, ($_.VTable - $base), $_.X, $_.Y, $_.Z, $_.FromCamera }
    } elseif ($rows.Count) {
        "    nearest: 0x{0:X8}  ({1,8:N1}, {2,6:N1}, {3,8:N1})  {4,5:N1} m from camera; next nearest {5:N1} m" -f $rows[0].Address, $rows[0].X, $rows[0].Y, $rows[0].Z, $rows[0].FromCamera, $(if ($rows.Count -gt 1) { $rows[1].FromCamera } else { [double]::NaN })
    }
    if ($i + 1 -lt $Repeats) { Start-Sleep -Milliseconds $GapMs }
}
