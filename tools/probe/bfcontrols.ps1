# Read-only. Watches what Battlefront II's player controller is being told.
#
# The game turns its devices into a flat array of "raw controls" on the
# player's controller object every frame (one float each: 760 of them, most
# of them joystick axes that never move) and then maps those to actions.
# This polls that array and reports which entries were ever non-zero, split
# by whether the game's window was the one in front and whether the game's
# own mouse object said the left button was down.
#
# It answers "when the player really fires, which raw control does it?" and
# so whether a button fed in from outside lands in the same place.
param(
    [string]$ProcessName = 'BattlefrontII',
    [long]$Controller = 0x1ABE078,     # player 1's controller object, exe-relative
    [long]$MouseHeld = 0x59D158,       # the mouse object's button bits
    [int]$Seconds = 120,
    [int]$IntervalMs = 15
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfControls {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

    public static List<string> Watch(int pid, long controller, long mouseHeld, double seconds, int intervalMs) {
        IntPtr h = OpenProcess(0x0410, false, pid);   // read and query only
        const int Count = 760; var buf = new byte[Count * 4]; var four = new byte[4]; IntPtr n;
        // key: "front/back, mouse down/up" -> index -> (samples non-zero, largest value)
        var seen = new SortedDictionary<string, SortedDictionary<int, double[]>>(); var samples = new Dictionary<string, int>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            uint fg; GetWindowThreadProcessId(GetForegroundWindow(), out fg);
            if (ReadProcessMemory(h, (IntPtr)(controller + 0x14), buf, (IntPtr)buf.Length, out n) && ReadProcessMemory(h, (IntPtr)mouseHeld, four, (IntPtr)4, out n)) {
                string key = (fg == pid ? "window in front" : "window behind  ") + ", left button " + ((four[0] & 1) != 0 ? "DOWN" : "up  ");
                if (!seen.ContainsKey(key)) { seen[key] = new SortedDictionary<int, double[]>(); samples[key] = 0; }
                samples[key]++;
                for (int i = 0; i < Count; i++) { float v = BitConverter.ToSingle(buf, 4 * i); if (v != 0 && !float.IsNaN(v)) { double[] e; if (!seen[key].TryGetValue(i, out e)) { e = new double[2]; seen[key][i] = e; } e[0]++; if (Math.Abs(v) > Math.Abs(e[1])) e[1] = v; } }
            }
            System.Threading.Thread.Sleep(intervalMs);
        }
        var res = new List<string>();
        foreach (var k in seen) {
            res.Add(string.Format("{0}: {1} looks", k.Key, samples[k.Key]));
            foreach (var e in k.Value) res.Add(string.Format("    raw control {0,3} (controller+0x{1:X3}): non-zero in {2,5:N0} looks, up to {3:F2}", e.Key, 0x14 + 4 * e.Key, e.Value[0], e.Value[1]));
        }
        return res;
    }
}
'@

$proc = Get-Process $ProcessName | Select-Object -First 1
[BfControls]::Watch($proc.Id, [int64]$proc.MainModule.BaseAddress + $Controller, [int64]$proc.MainModule.BaseAddress + $MouseHeld, $Seconds, $IntervalMs)
