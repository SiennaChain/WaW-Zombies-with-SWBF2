# Read-only. Watches the weapon in hand in both games, side by side: what
# World at War's is doing and how many rounds its scripts say are in the
# magazine, and what Battlefront II's is doing, which weapon it is, and how
# full its magazine is. A line each time anything changes, for -Seconds.
param([int]$Seconds = 15, [int]$Most = 80)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class GunWatch {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static byte[] Bytes(IntPtr h, long a, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r); return b; }
  static uint U(IntPtr h, long a) { return BitConverter.ToUInt32(Bytes(h, a, 4), 0); } static float F(IntPtr h, long a) { return BitConverter.ToSingle(Bytes(h, a, 4), 0); }
  public static List<string> Watch(int wawPid, long waw, int bfPid, long bf, double seconds, int most) {
    IntPtr w = OpenProcess(0x0410, false, wawPid), b = OpenProcess(0x0410, false, bfPid); var res = new List<string>(); string last = ""; var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.Elapsed.TotalSeconds < seconds && res.Count < most) {
      uint state = U(w, waw + 0x14ED170); uint says = U(w, waw + 0x136C8C4); bool attack = Bytes(w, waw + 0x2C0FE5C, 1)[0] != 0;
      long unit = (long)U(b, bf + 0x1A296B0) - 0x120; byte slot = Bytes(b, unit + 0x740, 1)[0]; long weapon = U(b, unit + 0x720 + 4 * slot);
      uint bfState = weapon != 0 ? U(b, weapon + 0xB0) : 99; long counter = weapon != 0 ? U(b, weapon + 0x88) : 0; float clip = counter != 0 ? F(b, counter + 0x10) : -1; byte view = Bytes(b, bf + 0x1AF9106, 1)[0];
      uint fire = U(b, unit + 0x278) & 0xFF;
      string now = string.Format("WaW: attack {0}, weapon state {1,2}, in hand {2}, magazine {3,3} of {4,3}{5}{6}   |   SWBF2 ({7} person): weapon {8} state {9}, magazine {10,4:F2}, fire control {11:X2}",
        attack ? "held" : "up  ", state, says & 3, (says >> 4) & 0xFF, (says >> 12) & 0xFF, (says & 8) != 0 ? ", DRY" : "", (says & 4) != 0 ? "" : ", no ability", view == 0 ? "third" : "first", slot + 1, bfState, Math.Round(clip, 2), fire);
      if (now != last) { res.Add(string.Format("{0,6:F2} s  {1}", sw.Elapsed.TotalSeconds, now)); last = now; }
      System.Threading.Thread.Sleep(12);
    }
    return res; } }
'@
$waw = Get-Process CoDWaW | Select-Object -First 1; $bf = Get-Process BattlefrontII | Select-Object -First 1
[GunWatch]::Watch($waw.Id, [int64]$waw.MainModule.BaseAddress, $bf.Id, [int64]$bf.MainModule.BaseAddress, $Seconds, $Most)
