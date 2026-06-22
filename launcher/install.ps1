[CmdletBinding()]
param(
    [string]$InstallRoot  = (Join-Path $env:LOCALAPPDATA 'MCreatorTurbo'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$DesktopDir   = ([Environment]::GetFolderPath('Desktop')),
    [string]$RegistryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    [string]$SourceDir    = $null,
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'

if (-not $SourceDir) { $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$AppName    = 'MCreator Turbo'
$AppVersion = '7.1.1'
$RegKey     = Join-Path $RegistryRoot 'MCreatorTurbo'

Write-Host "Installing $AppName -> $InstallRoot"

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
foreach ($f in @('MCreatorTurbo.ps1','uninstall.ps1','README.md','turbo.ico','payload')) {
    $src = Join-Path $SourceDir $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $InstallRoot -Recurse -Force
    }
}
$appScript = Join-Path $InstallRoot 'MCreatorTurbo.ps1'
if (-not (Test-Path $appScript)) { throw "MCreatorTurbo.ps1 missing after copy: $appScript" }

$iconSrc = Join-Path $InstallRoot 'turbo.ico'
if (-not (Test-Path $iconSrc)) { $iconSrc = "$env:ProgramFiles\Pylo\MCreator\mcreator.exe" }
if (-not (Test-Path $iconSrc)) { $iconSrc = (Join-Path $env:SystemRoot 'System32\shell32.dll') }

function New-Shortcut([string]$lnkPath, [string]$target, [string]$arguments, [string]$workdir, [string]$icon) {
    New-Item -ItemType Directory -Force -Path (Split-Path $lnkPath) | Out-Null
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnkPath)
    $sc.TargetPath = $target
    $sc.Arguments = $arguments
    $sc.WorkingDirectory = $workdir
    $sc.WindowStyle = 7
    $sc.Description = 'MCreator Turbo - launcher + tuner'
    if ($icon -and (Test-Path $icon)) { $sc.IconLocation = "$icon,0" }
    $sc.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
}

$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnkArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""

$startLnk = Join-Path $StartMenuDir 'MCreator Turbo.lnk'
$deskLnk  = Join-Path $DesktopDir   'MCreator Turbo.lnk'
New-Shortcut $startLnk $psExe $lnkArgs $InstallRoot $iconSrc
New-Shortcut $deskLnk  $psExe $lnkArgs $InstallRoot $iconSrc

$uninstallScript = Join-Path $InstallRoot 'uninstall.ps1'
New-Item -Path $RegKey -Force | Out-Null
$uninstCmd = "$psExe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstallScript`""
New-ItemProperty -Path $RegKey -Name 'DisplayName'     -Value $AppName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'DisplayVersion'  -Value $AppVersion -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'Publisher'       -Value 'MCreator Tools' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'InstallLocation' -Value $InstallRoot -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'UninstallString' -Value $uninstCmd -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'DisplayIcon'     -Value $iconSrc -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'NoModify'        -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'NoRepair'        -Value 1 -PropertyType DWord -Force | Out-Null

$manifest = [pscustomobject]@{
    InstallRoot   = $InstallRoot
    StartMenuLnk  = $startLnk
    DesktopLnk    = $deskLnk
    RegKey        = $RegKey
}
$manifest | ConvertTo-Json | Set-Content -Path (Join-Path $InstallRoot '.install-manifest.json') -Encoding UTF8

Write-Host "$AppName installed."

if (-not $NoLaunch) {
    Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$appScript`"") -WorkingDirectory $InstallRoot
}
