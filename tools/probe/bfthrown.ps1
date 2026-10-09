# Read-only. Follows what Battlefront II's unit has just thrown or fired.
#
# A weapon that throws things holds the next one ready: a pointer at +0xD8 in
# the weapon, which goes to 0 as the thing leaves the hand and is filled again
# when the next is ready (docs/PHASE3.md). This notes that pointer, has the
# bridge use the unit's ability ([debug] force_functions), and lists every
# word of the thing pointed at that changes, with the values it goes through
# and when: its position, its speed, and whatever counts down to its going
# off are in there.
#
#   bfthrown.ps1                  the ability in hand, used with function 1
#   bfthrown.ps1 -Wait            wait for the pointer to change instead, and
#                                 follow what it changes to (-Launched 0xE0)
param(
    [int]$Slot = -1,                   # -1: the ability in hand
    [int]$Function = 1,
    [int]$Size = 0x200,
    [int]$Ms = 3500,
    [int]$Most = 9,
    [long]$Launched = 0xD8,            # in a weapon: pointer to what it will throw next
    [switch]$Wait,
    [string]$Ini = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData\wawbf.ini',
    [long]$UnitPointer = 0x1A296B0
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class BfThrown {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr h; public static void Open(int pid) { h = OpenProcess(0x0410, false, pid); }
  public static byte[] Bytes(long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }
  public static uint U32(long a) { var b = Bytes(a, 4); return b == null ? 0 : BitConverter.ToUInt32(b, 0); }
  static string Show(uint u, float f) { return u < 0x10000 ? u.ToString() : (Math.Abs(f) > 1e-4 && Math.Abs(f) < 1e7) ? string.Format("{0:G5}", f) : string.Format("0x{0:X8}", u); }
  // Waits for the pointer at `slot` to change, then traces what it points at.
  public static List<string> Follow(long slot, int size, int waitMs, int ms, int most, bool wait) {
    var res = new List<string>(); uint was = U32(slot); var sw = System.Diagnostics.Stopwatch.StartNew(); uint now = was;
    if (wait) {
      while (sw.ElapsedMilliseconds < waitMs && (now = U32(slot)) == was) System.Threading.Thread.Sleep(1);
      if (now == was || now < 0x10000) { res.Add(string.Format("the pointer did not change (still 0x{0:X8})", was)); return res; }
      res.Add(string.Format("launched after {0} ms: 0x{1:X8} (before: 0x{2:X8})", sw.ElapsedMilliseconds, now, was));
    } else {
      if (now < 0x10000) { res.Add("nothing is held ready"); return res; }
      res.Add(string.Format("held ready: 0x{0:X8}", now));
    }
    var last = Bytes(now, size); if (last == null) { res.Add("could not be read"); return res; }
    var first = (byte[])last.Clone(); var seen = new SortedDictionary<int, List<string>>(); sw.Restart();
    while (sw.ElapsedMilliseconds < ms) {
      var b = Bytes(now, size); if (b == null) break; long at = sw.ElapsedMilliseconds;
      for (int i = 0; i + 4 <= size; i += 4) {
        uint x = BitConverter.ToUInt32(last, i), y = BitConverter.ToUInt32(b, i); if (x == y) continue;
        List<string> l; if (!seen.TryGetValue(i, out l)) { l = new List<string>(); l.Add(Show(x, BitConverter.ToSingle(last, i))); seen[i] = l; }
        if (l.Count <= most) l.Add(string.Format("{0}ms {1}", at, Show(y, BitConverter.ToSingle(b, i)))); else if (l.Count == most + 1) l.Add("...");
      }
      last = b; System.Threading.Thread.Sleep(8);
    }
    var head = new List<string>(); for (int i = 0; i < 0x20; i += 4) head.Add(Show(BitConverter.ToUInt32(first, i), BitConverter.ToSingle(first, i)));
    res.Add("its first words: " + string.Join(" ", head.ToArray()));
    foreach (var k in seen) res.Add(string.Format("  +0x{0:X3}: {1}", k.Key, string.Join("  ->  ", k.Value.ToArray())));
    return res;
  }
}
'@
function Set-Force([uint32]$Mask) { $text = (Get-Content $Ini -Raw) -replace '(?m)^force_functions\s*=.*$', ('force_functions = 0x{0:X}' -f $Mask); [IO.File]::WriteAllText($Ini, $text, (New-Object Text.ASCIIEncoding)) }
$bf = Get-Process BattlefrontII | Select-Object -First 1; [BfThrown]::Open($bf.Id); $base = [int64]$bf.MainModule.BaseAddress
$unit = [int64][BfThrown]::U32($base + $UnitPointer) - 0x120
if ($Slot -lt 0) { $Slot = [BfThrown]::Bytes($unit + 0x741, 1)[0] }
$weapon = [int64][BfThrown]::U32($unit + 0x720 + 4 * $Slot)
$p = [BfThrown]::Bytes($unit + 0x120, 12)
'unit 0x{0:X8} at ({1:F2} {2:F2} {3:F2}); weapon in slot {4} at 0x{5:X8}' -f $unit, [BitConverter]::ToSingle($p, 0), [BitConverter]::ToSingle($p, 4), [BitConverter]::ToSingle($p, 8), $Slot, $weapon
try { Set-Force ([uint32]1 -shl $Function); [BfThrown]::Follow($weapon + $Launched, $Size, 4000, $Ms, $Most, [bool]$Wait) } finally { Set-Force 0 }
