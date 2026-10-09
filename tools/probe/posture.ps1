# Read-only. Watches how both games think the player is standing, side by side.
#
# World at War: the player's flags (a bit of which is "crouched"), what its
# weapon is doing (sprinting shows there), and how high the camera is above
# the feet. Battlefront II: the unit's posture byte, how high its eyes are,
# the view (first or third person), and its control words for sprint, jump and
# crouch. A line is printed each time any of them changes, for -Seconds.
param([int]$Seconds = 25, [switch]$Quiet)   # -Quiet: only crouching, sprinting and the view, not every shot
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Posture {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static byte[] Bytes(IntPtr h, long a, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r); return b; }
  static uint U(IntPtr h, long a) { return BitConverter.ToUInt32(Bytes(h, a, 4), 0); } static float F(IntPtr h, long a) { return BitConverter.ToSingle(Bytes(h, a, 4), 0); }
  public static List<string> Watch(int wawPid, long waw, int bfPid, long bf, double seconds, bool quiet) {
    IntPtr w = OpenProcess(0x0410, false, wawPid), b = OpenProcess(0x0410, false, bfPid); var res = new List<string>(); string last = ""; var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.Elapsed.TotalSeconds < seconds) {
      uint flags = U(w, waw + 0x14ED134); uint state = U(w, waw + 0x14ED170); float eye = F(w, waw + 0x312035C) - F(w, waw + 0x14ED090);
      long unit = (long)U(b, bf + 0x1A296B0) - 0x120; byte posture = Bytes(b, unit + 0x742, 1)[0]; float bfEye = F(b, unit + 0x320) - F(b, unit + 0x124); byte view = Bytes(b, bf + 0x1AF9106, 1)[0];
      uint sprint = U(b, unit + 0x28C) & 0xFF, crouch = U(b, unit + 0x288) & 0xFF, jump = U(b, unit + 0x284) & 0xFF; float height = F(b, unit + 0x124);
      float vx = F(b, unit + 0x4DC), vz = F(b, unit + 0x4E4); double speed = Math.Sqrt(vx * vx + vz * vz);
      string now = quiet
        ? string.Format("WaW {0}{1}   |   SWBF2 {2}, {3} person, sprint held {4}, moving {5}",
            (flags & 4) != 0 ? "crouched" : "standing", state >= 23 && state <= 25 ? ", sprinting (state " + state + ")" : "", (posture & 0x40) != 0 ? "crouched" : "standing", view == 0 ? "third" : "first",
            (sprint & 3) != 0 ? "yes" : "no", speed < 0.5 ? "no" : speed < 5.5 ? "at a walk or run" : "fast")
        : string.Format("WaW flags 0x{0:X}, weapon state {1,2}, camera {2,4:F0} above the feet   |   SWBF2 posture 0x{3:X2}, eyes {4:F2} m up, {5} person, feet at {6,5:F2}, control words: sprint {7:X2} crouch {8:X2} jump {9:X2}",
            flags, state, Math.Round(eye / 4) * 4, posture, Math.Round(bfEye, 1), view == 0 ? "third" : "first", Math.Round(height, 1), sprint, crouch, jump);
      if (now != last) { res.Add(string.Format("{0,6:F2} s  {1}", sw.Elapsed.TotalSeconds, now)); last = now; }
      System.Threading.Thread.Sleep(15);
    }
    return res; } }
'@
$waw = Get-Process CoDWaW | Select-Object -First 1; $bf = Get-Process BattlefrontII | Select-Object -First 1
[Posture]::Watch($waw.Id, [int64]$waw.MainModule.BaseAddress, $bf.Id, [int64]$bf.MainModule.BaseAddress, $Seconds, [bool]$Quiet)
