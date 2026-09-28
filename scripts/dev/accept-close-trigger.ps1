# Acceptance helper for FID-2026-0915-002's close-contract verification.
# Drives the REAL close path of the running VM without needing foreground
# permission: probe the window's close-button hit-test (WM_NCHITTEST ==
# HTCLOSE), then click it with SetCursorPos + mouse_event. The launcher's
# low-level mouse hook (closeguard.go) intercepts exactly that click and
# raises the close confirmation; we then click Yes. The Alt+F4 keyboard path
# is kept as a fallback (needs a successful foreground steal).
# Prints RESULT lines the orchestrator records as evidence.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File accept-close-trigger.ps1

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class AC {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Get-Text($hwnd) {
    $sb = New-Object System.Text.StringBuilder 4096
    [void][AC]::GetWindowText($hwnd, $sb, 4096)
    return $sb.ToString()
}

# 1. Locate the VM window.
$q = Get-Process qemu-system-x86_64w -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $q) { Write-Output 'RESULT=NO-QEMU-WINDOW'; exit 1 }
$h = $q.MainWindowHandle
if ([AC]::IsIconic($h)) { [AC]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 800 }

# 2. Find a point whose hit-test is HTCLOSE (20): the caption close button.
#    Probed, not guessed - DPI and frame sizes vary.
$rect = New-Object AC+RECT
[AC]::GetWindowRect($h, [ref]$rect) | Out-Null
$hitPoint = $null
for ($x = $rect.Right - 4; $x -gt ($rect.Right - 140) -and -not $hitPoint; $x -= 4) {
    for ($y = $rect.Top + 2; $y -lt ($rect.Top + 48); $y += 4) {
        $lp = [IntPtr]((($y -shl 16) -bor ($x -band 0xFFFF)) -band 0xFFFFFFFF)
        $ht = [AC]::SendMessage($h, 0x0084, [IntPtr]::Zero, $lp)   # WM_NCHITTEST
        if ($ht.ToInt64() -eq 20) { $hitPoint = @($x, $y); break }
    }
}
if (-not $hitPoint) { Write-Output 'RESULT=NO-CLOSE-BUTTON-HIT'; exit 1 }

# 3. Click it: the launcher's WH_MOUSE_LL hook swallows the click at HTCLOSE
#    and turns it into the close confirmation (this works without focus).
[AC]::SetCursorPos($hitPoint[0], $hitPoint[1]) | Out-Null
Start-Sleep -Milliseconds 250
[AC]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)   # LEFTDOWN
Start-Sleep -Milliseconds 120
[AC]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)   # LEFTUP
Start-Sleep -Milliseconds 300

# 4. Find the confirm dialog (MessageBoxW, class #32770, caption "SavantOS")
#    and verify it is the close confirm, not some other box.
$dlg = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $dlg -eq [IntPtr]::Zero; $i++) {
    $cand = [AC]::FindWindow('#32770', 'SavantOS')
    if ($cand -ne [IntPtr]::Zero) {
        # NOTE: FindWindowEx's 4th arg is a window-title *string*; passing
        # [IntPtr]::Zero coerces to "0" and silently finds nothing. NULL/null
        # means "ignore this key" and enumerates every child.
        $texts = @()
        $c = [AC]::FindWindowEx($cand, [IntPtr]::Zero, $null, $null)
        for ($j = 0; $j -lt 12 -and $c -ne [IntPtr]::Zero; $j++) {
            $texts += (Get-Text $c)
            $c = [AC]::FindWindowEx($cand, $c, $null, $null)
        }
        # Accept when the body text matches (the real confirm wording), or
        # when the box carries the Yes button (the only #32770 captioned
        # "SavantOS" is this confirm).
        $yesProbe = [AC]::FindWindowEx($cand, [IntPtr]::Zero, 'Button', '&Yes')
        if ($yesProbe -eq [IntPtr]::Zero) { $yesProbe = [AC]::FindWindowEx($cand, [IntPtr]::Zero, 'Button', 'Yes') }
        if ((($texts -join ' ') -match 'Shut down SavantOS') -or ($yesProbe -ne [IntPtr]::Zero)) { $dlg = $cand }
    }
    if ($dlg -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
}

# Fallback: the Alt+F4 keyboard path (needs a successful foreground steal).
if ($dlg -eq [IntPtr]::Zero) {
    $fg = [AC]::GetForegroundWindow()
    $fgPid = 0
    $fgThread = [AC]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $myThread = [AC]::GetCurrentThreadId()
    [AC]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
    [AC]::SetForegroundWindow($h) | Out-Null
    [AC]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
    Start-Sleep -Milliseconds 500
    if ([AC]::GetForegroundWindow() -eq $h) {
        Write-Output 'RESULT=FALLBACK-ALTF4'
        [AC]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)      # VK_MENU down
        Start-Sleep -Milliseconds 80
        [AC]::keybd_event(0x73, 0, 0, [UIntPtr]::Zero)      # VK_F4 down
        Start-Sleep -Milliseconds 80
        [AC]::keybd_event(0x73, 0, 2, [UIntPtr]::Zero)      # VK_F4 up
        Start-Sleep -Milliseconds 80
        [AC]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)      # VK_MENU up
        for ($i = 0; $i -lt 40 -and $dlg -eq [IntPtr]::Zero; $i++) {
            $cand = [AC]::FindWindow('#32770', 'SavantOS')
            if ($cand -ne [IntPtr]::Zero) {
                $texts = @()
                $c = [AC]::FindWindowEx($cand, [IntPtr]::Zero, $null, $null)
                for ($j = 0; $j -lt 12 -and $c -ne [IntPtr]::Zero; $j++) {
                    $texts += (Get-Text $c)
                    $c = [AC]::FindWindowEx($cand, $c, $null, $null)
                }
                $yesProbe = [AC]::FindWindowEx($cand, [IntPtr]::Zero, 'Button', '&Yes')
                if ($yesProbe -eq [IntPtr]::Zero) { $yesProbe = [AC]::FindWindowEx($cand, [IntPtr]::Zero, 'Button', 'Yes') }
                if ((($texts -join ' ') -match 'Shut down SavantOS') -or ($yesProbe -ne [IntPtr]::Zero)) { $dlg = $cand }
            }
            if ($dlg -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
        }
    }
}
if ($dlg -eq [IntPtr]::Zero) { Write-Output 'RESULT=CONFIRM-DIALOG-NOT-FOUND'; exit 1 }

# 5. Click Yes (BM_CLICK on the button - no focus games). The dialog is
#    MB_DEFBUTTON2, so the default is No and the button must be addressed
#    explicitly.
$yes = [AC]::FindWindowEx($dlg, [IntPtr]::Zero, 'Button', '&Yes')
if ($yes -eq [IntPtr]::Zero) { $yes = [AC]::FindWindowEx($dlg, [IntPtr]::Zero, 'Button', 'Yes') }
if ($yes -eq [IntPtr]::Zero) {
    $b = [AC]::FindWindowEx($dlg, [IntPtr]::Zero, 'Button', $null)
    for ($j = 0; $j -lt 6 -and $b -ne [IntPtr]::Zero; $j++) {
        if ((Get-Text $b) -like '*Yes*') { $yes = $b; break }
        $b = [AC]::FindWindowEx($dlg, $b, 'Button', $null)
    }
}
if ($yes -eq [IntPtr]::Zero) { Write-Output 'RESULT=YES-BUTTON-NOT-FOUND'; exit 1 }
[AC]::SendMessage($yes, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # BM_CLICK
Write-Output 'RESULT=OK-CLOSE-CONFIRMED'
exit 0
