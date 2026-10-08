# Finds which copy of the player's position Battlefront II actually obeys.
# Takes the results of bfscan.ps1, keeps the ones that followed a given path,
# then raises each one's height by 3 m in turn and watches both that value and
# the other copies. A copy the game recomputes snaps back at once. The one the
# game moves the unit from stays raised, the others rise with it, and it falls.
param(
    [string]$ProcessName = 'BattlefrontII',
    [string]$ResultFile,
    [string]$PathXList,   # comma-separated, one value per stop
    [string]$PathZList,
    [double]$Within = 3,
    [single]$Lift = 3
)
$PathX = @($PathXList -split ',' | ForEach-Object { [double]$_ })
$PathZ = @($PathZList -split ',' | ForEach-Object { [double]$_ })

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Nudge {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);

    public static IntPtr Open(int pid) { return OpenProcess(0x0438, false, pid); }

    public static float Read(IntPtr h, long addr) {
        var b = new byte[4];
        IntPtr n;
        return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? BitConverter.ToSingle(b, 0) : float.NaN;
    }

    // Row 0: target before, then target at each time. Rows 1..: the same for each watched address.
    public static float[][] Lift(IntPtr h, long target, float delta, long[] watch, int[] atMs) {
        var rows = new float[watch.Length + 1][];
        for (int r = 0; r < rows.Length; r++) rows[r] = new float[atMs.Length + 1];
        rows[0][0] = Read(h, target);
        for (int w = 0; w < watch.Length; w++) rows[w + 1][0] = Read(h, watch[w]);
        IntPtr n;
        if (float.IsNaN(rows[0][0]) || !WriteProcessMemory(h, (IntPtr)target, BitConverter.GetBytes(rows[0][0] + delta), (IntPtr)4, out n)) return null;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < atMs.Length; i++) {
            while (sw.ElapsedMilliseconds < atMs[i]) System.Threading.Thread.Sleep(1);
            rows[0][i + 1] = Read(h, target);
            for (int w = 0; w < watch.Length; w++) rows[w + 1][i + 1] = Read(h, watch[w]);
        }
        return rows;
    }
}
'@

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$r = Get-Content $ResultFile -Raw | ConvertFrom-Json
if ($r.pid -ne $proc.Id) { throw "the game has been restarted since the scan (pid $($r.pid) -> $($proc.Id)); heap addresses are stale" }
$h = [Nudge]::Open($proc.Id)

$cands = foreach ($t in $r.triples) {
    $x = @($t.x -split ' > ' | ForEach-Object { [double]$_ }); $z = @($t.z -split ' > ' | ForEach-Object { [double]$_ })
    $ok = $true
    for ($i = 0; $i -lt $PathX.Count; $i++) { if ([Math]::Abs($x[$i] - $PathX[$i]) -gt $Within -or [Math]::Abs($z[$i] - $PathZ[$i]) -gt $Within) { $ok = $false } }
    if ($ok) { [pscustomobject]@{ Name = $t.name; Addr = [int64]$t.address } }
}
$cands = @($cands | Sort-Object Addr)
"candidates on the path: $($cands.Count)"
"--- where each one is right now ---"
foreach ($c in $cands) { "  {0,-28} ({1,9:N2}, {2,8:N2}, {3,9:N2})" -f $c.Name, [Nudge]::Read($h, $c.Addr), [Nudge]::Read($h, $c.Addr + 4), [Nudge]::Read($h, $c.Addr + 8) }

"--- lift each by $Lift m: its own height before, then at +20 ms, +60, +150, +300, +600; and how many of the others rose with it ---"
$times = [int[]]@(20, 60, 150, 300, 600)
foreach ($c in $cands) {
    $others = @($cands | Where-Object { $_.Addr -ne $c.Addr })
    $watch = [long[]]($others | ForEach-Object { $_.Addr + 4 })
    $rows = [Nudge]::Lift($h, $c.Addr + 4, $Lift, $watch, $times)
    if (-not $rows) { "  {0,-28} could not read or write" -f $c.Name; continue }
    $followed = 0
    for ($w = 1; $w -lt $rows.Count; $w++) {
        $peak = ($rows[$w][1..5] | Measure-Object -Maximum).Maximum
        if ($peak - $rows[$w][0] -ge ($Lift * 0.5)) { $followed++ }
    }
    "  {0,-28} {1,8:N2} -> {2}   others that rose: {3} of {4}" -f $c.Name, $rows[0][0], (($rows[0][1..5] | ForEach-Object { '{0,8:N2}' -f $_ }) -join ' '), $followed, $others.Count
    Start-Sleep -Milliseconds 1200   # let the unit land before the next one
}
