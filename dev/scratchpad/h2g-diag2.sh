#!/bin/bash
# Stage-2 diagnostics for the stalled host -> guest send (FID-2026-0922-001).
SSH="ssh -o ConnectTimeout=8 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 savant@127.0.0.1"
GE="export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"

echo "=== launcher clipboard log (pre) ==="
grep "clipboard:" /c/Users/spenc/savantos-fp1/vm/shell.log | tail -8
echo "=== A: guest -> host direction (launcher writes Windows clipboard) ==="
# wl-copy forks an owner that holds the SSH channel open; detach it.
$SSH "$GE; nohup sh -c 'printf G2H-DIAG-20260927 | wl-copy' >/dev/null 2>&1 </dev/null & exit"
sleep 3
powershell -NoProfile -Command "Write-Output ('HOST-CLIPBOARD: [' + (Get-Clipboard -Raw) + ']')"
echo "=== B: sequence number bumps in this context? ==="
powershell -NoProfile -Command "Add-Type -Namespace W -Name U -MemberDefinition '[DllImport(\"user32.dll\")] public static extern uint GetClipboardSequenceNumber();'; Write-Output ('SEQ-BEFORE: ' + [W.U]::GetClipboardSequenceNumber()); Set-Clipboard -Value 'H2G-DIAG-2'; Start-Sleep -Milliseconds 300; Write-Output ('SEQ-AFTER: ' + [W.U]::GetClipboardSequenceNumber())"
echo "=== C: pull connection (host side, launcher pid) ==="
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 4449 -State Established | Format-List LocalPort,RemotePort,OwningProcess"
echo "=== D: guest pull connection age + repro ==="
$SSH "$GE; ss -tn 2>/dev/null | grep -E '444[89]' | head -6"
sleep 2
$SSH "$GE; echo GUEST-TEXT: \$(wl-paste 2>/dev/null | head -c 60); echo TYPES: \$(wl-paste --list-types 2>/dev/null | tr '\n' ' ')"
echo "=== launcher clipboard log ==="
grep "clipboard:" /c/Users/spenc/savantos-fp1/vm/shell.log | tail -8
