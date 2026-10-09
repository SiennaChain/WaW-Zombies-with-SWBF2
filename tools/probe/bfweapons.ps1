# Finds where Battlefront II keeps "which weapon is in hand".
#
# The bridge can press any of the game's functions from inside the game
# ([debug] force_functions in wawbf.ini, with [swbf2] forward_fire = 1). This
# presses one of them a few times, with nobody touching the game, and after
# each press says which words of the player's unit changed and stayed changed.
# Words that change by themselves (timers, the animation) are found first, by
# watching for a while without pressing, and left out.
#
#   bfweapons.ps1 -Function 13            press function 13 three times
#   bfweapons.ps1 -Function 15 -Presses 4
#   bfweapons.ps1 -Function -1            press nothing: only list what the words hold (-Show)
#   bfweapons.ps1 -Slot 1 -Function 1     watch the weapon in the unit's slot 1 instead of the unit
#
# A word that steps 0, 1, 0, 1 as a two-weapon soldier's "next weapon" is
# pressed is the one. It only reads the game; the pressing is done by the
# bridge when it sees the setting change. A soldier has to be spawned.
#
# What it found (the Steam build): the unit holds pointers to its weapons, up
# to eight, from +0x720, and at +0x740 and +0x741 the slot in hand for each of
# the two channels (primary, secondary). Function 13 is "next primary", 15
# "next secondary".
param(
    [int]$Function = 13,
    [int]$Presses = 3,
    [string]$Ini = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData\wawbf.ini',
    [int]$Size = 0xFD0,                # how much of the unit to watch, in bytes (a soldier is 0xFD0)
    [int]$Slot = -1,                   # 0..7: watch the weapon in this slot of the unit instead
    [int]$HoldMs = 0,                  # keep the function on this long (for the ones that are held)
    [int]$TraceMs = 0,                 # instead: press once and list every word that changes in this long, with when (-HoldMs in, it is let go)
    [int]$Most = 7,                    # how many values to list for each word in a trace
    [long]$UnitWeapons = 0x720,        # in the unit: pointers to its weapons
    [int]$WeaponSize = 0x1C0,
    [int]$QuietMs = 2500,              # how long to watch for words that change by themselves
    [int]$SettleMs = 1200,             # how long after a press before looking
    [int[]]$Show = @(),                # offsets to print after every step, whatever they do
    [long]$ControlState = 0x1AC0918,   # player 1's control state, exe-relative
    [long]$UnitPointer = 0x1A296B0,    # pointer to the followed unit's position
    [long]$UnitType = 0x39D114         # what a soldier's first word points at
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfWeapons {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    static IntPtr proc; static long image;
    public static void Open(int pid, long imageBase) { proc = OpenProcess(0x0410, false, pid); image = imageBase; }   // read and query only
    public static byte[] Bytes(long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(proc, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }
    public static uint U32(long a) { var b = Bytes(a, 4); return b == null ? 0 : BitConverter.ToUInt32(b, 0); }
    public static long Unit(long pointer, long type) { long pos = U32(image + pointer); return pos > 0x10000 && U32(pos - 0x120) == image + type ? pos - 0x120 : 0; }

    // The offsets of the words that changed at any time in `ms`.
    public static HashSet<int> Restless(long unit, int size, int ms) {
        var moved = new HashSet<int>(); var first = Bytes(unit, size); if (first == null) return moved;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms) {
            var now = Bytes(unit, size); if (now == null) break;
            for (int i = 0; i + 4 <= size; i += 4) if (BitConverter.ToUInt32(now, i) != BitConverter.ToUInt32(first, i)) moved.Add(i);
            System.Threading.Thread.Sleep(5);
        }
        return moved;
    }
    // Every word that changed in `ms`, with the values it went through and when (ms).
    // If `releaseAt` is not negative the function is let go that long in (by
    // putting force_functions back to 0 in the ini), so the trace covers it.
    public static List<string> Trace(long unit, int size, int ms, int most, string ini, int releaseAt) {
        var lines = new List<string>(); var last = Bytes(unit, size); if (last == null) return lines;
        var seen = new SortedDictionary<int, List<string>>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms) {
            if (releaseAt >= 0 && sw.ElapsedMilliseconds >= releaseAt) {
                releaseAt = -1;
                System.IO.File.WriteAllText(ini, System.Text.RegularExpressions.Regex.Replace(System.IO.File.ReadAllText(ini), @"(?m)^force_functions\s*=.*$", "force_functions = 0x0"), new System.Text.ASCIIEncoding());
            }
            var now = Bytes(unit, size); if (now == null) break; long at = sw.ElapsedMilliseconds;
            for (int i = 0; i + 4 <= size; i += 4) {
                uint a = BitConverter.ToUInt32(last, i), b = BitConverter.ToUInt32(now, i); if (a == b) continue;
                List<string> l; if (!seen.TryGetValue(i, out l)) { l = new List<string>(); l.Add(Show(a, BitConverter.ToSingle(last, i))); seen[i] = l; }
                if (l.Count <= most) l.Add(string.Format("{0}ms {1}", at, Show(b, BitConverter.ToSingle(now, i))));
                else if (l.Count == most + 1) l.Add("...");
            }
            last = now; System.Threading.Thread.Sleep(3);
        }
        foreach (var k in seen) lines.Add(string.Format("  +0x{0:X4}: {1}", k.Key, string.Join("  ->  ", k.Value.ToArray())));
        return lines;
    }
    static string Show(uint u, float f) { return u < 0x10000 ? u.ToString() : (Math.Abs(f) > 1e-4 && Math.Abs(f) < 1e7) ? string.Format("{0:G5}", f) : string.Format("0x{0:X8}", u); }
    public static bool WaitBit(long state, uint bit, int ms) {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms) { if ((U32(image + state + 0x10) & bit) != 0) return true; System.Threading.Thread.Sleep(1); }
        return false;
    }
}
'@

function Set-Force([uint32]$Mask) {
    $text = (Get-Content $Ini -Raw) -replace '(?m)^force_functions\s*=.*$', ('force_functions = 0x{0:X}' -f $Mask)
    [IO.File]::WriteAllText($Ini, $text, (New-Object Text.ASCIIEncoding))
}
function Word([byte[]]$b, [int]$at) {
    $u = [BitConverter]::ToUInt32($b, $at); $f = [BitConverter]::ToSingle($b, $at)
    if ($u -lt 0x10000) { "$u" } elseif ([Math]::Abs($f) -gt 1e-4 -and [Math]::Abs($f) -lt 1e7) { '0x{0:X8} ({1:G5})' -f $u, $f } else { '0x{0:X8}' -f $u }
}

$bf = Get-Process BattlefrontII | Select-Object -First 1
[BfWeapons]::Open($bf.Id, [int64]$bf.MainModule.BaseAddress)
$unit = [BfWeapons]::Unit($UnitPointer, $UnitType)
if (-not $unit) { 'no soldier: spawn first'; exit 2 }
'unit at 0x{0:X8}; weapons {1}; in hand: primary slot {2}, secondary slot {3}' -f $unit, ((0..7 | ForEach-Object { '{0:X8}' -f [BfWeapons]::U32($unit + $UnitWeapons + 4 * $_) }) -join ' '), [BfWeapons]::Bytes($unit + $UnitWeapons + 0x20, 2)[0], [BfWeapons]::Bytes($unit + $UnitWeapons + 0x20, 2)[1]
if ($Slot -ge 0) {
    $unit = [int64][BfWeapons]::U32($unit + $UnitWeapons + 4 * $Slot); $Size = $WeaponSize
    if ($unit -lt 0x10000) { "no weapon in slot $Slot"; exit 2 }
    'watching the weapon in slot {0}, at 0x{1:X8}' -f $Slot, $unit
}

$restless = [BfWeapons]::Restless($unit, $Size, $QuietMs)
"$($restless.Count) of $($Size / 4) words change by themselves and are left out"
$steps = New-Object Collections.Generic.List[byte[]]
$steps.Add([BfWeapons]::Bytes($unit, $Size))
if ($Show) { 'shown: ' + (($Show | ForEach-Object { '+0x{0:X} = {1}' -f $_, (Word $steps[0] $_) }) -join '   ') }
if ($Function -lt 0) { exit 0 }
if ($TraceMs -gt 0) {
    try { Set-Force ([uint32]1 -shl $Function); $lines = [BfWeapons]::Trace($unit, $Size, $TraceMs, $Most, $Ini, $(if ($HoldMs -gt 0) { $HoldMs } else { -1 })) } finally { Set-Force 0 }
    "words that changed in $TraceMs ms from asking for function $Function (the bridge takes up to a second to see the request):"; $lines; exit 0
}

try {
    $bit = [uint32]1 -shl $Function
    for ($p = 1; $p -le $Presses; $p++) {
        Set-Force $bit
        $seen = [BfWeapons]::WaitBit($ControlState, $bit, 3000)
        if ($HoldMs -gt 0) { Start-Sleep -Milliseconds $HoldMs }
        Set-Force 0
        Start-Sleep -Milliseconds ([Math]::Max($SettleMs, 1300))   # the bridge rereads its settings once a second
        $steps.Add([BfWeapons]::Bytes($unit, $Size))
        "press $p of function ${Function}: " + $(if ($seen) { 'the game showed it on' } else { 'the game never showed it on (is forward_fire = 1?)' })
        if ($Show) { '    shown: ' + (($Show | ForEach-Object { '+0x{0:X} = {1}' -f $_, (Word $steps[$p] $_) }) -join '   ') }
    }
} finally { Set-Force 0 }

# The words that a press changed, with what they held after each.
$rows = for ($i = 0; $i + 4 -le $Size; $i += 4) {
    if ($restless.Contains($i)) { continue }
    $values = $steps | ForEach-Object { [BitConverter]::ToUInt32($_, $i) }
    if (($values | Select-Object -Unique).Count -lt 2) { continue }
    '  +0x{0:X4}: {1}' -f $i, (($steps | ForEach-Object { Word $_ $i }) -join '  ->  ')
}
if ($rows) { "words a press changed ($($rows.Count)), before and after each press:"; $rows | Select-Object -First 60 } else { 'no word changed and stayed changed' }
