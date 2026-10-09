# Read-only. Lists Battlefront II's bindings: which keys and buttons work each
# of the game's functions.
#
# The player's bindings are a table on their controller object: for each of
# 43 game functions, three codes of two bytes each. A code up to 0xFF is a
# keyboard key (a DirectInput scan code); a higher one is one of the "raw
# controls" the game copies its devices into, (code >> 8) - 1, 76 to a device
# (docs/PHASE2.md). A second table of the same shape follows it, for vehicles.
#
# The game does not name its functions anywhere that can be read, but the
# player knows what their buttons do: "secondary fire is on the left trigger"
# picks its function out of this list at once (docs/PHASE3.md has the ones
# found so far).
param(
    [long]$Controller = 0x1ABE078,   # player 1's controller object, exe-relative
    [long]$Bindings = 0x20BC,        # in the controller: the table
    [int]$Functions = 43,
    [switch]$Vehicles                # the second table instead
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class BfBindings {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static byte[] Bytes(int pid, long a, int n) { IntPtr h = OpenProcess(0x0410, false, pid); var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }   // read and query only
}
'@

function Describe([int]$code) {
    if ($code -eq 0) { return '' }
    if ($code -le 0xFF) { return 'key 0x{0:X2}' -f $code }
    $raw = ($code -shr 8) - 1
    'raw {0} (device {1}, control {2})' -f $raw, [Math]::Floor($raw / 76), ($raw % 76)
}

$bf = Get-Process BattlefrontII | Select-Object -First 1
$at = [int64]$bf.MainModule.BaseAddress + $Controller + $Bindings
if ($Vehicles) { $at += $Functions * 6 }
$table = [BfBindings]::Bytes($bf.Id, $at, $Functions * 6)
if (-not $table) { 'the table could not be read'; exit 2 }
for ($i = 0; $i -lt $Functions; $i++) {
    $codes = 0..2 | ForEach-Object { Describe ([BitConverter]::ToUInt16($table, 6 * $i + 2 * $_)) } | Where-Object { $_ }
    'function {0,2}: {1}' -f $i, $(if ($codes) { $codes -join ', ' } else { '-' })
}
