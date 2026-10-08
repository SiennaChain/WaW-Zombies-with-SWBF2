# Read-only. Shows how far the arena's self-start got.
#
# The shipped game keeps no log of what its menu scripts do, so
# swbf2/arena/addme.lua leaves a string in memory at each step, put together
# at run time ("wawbf-trace:" .. step) so that it only exists if the step
# ran. This looks for those strings.
#
#   hooks-in                 the script ran and wrapped the menu's functions
#   logging-in-profile-N     it logged in the highlighted profile
#   launching-<mission>      it reached the single player tab
#   entered-<mission>        the game accepted the launch
#
# Old steps can linger after newer ones; the furthest one is what matters.
# Once a mission is running the menu's memory is thrown away, so "nothing
# found" in a match that started by itself is normal.
param([string]$ProcessName = 'BattlefrontII', [string]$Prefix = 'wawbf-trace:')
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class BfLuaTrace {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static SortedDictionary<string, int> Find(int pid, string prefix) {
        var found = new SortedDictionary<string, int>(); IntPtr h = OpenProcess(0x0410, false, pid);   // read and query only
        byte[] p = Encoding.ASCII.GetBytes(prefix); long addr = 0x10000;
        while (addr < 0x7FFF0000L) {
            MBI m; if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize; if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var buf = new byte[size]; IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got)) {
                    for (int i = 0; i + p.Length < buf.Length; i++) {
                        if (buf[i] != p[0]) continue;
                        int k = 1; while (k < p.Length && buf[i + k] == p[k]) k++;
                        if (k < p.Length) continue;
                        int e = i + p.Length; while (e < buf.Length && e - i < 80 && buf[e] >= 0x21 && buf[e] < 0x7F) e++;
                        if (e == i + p.Length) continue;   // the bare prefix is the script's own constant
                        string s = Encoding.ASCII.GetString(buf, i + p.Length, e - i - p.Length);
                        int c; found.TryGetValue(s, out c); found[s] = c + 1;
                    }
                }
            }
            addr = b + size;
        }
        return found;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$found = [BfLuaTrace]::Find($proc.Id, $Prefix)
if ($found.Count -eq 0) { 'no trace strings in memory' } else { foreach ($k in $found.Keys) { '  {0}  (x{1})' -f $k, $found[$k] } }
