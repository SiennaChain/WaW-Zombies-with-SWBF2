# Read-only. Finds where World at War keeps the view it is drawing: the
# picture's size, the field of view, and where the eye is.
#
# The engine keeps these together: four integers (x, y, width, height), then
# the tangents of half the horizontal and half the vertical field of view,
# then the eye position and the three axes of the view. So the search is for
# 0, 0, <width>, <height> followed by two floats whose ratio is the picture's
# aspect, and each hit is checked against where the player is known to be.
param(
    [string]$ProcessName = 'CoDWaW',
    [int]$Width = 1280,
    [int]$Height = 720,
    [long]$Origin = 0x14ED088,   # player_origin, exe-relative
    [long]$Angles = 0x14ED18C    # view_angles, exe-relative
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class WawFov {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static float[] F(IntPtr h, long a, int c) { var b = new byte[4 * c]; IntPtr n; if (!ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)b.Length, out n)) return null; var f = new float[c]; for (int i = 0; i < c; i++) f[i] = BitConverter.ToSingle(b, 4 * i); return f; }

    public static List<long> Find(IntPtr h, int width, int height) {
        var hits = new List<long>(); long addr = 0x10000;
        while (addr < 0x7FFF0000L) {
            MBI m; if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize; if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && size <= (512L << 20)) {
                var buf = new byte[size]; IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got)) {
                    for (int o = 0; o + 24 <= buf.Length; o += 4) {
                        if (BitConverter.ToInt32(buf, o + 8) != width || BitConverter.ToInt32(buf, o + 12) != height) continue;
                        if (BitConverter.ToInt32(buf, o) != 0 || BitConverter.ToInt32(buf, o + 4) != 0) continue;
                        float tx = BitConverter.ToSingle(buf, o + 16), ty = BitConverter.ToSingle(buf, o + 20);
                        if (!(tx > 0.05f && tx < 5 && ty > 0.05f && ty < 5)) continue;
                        if (Math.Abs(tx / ty - (double)width / height) > 0.02) continue;
                        hits.Add(b + o);
                    }
                }
            }
            addr = b + size;
        }
        return hits;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [WawFov]::Open($proc.Id); $base = [int64]$proc.MainModule.BaseAddress; $end = $base + $proc.MainModule.ModuleMemorySize
$o = [WawFov]::F($h, $base + $Origin, 3); $a = [WawFov]::F($h, $base + $Angles, 3)
"player at ({0:N1}, {1:N1}, {2:N1}), looking pitch {3:N1} yaw {4:N1}" -f $o[0], $o[1], $o[2], $a[0], $a[1]
$hits = [WawFov]::Find($h, $Width, $Height)
"{0} places hold 0, 0, {1}, {2} followed by two tangents in that aspect" -f $hits.Count, $Width, $Height
foreach ($hit in $hits) {
    $f = [WawFov]::F($h, $hit + 16, 14)   # tanX, tanY, eye xyz, three axes
    $name = if ($hit -ge $base -and $hit -lt $end) { '{0}.exe+0x{1:X}' -f $ProcessName, ($hit - $base) } else { '0x{0:X8}' -f $hit }
    $eyeUp = $f[4] - $o[2]; $flat = [Math]::Sqrt([Math]::Pow($f[2] - $o[0], 2) + [Math]::Pow($f[3] - $o[1], 2))
    $yaw = [Math]::Atan2($f[6], $f[5]) * 180 / [Math]::PI; $pitch = -[Math]::Asin([Math]::Max(-1, [Math]::Min(1, $f[7]))) * 180 / [Math]::PI
    "  {0,-22} tangents {1:F4} x {2:F4} = {3:F1} x {4:F1} degrees; eye {5:N1} units from the player on the ground, {6:N1} above; first axis looks yaw {7:N1} pitch {8:N1}" -f $name, $f[0], $f[1], (2 * [Math]::Atan($f[0]) * 180 / [Math]::PI), (2 * [Math]::Atan($f[1]) * 180 / [Math]::PI), $flat, $eyeUp, $yaw, $pitch
}
