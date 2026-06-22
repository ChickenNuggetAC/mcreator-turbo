[CmdletBinding()]
param(
    [string]$InstallRoot  = (Join-Path $env:LOCALAPPDATA 'MCreatorTurbo'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$DesktopDir   = ([Environment]::GetFolderPath('Desktop')),
    [string]$RegistryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)
$ErrorActionPreference = 'Continue'

$startLnk = Join-Path $StartMenuDir 'MCreator Turbo.lnk'
$deskLnk  = Join-Path $DesktopDir   'MCreator Turbo.lnk'
$regKey   = Join-Path $RegistryRoot 'MCreatorTurbo'

$manifestPath = Join-Path $InstallRoot '.install-manifest.json'
if (Test-Path $manifestPath) {
    try {
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($m.StartMenuLnk) { $startLnk = $m.StartMenuLnk }
        if ($m.DesktopLnk)   { $deskLnk  = $m.DesktopLnk }
        if ($m.RegKey)       { $regKey   = $m.RegKey }
        if ($m.InstallRoot)  { $InstallRoot = $m.InstallRoot }
    } catch { }
}

Write-Host "Uninstalling MCreator Turbo..."

foreach ($lnk in @($startLnk, $deskLnk)) {
    if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue; Write-Host "  removed shortcut: $lnk" }
}

if (Test-Path $regKey) { Remove-Item $regKey -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "  removed registry key: $regKey" }

if (Test-Path $InstallRoot) {
    try {
        Remove-Item $InstallRoot -Recurse -Force -ErrorAction Stop
        Write-Host "  removed folder: $InstallRoot"
    } catch {
        Write-Host "  could not fully remove $InstallRoot ($($_.Exception.Message)); it may be in use."
    }
}

Write-Host "MCreator Turbo uninstalled." -ForegroundColor Green
