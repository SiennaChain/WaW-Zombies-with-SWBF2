# Read-only. Second stage after bftoggle.ps1.
#
# If the player stood still while switching the setting, bftoggle.ps1 is left
# with thousands of bytes: everything that depends on where the camera is
# repeats exactly, not just the setting. This watches those candidates while
# the game is played normally in ONE state and drops every byte that strays
# from the value it had in that state. What depends on the camera goes; what
# holds the setting stays.
#
# -In takes bftoggle.ps1's -OutFile (.json) or this script's own -Out (.csv),
# so it can be run again in the other state with -Expect B.
param(
    [Parameter(Mandatory)][string]$In,
    [Parameter(Mandatory)][string]$Out,
    [string]$ProcessName = 'BattlefrontII',
    [ValidateSet('A', 'B')][string]$Expect = 'A',
    [int]$Seconds = 40,
    [int]$IntervalMs = 200
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

public static class BfSettle {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    public static List<long> Addr = new List<long>(); public static List<string> Name = new List<string>(); public static List<byte> A = new List<byte>(); public static List<byte> B = new List<byte>();

    public static void Load(string path) {
        string text = File.ReadAllText(path);
        if (path.EndsWith(".csv", StringComparison.OrdinalIgnoreCase)) {
            foreach (string line in text.Split('\n')) { var p = line.Trim().Split(','); if (p.Length < 4) continue; long a; if (!long.TryParse(p[0], out a)) continue; Addr.Add(a); Name.Add(p[1]); A.Add(byte.Parse(p[2])); B.Add(byte.Parse(p[3])); }
            return;
        }
        var ra = new Regex("\"address\":\\s*(\\d+)"); var rn = new Regex("\"name\":\\s*\"([^\"]*)\""); var rA = new Regex("\"a\":\\s*(\\d+)"); var rB = new Regex("\"b\":\\s*(\\d+)");
        foreach (Match m in Regex.Matches(text, "\\{[^{}]*\"address\"[^{}]*\\}")) {
            Addr.Add(long.Parse(ra.Match(m.Value).Groups[1].Value)); Name.Add(rn.Match(m.Value).Groups[1].Value);
            A.Add(byte.Parse(rA.Match(m.Value).Groups[1].Value)); B.Add(byte.Parse(rB.Match(m.Value).Groups[1].Value));
        }
    }

    // Returns how many candidates were left after each pass.
    public static List<int> Watch(IntPtr h, bool expectA, double seconds, int intervalMs, bool[] alive) {
        var left = new List<int>(); var one = new byte[1]; IntPtr n; var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            int count = 0;
            for (int i = 0; i < Addr.Count; i++) {
                if (!alive[i]) continue;
                if (!ReadProcessMemory(h, (IntPtr)Addr[i], one, (IntPtr)1, out n) || one[0] != (expectA ? A[i] : B[i])) { alive[i] = false; continue; }
                count++;
            }
            left.Add(count); System.Threading.Thread.Sleep(intervalMs);
        }
        return left;
    }
}
'@

[BfSettle]::Load($In)
$n = [BfSettle]::Addr.Count
$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [BfSettle]::Open($proc.Id)
$alive = New-Object bool[] $n; for ($i = 0; $i -lt $n; $i++) { $alive[$i] = $true }
$left = [BfSettle]::Watch($h, ($Expect -eq 'A'), $Seconds, $IntervalMs, $alive)
"{0:N0} candidates; holding their {1} value after the first look: {2:N0}; after {3} looks over {4} s: {5:N0}" -f $n, $Expect, $left[0], $left.Count, $Seconds, $left[$left.Count - 1]
$lines = New-Object Collections.Generic.List[string]
$inExe = 0
for ($i = 0; $i -lt $n; $i++) { if ($alive[$i]) { $lines.Add(('{0},{1},{2},{3}' -f [BfSettle]::Addr[$i], [BfSettle]::Name[$i], [BfSettle]::A[$i], [BfSettle]::B[$i])); if ([BfSettle]::Name[$i] -like '*.exe+*') { $inExe++ } } }
[IO.File]::WriteAllLines($Out, $lines)
"{0:N0} left, {1:N0} of them at fixed addresses in the exe; saved to {2}" -f $lines.Count, $inExe, $Out
$lines | Where-Object { $_ -like '*.exe+*' } | Select-Object -First 120 | ForEach-Object { $p = $_.Split(','); "  {0,-28} A = {1,3}   B = {2,3}" -f $p[1], $p[2], $p[3] }
