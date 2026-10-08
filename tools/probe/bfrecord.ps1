# Read-only. Records the player's soldier object and the camera for a few
# seconds while the player runs and turns, then looks inside the object for:
#
#   - velocity: three floats that match how fast the position is changing
#   - facing:   a float (an angle) or a pair of floats (a direction) that turns
#               with the camera
#
# Beeps once when recording starts and three times when it ends.
param(
    [string]$ProcessName = 'BattlefrontII',
    [long]$PositionPointer = 0x1A296B0,   # exe slot pointing at the followed unit's position
    [long]$SoldierType = 0x39D114,
    [long]$CameraMatrix = 0x3DE378,        # 4x4, rows of 4 floats; row 2 is the view direction
    [int]$Seconds = 20,
    [int]$Hz = 100,
    [int]$LeadInSec = 0,
    [int]$WaitForSoldierSec = 0,           # wait this long for the player to be in a match and alive
    [string]$SaveTo
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class BfRecord {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    public const int ObjSize = 0xFD0;   // soldiers sit 0xFD0 apart in their pool
    public const int PosOff = 0x120;

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static long U32(IntPtr h, long addr) { var b = new byte[4]; IntPtr n; return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? (long)BitConverter.ToUInt32(b, 0) : -1; }

    public class Rec { public List<double> T = new List<double>(); public List<byte[]> Obj = new List<byte[]>(); public List<float[]> Cam = new List<float[]>(); public string Stopped = ""; }

    public static Rec Record(IntPtr h, long slot, long type, long cam, double seconds, int hz) {
        var r = new Rec();
        long obj = U32(h, slot) - PosOff;
        if (U32(h, obj) != type) { r.Stopped = "the camera is not following a soldier"; return r; }
        var sw = Stopwatch.StartNew();
        double step = 1.0 / hz, next = 0;
        while (sw.Elapsed.TotalSeconds < seconds) {
            double now = sw.Elapsed.TotalSeconds;
            if (now < next) { System.Threading.Thread.Sleep(1); continue; }
            next += step;
            if (U32(h, slot) - PosOff != obj || U32(h, obj) != type) { r.Stopped = "the soldier changed (death or respawn) at " + now.ToString("F1") + " s"; break; }
            var o = new byte[ObjSize]; var c = new byte[64]; IntPtr n;
            if (!ReadProcessMemory(h, (IntPtr)obj, o, (IntPtr)ObjSize, out n) || !ReadProcessMemory(h, (IntPtr)cam, c, (IntPtr)64, out n)) continue;
            var cf = new float[16]; for (int i = 0; i < 16; i++) cf[i] = BitConverter.ToSingle(c, i * 4);
            r.T.Add(now); r.Obj.Add(o); r.Cam.Add(cf);
        }
        return r;
    }

    static float F(byte[] o, int off) { return BitConverter.ToSingle(o, off); }
    static double Median(List<double> v) { if (v.Count == 0) return double.NaN; v.Sort(); return v[v.Count / 2]; }
    static double Wrap(double a) { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; }

    // Offsets whose three floats match the measured velocity while moving.
    public static List<string> Velocity(Rec r) {
        int n = r.T.Count; var res = new List<string>();
        var v = new double[n][]; var moving = new List<int>(); var still = new List<int>();
        for (int i = 1; i + 1 < n; i++) {
            double dt = r.T[i + 1] - r.T[i - 1]; if (dt <= 0) continue;
            v[i] = new double[3];
            for (int k = 0; k < 3; k++) v[i][k] = (F(r.Obj[i + 1], PosOff + 4 * k) - F(r.Obj[i - 1], PosOff + 4 * k)) / dt;
            double speed = Math.Sqrt(v[i][0] * v[i][0] + v[i][2] * v[i][2]);
            if (speed > 2) moving.Add(i); else if (speed < 0.05) still.Add(i);
        }
        res.Add(string.Format("samples: {0} moving faster than 2 m/s, {1} standing", moving.Count, still.Count));
        if (moving.Count < 30) { res.Add("not enough movement to judge"); return res; }
        for (int o = 0; o + 12 <= ObjSize; o += 4) {
            if (o == PosOff) continue;
            var err = new List<double>(); var rest = new List<double>();
            foreach (int i in moving) {
                double ex = F(r.Obj[i], o) - v[i][0], ez = F(r.Obj[i], o + 8) - v[i][2];
                err.Add(Math.Sqrt(ex * ex + ez * ez));
            }
            double m = Median(err);
            if (!(m < 1.0)) continue;
            foreach (int i in still) rest.Add(Math.Abs(F(r.Obj[i], o)) + Math.Abs(F(r.Obj[i], o + 8)));
            res.Add(string.Format("+0x{0:X3}: off by {1:F2} m/s (median) while moving; reads {2:F2} when standing", o, m, rest.Count > 0 ? Median(rest) : double.NaN));
        }
        return res;
    }

    // Offsets that turn with the camera, as an angle or as a direction.
    public static List<string> Facing(Rec r) {
        int n = r.T.Count; var res = new List<string>();
        var yaw = new double[n]; double lo = 9, hi = -9, turned = 0;
        for (int i = 0; i < n; i++) { yaw[i] = Math.Atan2(r.Cam[i][8], r.Cam[i][10]); if (i > 0) turned += Math.Abs(Wrap(yaw[i] - yaw[i - 1])); lo = Math.Min(lo, yaw[i]); hi = Math.Max(hi, yaw[i]); }
        res.Add(string.Format("camera turned {0:F0} degrees in total", turned * 180 / Math.PI));
        if (turned < 4) { res.Add("not enough turning to judge"); return res; }
        string[] kinds = { "angle in radians", "angle in degrees", "direction (x at this offset, z 8 bytes on)", "direction (z at this offset, x 8 bytes on)" };
        for (int o = 0; o + 12 <= ObjSize; o += 4) {
            for (int kind = 0; kind < 4; kind++) {
                foreach (int sign in new[] { 1, -1 }) {
                    double sx = 0, sy = 0; bool ok = true; double span = 0, prev = 0;
                    for (int i = 0; i < n && ok; i++) {
                        double a;
                        float f0 = F(r.Obj[i], o), f2 = F(r.Obj[i], o + 8);
                        if (kind == 0) { if (!(Math.Abs(f0) < 7)) { ok = false; break; } a = f0; }
                        else if (kind == 1) { if (!(Math.Abs(f0) <= 361)) { ok = false; break; } a = f0 * Math.PI / 180; }
                        else { double len = Math.Sqrt(f0 * f0 + f2 * f2); if (!(len > 0.85 && len < 1.15)) { ok = false; break; } a = kind == 2 ? Math.Atan2(f0, f2) : Math.Atan2(f2, f0); }
                        if (i > 0) span += Math.Abs(Wrap(a - prev)); prev = a;
                        double d = Wrap(a - sign * yaw[i]); sx += Math.Cos(d); sy += Math.Sin(d);
                    }
                    if (!ok || span < turned * 0.5) continue;      // must itself turn about as much as the camera
                    double agreement = Math.Sqrt(sx * sx + sy * sy) / n;   // 1 = turns exactly with the camera
                    if (agreement < 0.93) continue;
                    res.Add(string.Format("+0x{0:X3}: {1}, turns {2} the camera, agreement {3:F3}, offset {4:F0} degrees", o, kinds[kind], sign > 0 ? "with" : "against", agreement, Math.Atan2(sy, sx) * 180 / Math.PI));
                }
            }
        }
        return res;
    }

    public static string Row(Rec r, int sample, int off, int count) {
        var p = new List<string>(); for (int k = 0; k < count; k++) p.Add(F(r.Obj[sample], off + 4 * k).ToString("F3").PadLeft(9)); return string.Join(" ", p);
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [BfRecord]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$waited = [Diagnostics.Stopwatch]::StartNew()
while ($waited.Elapsed.TotalSeconds -lt $WaitForSoldierSec) {
    $obj = [BfRecord]::U32($h, $base + $PositionPointer) - [BfRecord]::PosOff
    if ([BfRecord]::U32($h, $obj) -eq $base + $SoldierType) { break }
    Start-Sleep -Milliseconds 500
}
if ($WaitForSoldierSec -gt 0) { "waited {0:N0} s for a soldier to follow" -f $waited.Elapsed.TotalSeconds }
if ($LeadInSec -gt 0) { Start-Sleep -Seconds $LeadInSec }
[Console]::Beep(1200, 250)
$r = [BfRecord]::Record($h, $base + $PositionPointer, $base + $SoldierType, $base + $CameraMatrix, $Seconds, $Hz)
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)
"recorded {0} samples over {1:N1} s{2}" -f $r.T.Count, $(if ($r.T.Count) { $r.T[$r.T.Count - 1] } else { 0 }), $(if ($r.Stopped) { "; stopped early: $($r.Stopped)" } else { '' })
if ($r.T.Count -lt 100) { 'not enough to analyse'; exit 2 }

if ($SaveTo) {
    $fs = [IO.File]::Create($SaveTo); $bw = New-Object IO.BinaryWriter($fs)
    $bw.Write([int]$r.T.Count); $bw.Write([int][BfRecord]::ObjSize)
    for ($i = 0; $i -lt $r.T.Count; $i++) { $bw.Write([double]$r.T[$i]); $bw.Write($r.Obj[$i]); foreach ($f in $r.Cam[$i]) { $bw.Write([single]$f) } }
    $bw.Close(); "saved to $SaveTo"
}

'--- the 4x4 at +0xF0 (position is its last row), first and last sample ---'
foreach ($s in 0, ($r.T.Count - 1)) { foreach ($row in 0..3) { '  ' + [BfRecord]::Row($r, $s, 0xF0 + 16 * $row, 4) }; '' }
'--- velocity candidates ---'
[BfRecord]::Velocity($r) | ForEach-Object { "  $_" }
'--- facing candidates ---'
[BfRecord]::Facing($r) | Select-Object -First 60 | ForEach-Object { "  $_" }
