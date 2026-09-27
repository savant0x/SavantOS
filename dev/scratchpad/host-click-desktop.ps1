Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native3 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
Add-Type -AssemblyName System.Drawing

$q = Get-Process qemu-system-x86_64w -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $q) { Write-Output "NO-QEMU-WINDOW"; exit 1 }
$h = $q.MainWindowHandle

if ([Native3]::IsIconic($h)) {
  [Native3]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
  Start-Sleep -Milliseconds 800
  Write-Output "window restored"
}
[Native3]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400

$cr = New-Object Native3+RECT
[Native3]::GetClientRect($h, [ref]$cr) | Out-Null
$origin = New-Object Native3+POINT; $origin.X = 0; $origin.Y = 0
[Native3]::ClientToScreen($h, [ref]$origin) | Out-Null
$cw = $cr.Right; $ch = $cr.Bottom
if ($cw -le 0 -or $ch -le 0) { Write-Output "BAD-CLIENT-RECT"; exit 1 }

# desktop click (center-ish, on the wallpaper away from icons)
$gx = 1280; $gy = 1100
$hx = $origin.X + [int]($gx * $cw / 2560)
$hy = $origin.Y + [int]($gy * $ch / 1440)
Write-Output "client ${cw}x${ch} at $($origin.X),$($origin.Y); click target $hx,$hy"

[Native3]::SetCursorPos($hx, $hy) | Out-Null
Start-Sleep -Milliseconds 300
[Native3]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[Native3]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "click sent"
