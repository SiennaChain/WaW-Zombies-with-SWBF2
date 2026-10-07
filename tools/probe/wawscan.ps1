# Finds where CoDWaW.exe keeps the player's origin and view angles.
# Works with the wawbf_probe script: reads the marker string it publishes, then
# looks for the same numbers stored as floats and keeps only addresses that
# track every step.
param(
    [string]$ProcessName = 'CoDWaW',
    [int]$TimeoutSec = 180,
    [int]$StepsWanted = 5,
    [string]$OutFile
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class MemScan {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);

    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public class Region { public long Base, Size; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); } // VM_READ | QUERY_INFORMATION

    public static List<Region> Regions(IntPtr h, bool writableOnly) {
        var list = new List<Region>();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long size = (long)m.RegionSize;
            if (size <= 0) break;
            bool readable = m.State == 0x1000 && (m.Protect & 0x101) == 0;   // committed, not NOACCESS/GUARD
            bool writable = (m.Protect & 0xCC) != 0;                         // RW, WC, XRW, XWC
            if (readable && (writable || !writableOnly)) list.Add(new Region { Base = (long)m.BaseAddress, Size = size });
            addr = (long)m.BaseAddress + size;
        }
        return list;
    }

    static int ReadInto(IntPtr h, long addr, byte[] buf, int size) {
        IntPtr got;
        return ReadProcessMemory(h, (IntPtr)addr, buf, (IntPtr)size, out got) ? (int)(long)got : 0;
    }

    // Searches readable regions that overlap [lo, hi).
    public static List<long> FindBytes(IntPtr h, byte[] pat, long lo, long hi) {
        var hits = new List<long>();
        const int chunk = 4 << 20;
        var buf = new byte[chunk + pat.Length];
        foreach (var r in Regions(h, false)) {
            if (r.Base >= hi || r.Base + r.Size <= lo) continue;
            for (long off = 0; off < r.Size; off += chunk) {
                int want = (int)Math.Min(chunk + pat.Length, r.Size - off);
                int got = ReadInto(h, r.Base + off, buf, want);
                for (int i = 0; i + pat.Length <= got; i++) {
                    if (buf[i] != pat[0]) continue;
                    int k = 1;
                    while (k < pat.Length && buf[i + k] == pat[k]) k++;
                    if (k == pat.Length && i < chunk) hits.Add(r.Base + off + i);
                }
            }
        }
        return hits;
    }

    // Addresses (4-byte aligned) where v.Length consecutive floats all match within tol.
    public static List<long> FindFloats(IntPtr h, float[] v, float tol) {
        var hits = new List<long>();
        const int chunk = 4 << 20;
        int tail = v.Length * 4;
        var buf = new byte[chunk + tail];
        foreach (var r in Regions(h, true)) {
            for (long off = 0; off < r.Size; off += chunk) {
                int want = (int)Math.Min(chunk + tail, r.Size - off);
                int got = ReadInto(h, r.Base + off, buf, want);
                for (int i = 0; i + tail <= got && i < chunk; i += 4) {
                    if (Math.Abs(BitConverter.ToSingle(buf, i) - v[0]) > tol) continue;
                    int k = 1;
                    while (k < v.Length && Math.Abs(BitConverter.ToSingle(buf, i + 4 * k) - v[k]) <= tol) k++;
                    if (k == v.Length) hits.Add(r.Base + off + i);
                }
            }
        }
        return hits;
    }

    public static float[] ReadFloats(IntPtr h, long addr, int n) {
        var buf = new byte[n * 4];
        if (ReadInto(h, addr, buf, buf.Length) != buf.Length) return null;
        var f = new float[n];
        for (int i = 0; i < n; i++) f[i] = BitConverter.ToSingle(buf, i * 4);
        return f;
    }

    public static string ReadAscii(IntPtr h, long addr, int max) {
        var buf = new byte[max];
        int got = ReadInto(h, addr, buf, max);
        int n = 0;
        while (n < got && buf[n] != 0) n++;
        return Encoding.ASCII.GetString(buf, 0, n);
    }
}
'@

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$h = [MemScan]::Open($proc.Id)
if ($h -eq [IntPtr]::Zero) { throw "could not open process $($proc.Id)" }
$imageBase = [int64]$proc.MainModule.BaseAddress
$imageEnd = $imageBase + $proc.MainModule.ModuleMemorySize
$marker = [Text.Encoding]::ASCII.GetBytes('WAWBFPROBE|')

# The dvar's text moves each time it is set, but stays in the same part of the
# heap, so after the first full sweep only that neighbourhood is searched.
$script:near = $null
function Find-Probe([long]$lo, [long]$hi) {
    $best = $null
    foreach ($a in [MemScan]::FindBytes($h, $marker, $lo, $hi)) {
        $s = [MemScan]::ReadAscii($h, $a, 96)
        if ($s -match '^WAWBFPROBE\|(\d+)\|(-?\d+)\|(-?\d+)\|(-?\d+)\|(-?\d+)\|(-?\d+)\|') {
            $step = [int]$Matches[1]
            if (-not $best -or $step -gt $best.Step) {
                $best = [pscustomobject]@{ Step = $step; Address = $a
                    Origin = [single[]]@(([int]$Matches[2] / 100), ([int]$Matches[3] / 100), ([int]$Matches[4] / 100))
                    Angles = [single[]]@(([int]$Matches[5] / 100), ([int]$Matches[6] / 100)) }
            }
        }
    }
    $best
}
function Get-Probe {
    $p = $null
    if ($script:near) { $p = Find-Probe ($script:near - 32MB) ($script:near + 32MB) }
    if (-not $p) { $p = Find-Probe 0 0xFFFF0000L }
    if ($p) { $script:near = $p.Address }
    $p
}

function Test-Floats([long]$addr, [single[]]$want, [single]$tol) {
    $got = [MemScan]::ReadFloats($h, $addr, $want.Length)
    if (-not $got) { return $false }
    for ($i = 0; $i -lt $want.Length; $i++) { if ([Math]::Abs($got[$i] - $want[$i]) -gt $tol) { return $false } }
    $true
}

$tol = [single]0.03
$origin = $null; $angles = $null; $last = 0; $seen = 0
$start = Get-Date
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec -and $seen -lt $StepsWanted) {
    if ($proc.HasExited) { throw 'game exited' }
    $p = Get-Probe
    # A lower step number is a stale copy of an earlier value still lying in memory.
    if (-not $p -or $p.Step -le $last) { Start-Sleep -Milliseconds 300; continue }

    if ($null -eq $origin) {
        $o = @([MemScan]::FindFloats($h, $p.Origin, $tol))
        $a = @([MemScan]::FindFloats($h, $p.Angles, $tol))
    } else {
        $o = @($origin | Where-Object { Test-Floats $_ $p.Origin $tol })
        $a = @($angles | Where-Object { Test-Floats $_ $p.Angles $tol })
    }
    # The script may have moved on while we were reading; only trust a result if it had not.
    $after = Get-Probe
    if (-not $after -or $after.Step -ne $p.Step) { "step $($p.Step): script moved on mid-scan, skipped"; continue }

    $origin = $o; $angles = $a; $last = $p.Step; $seen++
    "step {0}: origin ({1:N2} {2:N2} {3:N2}) -> {4} candidates; angles ({5:N2} {6:N2}) -> {7} candidates  [t+{8:N0}s]" -f `
        $p.Step, $p.Origin[0], $p.Origin[1], $p.Origin[2], $origin.Count, $p.Angles[0], $p.Angles[1], $angles.Count, ((Get-Date) - $start).TotalSeconds
}

function Format-Addr([long]$a) {
    if ($a -ge $imageBase -and $a -lt $imageEnd) { '{0}.exe+0x{1:X}' -f $ProcessName, ($a - $imageBase) } else { '0x{0:X8} (outside the exe image)' -f $a }
}

if ($seen -lt 3) { "NOT ENOUGH DATA: only $seen step(s) seen in $TimeoutSec s (is the game in front and unpaused?)"; exit 2 }
'--- origin candidates that tracked every step ---'
$origin | ForEach-Object { '  ' + (Format-Addr $_) }
'--- view angle candidates that tracked every step ---'
$angles | ForEach-Object { '  ' + (Format-Addr $_) }
if ($OutFile) {
    @{ steps = $seen; imageBase = $imageBase
       origin = @($origin | ForEach-Object { Format-Addr $_ }); angles = @($angles | ForEach-Object { Format-Addr $_ }) } |
        ConvertTo-Json | Set-Content -Encoding utf8 $OutFile
}
