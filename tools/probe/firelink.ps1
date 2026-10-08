# Read-only. Watches a button go from one game to the other.
#
# World at War keeps a record of each of its actions: which key or button is
# holding it down, and whether it is held. Battlefront II keeps a bit for each
# of its game functions in the player's control state. This polls a WaW action
# and a SWBF2 function together and counts, for every press in WaW, whether
# SWBF2's function came on with it, and says which key or button did the
# pressing (WaW's own key numbers: 19 is a controller's right trigger, 200 the
# left mouse button).
#
#   firelink.ps1                    WaW's attack against SWBF2's fire
#   firelink.ps1 -Action reload     WaW's reload (either kind) against SWBF2's reload
#
# Aim is not a job for this: SWBF2's zoom is pressed, not held (see
# docs/PHASE2.md), so its function is on only for a moment at each change.
#
# Stops after -Presses presses or -Seconds seconds, whichever comes first.
param(
    [ValidateSet('fire', 'reload')][string]$Action = 'fire',
    [long[]]$WawRecords,               # WaW's records for the action, exe-relative; default by -Action
    [int]$BfFunction = -1,             # SWBF2's game function; default by -Action
    [long]$BfControlState = 0x1AC0918, # SWBF2's control state for player 1, exe-relative
    [int]$Presses = 6,
    [int]$Seconds = 90
)
$ErrorActionPreference = 'Stop'
if (-not $WawRecords) { $WawRecords = if ($Action -eq 'fire') { , 0x2C0FE4C } else { 0x2C0FEC4, 0x2C0FED8 } }   # +attack; +reload, +usereload
if ($BfFunction -lt 0) { $BfFunction = if ($Action -eq 'fire') { 0 } else { 7 } }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class FireLink {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    public static List<string> Watch(int wawPid, long[] records, int bfPid, long state, uint bit, int presses, double seconds) {
        IntPtr waw = OpenProcess(0x0410, false, wawPid), bf = OpenProcess(0x0410, false, bfPid);   // read and query only
        var record = new byte[20]; var bits = new byte[4]; IntPtr n;
        var keys = new SortedDictionary<int, int>(); var res = new List<string>();
        int seen = 0, answered = 0; bool held = false, on = false; long heldAt = 0; var delays = new List<long>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds && (seen < presses || held)) {
            bool now = false; int key = 0;
            foreach (long address in records) {
                if (!ReadProcessMemory(waw, (IntPtr)address, record, (IntPtr)20, out n)) { res.Add("WaW could not be read"); return res; }
                if (record[16] != 0) { now = true; key = BitConverter.ToInt32(record, 0); }
            }
            if (!ReadProcessMemory(bf, (IntPtr)(state + 0x10), bits, (IntPtr)4, out n)) { res.Add("SWBF2 could not be read"); return res; }
            bool function = (BitConverter.ToUInt32(bits, 0) & bit) != 0;
            if (now && !held) { seen++; heldAt = sw.ElapsedMilliseconds; on = false; int c; keys.TryGetValue(key, out c); keys[key] = c + 1; }
            if (now && function && !on) { on = true; answered++; delays.Add(sw.ElapsedMilliseconds - heldAt); }
            held = now;
            System.Threading.Thread.Sleep(2);
        }
        res.Add(string.Format("{0} press(es) of WaW's action in {1:N0} s; SWBF2's function came on in {2} of them", seen, sw.Elapsed.TotalSeconds, answered));
        foreach (var k in keys) res.Add(string.Format("    held down by WaW key number {0}: {1} time(s)", k.Key, k.Value));
        if (delays.Count > 0) { delays.Sort(); res.Add(string.Format("    SWBF2's function followed after {0} to {1} ms (as seen by polling every 2 ms)", delays[0], delays[delays.Count - 1])); }
        return res;
    }
}
'@

$waw = Get-Process CoDWaW | Select-Object -First 1
$bf = Get-Process BattlefrontII | Select-Object -First 1
$wawBase = [int64]$waw.MainModule.BaseAddress
"WaW's $Action against SWBF2's game function $BfFunction"
[FireLink]::Watch($waw.Id, [long[]]($WawRecords | ForEach-Object { $wawBase + $_ }), $bf.Id, [int64]$bf.MainModule.BaseAddress + $BfControlState, [uint32]1 -shl $BfFunction, $Presses, $Seconds)
