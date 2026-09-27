Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
Add-Type -AssemblyName System.Drawing

$q = Get-Process qemu-system-x86_64w -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $q) { Write-Output "NO-QEMU-WINDOW"; exit 1 }
$h = $q.MainWindowHandle

$wr = New-Object Native2+RECT
$cr = New-Object Native2+RECT
[Native2]::GetWindowRect($h, [ref]$wr) | Out-Null
[Native2]::GetClientRect($h, [ref]$cr) | Out-Null
$origin = New-Object Native2+POINT; $origin.X = 0; $origin.Y = 0
[Native2]::ClientToScreen($h, [ref]$origin) | Out-Null
$cw = $cr.Right; $ch = $cr.Bottom
Write-Output "window rect: $($wr.Left),$($wr.Top) $(( $wr.Right - $wr.Left))x$(($wr.Bottom - $wr.Top)); client ${cw}x${ch} at $($origin.X),$($origin.Y)"

# guest surface 2560x1440 -> client coords (SDL renders the surface into the client area)
$gx = 1373; $gy = 789
$hx = $origin.X + [int]($gx * $cw / 2560)
$hy = $origin.Y + [int]($gy * $ch / 1440)
Write-Output "host click target: $hx,$hy"

function Snap($path) {
  $b = New-Object System.Drawing.Bitmap($cw, $ch)
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
  $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
  $g.Dispose(); $b.Dispose()
}
Snap "C:\savantos\vm\before-click.bmp"
Write-Output "before saved"

[Native2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
[Native2]::SetCursorPos($hx, $hy) | Out-Null
Start-Sleep -Milliseconds 300
[Native2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[Native2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "click sent"

Start-Sleep -Seconds 3
Snap "C:\savantos\vm\after-click.bmp"
Write-Output "after saved"
