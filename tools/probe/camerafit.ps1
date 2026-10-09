# Read-only. Says whether the two games are drawing the player from the same
# place.
#
# In third person SWBF2 is given WaW's camera. This reads both cameras and
# both players from memory and works out where the player's feet land on
# screen in each (across, up; as fractions of half the screen, so 0, 0 is the
# centre and anything beyond 1 is off it). If the two are being drawn from the
# same place the figures agree. It also shows each game's lens (the tangents
# of half its view across and top to bottom) and SWBF2's own zoom, which
# should stay at 1 in third person.
#
# A line where WaW's "up" is a large negative number is WaW drawing from the
# player's eyes: first person, or not yet switched.
param([int]$Looks = 6, [int]$GapMs = 400)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CameraFit {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    static float[] F(IntPtr h, long a, int n) { var b = new byte[4 * n]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)b.Length, out r); var f = new float[n]; for (int i = 0; i < n; i++) f[i] = BitConverter.ToSingle(b, 4 * i); return f; }
    static uint U(IntPtr h, long a) { var b = new byte[4]; IntPtr r; ReadProcessMemory(h, (IntPtr)a, b, (IntPtr)4, out r); return BitConverter.ToUInt32(b, 0); }
    static double Dot(float[] a, int i, double x, double y, double z) { return a[i] * x + a[i + 1] * y + a[i + 2] * z; }

    public static string Look(int wawPid, long wawBase, int bfPid, long bfBase) {
        IntPtr waw = OpenProcess(0x0410, false, wawPid), bf = OpenProcess(0x0410, false, bfPid);   // read and query only
        // WaW: the player's feet, the lens, where it draws from, and its forward / left / up
        var feet = F(waw, wawBase + 0x14ED088, 3); var lens = F(waw, wawBase + 0x3120348, 2);
        var from = F(waw, wawBase + 0x3120354, 3); var axis = F(waw, wawBase + 0x3120364, 9);
        double x = feet[0] - from[0], y = feet[1] - from[1], z = feet[2] - from[2], depth = Dot(axis, 0, x, y, z);
        string s = string.Format("feet: WaW ({0,6:F3},{1,7:F3})", -Dot(axis, 3, x, y, z) / depth / lens[0], Dot(axis, 6, x, y, z) / depth / lens[1]);
        // SWBF2: the unit, and the camera on it. The pointer is to whichever camera is being drawn
        // with at that instant, so look until it is the one near the unit.
        long unit = U(bf, bfBase + 0x1A296B0); var at = F(bf, unit, 3); uint camera = 0; float[] placed = null;
        for (int tries = 0; tries < 300; tries++) { camera = U(bf, bfBase + 0x3F58E0); placed = F(bf, camera + 0x30, 16); if (Math.Abs(placed[12] - at[0]) < 30 && Math.Abs(placed[14] - at[2]) < 30) break; }
        var own = F(bf, camera + 0x138, 3);
        x = at[0] - placed[12]; y = at[1] - placed[13]; z = at[2] - placed[14]; depth = -Dot(placed, 8, x, y, z);
        s += string.Format("  SWBF2 ({0,6:F3},{1,7:F3})", Dot(placed, 0, x, y, z) / depth / (own[0] / own[2]), Dot(placed, 4, x, y, z) / depth / (own[1] / own[2]));
        return s + string.Format("  | lens: WaW {0:F3} x {1:F3}, SWBF2 {2:F3} x {3:F3}; SWBF2's zoom {4:F2}", lens[0], lens[1], own[0] / own[2], own[1] / own[2], own[2]);
    }
}
'@

$waw = Get-Process CoDWaW | Select-Object -First 1
$bf = Get-Process BattlefrontII | Select-Object -First 1
for ($i = 0; $i -lt $Looks; $i++) {
    [CameraFit]::Look($waw.Id, [int64]$waw.MainModule.BaseAddress, $bf.Id, [int64]$bf.MainModule.BaseAddress)
    Start-Sleep -Milliseconds $GapMs
}
