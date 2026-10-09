# Read-only. How tall Battlefront II's character is being drawn, in World at
# War's units, in third person.
#
# Battlefront II's window shows the character on black. The rows it covers in
# the middle of the picture, with how far World at War's camera is from its
# player and the lens both games are using, give its height as World at War
# would measure it. A World at War soldier is 72 units tall standing; its
# zombies stoop to rather less.
param([long]$Origin = 0x14ED088, [long]$ViewOrigin = 0x3120354, [long]$ViewAxis = 0x3120364, [long]$Fov = 0x3120348, [int]$Times = 3, [int]$GapMs = 700)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Runtime.InteropServices;
public static class Stature {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid); [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r); [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public struct RECT { public int L, T, R, B; } public struct POINT { public int X, Y; }
  public static float[] Floats(int pid, long a, int n) { IntPtr h = OpenProcess(0x0410, false, pid); var b = new byte[4 * n]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)b.Length, out r); var f = new float[n]; Buffer.BlockCopy(b, 0, f, 0, b.Length); return f; }
  // The first and last rows, in the middle third of the picture across, that are not black; and the picture's height.
  public static int[] Rows(IntPtr window) {
    SetProcessDPIAware(); RECT r; GetClientRect(window, out r); var p = new POINT(); ClientToScreen(window, ref p); int w = r.R - r.L, h = r.B - r.T;
    using (var bmp = new Bitmap(w, h)) { using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(p.X, p.Y, 0, 0, new Size(w, h));
      // From the feet up, as far as the picture is unbroken: the crosshair's ring floats above the head, with a gap between.
      int top = -1, bottom = -1, gap = 0;
      for (int y = h - 1; y >= 0; y--) { int lit = 0; for (int x = w * 3 / 8; x < w * 5 / 8; x += 2) { var c = bmp.GetPixel(x, y); if (c.R + c.G + c.B > 60) lit++; }
        if (lit >= 6) { if (bottom < 0) bottom = y; top = y; gap = 0; } else if (bottom >= 0 && ++gap >= 6) break; }
      return new[] { top, bottom, h }; } }
}
'@
$waw = Get-Process CoDWaW | Select-Object -First 1; $bf = Get-Process BattlefrontII | Select-Object -First 1; $base = [int64]$waw.MainModule.BaseAddress
for ($i = 0; $i -lt $Times; $i++) {
    $o = [Stature]::Floats($waw.Id, $base + $Origin, 3); $c = [Stature]::Floats($waw.Id, $base + $ViewOrigin, 3); $a = [Stature]::Floats($waw.Id, $base + $ViewAxis, 9); $f = [Stature]::Floats($waw.Id, $base + $Fov, 2)
    $rows = [Stature]::Rows($bf.MainWindowHandle)
    $ahead = ($o[0] - $c[0]) * $a[0] + ($o[1] - $c[1]) * $a[1] + ($o[2] + 36 - $c[2]) * $a[2]   # to the middle of the player
    if ($rows[0] -lt 0 -or $ahead -lt 40) { "no character in the picture, or the view is through the player's eyes (the camera is $([Math]::Round($ahead)) units behind)" }
    else { 'rows {0} to {1} of {2}; the camera is {3:F0} units behind: the character is drawn {4:F0} units tall' -f $rows[0], $rows[1], $rows[2], $ahead, (($rows[1] - $rows[0]) / $rows[2] * 2 * $f[1] * $ahead) }
    Start-Sleep -Milliseconds $GapMs
}
