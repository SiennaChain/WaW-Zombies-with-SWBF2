# Read-only. Finds where a game keeps an on/off setting by watching memory
# while the player flips it back and forth.
#
# The player starts in state A. At each long beep they switch to the other
# state and get back into play before the next beep. A snapshot is taken just
# before every beep, giving A, B, A, B, A. A byte that holds the setting is
# the same in every A, the same in every B, and different between the two.
# Almost nothing else in a running game behaves like that five times running.
#
# Written for SWBF2's first/third person view, which can only be changed from
# the pause menu, but nothing in it is specific to that.
#
# Two short beeps = a snapshot is being taken, don't touch anything.
# One long beep   = switch now.
# Three quick     = finished.
param(
    [string]$ProcessName = 'BattlefrontII',
    [int]$States = 5,            # odd: A B A B A
    [int]$SecondsPerSwitch = 25,
    [int]$LeadInSec = 10,
    [string]$OutFile,
    [switch]$Quiet               # no beeps: for checking that the snapshots work
)
$ErrorActionPreference = 'Stop'
function Beep($hz, $ms) { if (-not $Quiet) { [Console]::Beep($hz, $ms) } }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfToggle {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only

    public class Snap { public List<long> Base = new List<long>(); public List<byte[]> Data = new List<byte[]>(); public long Bytes;
        public bool TryByte(long addr, out byte v) { v = 0; int i = Base.BinarySearch(addr); if (i < 0) i = ~i - 1; if (i < 0) return false; long off = addr - Base[i]; if (off >= Data[i].Length) return false; v = Data[i][off]; return true; } }

    public static Snap Take(IntPtr h) {
        var s = new Snap(); long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m; if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize; if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var buf = new byte[size]; IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got) && (long)got == size) { s.Base.Add(b); s.Data.Add(buf); s.Bytes += size; }
            }
            addr = b + size;
        }
        return s;
    }

    public class Cands { public List<long> Addr = new List<long>(); public List<byte> A = new List<byte>(); public List<byte> B = new List<byte>(); }

    // Bytes that differ between the first A and the first B.
    public static Cands Start(Snap a, Snap b) {
        var c = new Cands();
        for (int i = 0; i < a.Base.Count; i++) {
            int j = b.Base.BinarySearch(a.Base[i]); if (j < 0 || b.Data[j].Length != a.Data[i].Length) continue;
            byte[] da = a.Data[i], db = b.Data[j];
            for (int o = 0; o < da.Length; o++) if (da[o] != db[o]) { c.Addr.Add(a.Base[i] + o); c.A.Add(da[o]); c.B.Add(db[o]); }
        }
        return c;
    }

    // Keep the ones that are back to their A value (wantA) or their B value in this snapshot.
    public static Cands Keep(Snap s, Cands c, bool wantA) {
        var r = new Cands();
        for (int i = 0; i < c.Addr.Count; i++) { byte v; if (s.TryByte(c.Addr[i], out v) && v == (wantA ? c.A[i] : c.B[i])) { r.Addr.Add(c.Addr[i]); r.A.Add(c.A[i]); r.B.Add(c.B[i]); } }
        return r;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [BfToggle]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress; $end = $base + $proc.MainModule.ModuleMemorySize

Start-Sleep -Seconds $LeadInSec
$cands = $null; $first = $null
for ($i = 0; $i -lt $States; $i++) {
    Beep 1500 100; Beep 1500 100
    $snap = [BfToggle]::Take($h)
    if ($i -eq 0) { $first = $snap; "state A captured ({0:N0} MB)" -f ($snap.Bytes / 1MB) }
    elseif ($i -eq 1) { $cands = [BfToggle]::Start($first, $snap); $first = $null; "state B: {0:N0} bytes differ from A" -f $cands.Addr.Count }
    else { $cands = [BfToggle]::Keep($snap, $cands, ($i % 2 -eq 0)); "state {0}: {1:N0} bytes still follow the pattern" -f $(if ($i % 2 -eq 0) { 'A' } else { 'B' }), $cands.Addr.Count }
    $snap = $null; [GC]::Collect()
    if ($i + 1 -lt $States) { Beep 500 700; Start-Sleep -Seconds $SecondsPerSwitch }
}
Beep 900 120; Beep 900 120; Beep 900 120

$rows = for ($i = 0; $i -lt $cands.Addr.Count; $i++) {
    $a = $cands.Addr[$i]; $inImage = ($a -ge $base -and $a -lt $end)
    [pscustomobject]@{ Address = $a; InImage = $inImage; A = $cands.A[$i]; B = $cands.B[$i]
        Name = $(if ($inImage) { '{0}.exe+0x{1:X}' -f $ProcessName, ($a - $base) } else { '0x{0:X8}' -f $a }) }
}
"--- {0} bytes held one value in every A and another in every B ({1} at fixed addresses in the exe, {2} in heap) ---" -f @($rows).Count, @($rows | Where-Object InImage).Count, @($rows | Where-Object { -not $_.InImage }).Count
$rows | Sort-Object @{ e = { -not $_.InImage } }, Address | Select-Object -First 80 | ForEach-Object { "  {0,-28} A = {1,3}   B = {2,3}" -f $_.Name, $_.A, $_.B }
if ($OutFile) { @{ pid = $proc.Id; candidates = @($rows | ForEach-Object { @{ address = $_.Address; name = $_.Name; a = $_.A; b = $_.B } }) } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $OutFile }
