# Finds where BattlefrontII.exe keeps the player's position when no script can
# publish it. The person playing follows beeps: low = stand still, high = walk.
# A coordinate is a float that never changes while standing and is different
# after every walk; a position is two of those 8 bytes apart (x and z, y between).
param(
    [string]$ProcessName = 'BattlefrontII',
    [int]$LeadInSec = 20,
    [int]$WalkSec = 5,
    [string]$OutFile
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BfScan {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);

    [StructLayout(LayoutKind.Sequential)]
    struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }

    public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }

    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
    public static IntPtr OpenWrite(int pid) { return OpenProcess(0x0438, false, pid); }  // + VM_WRITE | VM_OPERATION

    // Adds `delta` to the float at addr, then reads it back at the given times.
    // Returns the value before, followed by the reading at each time. A copy the
    // game recomputes snaps straight back; the value physics actually uses stays
    // changed and then drifts as the game reacts.
    public static float[] Poke(IntPtr h, long addr, float delta, int[] atMs) {
        var b = new byte[4];
        IntPtr n;
        if (!ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n)) return null;
        float before = BitConverter.ToSingle(b, 0);
        if (!WriteProcessMemory(h, (IntPtr)addr, BitConverter.GetBytes(before + delta), (IntPtr)4, out n)) return null;
        var result = new float[atMs.Length + 1];
        result[0] = before;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < atMs.Length; i++) {
            while (sw.ElapsedMilliseconds < atMs[i]) System.Threading.Thread.Sleep(1);
            result[i + 1] = ReadProcessMemory(h, (IntPtr)addr, b, (IntPtr)4, out n) ? BitConverter.ToSingle(b, 0) : float.NaN;
        }
        return result;
    }

    // A copy of every committed, writable region.
    public class Snap {
        public List<long> Base = new List<long>();
        public List<byte[]> Data = new List<byte[]>();
        public long Bytes;
        public byte[] Region(long b, int len) {
            int i = Base.BinarySearch(b);
            return i >= 0 && Data[i].Length == len ? Data[i] : null;
        }
        public bool TryInt(long addr, out int v) {
            v = 0;
            int i = Base.BinarySearch(addr);
            if (i < 0) i = ~i - 1;
            if (i < 0) return false;
            long off = addr - Base[i];
            if (off + 4 > Data[i].Length) return false;
            v = BitConverter.ToInt32(Data[i], (int)off);
            return true;
        }
    }

    public static Snap Take(IntPtr h) {
        var s = new Snap();
        long addr = 0x10000;
        while (addr < 0xFFFF0000L) {
            MBI m;
            if (VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
            long b = (long)m.BaseAddress, size = (long)m.RegionSize;
            if (size <= 0) break;
            if (m.State == 0x1000 && (m.Protect & 0x101) == 0 && (m.Protect & 0xCC) != 0 && size <= (512L << 20)) {
                var buf = new byte[size];
                IntPtr got;
                if (ReadProcessMemory(h, (IntPtr)b, buf, (IntPtr)size, out got) && (long)got == size) { s.Base.Add(b); s.Data.Add(buf); s.Bytes += size; }
            }
            addr = b + size;
        }
        return s;
    }

    // How many 4-byte words differ between two snapshots: a rough "is the game doing anything" figure.
    public static long CountChanged(Snap a, Snap b) {
        long n = 0;
        for (int i = 0; i < a.Base.Count; i++) {
            byte[] da = a.Data[i], db = b.Region(a.Base[i], da.Length);
            if (db == null) continue;
            for (int o = 0; o + 4 <= da.Length; o += 4) if (BitConverter.ToInt32(da, o) != BitConverter.ToInt32(db, o)) n++;
        }
        return n;
    }

    static bool Plausible(float f) { float a = Math.Abs(f); return a > 1e-4f && a < 1e5f; }  // also rejects NaN, ints and pointers read as floats
    // A character resting on the ground jitters slightly, so "still" is a small tolerance, not bit-equality.
    const float Still = 0.02f;
    static bool Moved(float from, float to) { float d = Math.Abs(to - from); return d >= 0.5f && d <= 120f; }

    public class Cands {
        public List<long> Addr = new List<long>();
        public List<float[]> Stops = new List<float[]>();   // value at each standing stop
    }

    // still1a/still1b: two snapshots while standing. still2: standing again after a walk.
    public static Cands Start(Snap still1a, Snap still1b, Snap still2) {
        var c = new Cands();
        for (int i = 0; i < still1a.Base.Count; i++) {
            long bs = still1a.Base[i];
            byte[] da = still1a.Data[i], db = still1b.Region(bs, da.Length), dc = still2.Region(bs, da.Length);
            if (db == null || dc == null) continue;
            for (int o = 0; o + 4 <= da.Length; o += 4) {
                if (BitConverter.ToInt32(da, o) == BitConverter.ToInt32(dc, o)) continue;
                float fa = BitConverter.ToSingle(da, o), fb = BitConverter.ToSingle(db, o), fc = BitConverter.ToSingle(dc, o);
                if (!Plausible(fa) || !Plausible(fc) || !(Math.Abs(fa - fb) <= Still) || !Moved(fa, fc)) continue;
                c.Addr.Add(bs + o);
                c.Stops.Add(new float[] { fa, fc });
            }
        }
        return c;
    }

    // same = true: keep candidates whose value is bit-identical to the last stop (still standing).
    // same = false: keep candidates that moved since the last stop, and record the new stop.
    public static Cands Keep(Snap s, Cands c, bool same) {
        var r = new Cands();
        for (int i = 0; i < c.Addr.Count; i++) {
            int bits;
            if (!s.TryInt(c.Addr[i], out bits)) continue;
            float[] stops = c.Stops[i];
            float last = stops[stops.Length - 1], now = BitConverter.ToSingle(BitConverter.GetBytes(bits), 0);
            if (same) {
                if (!(Math.Abs(now - last) <= Still)) continue;
                r.Addr.Add(c.Addr[i]); r.Stops.Add(stops);
            } else {
                if (!Plausible(now) || !Moved(last, now)) continue;
                var next = new float[stops.Length + 1];
                Array.Copy(stops, next, stops.Length);
                next[stops.Length] = now;
                r.Addr.Add(c.Addr[i]); r.Stops.Add(next);
            }
        }
        return r;
    }
}
'@
Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'

function Beep-Low { [Console]::Beep(350, 450) }
function Beep-High { [Console]::Beep(1400, 200); [Console]::Beep(1400, 200) }
function Test-GameFocused { $fp = 0; [void][W.U]::GetWindowThreadProcessId([W.U]::GetForegroundWindow(), [ref]$fp); $fp -eq $proc.Id }

$proc = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$h = [BfScan]::Open($proc.Id)
if ($h -eq [IntPtr]::Zero) { throw "could not open process $($proc.Id)" }
$sw = [Diagnostics.Stopwatch]::StartNew()

# Before the player returns to the game: how much memory changes per second while it is not focused?
$focusedAtStart = Test-GameFocused
$u1 = [BfScan]::Take($h); Start-Sleep -Milliseconds 1000; $u2 = [BfScan]::Take($h)
$unfocusedRate = [BfScan]::CountChanged($u1, $u2)
"start: game focused = $focusedAtStart; snapshot {0:N0} MB; words changing per second = {1:N0}" -f ($u1.Bytes / 1MB), $unfocusedRate
$u1 = $null; $u2 = $null; [GC]::Collect()

while ($sw.Elapsed.TotalSeconds -lt $LeadInSec) { Start-Sleep -Milliseconds 200 }

# Stand 1
Beep-Low; "t+{0:N0}s LOW  (stand)  focused = {1}" -f $sw.Elapsed.TotalSeconds, (Test-GameFocused)
Start-Sleep -Milliseconds 1800; $a = [BfScan]::Take($h)
Start-Sleep -Milliseconds 1500; $b = [BfScan]::Take($h)
$focusedRate = [BfScan]::CountChanged($a, $b) / 1.5
"  standing: words changing per second = {0:N0}" -f $focusedRate

$cands = $null
for ($round = 1; $round -le 3; $round++) {
    Beep-High; "t+{0:N0}s HIGH (walk {1})" -f $sw.Elapsed.TotalSeconds, $round
    Start-Sleep -Seconds $WalkSec
    Beep-Low; "t+{0:N0}s LOW  (stand)  focused = {1}" -f $sw.Elapsed.TotalSeconds, (Test-GameFocused)
    Start-Sleep -Milliseconds 1800; $s1 = [BfScan]::Take($h)
    Start-Sleep -Milliseconds 1500; $s2 = [BfScan]::Take($h)
    if ($round -eq 1) { $cands = [BfScan]::Start($a, $b, $s1); $a = $null; $b = $null }
    else { $cands = [BfScan]::Keep($s1, $cands, $false) }
    $moved = $cands.Addr.Count
    $cands = [BfScan]::Keep($s2, $cands, $true)
    "  after walk {0}: {1:N0} moved, {2:N0} of those then held still" -f $round, $moved, $cands.Addr.Count
    $s1 = $null; $s2 = $null; [GC]::Collect()
}
"t+{0:N0}s scan finished; keep standing still" -f $sw.Elapsed.TotalSeconds

$imageBase = [int64]$proc.MainModule.BaseAddress
$imageEnd = $imageBase + $proc.MainModule.ModuleMemorySize
function Format-Addr([long]$a) { if ($a -ge $imageBase -and $a -lt $imageEnd) { '{0}.exe+0x{1:X}' -f $ProcessName, ($a - $imageBase) } else { '0x{0:X8}' -f $a } }

$index = @{}
for ($i = 0; $i -lt $cands.Addr.Count; $i++) { $index[$cands.Addr[$i]] = $i }
$triples = @()
foreach ($addr in $cands.Addr) {
    if (-not $index.ContainsKey($addr + 8)) { continue }
    $x = $cands.Stops[$index[$addr]]; $z = $cands.Stops[$index[$addr + 8]]
    $yIdx = $index[$addr + 4]
    $legs = @(); for ($k = 1; $k -lt $x.Length; $k++) { $legs += [Math]::Sqrt([Math]::Pow($x[$k] - $x[$k - 1], 2) + [Math]::Pow($z[$k] - $z[$k - 1], 2)) }
    $triples += [pscustomobject]@{ Address = $addr; Name = (Format-Addr $addr)
        X = ($x | ForEach-Object { '{0:N2}' -f $_ }) -join ' > '
        Z = ($z | ForEach-Object { '{0:N2}' -f $_ }) -join ' > '
        Legs = ($legs | ForEach-Object { '{0:N1}' -f $_ }) -join ' / '
        MinLeg = ($legs | Measure-Object -Minimum).Minimum; MaxLeg = ($legs | Measure-Object -Maximum).Maximum
        YAlsoMoved = ($null -ne $yIdx) }
}
# Save before anything else can go wrong.
if ($OutFile) {
    @{ pid = $proc.Id; imageBase = $imageBase; unfocusedWordsPerSec = $unfocusedRate; focusedWordsPerSec = $focusedRate
       triples = @($triples | ForEach-Object { @{ address = $_.Address; name = $_.Name; x = $_.X; z = $_.Z; legs = $_.Legs; yMoved = $_.YAlsoMoved } }) } |
        ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $OutFile
}
"--- {0:N0} single values behaved like a coordinate; {1} look like positions (x and z 8 bytes apart) ---" -f $cands.Addr.Count, $triples.Count
$triples | ForEach-Object { "  {0,-28} x: {1,-40} z: {2,-40} legs {3} m" -f $_.Name, $_.X, $_.Z, $_.Legs }

# Nudge test. For each result that moved like someone on foot, raise its height
# value by 3 m and watch what the game does with it.
$walkLike = @($triples | Where-Object { $_.MinLeg -ge 1 -and $_.MaxLeg -le 80 })
"--- nudge test on {0} walk-like results: height before, then +20 ms, +60, +150, +300, +600 ---" -f $walkLike.Count
$hw = [BfScan]::OpenWrite($proc.Id)
foreach ($t in ($walkLike | Select-Object -First 40)) {
    $r = [BfScan]::Poke($hw, $t.Address + 4, [single]3.0, [int[]]@(20, 60, 150, 300, 600))
    if ($r) { "  {0,-28} {1,8:N2} -> {2}" -f $t.Name, $r[0], (($r[1..5] | ForEach-Object { '{0,8:N2}' -f $_ }) -join ' ') }
    else { "  {0,-28} could not read or write" -f $t.Name }
    Start-Sleep -Milliseconds 700
}
[Console]::Beep(900, 120); [Console]::Beep(900, 120); [Console]::Beep(900, 120)
"t+{0:N0}s done" -f $sw.Elapsed.TotalSeconds

