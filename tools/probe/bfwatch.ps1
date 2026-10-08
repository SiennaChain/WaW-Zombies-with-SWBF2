# Read-only. Watches a few small pieces of Battlefront II's memory and says
# which bytes of them changed and what values they took.
#
# For finding what a real input does to the game's state: start it, have the
# player do the thing a few times, and read off which bytes moved.
#
# -Regions is "name=address:length, name=address:length". An address is
# exe-relative hex, optionally "> offset" to follow a pointer first, and
# "unit" stands for the soldier object the camera is following.
param(
    [string]$ProcessName = 'BattlefrontII',
    [string]$Regions = 'control=0x1AC0918:0x20, actions=0x1AC0964:0x138, pad=0x59E768:0x60, soldier=unit+0x2A0:0xA0',
    [int]$Seconds = 120,
    [int]$IntervalMs = 4,
    [switch]$OnlyInFront       # count only looks taken while the game's window was the one in front
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfWatch {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    static uint U32(IntPtr h, long a) { var b = new byte[4]; IntPtr n; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)4, out n) ? BitConverter.ToUInt32(b, 0) : 0; }

    public class Region { public string Name; public long Address; public bool Unit; public int Length; public byte[] First; public SortedSet<byte>[] Seen; }

    public static List<string> Run(int pid, long imageBase, List<Region> regions, double seconds, int intervalMs, bool onlyInFront, long unitPointer, long unitType) {
        IntPtr h = OpenProcess(0x0410, false, pid);   // read and query only
        IntPtr n; int looks = 0; var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            uint fg; GetWindowThreadProcessId(GetForegroundWindow(), out fg);
            if (!onlyInFront || fg == pid) {
                long unit = 0; long pos = U32(h, imageBase + unitPointer); if (pos > 0x10000 && U32(h, pos - 0x120) == imageBase + unitType) unit = pos - 0x120;
                foreach (var r in regions) {
                    long addr = r.Unit ? (unit == 0 ? 0 : unit + r.Address) : imageBase + r.Address; if (addr == 0) continue;
                    var buf = new byte[r.Length]; if (!ReadProcessMemory(h, (IntPtr)addr, buf, (IntPtr)r.Length, out n)) continue;
                    if (r.Seen == null) { r.First = buf; r.Seen = new SortedSet<byte>[r.Length]; for (int i = 0; i < r.Length; i++) r.Seen[i] = new SortedSet<byte>(); }
                    for (int i = 0; i < r.Length; i++) if (r.Seen[i].Count < 12) r.Seen[i].Add(buf[i]);
                }
                looks++;
            }
            System.Threading.Thread.Sleep(intervalMs);
        }
        var res = new List<string>(); res.Add(looks + " looks");
        foreach (var r in regions) {
            if (r.Seen == null) { res.Add(r.Name + ": never readable"); continue; }
            int changed = 0; for (int i = 0; i < r.Length; i++) if (r.Seen[i].Count > 1) changed++;
            res.Add(string.Format("{0}: {1} of {2} bytes changed", r.Name, changed, r.Length));
            for (int i = 0; i < r.Length; i += 4) {
                bool any = false; for (int k = 0; k < 4 && i + k < r.Length; k++) if (r.Seen[i + k].Count > 1) any = true;
                if (!any) continue;
                var parts = new List<string>();
                for (int k = 0; k < 4 && i + k < r.Length; k++) { var v = new List<string>(); foreach (byte b in r.Seen[i + k]) v.Add(b.ToString("X2")); parts.Add("[" + string.Join(" ", v) + (r.Seen[i + k].Count >= 12 ? " .." : "") + "]"); }
                res.Add(string.Format("    +0x{0:X3}: {1}", i, string.Join(" ", parts)));
            }
        }
        return res;
    }
}
'@

$list = New-Object 'Collections.Generic.List[BfWatch+Region]'
foreach ($part in ($Regions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    if ($part -notmatch '^(\w+)=(unit\+)?(0x[0-9A-Fa-f]+):(0x[0-9A-Fa-f]+|\d+)$') { throw "can't read region '$part'" }
    $r = New-Object BfWatch+Region; $r.Name = $Matches[1]; $r.Unit = [bool]$Matches[2]; $r.Address = [Convert]::ToInt64($Matches[3], 16); $r.Length = [int]$Matches[4]; $list.Add($r)
}
$proc = Get-Process $ProcessName | Select-Object -First 1
[BfWatch]::Run($proc.Id, [int64]$proc.MainModule.BaseAddress, $list, $Seconds, $IntervalMs, [bool]$OnlyInFront, 0x1A296B0, 0x39D114)
