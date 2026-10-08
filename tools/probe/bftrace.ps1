# Read-only trace of what happens to the followed SWBF2 unit between frames.
#
# Switches following on, then records every change to the unit's position as
# fast as memory can be read. The bridge writes the position once per frame;
# any other change in the same frame is the game's own doing (physics,
# collision, ground snapping). The pattern of those changes shows what the
# game is fighting us over.
#
# One beep = walk in straight lines in World at War. Three = done.
param(
    [string]$BfDir = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData',
    [long]$BfPositionPointer = 0x1A296B0,
    [long]$BfSoldierType = 0x39D114,
    [long]$WawOrigin = 0x14ED088,
    [int]$Seconds = 12,
    [int]$ZSign = -1,
    [string]$SaveTo
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class BfTrace {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static long U32(IntPtr h, long addr) { var b = new byte[4]; IntPtr n; return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? (long)BitConverter.ToUInt32(b, 0) : -1; }
    public static float[] F3(IntPtr h, long addr) { var b = new byte[12]; IntPtr n; if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) return null; return new float[] { BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 4), BitConverter.ToSingle(b, 8) }; }

    public class Ev { public double Ms; public float X, Y, Z; }

    // Every change to the three floats at addr, with the time it was first seen.
    public static List<Ev> Record(IntPtr h, long addr, double seconds) {
        var ev = new List<Ev>(); var b = new byte[12]; IntPtr n; float lx = 0, ly = 0, lz = 0; bool have = false;
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) break;
            float x = BitConverter.ToSingle(b, 0), y = BitConverter.ToSingle(b, 4), z = BitConverter.ToSingle(b, 8);
            if (have && x == lx && y == ly && z == lz) continue;
            ev.Add(new Ev { Ms = sw.Elapsed.TotalMilliseconds, X = x, Y = y, Z = z }); lx = x; ly = y; lz = z; have = true;
        }
        return ev;
    }
}
'@

$bf = Get-Process BattlefrontII | Select-Object -First 1; $waw = Get-Process CoDWaW | Select-Object -First 1
$hb = [BfTrace]::Open($bf.Id); $hw = [BfTrace]::Open($waw.Id)
$bb = [int64]$bf.MainModule.BaseAddress; $wb = [int64]$waw.MainModule.BaseAddress
$pos = [BfTrace]::U32($hb, $bb + $BfPositionPointer)
if ([BfTrace]::U32($hb, $pos - 0x120) -ne $bb + $BfSoldierType) { 'the camera is not following a live soldier'; exit 2 }
$p = [BfTrace]::F3($hb, $pos); $o = [BfTrace]::F3($hw, $wb + $WawOrigin)

$ini = Join-Path $BfDir 'wawbf.ini'; $inv = [Globalization.CultureInfo]::InvariantCulture
function Set-Follow([int]$on) {
    $t = Get-Content $ini -Raw
    if ($on) {
        $t = $t -replace '(?m)^anchor_waw\s*=.*$', ('anchor_waw = {0}, {1}, {2}' -f $o[0].ToString('F2', $inv), $o[1].ToString('F2', $inv), $o[2].ToString('F2', $inv))
        $t = $t -replace '(?m)^anchor_bf\s*=.*$', ('anchor_bf = {0}, {1}, {2}' -f $p[0].ToString('F3', $inv), $p[1].ToString('F3', $inv), $p[2].ToString('F3', $inv))
        $t = $t -replace '(?m)^z_sign\s*=.*$', "z_sign = $ZSign"
    }
    $t = $t -replace '(?m)^follow\s*=.*$', "follow = $on"
    [IO.File]::WriteAllText($ini, $t, (New-Object Text.ASCIIEncoding))
}
Set-Follow 1; Start-Sleep -Milliseconds 1500
[Console]::Beep(1200, 300)
$ev = [BfTrace]::Record($hb, $pos, $Seconds)
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)
Set-Follow 0

"{0} position changes in {1} s ({2:N0} a second)" -f $ev.Count, $Seconds, ($ev.Count / $Seconds)
if ($ev.Count -lt 50) { 'too little movement to analyse'; exit 2 }
if ($SaveTo) { $ev | ForEach-Object { '{0:F3},{1:R},{2:R},{3:R}' -f $_.Ms, $_.X, $_.Y, $_.Z } | Set-Content -Encoding ascii $SaveTo }

# Classify each change by what moved and how long after the previous change it came.
$rows = for ($i = 1; $i -lt $ev.Count; $i++) {
    $a = $ev[$i - 1]; $b = $ev[$i]
    [pscustomobject]@{ Ms = $b.Ms; Gap = $b.Ms - $a.Ms; Flat = [Math]::Sqrt([Math]::Pow($b.X - $a.X, 2) + [Math]::Pow($b.Z - $a.Z, 2)); Up = $b.Y - $a.Y; Dx = $b.X - $a.X; Dz = $b.Z - $a.Z }
}
$flat = @($rows | Where-Object { $_.Flat -gt 0 }); $onlyUp = @($rows | Where-Object { $_.Flat -eq 0 })
"changes that moved it along the ground: {0}; changes to height only: {1}" -f $flat.Count, $onlyUp.Count
'--- time since the previous change (ms): how the changes are spaced ---'
foreach ($band in @(@(0, 1), @(1, 4), @(4, 9), @(9, 16), @(16, 1000))) { $n = @($rows | Where-Object { $_.Gap -ge $band[0] -and $_.Gap -lt $band[1] }).Count; "  {0,4} to {1,4} ms: {2,5}  ({3:P0})" -f $band[0], $band[1], $n, ($n / $rows.Count) }
'--- a stretch of 45 consecutive changes while moving: ms since previous, ground step (cm), height step (cm), direction of ground step (degrees) ---'
$start = 0; for ($i = 0; $i -lt $rows.Count - 60; $i++) { if (@($rows[$i..($i + 20)] | Where-Object { $_.Flat -gt 0.02 }).Count -ge 8) { $start = $i; break } }
$rows[$start..([Math]::Min($rows.Count - 1, $start + 44))] | ForEach-Object { "  +{0,6:N2} ms   ground {1,7:N2} cm   height {2,7:N2} cm   heading {3,6:N0}" -f $_.Gap, ($_.Flat * 100), ($_.Up * 100), $(if ($_.Flat -gt 0) { [Math]::Atan2($_.Dz, $_.Dx) * 180 / [Math]::PI } else { [double]::NaN }) }
