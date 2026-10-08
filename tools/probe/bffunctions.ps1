# Finds out what Battlefront II's game functions do, one number at a time.
#
# The bridge can hold any of the game's functions on from inside the game
# ([debug] force_functions in wawbf.ini, with [swbf2] forward_fire = 1). This
# holds each function in -Functions on for a moment, with nobody touching the
# game, and measures two things that give some of them away:
#
#   the vertical field of view   zoom narrows it
#   the height of the eye        crouching lowers it
#
# The rest have to be told by eye (see docs/PHASE2.md). It only reads the
# game; the holding is done by the bridge when it sees the setting change.
# A soldier has to be spawned. Some functions open things: 8 is "use", which
# at a command post brings up the class menu, and 17 to 28 include chat. Try
# unknown ones one at a time, watching. Zoom is a press, not a hold: running
# this on it an odd number of times leaves the soldier zoomed in.
param(
    [int[]]$Functions = @(5),
    [string]$Ini = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData\wawbf.ini',
    [int]$HoldMs = 900,
    [long]$ControlState = 0x1AC0918,   # player 1's control state, exe-relative
    [long]$ViewProjection = 0x3DE368,  # the camera's view-projection matrix
    [long]$UnitPointer = 0x1A296B0,    # pointer to the followed unit's position
    [long]$UnitType = 0x39D114         # what a soldier's first word points at
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class BfFunctions {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    static IntPtr proc; static long image;
    public static void Open(int pid, long imageBase) { proc = OpenProcess(0x0410, false, pid); image = imageBase; }   // read and query only
    static byte[] Bytes(long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(proc, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }
    public static uint U32(long a) { var b = Bytes(a, 4); return b == null ? 0 : BitConverter.ToUInt32(b, 0); }
    public static long Unit(long pointer, long type) { long pos = U32(image + pointer); return pos > 0x10000 && U32(pos - 0x120) == image + type ? pos - 0x120 : 0; }

    // Vertical field of view in degrees: the matrix's second column, less its
    // last entry, is the camera's up direction scaled by 1 / tan(half of it).
    public static double Fov(long matrix) {
        var b = Bytes(image + matrix, 64); if (b == null) return 0;
        double x = BitConverter.ToSingle(b, 4), y = BitConverter.ToSingle(b, 20), z = BitConverter.ToSingle(b, 36);
        double scale = Math.Sqrt(x * x + y * y + z * z);
        return scale > 0 ? 2 * Math.Atan(1 / scale) * 180 / Math.PI : 0;
    }
    public static double EyeHeight(long unit) { var b = Bytes(unit + 0x120, 12); var e = Bytes(unit + 0x31C, 12); return b == null || e == null ? 0 : BitConverter.ToSingle(e, 4) - BitConverter.ToSingle(b, 4); }

    // Polls for `ms`; returns { smallest fov, largest fov, lowest eye, highest eye, looks with the bit on }.
    public static double[] Sample(long state, uint bit, long matrix, long unit, int ms) {
        double fovLo = 1e9, fovHi = 0, eyeLo = 1e9, eyeHi = -1e9; int on = 0;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms) {
            double f = Fov(matrix), e = EyeHeight(unit);
            if (f > 0) { fovLo = Math.Min(fovLo, f); fovHi = Math.Max(fovHi, f); }
            eyeLo = Math.Min(eyeLo, e); eyeHi = Math.Max(eyeHi, e);
            if ((U32(image + state + 0x10) & bit) != 0) on++;
            System.Threading.Thread.Sleep(2);
        }
        return new[] { fovLo, fovHi, eyeLo, eyeHi, on };
    }
    public static bool WaitBit(long state, uint bit, bool want, int ms) {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms) { if (((U32(image + state + 0x10) & bit) != 0) == want) return true; System.Threading.Thread.Sleep(1); }
        return false;
    }
}
'@

function Set-Force([uint32]$Mask) {
    $text = (Get-Content $Ini -Raw) -replace '(?m)^force_functions\s*=.*$', ('force_functions = 0x{0:X}' -f $Mask)
    [IO.File]::WriteAllText($Ini, $text, (New-Object Text.ASCIIEncoding))
}

$bf = Get-Process BattlefrontII | Select-Object -First 1
[BfFunctions]::Open($bf.Id, [int64]$bf.MainModule.BaseAddress)
$unit = [BfFunctions]::Unit($UnitPointer, $UnitType)
if (-not $unit) { 'no soldier: spawn first'; exit 2 }

try {
    foreach ($n in $Functions) {
        $bit = [uint32]1 -shl $n
        $before = [BfFunctions]::Sample($ControlState, $bit, $ViewProjection, $unit, 300)
        Set-Force $bit
        if (-not [BfFunctions]::WaitBit($ControlState, $bit, $true, 3000)) { Set-Force 0; 'function {0,2}: the game never showed it on (is forward_fire = 1?)' -f $n; continue }
        $during = [BfFunctions]::Sample($ControlState, $bit, $ViewProjection, $unit, $HoldMs)
        Set-Force 0
        Start-Sleep -Milliseconds 1500   # the bridge rereads its settings once a second
        $after = [BfFunctions]::Sample($ControlState, $bit, $ViewProjection, $unit, 300)
        $notes = @()
        if ([Math]::Abs($during[0] - $before[0]) -gt 1) { $notes += 'the view narrowed' }
        if ($during[2] -lt $before[2] - 0.15) { $notes += 'the eye dropped' }
        if ($during[3] -gt $before[3] + 0.15) { $notes += 'the eye rose' }
        if ([Math]::Abs($after[2] - $before[2]) -gt 0.15) { $notes += 'and the eye stayed there after' }
        'function {0,2}: field of view {1:F1} -> {2:F1} -> {3:F1} degrees; eye height {4:F2} -> {5:F2}..{6:F2} -> {7:F2}  {8}' -f `
            $n, $before[0], $during[0], $after[0], $before[2], $during[2], $during[3], $after[2], $(if ($notes) { '<< ' + ($notes -join ', ') } else { '' })
    }
} finally { Set-Force 0 }
