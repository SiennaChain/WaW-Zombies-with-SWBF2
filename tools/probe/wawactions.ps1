# Read-only. Finds where the running World at War records each of its actions
# ("+attack", "+reload" ...) as held, for [waw] held_fire and the like.
#
# The game's exe is encrypted on disk, so this reads the running game. For
# each action it finds the action's name, then the code that registers the
# name as a command, then the function that code registers. That function
# only loads the address of the action's record and calls the routine that
# marks it held; the "held" byte is 0x10 into the record.
#
# An action that is found prints its record(s); a combined one such as
# +speed_throw has two. One that is not found is not an action in this build.
param(
    [string]$ProcessName = 'CoDWaW',
    [string[]]$Actions = @('+attack', '+speed', '+speed_throw', '+toggleads_throw', '+reload', '+usereload', '+frag', '+smoke',
                           '+melee', '+activate', '+sprint', '+breath_sprint', '+holdbreath', '+gostand')
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class WawActions {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    public static byte[] Read(int pid, long address, int length) {
        IntPtr h = OpenProcess(0x0410, false, pid);   // read and query only
        var all = new byte[length]; var page = new byte[0x1000]; IntPtr n;
        for (int done = 0; done < length; done += 0x1000) {
            int take = Math.Min(0x1000, length - done);
            if (ReadProcessMemory(h, (IntPtr)(address + done), page, (IntPtr)take, out n)) Buffer.BlockCopy(page, 0, all, done, take);
        }
        return all;
    }

    public static List<int> Find(byte[] hay, byte[] needle) {
        var res = new List<int>();
        for (int i = 0; i + needle.Length <= hay.Length; i++) { int k = 0; while (k < needle.Length && hay[i + k] == needle[k]) k++; if (k == needle.Length) res.Add(i); }
        return res;
    }
}
'@

$waw = Get-Process $ProcessName | Select-Object -First 1
$base = [int64]$waw.MainModule.BaseAddress
# The exe's code, its constants and the start of its data, as loaded.
$from = $base + 0x1000
$image = [WawActions]::Read($waw.Id, $from, 0x4E5000)

foreach ($action in $Actions) {
    $found = $false
    foreach ($at in [WawActions]::Find($image, [Text.Encoding]::ASCII.GetBytes($action) + [byte]0)) {
        if ($at -gt 0 -and $image[$at - 1] -ne 0) { continue }   # the tail of a longer name
        foreach ($ref in [WawActions]::Find($image, [BitConverter]::GetBytes([uint32]($from + $at)))) {
            # mov esi, name / call / test eax, eax / jz / mov reg, function
            if ($image[$ref - 1] -ne 0xBE -or $image[$ref + 4] -ne 0xE8 -or $image[$ref + 9] -ne 0x85 -or $image[$ref + 11] -ne 0x74) { continue }
            $function = [BitConverter]::ToUInt32($image, $ref + 14); $f = $function - $from
            # in the function: mov esi, record / call, once for each record it marks
            $records = @()
            for ($i = 0; $i -lt 40 -and $image[$f + $i] -ne 0xC3; $i++) {
                if ($image[$f + $i] -eq 0xBE -and $image[$f + $i + 5] -eq 0xE8) { $records += [BitConverter]::ToUInt32($image, $f + $i + 1) }
            }
            '{0,-17} {1}' -f $action, (($records | ForEach-Object { '{0}.exe+0x{1:X} (held: +0x{2:X})' -f $ProcessName, ($_ - $base), ($_ - $base + 0x10) }) -join ' and ')
            $found = $true
        }
    }
    if (-not $found) { '{0,-17} not an action in this game' -f $action }
}
