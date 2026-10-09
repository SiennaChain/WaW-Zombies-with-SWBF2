# Read-only. Says why World at War's shots do or do not hurt zombies.
#
# While the player fires, two lines are followed many times a second: the one
# a shot really takes (from the player's eyes along the two angles the game
# keeps for the way their gun points, which is not always the way they look), and
# the one through the middle of the screen (from the camera, along the way it
# looks). For each it is noted whether the line passes through a zombie, and
# every loss of health by a zombie is noted with it. First person and third
# person are counted apart, so one can be held against the other.
#
# Each hurt is listed with how much health was lost: a rifle takes tens, and a
# zombie that loses everything at once was killed by something else (the
# game itself puts down a zombie that has been stuck too long).
#
#   the shot's line is on zombies and they are not hurt  -> shots do nothing
#   the middle of the screen is on zombies, the shot's line is not -> shots
#     do not go where the screen says
#
# It waits (-Wait seconds at most) for the first shot, beeps, watches for
# -Seconds, and beeps twice.
param([double]$Wait = 240, [double]$Seconds = 30, [long]$Entities = 0x136C6F0, [int]$Size = 0x378, [int]$Count = 1024,
      [int]$Origin = 0x160, [double]$Wide = 14, [double]$Tall = 70)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class ShotWatch {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr h; static bool Read(long at, byte[] b) { IntPtr r; return ReadProcessMemory(h, (IntPtr)at, b, (IntPtr)b.Length, out r); }
  static double F(byte[] b, int o) { return BitConverter.ToSingle(b, o); }
  // Where a line passes an upright thing standing at 'feet': how far along the line, how far to its side (+ = the thing is to the left), how high above its feet.
  static bool Past(double[] from, double[] dir, double[] feet, out double along, out double side, out double high) {
    double dx = feet[0] - from[0], dy = feet[1] - from[1], flat = dir[0] * dir[0] + dir[1] * dir[1]; along = -1; side = 0; high = 0; if (flat < 1e-6) return false;
    along = (dx * dir[0] + dy * dir[1]) / flat; side = (dir[0] * dy - dir[1] * dx) / Math.Sqrt(flat); high = from[2] + along * dir[2] - feet[2]; return true; }
  class Near { public bool any, on; public double along, side, high, off = 1e9; }
  static string Say(Near n) { if (!n.any) return "no zombie ahead"; if (n.on) return string.Format("ON one {0:N0} off", n.along);
    return string.Format("{0:N0} to the {1} of one {2:N0} off, {3:N0} above its feet", Math.Abs(n.side), n.side > 0 ? "right" : "left", n.along, n.high); }
  static string Where(double[] from, double[] dir, double[] feet, double wide, double tall) { double along, side, high; if (!Past(from, dir, feet, out along, out side, out high) || along <= 0) return "behind";
    return string.Format("{0} (side {1:N0}, height {2:N0}, {3:N0} off)", Math.Abs(side) <= wide && high >= 0 && high <= tall ? "ON" : "off", side, high, along); }
  class Tally { public double fired, eyeOn, middleOn, bothOn, pitch; public int looks, hurts, hurtsOn, deaths, shots, rounds; public List<string> lines = new List<string>(), each = new List<string>(); public double lastLine = -9; }
  public static List<string> Watch(int pid, long image, long entities, int size, int count, int origin, double wait, double seconds, double wide, double tall) {
    h = OpenProcess(0x0410, false, pid); var res = new List<string>(); var ps = new byte[0x140]; var cam = new byte[0x40]; var four = new byte[4]; var one = new byte[1]; var gunAt = new byte[8];
    var all = new byte[size * count]; var health = new int[count]; var max = new int[count]; bool first = true;
    var tallies = new Tally[] { new Tally(), new Tally() }; int lastState = -1, lastClip = -1, kit = 0; double firstFire = -1, lastFire = -9, lastOn = -9, was = 0; bool lastThird = false;
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (true) {
      double now = sw.Elapsed.TotalSeconds; if (firstFire < 0 && now > wait) break; if (firstFire >= 0 && now - firstFire > seconds) break; double dt = Math.Min(now - was, 0.05); was = now;
      for (int done = 0; done < all.Length; done += 0x10000) { var part = new byte[Math.Min(0x10000, all.Length - done)]; if (Read(entities + done, part)) Buffer.BlockCopy(part, 0, all, done, part.Length); }
      if (!Read(image + 0x14ED068, ps) || !Read(image + 0x3120348, cam)) { System.Threading.Thread.Sleep(50); continue; }
      bool third = false; if (Read(image + 0x2F9CC14, four)) { long dv = BitConverter.ToUInt32(four, 0); if (dv != 0 && Read(dv + 0x10, one)) third = one[0] != 0; }
      int state = BitConverter.ToInt32(ps, 0x108), flags = BitConverter.ToInt32(ps, 0xCC), says = BitConverter.ToInt32(all, 0x1D4), clip = (says >> 4) & 0xFF, far = ((says >> 20) & 0x7FF) * 2; kit = BitConverter.ToInt32(all, 0x24C) & 31;
      Tally t = tallies[third ? 1 : 0]; bool firing = state == 5;
      Read(image + 0x14ED068 + 0x2258, gunAt);  // the two angles the game fires along: not the way the player looks (docs/PHASE3.md)
      double pitch = BitConverter.ToSingle(gunAt, 0) * Math.PI / 180, yaw = BitConverter.ToSingle(gunAt, 4) * Math.PI / 180;
      var eye = new double[] { F(ps, 0x20), F(ps, 0x24), F(ps, 0x28) + ((flags & 4) != 0 ? 40 : 60) }; var aim = new double[] { Math.Cos(pitch) * Math.Cos(yaw), Math.Cos(pitch) * Math.Sin(yaw), -Math.Sin(pitch) };
      var lens = new double[] { F(cam, 0xC), F(cam, 0x10), F(cam, 0x14) }; var look = new double[] { F(cam, 0x1C), F(cam, 0x20), F(cam, 0x24) };
      double a0, s0, h0; Past(lens, look, eye, out a0, out s0, out h0); double beyond = third ? a0 + 12 : 0;
      var byEye = new Near(); var byMiddle = new Near();
      for (int i = 4; i < count; i++) {
        int nowH = BitConverter.ToInt32(all, i * size + 0x1C8), top = BitConverter.ToInt32(all, i * size + 0x1CC); bool sane = top > 0 && top < 10000000;
        var feet = new double[] { F(all, i * size + origin), F(all, i * size + origin + 4), F(all, i * size + origin + 8) };
        if (firing && sane && (nowH > 0 || health[i] > 0)) {
          for (int which = 0; which < 2; which++) { double along, side, high; Near n = which == 0 ? byEye : byMiddle;
            if (!Past(which == 0 ? eye : lens, which == 0 ? aim : look, feet, out along, out side, out high) || along <= (which == 0 ? 0 : beyond)) continue;
            double off = Math.Max(Math.Abs(side) - wide, 0) + (high < 0 ? -high : high > tall ? high - tall : 0);
            if (off < n.off || (off == n.off && along < n.along)) { n.any = true; n.off = off; n.on = off == 0; n.along = along; n.side = side; n.high = high; } } }
        if (!first && max[i] == top && sane && health[i] > 0 && nowH < health[i]) { Tally to = tallies[lastThird ? 1 : 0];
          if (now - lastFire < 0.3) { to.hurts++; if (now - lastOn < 0.3) to.hurtsOn++; if (nowH <= 0) to.deaths++;
            if (to.each.Count < 40) to.each.Add(string.Format("    {0,5:N1} s  lost {1} of {2}{3} | the shot's line {4} | middle of the screen {5}", now - firstFire, health[i] - Math.Max(nowH, 0), top, nowH <= 0 ? " (died)" : "", Where(eye, aim, feet, wide, tall), Where(lens, look, feet, wide, tall))); } }
        health[i] = nowH; max[i] = top; }
      if (lastClip >= 0 && clip < lastClip && lastClip - clip < 12) t.rounds += lastClip - clip; lastClip = clip;
      if (firing) { if (firstFire < 0) { firstFire = now; Console.Beep(880, 250); } lastFire = now; lastThird = third; t.looks++; t.fired += dt; t.pitch += F(ps, 0x124); if (lastState != 5) t.shots++;
        if (byEye.on) { t.eyeOn += dt; lastOn = now; } if (byMiddle.on) t.middleOn += dt; if (byEye.on && byMiddle.on) t.bothOn += dt;
        if (now - t.lastLine > 0.35 && t.lines.Count < 40) { t.lastLine = now; t.lines.Add(string.Format("    {0,5:N1} s  looking {1,3:N0} down | the shot: {2} | middle of the screen: {3} | the script says the middle of the screen is {4} off", now - firstFire, F(ps, 0x124), Say(byEye), Say(byMiddle), far)); } }
      lastState = state; first = false; System.Threading.Thread.Sleep(5); }
    if (firstFire < 0) { res.Add("nobody fired"); return res; } Console.Beep(880, 150); Console.Beep(880, 150);
    res.Add("kit " + kit);
    for (int v = 1; v >= 0; v--) { Tally t = tallies[v]; res.Add(""); res.Add(v == 1 ? "THIRD PERSON" : "FIRST PERSON"); if (t.looks == 0) { res.Add("  no firing"); continue; }
      res.Add(string.Format("  firing for {0:N1} s ({1} looks, {2} pulls, {3} rounds by the script's count), looking {4:N0} degrees down on average", t.fired, t.looks, t.shots, t.rounds, t.pitch / t.looks));
      res.Add(string.Format("  the shot's own line was on a zombie for {0:N1} s; the middle of the screen was on one for {1:N1} s; both at once {2:N1} s", t.eyeOn, t.middleOn, t.bothOn));
      res.Add(string.Format("  zombies were hurt {0} times ({1} died); {2} of those just after the shot's line was on one", t.hurts, t.deaths, t.hurtsOn));
      if (t.each.Count > 0) { res.Add("  each hurt:"); res.AddRange(t.each); } res.Add("  now and then while firing:"); res.AddRange(t.lines); }
    return res; } }
'@
$p = Get-Process CoDWaW | Select-Object -First 1; $base = [int64]$p.MainModule.BaseAddress
[ShotWatch]::Watch($p.Id, $base, $base + $Entities, $Size, $Count, $Origin, $Wait, $Seconds, $Wide, $Tall)
