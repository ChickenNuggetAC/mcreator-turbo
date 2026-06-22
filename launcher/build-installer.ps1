$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$agents = Join-Path (Split-Path $root -Parent) 'agents'
$stage  = Join-Path $root '_setup'
$zip    = Join-Path $stage 'payload.zip'
$boot   = Join-Path $stage 'setup_bootstrap.ps1'
$vbs    = Join-Path $stage 'runsetup.vbs'
$sed    = Join-Path $root 'installer.sed'
$setupExe = Join-Path $root 'Setup.exe'

& (Join-Path $agents 'fastsave\build.ps1') | Out-Null

$payload = Join-Path $root 'payload'
Remove-Item $payload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $payload | Out-Null
Copy-Item (Join-Path $agents 'fastsave\fastsave-agent.jar')             $payload
Copy-Item (Join-Path $agents 'fastsave\javassist-*.jar') $payload
Copy-Item (Join-Path $root 'turbo.ico')                  $payload

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$ziproot = Join-Path $stage 'ziproot'
New-Item -ItemType Directory -Force $ziproot | Out-Null
foreach ($f in 'MCreatorTurbo.ps1','install.ps1','uninstall.ps1','README.md','turbo.ico','payload') {
    $p = Join-Path $root $f
    if (Test-Path $p) { Copy-Item $p $ziproot -Recurse -Force }
}
[System.IO.Compression.ZipFile]::CreateFromDirectory($ziproot, $zip)
Remove-Item $ziproot -Recurse -Force

$bootSrc = @'
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:TEMP ('MCreatorTurbo_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $here 'payload.zip'), $dest)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $dest 'install.ps1')
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
'@
[System.IO.File]::WriteAllText($boot, $bootSrc, (New-Object System.Text.UTF8Encoding($false)))

$vbsSrc = @'
Dim fso, sh, here
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\setup_bootstrap.ps1""", 0, True
'@
[System.IO.File]::WriteAllText($vbs, $vbsSrc, (New-Object System.Text.ASCIIEncoding))

$sedSrc = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuMode=%AdminQuMode%
USERQUMODE=%USERQUMODE%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$setupExe
FriendlyName=MCreator Turbo Installer
AppLaunched=wscript.exe runsetup.vbs
PostInstallCmd=<None>
AdminQuMode=0
USERQUMODE=0
FILE0="payload.zip"
FILE1="setup_bootstrap.ps1"
FILE2="runsetup.vbs"
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
[System.IO.File]::WriteAllText($sed, $sedSrc, (New-Object System.Text.ASCIIEncoding))

Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
& (Join-Path $env:SystemRoot 'System32\iexpress.exe') /N /Q $sed | Out-Null

$last = -1; $stable = 0
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 250
    if (-not (Test-Path $setupExe)) { continue }
    $sz = (Get-Item $setupExe).Length
    if ($sz -gt 0 -and $sz -eq $last) { $stable++ } else { $stable = 0 }
    $last = $sz
    if ($stable -ge 6) { break }
}
if (-not (Test-Path $setupExe)) { throw "iexpress did not produce Setup.exe" }

$rcedit = Join-Path $root 'tools\rcedit.exe'
$ico    = Join-Path $root 'turbo.ico'
if ((Test-Path $rcedit) -and (Test-Path $ico)) { & $rcedit "$setupExe" --set-icon "$ico" | Out-Null }

$desktop = [Environment]::GetFolderPath('Desktop')
if ($desktop) { Copy-Item $setupExe (Join-Path $desktop 'MCreator Turbo Installer.exe') -Force }
Get-Item $setupExe
