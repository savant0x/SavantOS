# Live-proof helper for the render guard (FID-2026-0917-001).
# Launches the dev launcher with forced GPU rendering, waits for the
# warning modal, captures its window and child texts as evidence, then
# kills the launcher. Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev/scratchpad/modal-probe.ps1
param(
    [string]$ImagePath = 'C:\Users\spenc\dev\SavantOS\app\SavantOS-dev.exe',
    [string]$Log = 'C:\Users\spenc\savantos-dev3\vm\shell.log',
    [string]$Dir = 'C:\Users\spenc\savantos-dev3',
    [string]$Sums = '3ef6350649ef86daa9cd19502f90353be59a5b00689948a9c7c580d449937263'
)

Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p,IntPtr a,string c,string t);
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr GetWindow(IntPtr h,uint cmd);
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,System.Text.StringBuilder s,int n);
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,System.Text.StringBuilder s,int n);
'@

function Get-WindowTextSafe($hwnd) {
    $sb = New-Object System.Text.StringBuilder 4096
    [void][W.U]::GetWindowText($hwnd, $sb, 4096)
    return $sb.ToString()
}
function Get-ClassNameSafe($hwnd) {
    $sb = New-Object System.Text.StringBuilder 128
    [void][W.U]::GetClassName($hwnd, $sb, 128)
    return $sb.ToString()
}

$before = (Get-Content $Log).Count
Start-Process -FilePath $ImagePath -ArgumentList `
    '-dir', $Dir, '-render', 'gpu', `
    '-release', 'http://127.0.0.1:8091', '-sums-sha256', $Sums, '-no-update'

# Wait for the render warning line to land in the session log.
for ($i = 0; $i -lt 240; $i++) {
    $new = Get-Content $Log | Select-Object -Skip $before
    if ($new -match 'rendering warning:') { break }
    Start-Sleep -Milliseconds 250
}
Start-Sleep -Milliseconds 500

# The warning is a MessageBoxW: dialog class #32770 titled "SavantOS".
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60 -and $h -eq [IntPtr]::Zero; $i++) {
    $h = [W.U]::FindWindow('#32770', 'SavantOS')
    if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
}
if ($h -eq [IntPtr]::Zero) {
    Write-Output 'MODAL-NOT-FOUND'
} else {
    Write-Output ('MODAL-FOUND hwnd=' + $h +
        ' class=' + (Get-ClassNameSafe $h) +
        ' title="' + (Get-WindowTextSafe $h) + '"')
    # Walk the children two ways: FindWindowEx any-class, then GW_CHILD chain.
    $seen = @{}
    $p = [IntPtr]::Zero
    for ($j = 0; $j -lt 12; $j++) {
        $p = [W.U]::FindWindowEx($h, $p, $null, [IntPtr]::Zero)
        if ($p -eq [IntPtr]::Zero) { break }
        $seen[$p] = $true
        Write-Output ('CHILD-ex[' + $j + '] class=' + (Get-ClassNameSafe $p) +
            ' text="' + (Get-WindowTextSafe $p) + '"')
    }
    $c = [W.U]::GetWindow($h, 5) # GW_CHILD
    for ($j = 0; $j -lt 12 -and $c -ne [IntPtr]::Zero; $j++) {
        if (-not $seen[$c]) {
            Write-Output ('CHILD-gw[' + $j + '] class=' + (Get-ClassNameSafe $c) +
                ' text="' + (Get-WindowTextSafe $c) + '"')
        }
        $c = [W.U]::GetWindow($c, 2) # GW_HWNDNEXT
    }
}

Stop-Process -Name SavantOS-dev -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Write-Output '=== new log lines ==='
Get-Content $Log | Select-Object -Skip $before | Select-String -Pattern 'rendering|headless|guest-ensure'
