# Read-only. Finds the thing Battlefront II's unit has just thrown, in flight.
#
# Nothing in the weapon points at it (docs/PHASE3.md), so it is found the slow
# way: the bridge uses the unit's ability ([debug] force_functions), this
# waits for the weapon to let go of what it was holding (the pointer at +0xD8
# in the weapon goes to 0), and then takes three pictures of the game's
# memory a moment apart. Whatever is three floats in a row that sit near the
# unit and move the same few metres from each picture to the next is the
# thing's position, or a copy of it.
#
#   bfflying.ps1            the ability in hand, thrown with function 1
#   -From / -To             the stretch of memory searched (the game's objects
#                           have all been between these)
#   -Follow                 then keep reading the first find until it stops
#                           changing, and list everything around it that moved
param(
    [int]$Function = 1,
    [long]$From = 0x08000000, [long]$To = 0x0C000000,
    [int]$GapMs = 70, [double]$MinStep = 0.6, [double]$MaxStep = 4.0, [double]$Near = 25,
    [switch]$Follow, [int]$Around = 0x180, [int]$FollowMs = 3500,
    [int]$Pick = 1,                    # which of the finds to follow (1 = the first)
    [int]$Back = 0x50, [int]$Span = 0x120,   # what to print of it: from this far before the position, this much
    [string]$Ini = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData\wawbf.ini',
    [long]$UnitPointer = 0x1A296B0
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class BfFlying {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI info, IntPtr len);
  [StructLayout(LayoutKind.Sequential)] public struct MBI { public IntPtr Base, AllocBase; public uint AllocProtect; public IntPtr Size; public uint State, Protect, Type; }
  static IntPtr h; public static void Open(int pid) { h = OpenProcess(0x0410, false, pid); }
  public static byte[] Bytes(long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }
  public static uint U32(long a) { var b = Bytes(a, 4); return b == null ? 0 : BitConverter.ToUInt32(b, 0); }
  public static bool WaitZero(long a, int ms) { var sw = System.Diagnostics.Stopwatch.StartNew(); bool was = false; while (sw.ElapsedMilliseconds < ms) { uint v = U32(a); if (v != 0) was = true; else if (was) return true; System.Threading.Thread.Sleep(1); } return false; }
  static List<KeyValuePair<long, byte[]>> Take(List<long[]> regions) { var res = new List<KeyValuePair<long, byte[]>>(); foreach (var r in regions) { var b = Bytes(r[0], (int)r[1]); if (b != null) res.Add(new KeyValuePair<long, byte[]>(r[0], b)); } return res; }
  public static List<string> Find(long from, long to, int gapMs, double minStep, double maxStep, double near, float ux, float uy, float uz) {
    var regions = new List<long[]>(); long at = from; MBI info;
    while (at < to && VirtualQueryEx(h, (IntPtr)at, out info, (IntPtr)Marshal.SizeOf(typeof(MBI))) != IntPtr.Zero) {
      long size = (long)info.Size; if (size <= 0) break;
      if (info.State == 0x1000 && (info.Protect & 0x04) != 0 && (info.Protect & 0x100) == 0 && size <= 0x4000000) regions.Add(new long[] { (long)info.Base, size });
      at = (long)info.Base + size;
    }
    var sw = System.Diagnostics.Stopwatch.StartNew();
    var a = Take(regions); long t1 = sw.ElapsedMilliseconds; System.Threading.Thread.Sleep(gapMs);
    var b = Take(regions); long t2 = sw.ElapsedMilliseconds; System.Threading.Thread.Sleep(gapMs);
    var c = Take(regions); long t3 = sw.ElapsedMilliseconds;
    var res = new List<string>(); long total = 0; foreach (var r in regions) total += r[1];
    res.Add(string.Format("{0} stretches, {1:N0} bytes; pictures at {2}, {3} and {4} ms after the throw left the hand", regions.Count, total, t1, t2, t3));
    for (int r = 0; r < a.Count && r < b.Count && r < c.Count; r++) {
      if (a[r].Key != b[r].Key || a[r].Key != c[r].Key) continue; byte[] x = a[r].Value, y = b[r].Value, z = c[r].Value; int n = Math.Min(x.Length, Math.Min(y.Length, z.Length));
      for (int i = 0; i + 12 <= n; i += 4) {
        if (BitConverter.ToUInt32(x, i) == BitConverter.ToUInt32(y, i) && BitConverter.ToUInt32(x, i + 8) == BitConverter.ToUInt32(y, i + 8)) continue;
        float x1 = BitConverter.ToSingle(x, i), y1 = BitConverter.ToSingle(x, i + 4), z1 = BitConverter.ToSingle(x, i + 8);
        if (float.IsNaN(x1) || Math.Abs(x1 - ux) > near || Math.Abs(y1 - uy) > near || Math.Abs(z1 - uz) > near) continue;
        float x2 = BitConverter.ToSingle(y, i), y2 = BitConverter.ToSingle(y, i + 4), z2 = BitConverter.ToSingle(y, i + 8);
        float x3 = BitConverter.ToSingle(z, i), y3 = BitConverter.ToSingle(z, i + 4), z3 = BitConverter.ToSingle(z, i + 8);
        double d1 = Math.Sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) + (z2 - z1) * (z2 - z1)), d2 = Math.Sqrt((x3 - x2) * (x3 - x2) + (y3 - y2) * (y3 - y2) + (z3 - z2) * (z3 - z2));
        if (d1 < minStep || d1 > maxStep || d2 < minStep || d2 > maxStep) continue;
        double dot = (x2 - x1) * (x3 - x2) + (z2 - z1) * (z3 - z2); if (dot <= 0) continue;   // still going the same way across the ground
        res.Add(string.Format("0x{0:X8}: ({1:F2} {2:F2} {3:F2}) -> ({4:F2} {5:F2} {6:F2}) -> ({7:F2} {8:F2} {9:F2})   steps {10:F2}, {11:F2} m", a[r].Key + i, x1, y1, z1, x2, y2, z2, x3, y3, z3, d1, d2));
        if (res.Count > 40) return res;
      }
    }
    return res;
  }
  static string Show(uint u, float f) { return u < 0x10000 ? u.ToString() : (Math.Abs(f) > 1e-4 && Math.Abs(f) < 1e7) ? string.Format("{0:G5}", f) : string.Format("0x{0:X8}", u); }
  public static List<string> Trace(long at, int size, int ms, int most) {
    var res = new List<string>(); var last = Bytes(at, size); if (last == null) return res; var seen = new SortedDictionary<int, List<string>>(); var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) { var b = Bytes(at, size); if (b == null) break; long t = sw.ElapsedMilliseconds;
      for (int i = 0; i + 4 <= size; i += 4) { uint x = BitConverter.ToUInt32(last, i), y = BitConverter.ToUInt32(b, i); if (x == y) continue; List<string> l;
        if (!seen.TryGetValue(i, out l)) { l = new List<string>(); l.Add(Show(x, BitConverter.ToSingle(last, i))); seen[i] = l; }
        if (l.Count <= most) l.Add(string.Format("{0}ms {1}", t, Show(y, BitConverter.ToSingle(b, i)))); else if (l.Count == most + 1) l.Add("..."); }
      last = b; System.Threading.Thread.Sleep(8); }
    foreach (var k in seen) res.Add(string.Format("  {0}0x{1:X3}: {2}", k.Key < size / 2 ? "-" : "+", Math.Abs(k.Key - size / 2), string.Join("  ->  ", k.Value.ToArray())));
    return res;
  }
}
'@
function Set-Force([uint32]$Mask) { $text = (Get-Content $Ini -Raw) -replace '(?m)^force_functions\s*=.*$', ('force_functions = 0x{0:X}' -f $Mask); [IO.File]::WriteAllText($Ini, $text, (New-Object Text.ASCIIEncoding)) }
$bf = Get-Process BattlefrontII | Select-Object -First 1; [BfFlying]::Open($bf.Id); $base = [int64]$bf.MainModule.BaseAddress
$unit = [int64][BfFlying]::U32($base + $UnitPointer) - 0x120
$slot = [BfFlying]::Bytes($unit + 0x741, 1)[0]; $weapon = [int64][BfFlying]::U32($unit + 0x720 + 4 * $slot)
$p = [BfFlying]::Bytes($unit + 0x120, 12); $ux = [BitConverter]::ToSingle($p, 0); $uy = [BitConverter]::ToSingle($p, 4); $uz = [BitConverter]::ToSingle($p, 8)
'unit 0x{0:X8} at ({1:F2} {2:F2} {3:F2}); ability in slot {4}, weapon 0x{5:X8}' -f $unit, $ux, $uy, $uz, $slot, $weapon
try {
    Set-Force ([uint32]1 -shl $Function)
    if (-not [BfFlying]::WaitZero($weapon + 0xD8, 5000)) { 'the weapon never let go of anything'; return }
    $found = [BfFlying]::Find($From, $To, $GapMs, $MinStep, $MaxStep, $Near, $ux, $uy, $uz)
    $found
    if ($Follow -and $found.Count -gt $Pick -and $found[$Pick] -match '^0x([0-9A-F]{8})') {
        $at = [Convert]::ToInt64($Matches[1], 16)
        $object = $at - $Back
        function Dump([string]$when) {
            $b = [BfFlying]::Bytes($object, $Span); $clock = [BitConverter]::ToSingle([BfFlying]::Bytes($weapon + 0xB4, 4), 0)
            "the object at 0x{0:X8}, {1} (the weapon's clock reads {2:F3}):" -f $object, $when, $clock
            for ($i = 0; $i -lt $Span; $i += 16) { '  +0x{0:X3}: {1}' -f $i, ((0..3 | ForEach-Object { $u = [BitConverter]::ToUInt32($b, $i + 4 * $_); $v = [BitConverter]::ToSingle($b, $i + 4 * $_); if ($u -lt 0x10000) { '{0,12}' -f $u } elseif ([Math]::Abs($v) -gt 1e-4 -and [Math]::Abs($v) -lt 1e7) { '{0,12:G6}' -f $v } else { '  0x{0:X8}' -f $u } }) -join ' ') }
        }
        Dump 'in flight'
        Start-Sleep -Milliseconds 500
        Dump 'half a second later'
        "everything within 0x{0:X} of 0x{1:X8} that changes over the next {2} ms (offsets from the position):" -f $Around, $at, $FollowMs
        [BfFlying]::Trace($at - $Around, 2 * $Around, $FollowMs, 8)
        Dump 'afterwards'
    }
} finally { Set-Force 0 }
