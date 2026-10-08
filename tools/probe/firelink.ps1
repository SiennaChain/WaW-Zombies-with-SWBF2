# Read-only. Watches a trigger pull go from one game to the other.
#
# World at War keeps a record of its attack action: which key or button is
# holding it down, and whether it is held. Battlefront II keeps a bit for its
# own "fire" in the player's control state. This polls both and counts, for
# every pull in WaW, whether Battlefront's fire came on with it, and says which
# key or button did the pulling (WaW's own key numbers: 19 is a controller's
# right trigger, 200 the left mouse button).
#
# Stops after -Pulls pulls or -Seconds seconds, whichever comes first.
param(
    [long]$WawAttack = 0x2C0FE4C,      # WaW's record for +attack, exe-relative
    [long]$BfControlState = 0x1AC0918, # SWBF2's control state for player 1, exe-relative
    [int]$Pulls = 6,
    [int]$Seconds = 90
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class FireLink {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    public static List<string> Watch(int wawPid, long attack, int bfPid, long state, int pulls, double seconds) {
        IntPtr waw = OpenProcess(0x0410, false, wawPid), bf = OpenProcess(0x0410, false, bfPid);   // read and query only
        var record = new byte[20]; var bits = new byte[4]; IntPtr n;
        var keys = new SortedDictionary<int, int>(); var res = new List<string>();
        int seen = 0, answered = 0; bool held = false, fired = false; long heldAt = 0; var delays = new List<long>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds && (seen < pulls || held)) {
            if (!ReadProcessMemory(waw, (IntPtr)attack, record, (IntPtr)20, out n) || !ReadProcessMemory(bf, (IntPtr)(state + 0x10), bits, (IntPtr)4, out n)) { res.Add("a game could not be read"); break; }
            bool now = record[16] != 0, fire = (bits[0] & 1) != 0;
            if (now && !held) { seen++; heldAt = sw.ElapsedMilliseconds; fired = false; int key = BitConverter.ToInt32(record, 0); int c; keys.TryGetValue(key, out c); keys[key] = c + 1; }
            if (now && fire && !fired) { fired = true; answered++; delays.Add(sw.ElapsedMilliseconds - heldAt); }
            held = now;
            System.Threading.Thread.Sleep(2);
        }
        res.Add(string.Format("{0} pull(s) of WaW's attack in {1:N0} s; SWBF2's fire came on in {2} of them", seen, sw.Elapsed.TotalSeconds, answered));
        foreach (var k in keys) res.Add(string.Format("    held down by WaW key number {0}: {1} time(s)", k.Key, k.Value));
        if (delays.Count > 0) { delays.Sort(); res.Add(string.Format("    SWBF2's fire followed after {0} to {1} ms (as seen by polling every 2 ms)", delays[0], delays[delays.Count - 1])); }
        return res;
    }
}
'@

$waw = Get-Process CoDWaW | Select-Object -First 1
$bf = Get-Process BattlefrontII | Select-Object -First 1
[FireLink]::Watch($waw.Id, [int64]$waw.MainModule.BaseAddress + $WawAttack, $bf.Id, [int64]$bf.MainModule.BaseAddress + $BfControlState, $Pulls, $Seconds)
