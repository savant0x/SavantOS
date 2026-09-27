Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FG2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$q = Get-Process qemu-system-x86_64w -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $q) { Write-Output "NO-QEMU-WINDOW"; exit 1 }
$h = $q.MainWindowHandle
if ([FG2]::IsIconic($h)) { [FG2]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 800 }

# real foreground steal via thread-input attachment
$fg = [FG2]::GetForegroundWindow()
$fgPid = 0
$fgThread = [FG2]::GetWindowThreadProcessId($fg, [ref]$fgPid)
$myThread = [FG2]::GetCurrentThreadId()
[FG2]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
[FG2]::SetForegroundWindow($h) | Out-Null
[FG2]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
Start-Sleep -Milliseconds 500
$nowFg = [FG2]::GetForegroundWindow()
Write-Output ("foreground-now-vm: {0}" -f ($nowFg -eq $h))

$cr = New-Object FG2+RECT
[FG2]::GetClientRect($h, [ref]$cr) | Out-Null
$origin = New-Object FG2+POINT; $origin.X = 0; $origin.Y = 0
[FG2]::ClientToScreen($h, [ref]$origin) | Out-Null

$gx = 1280; $gy = 1100
$hx = $origin.X + [int]($gx * $cr.Right / 2560)
$hy = $origin.Y + [int]($gy * $cr.Bottom / 1440)
Write-Output "click target $hx,$hy"

# click 1: ensure activation; click 2: the measured one
foreach ($round in 1, 2) {
  [FG2]::SetCursorPos($hx, $hy) | Out-Null
  Start-Sleep -Milliseconds 250
  [FG2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 120
  [FG2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 600
  Write-Output "click $round sent"
}
