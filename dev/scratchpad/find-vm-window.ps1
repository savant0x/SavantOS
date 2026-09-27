Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinEnum {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
$target = (Get-Process qemu-system-x86_64w -ErrorAction SilentlyContinue).Id
if (-not $target) { Write-Output "NO-QEMU"; exit 1 }
$cb = {
  param($h, $l)
  [uint32]$pid2 = 0
  [WinEnum]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq $target -and [WinEnum]::IsWindowVisible($h)) {
    $t = New-Object System.Text.StringBuilder 256
    $c = New-Object System.Text.StringBuilder 256
    [WinEnum]::GetWindowText($h, $t, 256) | Out-Null
    [WinEnum]::GetClassName($h, $c, 256) | Out-Null
    Write-Output ("HWND=0x{0:X} class=[{1}] title=[{2}]" -f $h.ToInt64(), $c.ToString(), $t.ToString())
  }
  return $true
}
[WinEnum]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
