# Read-only. Times a character's legs from pictures of a game's window.
#
# A run of pictures is taken of the part of the window where the legs are, a
# few hundredths of a second apart. Each picture is compared with every later
# one; the legs are back where they were after one whole stride (two steps),
# so the pictures that far apart are the most alike. That gap is the stride.
#
# With the SWBF2 bridge's  [debug] treadmill  the unit runs on the spot with
# nobody playing, and this says how fast its legs are going.
#
#   -X -Y      the middle of the part looked at, as fractions of the window
#   -W -H      its size in pixels
#   -Count / -GapMs   how many pictures, how far apart
#   -Sheet     also save every third picture side by side, to look at
param([ValidateSet('bf', 'waw')][string]$Window = 'bf', [double]$X = 0.52, [double]$Y = 0.78, [int]$W = 360, [int]$H = 300,
      [int]$Count = 90, [int]$GapMs = 22, [string]$Sheet = '')
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class Stride {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r); [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public struct RECT { public int L, T, R, B; } public struct POINT { public int X, Y; }
  public static List<string> Time(IntPtr window, double fx, double fy, int w, int h, int count, int gapMs, string sheet) {
    SetProcessDPIAware(); RECT r; GetClientRect(window, out r); var p = new POINT(); ClientToScreen(window, ref p); var res = new List<string>();
    int x = p.X + (int)((r.R - r.L) * fx) - w / 2, y = p.Y + (int)((r.B - r.T) * fy) - h / 2; const int step = 4; int gw = w / step, gh = h / step;
    var looks = new List<byte[]>(); var at = new List<double>(); var kept = new List<Bitmap>(); var sw = System.Diagnostics.Stopwatch.StartNew();
    using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) using (var g = Graphics.FromImage(bmp)) {
      for (int k = 0; k < count; k++) { double due = k * gapMs; while (sw.Elapsed.TotalMilliseconds < due) System.Threading.Thread.Sleep(1);
        at.Add(sw.Elapsed.TotalMilliseconds); g.CopyFromScreen(x, y, 0, 0, new Size(w, h));
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var row = new byte[data.Stride]; var grey = new byte[gw * gh];
        for (int j = 0; j < gh; j++) { Marshal.Copy(data.Scan0 + j * step * data.Stride, row, 0, data.Stride); for (int i = 0; i < gw; i++) { int o = i * step * 4; grey[j * gw + i] = (byte)((row[o] + row[o + 1] * 2 + row[o + 2]) / 4); } }
        bmp.UnlockBits(data); looks.Add(grey); if (sheet.Length > 0 && k % 3 == 0 && kept.Count < 16) kept.Add((Bitmap)bmp.Clone()); } }
    double gap = (at[at.Count - 1] - at[0]) / (at.Count - 1);
    // how unlike two pictures a given number of pictures apart are, on average
    int most = count * 2 / 3; var unlike = new double[most + 1];
    for (int lag = 1; lag <= most; lag++) { double sum = 0; int n = 0; for (int k = 0; k + lag < count; k++) { long d = 0; var a = looks[k]; var b = looks[k + lag]; for (int i = 0; i < a.Length; i++) d += Math.Abs(a[i] - b[i]); sum += d; n++; } unlike[lag] = sum / n / (gw * gh); }
    double top = 0; for (int lag = 1; lag <= most; lag++) top = Math.Max(top, unlike[lag]);
    // the first gap, after the pictures have had time to become unlike, at which they are most alike again
    int rise = 1; while (rise < most && unlike[rise] < top * 0.7) rise++; int best = -1;
    for (int lag = rise + 1; lag < most; lag++) { if (unlike[lag] < unlike[lag - 1] && unlike[lag] <= unlike[lag + 1] && unlike[lag] < top * 0.75) { best = lag; break; } }
    res.Add(string.Format("{0} pictures {1:N1} ms apart; the legs moved (pictures differ by up to {2:N1} of 255 a point)", count, gap, top));
    if (top < 1.0) res.Add("  nothing is moving there");
    else if (best < 0) res.Add("  no stride found: the pictures never come round to alike again");
    else res.Add(string.Format("  ONE STRIDE (two steps) = {0:N0} ms: {1:N2} steps a second", best * gap, 2000.0 / (best * gap)));
    var line = new System.Text.StringBuilder("  unlike by gap: "); for (int lag = 1; lag <= most; lag += 2) line.AppendFormat("{0:N0}ms={1:N1} ", lag * gap, unlike[lag]); res.Add(line.ToString());
    if (kept.Count > 0) { using (var all = new Bitmap(w / 2 * kept.Count, h / 2)) { using (var g = Graphics.FromImage(all)) for (int k = 0; k < kept.Count; k++) g.DrawImage(kept[k], k * (w / 2), 0, w / 2, h / 2); all.Save(sheet, ImageFormat.Png); } res.Add("  pictures: " + sheet); }
    return res; } }
'@
$p = Get-Process $(if ($Window -eq 'bf') { 'BattlefrontII' } else { 'CoDWaW' }) | Select-Object -First 1
[Stride]::Time($p.MainWindowHandle, $X, $Y, $W, $H, $Count, $GapMs, $Sheet)
