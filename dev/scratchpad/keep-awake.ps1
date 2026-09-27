# Keep-awake watchdog for the dual-build (prevents WSL/Docker death by idle sleep).
# Restores the original standby timeout when the build finishes, stalls, or the cap is hit.
param(
    [Parameter(Mandatory=$true)][string]$LogPath,
    [Parameter(Mandatory=$true)][int]$OriginalIndex,   # STANDBYIDLE AC index (seconds)
    [int]$MaxMinutes = 240,
    [int]$StallMinutes = 45
)
$ErrorActionPreference = "SilentlyContinue"
function Restore-Sleep {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $OriginalIndex | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
}
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($true) {
    Start-Sleep -Seconds 30
    $finished = $false
    if (Test-Path $LogPath) {
        if (Select-String -Path $LogPath -Pattern "GATE GREEN|GATE RED|BUILD EXIT" -Quiet) { $finished = $true }
        $idleMin = ((Get-Date) - (Get-Item $LogPath).LastWriteTime).TotalMinutes
        if ($idleMin -gt $StallMinutes) { $finished = $true }
    }
    if ($finished -or ($sw.Elapsed.TotalMinutes -gt $MaxMinutes)) {
        Restore-Sleep
        exit 0
    }
}
