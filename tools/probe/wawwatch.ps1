# Watches candidate addresses at high rate across one probe teleport and reports,
# for each, when it first changed and how many times. The copy that changes
# first is the authoritative one; ring-buffer entries change once, late.
param(
    [string]$ProcessName = 'CoDWaW',
    [string]$ResultFile,
    [int]$DurationMs = 11000
)

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class MemWatch {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }

    // out arrays are per address: ms of first change (-1 = never), number of changes.
    public static int Watch(IntPtr h, long[] addrs, int bytes, int durationMs, double[] firstMs, int[] changes) {
        var last = new byte[addrs.Length][];
        var buf = new byte[bytes];
        for (int i = 0; i < addrs.Length; i++) { firstMs[i] = -1; changes[i] = 0; }
        int passes = 0;
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < durationMs) {
            for (int i = 0; i < addrs.Length; i++) {
                IntPtr got;
                if (!ReadProcessMemory(h, (IntPtr)addrs[i], buf, (IntPtr)bytes, out got) || (long)got != bytes) continue;
                if (last[i] == null) { last[i] = (byte[])buf.Clone(); continue; }
                bool same = true;
                for (int k = 0; k < bytes; k++) if (buf[k] != last[i][k]) { same = false; break; }
                if (same) continue;
                changes[i]++;
                if (firstMs[i] < 0) firstMs[i] = sw.Elapsed.TotalMilliseconds;
                Buffer.BlockCopy(buf, 0, last[i], 0, bytes);
            }
            passes++;
        }
        return passes;
    }
}
'@

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$h = [MemWatch]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$r = Get-Content $ResultFile -Raw | ConvertFrom-Json

function Resolve-Addr([string]$s) {
    if ($s -match '\.exe\+0x([0-9A-Fa-f]+)') { $base + [Convert]::ToInt64($Matches[1], 16) }
    elseif ($s -match '^0x([0-9A-Fa-f]+)') { [Convert]::ToInt64($Matches[1], 16) }
}

$items = @()
foreach ($s in $r.origin) { $items += [pscustomobject]@{ Kind = 'origin'; Name = $s; Addr = (Resolve-Addr $s); Bytes = 12 } }
foreach ($s in $r.angles) { $items += [pscustomobject]@{ Kind = 'angles'; Name = $s; Addr = (Resolve-Addr $s); Bytes = 8 } }

# One pass over everything so origin and angle timings share a clock (8 bytes is enough to see either change).
$addrs = [long[]]($items | ForEach-Object { $_.Addr })
$first = New-Object double[] $addrs.Length
$changes = New-Object int[] $addrs.Length
$passes = [MemWatch]::Watch($h, $addrs, 8, $DurationMs, $first, $changes)
"sampled {0} addresses {1} times in {2} ms ({3:N0} Hz)" -f $addrs.Length, $passes, $DurationMs, ($passes * 1000 / $DurationMs)

for ($i = 0; $i -lt $items.Count; $i++) {
    $items[$i] | Add-Member -NotePropertyName FirstMs -NotePropertyValue $first[$i]
    $items[$i] | Add-Member -NotePropertyName Changes -NotePropertyValue $changes[$i]
}
$t0 = ($items | Where-Object { $_.FirstMs -ge 0 } | Measure-Object FirstMs -Minimum).Minimum
if ($null -eq $t0) { 'NOTHING CHANGED during the watch (game paused or not in front?)'; exit 2 }
foreach ($kind in 'origin', 'angles') {
    "--- ${kind}: ms after the first change anywhere / number of changes ---"
    $items | Where-Object Kind -eq $kind | Sort-Object { if ($_.FirstMs -lt 0) { 1e9 } else { $_.FirstMs } } | ForEach-Object {
        if ($_.FirstMs -lt 0) { '  {0,-34} never changed' -f $_.Name }
        else { '  {0,-34} +{1,7:N1} ms   {2,3} change(s)' -f $_.Name, ($_.FirstMs - $t0), $_.Changes }
    }
}
