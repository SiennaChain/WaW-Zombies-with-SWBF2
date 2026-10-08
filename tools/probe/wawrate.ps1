# Read-only. Of the many places World at War keeps the player's position and
# view angles (the candidate list wawscan.ps1 saves), which update every
# rendered frame and which only at the game's slower internal tick?
#
# The player must be walking and turning while this runs. For each candidate
# it reports how many times a second the value changed and how far it sits
# from the reference copy. A good source for a smooth follower changes about
# as often as the game draws frames and stays close to the reference.
#
# One beep = start moving, three = done.
param(
    [string]$ProcessName = 'CoDWaW',
    [string]$ResultFile,
    [long]$RefOrigin = 0x14ED088,
    [long]$RefAngles = 0x14ED18C,
    [int]$Seconds = 12,
    [int]$LeadInSec = 6
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class WawRate {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    static bool Read3(IntPtr h, long addr, float[] f, byte[] b) {
        IntPtr n; if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)12, out n)) return false;
        f[0] = BitConverter.ToSingle(b, 0); f[1] = BitConverter.ToSingle(b, 4); f[2] = BitConverter.ToSingle(b, 8); return true;
    }

    // kind 0 = position (distance in the ground plane), 1 = angles (yaw difference in degrees).
    // changes[i] = how often candidate i changed; meanOff[i], maxOff[i] = distance from the reference.
    public static double Measure(IntPtr h, long reference, long[] addrs, int kind, int seconds, int[] changes, double[] meanOff, double[] maxOff, out double refTravel) {
        int n = addrs.Length; var last = new float[n][]; var sum = new double[n]; var cnt = new long[n];
        var buf = new byte[12]; var cur = new float[3]; var r = new float[3]; var prevRef = new float[3]; bool haveRef = false; refTravel = 0;
        for (int i = 0; i < n; i++) { changes[i] = 0; maxOff[i] = 0; }
        var sw = Stopwatch.StartNew(); long passes = 0;
        while (sw.Elapsed.TotalSeconds < seconds) {
            if (!Read3(h, reference, r, buf)) continue;
            if (haveRef) refTravel += kind == 0 ? Math.Sqrt((r[0] - prevRef[0]) * (r[0] - prevRef[0]) + (r[1] - prevRef[1]) * (r[1] - prevRef[1])) : Math.Abs(Wrap(r[1] - prevRef[1]));
            prevRef[0] = r[0]; prevRef[1] = r[1]; prevRef[2] = r[2]; haveRef = true;
            for (int i = 0; i < n; i++) {
                if (!Read3(h, addrs[i], cur, buf)) continue;
                if (last[i] == null) last[i] = new float[] { cur[0], cur[1], cur[2] };
                else if (cur[0] != last[i][0] || cur[1] != last[i][1] || cur[2] != last[i][2]) { changes[i]++; last[i][0] = cur[0]; last[i][1] = cur[1]; last[i][2] = cur[2]; }
                double off = kind == 0 ? Math.Sqrt((cur[0] - r[0]) * (cur[0] - r[0]) + (cur[1] - r[1]) * (cur[1] - r[1])) : Math.Abs(Wrap(cur[1] - r[1]));
                sum[i] += off; cnt[i]++; if (off > maxOff[i]) maxOff[i] = off;
            }
            passes++;
        }
        for (int i = 0; i < n; i++) meanOff[i] = cnt[i] > 0 ? sum[i] / cnt[i] : double.NaN;
        return passes / sw.Elapsed.TotalSeconds;
    }
    static double Wrap(double d) { while (d > 180) d -= 360; while (d < -180) d += 360; return d; }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [WawRate]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$r = Get-Content $ResultFile -Raw | ConvertFrom-Json
function Resolve-Addr([string]$s) { if ($s -match '\.exe\+0x([0-9A-Fa-f]+)') { $base + [Convert]::ToInt64($Matches[1], 16) } elseif ($s -match '^0x([0-9A-Fa-f]+)') { [Convert]::ToInt64($Matches[1], 16) } }

if ($LeadInSec -gt 0) { Start-Sleep -Seconds $LeadInSec }
[Console]::Beep(1200, 250)
$half = [int]($Seconds / 2)
foreach ($pass in @(@{ Name = 'position'; Kind = 0; List = $r.origin; Ref = $RefOrigin; Unit = 'units' }, @{ Name = 'view angles'; Kind = 1; List = $r.angles; Ref = $RefAngles; Unit = 'degrees' })) {
    $names = @($pass.List | Where-Object { $_ -like '*.exe+*' })   # fixed addresses only
    $addrs = [long[]]($names | ForEach-Object { Resolve-Addr $_ })
    $changes = New-Object int[] $addrs.Length; $mean = New-Object double[] $addrs.Length; $max = New-Object double[] $addrs.Length; $travel = 0.0
    $hz = [WawRate]::Measure($h, $base + $pass.Ref, $addrs, $pass.Kind, $half, $changes, $mean, $max, [ref]$travel)
    "=== {0}: {1} fixed candidates, sampled {2:N0} times a second for {3} s; the reference moved {4:N0} {5} ===" -f $pass.Name, $addrs.Length, $hz, $half, $travel, $pass.Unit
    $rows = for ($i = 0; $i -lt $addrs.Length; $i++) { [pscustomobject]@{ Name = $names[$i]; PerSec = $changes[$i] / $half; Mean = $mean[$i]; Max = $max[$i] } }
    $rows | Sort-Object PerSec -Descending | Select-Object -First 14 | ForEach-Object { "  {0,-24} changed {1,6:N1} times/s   from the reference: {2,7:N2} mean, {3,7:N2} worst ({4})" -f $_.Name, $_.PerSec, $_.Mean, $_.Max, $pass.Unit }
}
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)
