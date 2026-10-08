# Read-only: follows pointer chains to the unit's position and prints where
# each one says the unit is, once a second. Use it to see whether a chain keeps
# tracking the player through deaths, respawns and new matches.
param(
    [string]$ProcessName = 'BattlefrontII',
    [string]$Chains = '0x1B84190>0x120,0x1B77078>0x120',   # exe-relative pointer > offset of x in the object
    [int]$WatchSec = 10
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ChainRead {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static long U32(IntPtr h, long addr) { var b = new byte[4]; IntPtr n; return ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? (long)BitConverter.ToUInt32(b, 0) : -1; }
    public static float F(IntPtr h, long addr) { var b = new byte[4]; IntPtr n; return (addr > 0x10000 && ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n)) ? BitConverter.ToSingle(b, 0) : float.NaN; }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
$h = [ChainRead]::Open($proc.Id)
$base = [int64]$proc.MainModule.BaseAddress
$list = foreach ($c in ($Chains -split ',')) { $p = $c -split '>'; [pscustomobject]@{ Name = $c.Trim(); Slot = [Convert]::ToInt64($p[0].Trim(), 16); Off = [Convert]::ToInt32($p[1].Trim(), 16) } }
for ($i = 0; $i -lt $WatchSec; $i++) {
    $parts = foreach ($c in $list) {
        $o = [ChainRead]::U32($h, $base + $c.Slot)
        if ($o -le 0x10000) { '{0}: no object' -f $c.Name }
        else { '{0}: 0x{1:X8} ({2,8:N2}, {3,6:N2}, {4,8:N2})' -f $c.Name, $o, [ChainRead]::F($h, $o + $c.Off), [ChainRead]::F($h, $o + $c.Off + 4), [ChainRead]::F($h, $o + $c.Off + 8) }
    }
    '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), ($parts -join '   |   ')
    Start-Sleep -Milliseconds 1000
}
