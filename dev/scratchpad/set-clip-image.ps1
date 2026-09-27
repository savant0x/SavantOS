# Puts a real image on the Windows clipboard for the host -> guest proof
# (FID-2026-0922-001 factory out-of-box). Two modes:
#   -Mode image : classic app copy (CF_DIB via Clipboard::SetImage) - the
#                 bridge re-encodes DIB to PNG on the host side.
#   -Mode png   : browser-style copy (image + registered "PNG" format) -
#                 the bridge passes the PNG bytes through byte-exact.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev/scratchpad/set-clip-image.ps1 -Path <png> [-Mode image|png]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('image', 'png')][string]$Mode = 'image'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$img = [System.Drawing.Image]::FromFile($Path)
Write-Output ('FIXTURE-DIMS ' + $img.Width + 'x' + $img.Height)

if ($Mode -eq 'png') {
    # Browser-style: the registered PNG format travels verbatim alongside
    # the bitmap, and the bridge prefers it.
    $bytes = [IO.File]::ReadAllBytes($Path)
    $data = New-Object System.Windows.Forms.DataObject
    $data.SetImage($img)
    $data.SetData('PNG', $bytes)
    [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
    Write-Output ('CLIP-SET image+PNG bytes=' + $bytes.Length)
} else {
    [System.Windows.Forms.Clipboard]::SetImage($img)
    Write-Output 'CLIP-SET image (DIB)'
}
$img.Dispose()
