# Offline. Mines a recording made by bfrecord.ps1 -SaveTo (the player's
# soldier object and the camera, 100 times a second) for what the camera and
# animation work needs:
#
#   - where the camera sits relative to the unit, and how far it pitches
#   - which floats in the object follow the camera's pitch (the aim)
#   - which unit-length vectors in the object point where the camera points
#   - which floats follow the unit's velocity, speed, forwards speed and
#     sideways speed
#   - which small integers take different values moving and standing
#
# Offsets are from the start of the soldier object; the position is at 0x120.
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;

public static class RecAn {
    public static int N, Size; public static double[] T; public static byte[][] Obj; public static float[][] Cam;
    public const int Pos = 0x120, Fwd = 0x110;

    public static void Load(string path) {
        using (var br = new BinaryReader(File.OpenRead(path))) {
            N = br.ReadInt32(); Size = br.ReadInt32(); T = new double[N]; Obj = new byte[N][]; Cam = new float[N][];
            for (int i = 0; i < N; i++) { T[i] = br.ReadDouble(); Obj[i] = br.ReadBytes(Size); Cam[i] = new float[16]; for (int k = 0; k < 16; k++) Cam[i][k] = br.ReadSingle(); }
        }
    }
    static float F(int i, int o) { return BitConverter.ToSingle(Obj[i], o); }
    static double Wrap(double a) { while (a > 180) a -= 360; while (a < -180) a += 360; return a; }
    static string Spread(List<double> v, string fmt) { var s = new List<double>(v); s.Sort(); return string.Format("{0} / {1} / {2}", s[(int)(s.Count * 0.05)].ToString(fmt).PadLeft(8), s[s.Count / 2].ToString(fmt).PadLeft(8), s[(int)(s.Count * 0.95)].ToString(fmt).PadLeft(8)); }

    public static double[] Pitch, Speed, VFwd, VRight, VUp, VX, VZ;

    // The 16 floats recorded as "the camera" are not a camera-to-world matrix.
    // They are three rows of the view-projection matrix followed by the
    // camera's position: floats 8..10 are the direction it looks in (unit
    // length; float 11 is minus that direction dotted with the position),
    // floats 4..7 are the same row with the projection's depth term, floats
    // 0..3 are the projection's vertical row, and floats 12..14 are where it is.
    public static List<string> Camera() {
        var res = new List<string>();
        var pitch = new List<double>(); var f = new List<double>(); var dy = new List<double>(); var flat = new List<double>(); var yawDiff = new List<double>(); var len = new List<double>();
        Pitch = new double[N];
        for (int i = 0; i < N; i++) {
            float[] c = Cam[i];
            Pitch[i] = Math.Asin(Math.Max(-1, Math.Min(1, c[9])));
            pitch.Add(Pitch[i] * 180 / Math.PI);
            len.Add(Math.Sqrt(c[8] * c[8] + c[9] * c[9] + c[10] * c[10]));
            double dx = c[12] - F(i, Pos), dyy = c[13] - F(i, Pos + 4), dz = c[14] - F(i, Pos + 8);
            f.Add(dx * c[8] + dyy * c[9] + dz * c[10]);
            dy.Add(dyy); flat.Add(Math.Sqrt(dx * dx + dz * dz));
            yawDiff.Add(Wrap((Math.Atan2(c[8], c[10]) - Math.Atan2(F(i, Fwd), F(i, Fwd + 8))) * 180 / Math.PI));
        }
        res.Add("                                                 5% /   median /      95%");
        res.Add("length of the camera's view direction:      " + Spread(len, "F3"));
        res.Add("camera pitch, degrees (+ = looking up):     " + Spread(pitch, "F1"));
        res.Add("camera yaw minus body yaw, degrees:         " + Spread(yawDiff, "F1"));
        res.Add("camera minus unit, along the view direction:" + Spread(f, "F2"));
        res.Add("camera height above the unit's origin:      " + Spread(dy, "F2"));
        res.Add("camera distance from unit on the ground:    " + Spread(flat, "F2"));
        return res;
    }

    // Velocity measured from the position, and its parts along the body's
    // forward and right. Measured over 60 ms either side: the game moves the
    // unit once per frame and the recording samples at its own rate, so the
    // step between two neighbouring samples is anything from none to two
    // frames' worth. Judging a velocity field against that is what made
    // bfrecord.ps1 miss the real one.
    public static string Motion() {
        Speed = new double[N]; VFwd = new double[N]; VRight = new double[N]; VUp = new double[N]; VX = new double[N]; VZ = new double[N]; int w = 6; var moving = new List<double>();
        for (int i = 0; i < N; i++) {
            int a = Math.Max(0, i - w), b = Math.Min(N - 1, i + w); double dt = T[b] - T[a]; if (dt <= 0) continue;
            double vx = (F(b, Pos) - F(a, Pos)) / dt, vy = (F(b, Pos + 4) - F(a, Pos + 4)) / dt, vz = (F(b, Pos + 8) - F(a, Pos + 8)) / dt;
            double fx = F(i, Fwd), fz = F(i, Fwd + 8);
            Speed[i] = Math.Sqrt(vx * vx + vz * vz); VFwd[i] = vx * fx + vz * fz; VRight[i] = vx * fz - vz * fx; VUp[i] = vy; VX[i] = vx; VZ[i] = vz;
            if (Speed[i] > 2) moving.Add(Speed[i]);
        }
        return "speed while moving, m/s (5% / median / 95%): " + Spread(moving, "F2");
    }

    // Floats that rise and fall with a target.
    public static List<string> Follows(double[] target, double minCorr) {
        var res = new List<string>(); double mt = 0; for (int i = 0; i < N; i++) mt += target[i]; mt /= N;
        double vt = 0; for (int i = 0; i < N; i++) vt += (target[i] - mt) * (target[i] - mt);
        if (vt / N < 1e-6) { res.Add("the target barely changed in this recording"); return res; }
        for (int o = 0; o + 4 <= Size; o += 4) {
            double mx = 0; bool ok = true;
            for (int i = 0; i < N; i++) { float x = F(i, o); if (float.IsNaN(x) || float.IsInfinity(x) || Math.Abs(x) > 1e6) { ok = false; break; } mx += x; }
            if (!ok) continue; mx /= N;
            double vx = 0, cov = 0; for (int i = 0; i < N; i++) { double d = F(i, o) - mx; vx += d * d; cov += d * (target[i] - mt); }
            if (vx / N < 1e-9) continue;
            double corr = cov / Math.Sqrt(vx * vt); if (Math.Abs(corr) < minCorr) continue;
            double slope = cov / vt;
            res.Add(string.Format("+0x{0:X3}: correlation {1,6:F3}; value = {2:F3} x target {3} {4:F3}", o, corr, slope, mx - slope * mt < 0 ? "-" : "+", Math.Abs(mx - slope * mt)));
        }
        return res;
    }

    // Unit-length vectors, and how they sit against the camera's view direction and the body's forward.
    public static List<string> Directions() {
        var res = new List<string>();
        for (int o = 0; o + 12 <= Size; o += 4) {
            bool ok = true; double dc = 0, db = 0, ay = 0, lo = 9, hi = -9;
            for (int i = 0; i < N && ok; i++) {
                float x = F(i, o), y = F(i, o + 4), z = F(i, o + 8); double l = Math.Sqrt(x * x + y * y + z * z);
                if (!(l > 0.98 && l < 1.02)) { ok = false; break; }
                dc += x * Cam[i][8] + y * Cam[i][9] + z * Cam[i][10]; db += x * F(i, Fwd) + z * F(i, Fwd + 8); ay += Math.Abs(y); lo = Math.Min(lo, y); hi = Math.Max(hi, y);
            }
            if (!ok || hi - lo < 1e-4 && Math.Abs(dc / N) < 0.5 && Math.Abs(db / N) < 0.5) continue;
            res.Add(string.Format("+0x{0:X3}: against the camera's view {1,6:F3}, against the body's forward {2,6:F3}; its up part runs {3,6:F3} to {4,6:F3}", o, dc / N, db / N, lo, hi));
        }
        return res;
    }

    // Small integers that never take the same value moving as standing.
    public static List<string> States() {
        var res = new List<string>();
        for (int o = 0; o + 4 <= Size; o += 4) {
            var mv = new SortedDictionary<uint, int>(); var st = new SortedDictionary<uint, int>(); bool ok = true;
            for (int i = 0; i < N && ok; i++) {
                uint v = BitConverter.ToUInt32(Obj[i], o); var d = Speed[i] > 2 ? mv : Speed[i] < 0.3 ? st : null; if (d == null) continue;
                int c; d.TryGetValue(v, out c); d[v] = c + 1; if (mv.Count + st.Count > 8) ok = false;
            }
            if (!ok || mv.Count == 0 || st.Count == 0) continue;
            bool disjoint = true; foreach (var k in st.Keys) if (mv.ContainsKey(k)) { disjoint = false; break; }
            if (!disjoint) continue;
            var a = new List<string>(); foreach (var k in mv) a.Add(string.Format("0x{0:X} x{1}", k.Key, k.Value));
            var b = new List<string>(); foreach (var k in st) b.Add(string.Format("0x{0:X} x{1}", k.Key, k.Value));
            res.Add(string.Format("+0x{0:X3}: moving {{ {1} }}   standing {{ {2} }}", o, string.Join(", ", a), string.Join(", ", b)));
        }
        return res;
    }

    public static string Standing() { int n = 0, first = -1, last = -1; for (int i = 0; i < N; i++) if (Speed[i] < 0.3) { n++; if (first < 0) first = i; last = i; } return string.Format("{0} standing samples, between {1:F1} s and {2:F1} s of {3:F1} s", n, first < 0 ? 0 : T[first], last < 0 ? 0 : T[last], T[N - 1]); }
}
'@

[RecAn]::Load($Path)
"{0} samples of a {1}-byte object" -f [RecAn]::N, [RecAn]::Size
'--- the camera against the unit ---'
[RecAn]::Camera() | ForEach-Object { "  $_" }
'--- motion ---'
"  " + [RecAn]::Motion()
"  " + [RecAn]::Standing()
'--- floats that follow the camera pitch (target in radians) ---'
[RecAn]::Follows([RecAn]::Pitch, 0.9) | ForEach-Object { "  $_" }
'--- unit-length vectors ---'
[RecAn]::Directions() | ForEach-Object { "  $_" }
'--- floats that follow the velocity along x (a velocity field shows here, at 1.000 x target) ---'
[RecAn]::Follows([RecAn]::VX, 0.95) | ForEach-Object { "  $_" }
'--- floats that follow the velocity along z ---'
[RecAn]::Follows([RecAn]::VZ, 0.95) | ForEach-Object { "  $_" }
'--- floats that follow speed along the ground ---'
[RecAn]::Follows([RecAn]::Speed, 0.85) | ForEach-Object { "  $_" }
'--- floats that follow speed along the body''s forward ---'
[RecAn]::Follows([RecAn]::VFwd, 0.85) | ForEach-Object { "  $_" }
'--- floats that follow speed along the body''s right ---'
[RecAn]::Follows([RecAn]::VRight, 0.85) | ForEach-Object { "  $_" }
'--- floats that follow vertical speed ---'
[RecAn]::Follows([RecAn]::VUp, 0.85) | ForEach-Object { "  $_" }
'--- integers that differ between moving and standing ---'
[RecAn]::States() | ForEach-Object { "  $_" }
