# Finds the map's own list of entities (plain text, "{ "classname" ... }") in
# World at War's memory and saves it. Reads only.
param([string]$Mark = '"targetname" "treasure_chest_use"', [string]$Out = (Join-Path (Get-Location) 'wawents.txt'))
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Ents {
  [StructLayout(LayoutKind.Sequential)] public struct MBI { public IntPtr Base, AllocBase; public uint AllocProtect; public IntPtr Size; public uint State, Protect, Type; }
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int p);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr a, out MBI m, IntPtr l);
  static int Find(byte[] hay, int length, byte[] needle, int from) { for (int i = from; i + needle.Length <= length; i++) { int j = 0; while (j < needle.Length && hay[i + j] == needle[j]) j++; if (j == needle.Length) return i; } return -1; }
  // The longest run of text around the first place the mark is found in each region.
  public static List<string> Run(int pid, string mark) {
    var found = new List<string>(); IntPtr h = OpenProcess(0x0410, false, pid); byte[] needle = Encoding.ASCII.GetBytes(mark);
    long at = 0x10000; MBI m;
    while (at < 0x7FFF0000 && VirtualQueryEx(h, (IntPtr)at, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) != IntPtr.Zero) {
      long size = (long)m.Size; if (size <= 0) break;
      if (m.State == 0x1000 && (m.Protect & 0x100) == 0 && (m.Protect & 0xEE) != 0 && size <= 512L * 1024 * 1024) {
        var buf = new byte[size]; IntPtr got;
        if (ReadProcessMemory(h, m.Base, buf, (IntPtr)size, out got)) {
          int n = (int)got, hit = Find(buf, n, needle, 0);
          if (hit >= 0) {
            int a = hit, b = hit;
            while (a > 0 && (buf[a - 1] == 10 || buf[a - 1] == 13 || buf[a - 1] == 9 || (buf[a - 1] >= 32 && buf[a - 1] < 127))) a--;
            while (b < n && (buf[b] == 10 || buf[b] == 13 || buf[b] == 9 || (buf[b] >= 32 && buf[b] < 127))) b++;
            found.Add(string.Format("0x{0:X}+0x{1:X} ({2} bytes)\n", (long)m.Base, a, b - a) + Encoding.ASCII.GetString(buf, a, b - a));
          }
        }
      }
      at = (long)m.Base + size;
    }
    return found;
  }
}
'@
$p = Get-Process CoDWaW | Select-Object -First 1
$found = [Ents]::Run($p.Id, $Mark)
"found in $($found.Count) place(s): " + (($found | ForEach-Object { $_.Length }) -join ', ') + ' characters'
if ($found.Count) { $best = $found | Sort-Object Length -Descending | Select-Object -First 1; [IO.File]::WriteAllText($Out, $best); "saved the longest to $Out" }
