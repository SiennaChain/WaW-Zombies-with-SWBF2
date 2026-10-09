# Read-only. Where World at War's camera is relative to its player, and so
# where on the screen the player's shots go.
#
# Shots leave from the player's eyes (60 units above the feet standing) along
# the direction the camera looks. Through the player's eyes that is the
# middle of the screen. From behind, the camera is somewhere else, and a shot
# crosses the screen's middle only if the eyes are on the camera's line of
# sight; this prints how far off it they are, and where on a 720-line screen
# a shot is at a few distances.
param([long]$Origin = 0x14ED088, [long]$ViewOrigin = 0x3120354, [long]$ViewAxis = 0x3120364, [long]$Fov = 0x3120348, [double]$Eye = 60, [int]$Lines = 720)
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WawAim { [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  static IntPtr h; public static void Open(int pid) { h = OpenProcess(0x0410, false, pid); }
  public static float[] Floats(long a, int n) { var b = new byte[4 * n]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)b.Length, out r); var f = new float[n]; Buffer.BlockCopy(b, 0, f, 0, b.Length); return f; } }
'@
$p = Get-Process CoDWaW | Select-Object -First 1; [WawAim]::Open($p.Id); $base = [int64]$p.MainModule.BaseAddress
$o = [WawAim]::Floats($base + $Origin, 3); $c = [WawAim]::Floats($base + $ViewOrigin, 3); $a = [WawAim]::Floats($base + $ViewAxis, 9); $f = [WawAim]::Floats($base + $Fov, 2)
$e = @(($o[0] - $c[0]), ($o[1] - $c[1]), ($o[2] + $Eye - $c[2]))   # the eyes, from the camera
$ahead = $e[0] * $a[0] + $e[1] * $a[1] + $e[2] * $a[2]
$left = $e[0] * $a[3] + $e[1] * $a[4] + $e[2] * $a[5]
$up = $e[0] * $a[6] + $e[1] * $a[7] + $e[2] * $a[8]
'camera to feet: ({0:F1} {1:F1} {2:F1}); the eyes are {3:F1} units ahead of the camera, {4:F1} to its left and {5:F1} above its line of sight' -f ($o[0] - $c[0]), ($o[1] - $c[1]), ($o[2] - $c[2]), $ahead, $left, $up
'the lens: tan(half the view top to bottom) = {0:F4}' -f $f[1]
foreach ($far in 200, 400, 800, 1600, 4000) {
    # a shot `far` units out from the eyes, along the camera's forward
    $y = $up / (($ahead + $far) * $f[1]) * ($Lines / 2)
    $x = -$left / (($ahead + $far) * $f[0]) * ($Lines / 2 * $f[0] / $f[1])
    '  a shot {0,5} units out is {1,6:F1} lines above the middle and {2,6:F1} to the right' -f $far, $y, $x
}
