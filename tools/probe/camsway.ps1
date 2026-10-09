# Read-only. Does World at War's third-person camera move when the player does not?
#
# The player's position and view, and the camera's position, are read many
# times a second. Over the longest stretch in which the player neither moved
# nor turned, it says how far the camera wandered: back and forth, side to
# side, and up and down. Left to itself the game hangs that camera on the
# head of the player's soldier, and it wanders some 9 units from side to side
# and 4 up and down as the soldier stands there (docs/PHASE3.md).
#
# (Each frame the game first puts the camera at the player's eyes and then
# moves it behind them. A look that lands between the two sees it at the eyes;
# those are left out.)
param([double]$Seconds = 20, [double]$Enough = 6)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class CamSway {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr h; static float[] Fs(long at, int n) { var b = new byte[4 * n]; IntPtr r; ReadProcessMemory(h, (IntPtr)at, b, (IntPtr)b.Length, out r); var f = new float[n]; for (int i = 0; i < n; i++) f[i] = BitConverter.ToSingle(b, 4 * i); return f; }
  static uint U(long at) { var b = new byte[4]; IntPtr r; ReadProcessMemory(h, (IntPtr)at, b, (IntPtr)4, out r); return BitConverter.ToUInt32(b, 0); }
  public static List<string> Watch(int pid, long image, double seconds, double enough) { h = OpenProcess(0x0410, false, pid); var res = new List<string>(); long client = image + 0x14ED068;
    var sw = System.Diagnostics.Stopwatch.StartNew(); float[] org0 = null, ang0 = null; double since = 0; double[] lo = new double[3], hi = new double[3]; double bestLen = 0; double[] bestMove = new double[3]; int looks = 0;
    while (sw.Elapsed.TotalSeconds < seconds && bestLen < enough) { var org = Fs(client + 0x20, 3); var ang = Fs(client + 0x124, 3); var cam = Fs(image + 0x3120354, 3); looks++; double now = sw.Elapsed.TotalSeconds;
      bool third = (U(U(image + 0x2F9CC14) + 0x10) & 0xFF) != 0, paused = (U(U(image + 0x1B552C4) + 0x10) & 0xFF) != 0;
      bool still = third && !paused && org0 != null && Math.Abs(org[0] - org0[0]) < 0.01 && Math.Abs(org[1] - org0[1]) < 0.01 && Math.Abs(org[2] - org0[2]) < 0.01 && Math.Abs(ang[0] - ang0[0]) < 0.01 && Math.Abs(ang[1] - ang0[1]) < 0.01;
      double y = ang[1] * Math.PI / 180, dx = cam[0] - org[0], dy = cam[1] - org[1]; var v = new double[] { -(dx * Math.Cos(y) + dy * Math.Sin(y)), dx * Math.Sin(y) - dy * Math.Cos(y), cam[2] - org[2] };
      // (the first quarter second after stopping is left out: the camera is still settling behind the player)
      if (!still) { org0 = org; ang0 = ang; since = now + 0.25; for (int i = 0; i < 3; i++) { lo[i] = 1e9; hi[i] = -1e9; } }
      else if (now >= since && v[0] > 30) { for (int i = 0; i < 3; i++) { lo[i] = Math.Min(lo[i], v[i]); hi[i] = Math.Max(hi[i], v[i]); } if (now - since > bestLen) { bestLen = now - since; for (int i = 0; i < 3; i++) bestMove[i] = hi[i] - lo[i]; } }
      System.Threading.Thread.Sleep(8); }
    if (bestLen < 1.0) res.Add(string.Format("in {0:N0} s the player never stood still in third person for a second", sw.Elapsed.TotalSeconds));
    else res.Add(string.Format("standing still for {0:N1} s, the camera wandered {1:N2} units back and forth, {2:N2} side to side, {3:N2} up and down", bestLen, bestMove[0], bestMove[1], bestMove[2]));
    return res; } }
'@
$p = Get-Process CoDWaW | Select-Object -First 1
[CamSway]::Watch($p.Id, [int64]$p.MainModule.BaseAddress, $Seconds, $Enough)
