# Sets up and measures the follow test without restarting anything.
#
# Waits for the player to be alive in a Battlefront II match, ties that spot
# to wherever the World at War player is standing, switches following on in
# SWBF2's wawbf.ini (the bridge re-reads it within a second), then watches
# both games read-only and reports how well the unit tracked.
#
# One beep = following is on, go and walk in World at War. Three = finished.
param(
    [string]$BfDir = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData',
    [long]$BfPositionPointer = 0x1A296B0,
    [long]$BfSoldierType = 0x39D114,
    [long]$WawOrigin = 0x14ED088,
    [long]$WawAngles = 0x14ED18C,
    [int]$WaitForSoldierSec = 300,
    [int]$Seconds = 75,
    [int]$ZSign = -1,
    [int]$Facing = 1,
    [int]$Velocity = 0,          # follow_velocity: give the unit the WaW player's speed
    [int]$Pitch = 0,             # follow_pitch: aim up and down with the WaW player
    [long]$BfVelocityOffset = 0x3BC,   # from the unit's position
    [long]$BfPitchOffset = 0x3C8
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class FollowRead {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static long U32(IntPtr h, long addr) { var b = new byte[4]; IntPtr n; return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? (long)BitConverter.ToUInt32(b, 0) : -1; }
    public static float[] F(IntPtr h, long addr, int count) { var b = new byte[4 * count]; IntPtr n; if (addr <= 0x10000 || !ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)b.Length, out n)) return null; var f = new float[count]; for (int i = 0; i < count; i++) f[i] = BitConverter.ToSingle(b, 4 * i); return f; }

    // How evenly a position moves. Watches (x, ?, z) at addr as fast as it can and records each
    // step. result: [0] real steps per second, [1] median step in metres, [2] median change from
    // one step to the next as a fraction of the step (0 = perfectly even, around 1 = stop-go
    // stutter), [3] the same at the 90th percentile.
    //
    // Only steps over 5 mm count. The game itself shifts the unit by about 0.1 mm every frame
    // (see bftrace.ps1); counting those once made a smooth run look like it had twice the
    // updates and a third of its steps "odd".
    public static double[] Smoothness(IntPtr h, long addr, double seconds) {
        var steps = new System.Collections.Generic.List<double>();
        var b = new byte[12]; IntPtr n; float lx = 0, lz = 0; bool have = false;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) break;
            float x = BitConverter.ToSingle(b, 0), z = BitConverter.ToSingle(b, 8);
            if (!have) { lx = x; lz = z; have = true; continue; }
            if (x == lx && z == lz) continue;
            steps.Add(Math.Sqrt((x - lx) * (x - lx) + (z - lz) * (z - lz))); lx = x; lz = z;
        }
        var moving = steps.FindAll(s => s > 0.005);   // ignore standing still
        if (moving.Count < 30) return new double[] { moving.Count / seconds, 0, double.NaN, double.NaN };
        var sorted = new System.Collections.Generic.List<double>(moving); sorted.Sort(); double med = sorted[sorted.Count / 2];
        var change = new System.Collections.Generic.List<double>();
        for (int i = 1; i < moving.Count; i++) change.Add(Math.Abs(moving[i] - moving[i - 1]) / moving[i - 1]);
        change.Sort();
        return new double[] { moving.Count / seconds, med, change[change.Count / 2], change[(int)(change.Count * 0.9)] };
    }
}
'@

$bf = Get-Process BattlefrontII | Select-Object -First 1
$waw = Get-Process CoDWaW | Select-Object -First 1
$hb = [FollowRead]::Open($bf.Id); $hw = [FollowRead]::Open($waw.Id)
$bb = [int64]$bf.MainModule.BaseAddress; $wb = [int64]$waw.MainModule.BaseAddress

function Get-Soldier { $pos = [FollowRead]::U32($hb, $bb + $BfPositionPointer); if ([FollowRead]::U32($hb, $pos - 0x120) -eq $bb + $BfSoldierType) { $pos } else { 0 } }

$waited = [Diagnostics.Stopwatch]::StartNew(); $pos = 0
while ($waited.Elapsed.TotalSeconds -lt $WaitForSoldierSec) { $pos = Get-Soldier; if ($pos) { break }; Start-Sleep -Milliseconds 500 }
if (-not $pos) { "no soldier to follow after $WaitForSoldierSec s"; exit 2 }
Start-Sleep -Seconds 4   # let the spawn settle onto the ground
$pos = Get-Soldier; if (-not $pos) { 'the soldier went away while settling'; exit 2 }
$p = [FollowRead]::F($hb, $pos, 3); $o = [FollowRead]::F($hw, $wb + $WawOrigin, 3)
"waited {0:N0} s. SWBF2 unit at ({1:N2}, {2:N2}, {3:N2}); WaW player at ({4:N1}, {5:N1}, {6:N1})" -f $waited.Elapsed.TotalSeconds, $p[0], $p[1], $p[2], $o[0], $o[1], $o[2]

$ini = Join-Path $BfDir 'wawbf.ini'
$t = Get-Content $ini -Raw
$inv = [Globalization.CultureInfo]::InvariantCulture
$t = $t -replace '(?m)^anchor_waw\s*=.*$', ('anchor_waw = {0}, {1}, {2}' -f $o[0].ToString('F2', $inv), $o[1].ToString('F2', $inv), $o[2].ToString('F2', $inv))
$t = $t -replace '(?m)^anchor_bf\s*=.*$', ('anchor_bf = {0}, {1}, {2}' -f $p[0].ToString('F3', $inv), $p[1].ToString('F3', $inv), $p[2].ToString('F3', $inv))
$t = $t -replace '(?m)^z_sign\s*=.*$', "z_sign = $ZSign" -replace '(?m)^follow_facing\s*=.*$', "follow_facing = $Facing" -replace '(?m)^follow\s*=.*$', 'follow = 1'
$t = $t -replace '(?m)^follow_velocity\s*=.*$', "follow_velocity = $Velocity" -replace '(?m)^follow_pitch\s*=.*$', "follow_pitch = $Pitch"
[IO.File]::WriteAllText($ini, $t, (New-Object Text.ASCIIEncoding))
Start-Sleep -Milliseconds 1500
[Console]::Beep(1200, 300)

$scale = 0.0254
$rows = @(); $deaths = 0; $unit = $pos; $sw = [Diagnostics.Stopwatch]::StartNew()
$smooth = $null
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    # Part-way in, once the player has had time to get moving, spend ten seconds watching how evenly the unit steps.
    if (-not $smooth -and $sw.Elapsed.TotalSeconds -gt 15) { $u = Get-Soldier; if ($u) { $smooth = [FollowRead]::Smoothness($hb, $u, 10) } }
    $cur = Get-Soldier
    if ($cur -ne $unit) { $deaths++; $unit = $cur }
    $w = [FollowRead]::F($hw, $wb + $WawOrigin, 3); $a = [FollowRead]::F($hw, $wb + $WawAngles, 3)
    if ($cur -and $w -and $a) {
        $m = [FollowRead]::F($hb, $cur - 0x30, 15)   # right, up, forward rows then position
        $wantX = $p[0] + ($w[0] - $o[0]) * $scale; $wantZ = $p[2] + ($w[1] - $o[1]) * $scale * $ZSign
        $yaw = $a[1] * [Math]::PI / 180; $wantFx = [Math]::Cos($yaw); $wantFz = $ZSign * [Math]::Sin($yaw)
        $dot = [Math]::Max(-1, [Math]::Min(1, $m[8] * $wantFx + $m[10] * $wantFz))
        $v = [FollowRead]::F($hb, $cur + $BfVelocityOffset, 3); $bp = [FollowRead]::F($hb, $cur + $BfPitchOffset, 1)
        $wp = $a[0]; while ($wp -gt 180) { $wp -= 360 }   # WaW pitch: degrees, positive looking down
        $rows += [pscustomobject]@{ T = $sw.Elapsed.TotalSeconds; Wx = $w[0]; Wy = $w[1]; Wz = $w[2]; Yaw = $a[1]
            Gap = [Math]::Sqrt([Math]::Pow($m[12] - $wantX, 2) + [Math]::Pow($m[14] - $wantZ, 2)) / $scale   # in WaW units
            Y = $m[13]; FaceErr = [Math]::Acos($dot) * 180 / [Math]::PI
            WawPitch = $wp; BfPitch = $bp[0] * 180 / [Math]::PI; PitchErr = [Math]::Abs($bp[0] * 180 / [Math]::PI + $wp)
            BfSpeed = [Math]::Sqrt($v[0] * $v[0] + $v[2] * $v[2]) }
    }
    Start-Sleep -Milliseconds 100
}
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)

# Leave the unit free again.
$t = (Get-Content $ini -Raw) -replace '(?m)^follow\s*=.*$', 'follow = 0'
[IO.File]::WriteAllText($ini, $t, (New-Object Text.ASCIIEncoding))

if ($rows.Count -lt 20) { "only $($rows.Count) samples; unit changed $deaths time(s)"; exit 2 }
function Stat($values) { $v = @($values | Sort-Object); '{0,7:N1} / {1,7:N1} / {2,7:N1}' -f $v[0], $v[[int]($v.Count / 2)], $v[-1] }
$travel = 0.0; $turn = 0.0
for ($i = 1; $i -lt $rows.Count; $i++) { $travel += [Math]::Sqrt([Math]::Pow($rows[$i].Wx - $rows[$i - 1].Wx, 2) + [Math]::Pow($rows[$i].Wy - $rows[$i - 1].Wy, 2)); $d = $rows[$i].Yaw - $rows[$i - 1].Yaw; while ($d -gt 180) { $d -= 360 }; while ($d -lt -180) { $d += 360 }; $turn += [Math]::Abs($d) }
"{0} samples over {1:N0} s. WaW player walked {2:N0} units and turned {3:N0} degrees. The unit the camera follows changed {4} time(s) (deaths/respawns)." -f $rows.Count, $rows[-1].T, $travel, $turn, $deaths
"                                         min /  median /     max"
"position gap, WaW units (1 = 1 inch): " + (Stat $rows.Gap)
"facing error, degrees:                " + (Stat $rows.FaceErr)
"unit height in SWBF2, metres:         " + (Stat $rows.Y)
"WaW height, units:                    " + (Stat $rows.Wz)
"WaW pitch, degrees (+ = down):        " + (Stat $rows.WawPitch)
"unit's aim pitch, degrees (+ = up):   " + (Stat $rows.BfPitch)
if ($Pitch) { "pitch error, degrees:                 " + (Stat $rows.PitchErr) }
"unit's own speed in SWBF2, m/s:       " + (Stat $rows.BfSpeed)
# A big gap on its own means little without knowing when it was and what WaW was doing at the time.
'--- the three worst moments ---'
$rows | Sort-Object Gap -Descending | Select-Object -First 3 | ForEach-Object {
    $i = [Array]::IndexOf($rows, $_); $before = if ($i -gt 0) { $rows[$i - 1] } else { $_ }
    "  at {0,5:N1} s: gap {1,6:N1} units, facing off by {2,5:N1} degrees; WaW player at ({3:N0}, {4:N0}, {5:N0}), {6:N0} units from where it was {7:N0} ms before" -f $_.T, $_.Gap, $_.FaceErr, $_.Wx, $_.Wy, $_.Wz, [Math]::Sqrt([Math]::Pow($_.Wx - $before.Wx, 2) + [Math]::Pow($_.Wy - $before.Wy, 2)), (($_.T - $before.T) * 1000)
}
if ($smooth) {
    '--- how evenly the unit moved (10 s, watched as fast as memory can be read) ---'
    "  {0:N0} steps a second while moving; median step {1:N3} m" -f $smooth[0], $smooth[1]
    "  change from one step to the next: {0:P0} at the median, {1:P0} at the 90th percentile (0% = perfectly even, about 100% = stop-go)" -f $smooth[2], $smooth[3]
}
'--- what the bridge says the game did with what it was given ---'
$log = Get-Content (Join-Path $BfDir 'wawbf_swbf2.log')
foreach ($what in 'facing: the game kept', 'pitch: the game kept', 'speed: given') { $log | Where-Object { $_ -match $what } | Select-Object -Last 3 }
