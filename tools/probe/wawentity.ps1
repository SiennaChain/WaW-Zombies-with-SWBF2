# Read-only. Finds where in one of World at War's entities its position is.
#
# The game keeps its entities in one array (g_entities, 0x378 bytes each;
# docs/PHASE3.md). The first is the player, whose position is known from
# elsewhere ([waw] player_origin), so the three floats in the first entity
# that equal it are where an entity keeps its position. With -Entity it then
# prints that entity's position a few times, to watch something move (a
# thrown grenade's number comes from the scripts).
param(
    [long]$Entities = 0x136C6F0, [int]$Size = 0x378, [long]$PlayerOrigin = 0x14ED088,
    [int]$Entity = -1, [int[]]$At = @(), [int]$Times = 8, [int]$GapMs = 150
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WawEntity { [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr h; public static void Open(int pid) { h = OpenProcess(0x0410, false, pid); }
  public static byte[] Bytes(long a, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)n, out r) ? b : null; } }
'@
$p = Get-Process CoDWaW | Select-Object -First 1; [WawEntity]::Open($p.Id); $base = [int64]$p.MainModule.BaseAddress
$o = [WawEntity]::Bytes($base + $PlayerOrigin, 12); $e = [WawEntity]::Bytes($base + $Entities, $Size)
$x = [BitConverter]::ToSingle($o, 0); $y = [BitConverter]::ToSingle($o, 4); $z = [BitConverter]::ToSingle($o, 8)
'the player is at ({0:F1} {1:F1} {2:F1})' -f $x, $y, $z
$found = @()
for ($i = 0; $i + 12 -le $Size; $i += 4) {
    if ([Math]::Abs([BitConverter]::ToSingle($e, $i) - $x) -lt 0.6 -and [Math]::Abs([BitConverter]::ToSingle($e, $i + 4) - $y) -lt 0.6 -and [Math]::Abs([BitConverter]::ToSingle($e, $i + 8) - $z) -lt 0.6) { $found += $i; 'the first entity has it at +0x{0:X}: ({1:F1} {2:F1} {3:F1})' -f $i, [BitConverter]::ToSingle($e, $i), [BitConverter]::ToSingle($e, $i + 4), [BitConverter]::ToSingle($e, $i + 8) }
}
if ($Entity -ge 0) {
    if (-not $At) { $At = $found }
    for ($t = 0; $t -lt $Times; $t++) {
        $b = [WawEntity]::Bytes($base + $Entities + $Entity * $Size, $Size)
        'entity {0}: {1}' -f $Entity, (($At | ForEach-Object { '+0x{0:X} ({1:F1} {2:F1} {3:F1})' -f $_, [BitConverter]::ToSingle($b, $_), [BitConverter]::ToSingle($b, $_ + 4), [BitConverter]::ToSingle($b, $_ + 8) }) -join '   ')
        Start-Sleep -Milliseconds $GapMs
    }
}
