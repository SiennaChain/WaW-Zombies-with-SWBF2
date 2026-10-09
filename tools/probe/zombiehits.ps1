# Read-only. Watches what World at War's zombies lose while the player shoots.
#
# Every entity with health is looked at many times a second. Each time one
# loses health the amount is noted, with what the player's weapon was doing at
# that moment. At the end: how many shots the weapon began, how many times a
# zombie was hurt and by how much, and how many died. A weapon that fires and
# "does nothing" shows as shots with no hurts; one that is merely weak shows
# as hurts that are small beside the zombies' health.
param([int]$Seconds = 15, [long]$Entities = 0x136C6F0, [int]$Size = 0x378, [int]$Count = 1024)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class ZombieHits {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  public static List<string> Watch(int pid, long image, long entities, int size, int count, double seconds) {
    IntPtr h = OpenProcess(0x0410, false, pid); IntPtr r; var res = new List<string>(); var four = new byte[4];
    var health = new int[count]; var max = new int[count]; var all = new byte[size * count]; bool first = true;
    var hurts = new SortedDictionary<int, int>(); int shots = 0, deaths = 0, lastState = -1, hurtCount = 0, firingLooks = 0, looks = 0; int toughest = 0; int weapon = -1;
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.Elapsed.TotalSeconds < seconds) {
      for (int done = 0; done < all.Length; done += 0x10000) { var part = new byte[Math.Min(0x10000, all.Length - done)]; if (ReadProcessMemory(h, (IntPtr)(entities + done), part, (IntPtr)part.Length, out r)) Buffer.BlockCopy(part, 0, all, done, part.Length); }
      ReadProcessMemory(h, (IntPtr)(image + 0x14ED170), four, (IntPtr)4, out r); int state = BitConverter.ToInt32(four, 0);
      ReadProcessMemory(h, (IntPtr)(image + 0x14ED16C), four, (IntPtr)4, out r); weapon = BitConverter.ToInt32(four, 0);
      looks++; if (state == 5) { firingLooks++; if (lastState != 5) shots++; } lastState = state;
      for (int i = 1; i < count; i++) {
        int now = BitConverter.ToInt32(all, i * size + 0x1C8), top = BitConverter.ToInt32(all, i * size + 0x1CC);
        if (!first && max[i] == top && top > 0 && top < 10000000 && health[i] > 0 && now < health[i]) {
          int lost = health[i] - Math.Max(now, 0); hurtCount++; int n; hurts.TryGetValue(lost, out n); hurts[lost] = n + 1; if (now <= 0) deaths++; }
        if (top > toughest && top < 10000000 && now > 0) toughest = top;
        health[i] = now; max[i] = top;
      }
      first = false; System.Threading.Thread.Sleep(8);
    }
    res.Add(string.Format("{0:N0} s; weapon index {1}; the weapon began {2} shots (firing in {3} of {4} looks)", seconds, weapon, shots, firingLooks, looks));
    res.Add(string.Format("zombies were hurt {0} times, {1} died; the toughest alive had {2} health to begin with", hurtCount, deaths, toughest));
    foreach (var k in hurts) res.Add(string.Format("    lost {0,5} health: {1} time(s)", k.Key, k.Value));
    return res; } }
'@
$p = Get-Process CoDWaW | Select-Object -First 1; $base = [int64]$p.MainModule.BaseAddress
[ZombieHits]::Watch($p.Id, $base, $base + $Entities, $Size, $Count, $Seconds)
