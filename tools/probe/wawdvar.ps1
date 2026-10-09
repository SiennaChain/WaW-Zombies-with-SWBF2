# Finds World at War settings (dvars) by a part of their name: every text in
# the game's memory that contains -Like and looks like a setting's name, and
# for each one the records that point at it with what they hold. Reads only.
#   -Like footstep
param([string]$Like = 'footstep', [int]$Most = 40)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Dvars {
  [StructLayout(LayoutKind.Sequential)] public struct MBI { public IntPtr Base, AllocBase; public uint AllocProtect; public IntPtr Size; public uint State, Protect, Type; }
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int p);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr a, out MBI m, IntPtr l);
  class Region { public long Base; public byte[] Data; }
  public static List<string> Run(int pid, string like, long imageBase, int most) {
    var lines = new List<string>(); IntPtr h = OpenProcess(0x0410, false, pid); var regions = new List<Region>();
    long at = 0x10000; MBI m;
    while (at < 0x7FFF0000 && VirtualQueryEx(h, (IntPtr)at, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) != IntPtr.Zero) {
      long size = (long)m.Size; if (size <= 0) break;
      if (m.State == 0x1000 && (m.Protect & 0x100) == 0 && (m.Protect & 0xEE) != 0 && size <= 256L * 1024 * 1024) {
        var buf = new byte[size]; IntPtr got; if (ReadProcessMemory(h, m.Base, buf, (IntPtr)size, out got) && (long)got > 0) { if ((long)got < size) Array.Resize(ref buf, (int)got); regions.Add(new Region { Base = (long)m.Base, Data = buf }); }
      }
      at = (long)m.Base + size;
    }
    byte[] needle = Encoding.ASCII.GetBytes(like.ToLowerInvariant());
    var names = new Dictionary<long, string>();
    foreach (var r in regions) {
      byte[] d = r.Data;
      for (int i = 0; i + needle.Length <= d.Length; i++) {
        int j = 0; while (j < needle.Length && (d[i + j] | 0x20) == needle[j]) j++;
        if (j < needle.Length) continue;
        int a = i, b = i; while (a > 0 && (d[a - 1] == '_' || char.IsLetterOrDigit((char)d[a - 1]))) a--; while (b < d.Length && (d[b] == '_' || char.IsLetterOrDigit((char)d[b]))) b++;
        if (b < d.Length && d[b] == 0 && (a == 0 || d[a - 1] == 0) && b - a < 64) { long addr = r.Base + a; if (!names.ContainsKey(addr)) names[addr] = Encoding.ASCII.GetString(d, a, b - a); }
        i = b;
      }
    }
    foreach (var name in names) {
      byte[] ptr = BitConverter.GetBytes((uint)name.Key); int shown = 0;
      foreach (var r in regions) {
        byte[] d = r.Data;
        for (int i = 0; i + 0x30 <= d.Length; i += 4) {
          if (d[i] != ptr[0] || d[i + 1] != ptr[1] || d[i + 2] != ptr[2] || d[i + 3] != ptr[3]) continue;
          long rec = r.Base + i;
          string where = (rec >= imageBase && rec < imageBase + 0x8000000) ? string.Format("CoDWaW.exe+0x{0:X}", rec - imageBase) : string.Format("0x{0:X}", rec);
          lines.Add(string.Format("{0,-36} record at {1,-22} type byte {2}  +0x10: float {3:G6} / int {4}   +0x14: {5:G6}  +0x20..: {6:G6} {7:G6} {8:G6}", name.Value, where, d[i + 0xC],
            BitConverter.ToSingle(d, i + 0x10), BitConverter.ToInt32(d, i + 0x10), BitConverter.ToSingle(d, i + 0x14), BitConverter.ToSingle(d, i + 0x20), BitConverter.ToSingle(d, i + 0x24), BitConverter.ToSingle(d, i + 0x28)));
          if (++shown >= 3) break;
        }
        if (shown >= 3) break;
      }
      if (shown == 0) lines.Add(string.Format("{0,-36} (nothing points at this text)", name.Value));
      if (lines.Count >= most) break;
    }
    return lines;
  }
}
'@
$p = Get-Process CoDWaW | Select-Object -First 1
[Dvars]::Run($p.Id, $Like, [int64]$p.MainModule.BaseAddress, $Most) | Sort-Object
