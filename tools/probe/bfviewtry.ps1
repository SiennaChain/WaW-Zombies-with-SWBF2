# Tries candidates for SWBF2's first / third person setting, one at a time.
#
# Each candidate is given its other value through [debug] poke in wawbf.ini
# (the bridge inside the game does the writing; this script only edits the
# ini and reads memory). The camera is then measured: in third person it sits
# about 3 m from the unit, in first person at its eyes. A candidate that moves
# the camera is the setting. One that does not is put back.
#
# Needs a live unit, and the match not paused.
param(
    [Parameter(Mandatory)][string]$Candidates,   # "0x1AC8106:0:1, 0x3DEB1C:0:1" = exe offset : one value : the other
    [string]$BfDir = 'E:\SteamLibrary\steamapps\common\Star Wars Battlefront II Classic\GameData',
    [long]$PositionPointer = 0x1A296B0,
    [long]$SoldierType = 0x39D114,
    [long]$CameraPosition = 0x3DE3A8,
    [string]$Type = 'u8',
    [int]$SettleMs = 2500,
    [int]$WaitForSoldierSec = 0   # wait this long for a live unit; then one beep at the start, three at the end
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BfViewTry {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // read and query only
    public static byte[] Bytes(IntPtr h, long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; }
    public static long U32(IntPtr h, long a) { var b = Bytes(h, a, 4); return b == null ? -1 : (long)BitConverter.ToUInt32(b, 0); }
    public static float[] F3(IntPtr h, long a) { var b = Bytes(h, a, 12); return b == null ? null : new float[] { BitConverter.ToSingle(b, 0), BitConverter.ToSingle(b, 4), BitConverter.ToSingle(b, 8) }; }
}
'@

$bf = Get-Process BattlefrontII | Select-Object -First 1
$h = [BfViewTry]::Open($bf.Id); $base = [int64]$bf.MainModule.BaseAddress
$ini = Join-Path $BfDir 'wawbf.ini'

# Distance from the camera to the unit's eyes (1.8 m above its origin), or $null without a live unit.
function Get-CameraDistance {
    $pos = [BfViewTry]::U32($h, $base + $PositionPointer)
    if ([BfViewTry]::U32($h, $pos - 0x120) -ne $base + $SoldierType) { return $null }
    $p = [BfViewTry]::F3($h, $pos); $c = [BfViewTry]::F3($h, $base + $CameraPosition)
    [Math]::Sqrt([Math]::Pow($c[0] - $p[0], 2) + [Math]::Pow($c[1] - $p[1] - 1.8, 2) + [Math]::Pow($c[2] - $p[2], 2))
}
function Set-Poke([string]$text) {
    $t = (Get-Content $ini -Raw) -replace '(?m)^poke\s*=.*$', "poke = $text"
    [IO.File]::WriteAllText($ini, $t, (New-Object Text.ASCIIEncoding))
    Start-Sleep -Milliseconds $SettleMs
}
function Get-Value([long]$offset) { if ($Type -eq 'u8') { [BfViewTry]::Bytes($h, $base + $offset, 1)[0] } else { [BfViewTry]::U32($h, $base + $offset) } }

$waited = [Diagnostics.Stopwatch]::StartNew(); $start = Get-CameraDistance
while ($null -eq $start -and $waited.Elapsed.TotalSeconds -lt $WaitForSoldierSec) { Start-Sleep -Milliseconds 500; $start = Get-CameraDistance }
if ($null -eq $start) { 'no live unit: spawn first'; exit 2 }
if ($WaitForSoldierSec) { Start-Sleep -Seconds 3; [Console]::Beep(1200, 300) }   # let the spawn settle; one beep = starting
"camera is {0:N2} m from the unit's eyes to begin with ({1})" -f $start, $(if ($start -lt 1) { 'first person' } else { 'third person' })
foreach ($c in ($Candidates -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $parts = $c -split ':'; $offset = [Convert]::ToInt64($parts[0], 16); $one = [int]$parts[1]; $other = [int]$parts[2]
    $name = 'BattlefrontII.exe+0x{0:X}' -f $offset
    $before = Get-CameraDistance; if ($null -eq $before) { "${name}: no live unit any more, stopping"; break }
    $now = Get-Value $offset
    if ($now -eq $one) { $try = $other } elseif ($now -eq $other) { $try = $one } else { "${name}: holds $now, neither $one nor $other; skipped"; continue }
    Set-Poke "$name = $Type $try"
    $after = Get-CameraDistance; $holds = Get-Value $offset
    if ($null -eq $after) { "${name}: the unit went away after the write (holds $holds); putting $now back and stopping"; Set-Poke "$name = $Type $now"; break }
    if ([Math]::Abs($after - $before) -gt 1.0) {
        "${name}: $now -> $try MOVED THE CAMERA from {0:N2} m to {1:N2} m (holds $holds)" -f $before, $after
        Set-Poke "$name = $Type $now"
        $back = Get-CameraDistance
        "${name}: $try -> $now put it at {0:N2} m" -f $back
        if ([Math]::Abs($back - $before) -lt 0.5) { "${name} is the view setting: $now and $try are its two values"; break }
        continue
    }
    "${name}: $now -> $try left the camera at {0:N2} m (holds $holds{1}); putting $now back" -f $after, $(if ($holds -ne $try) { ', so the game replaced it' } else { '' })
    Set-Poke "$name = $Type $now"
}
Set-Poke ''
if ($WaitForSoldierSec) { [Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120) }
