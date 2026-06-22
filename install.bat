@echo off
setlocal
echo Downloading the MCreator Turbo installer...
set "URL=https://github.com/ChickenNuggetAC/mcreator-turbo/releases/latest/download/MCreator-Turbo-Installer.exe"
set "OUT=%TEMP%\MCreator-Turbo-Installer.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri '%URL%' -OutFile '%OUT%' } catch { exit 1 }"
if exist "%OUT%" (
    start "" "%OUT%"
) else (
    echo Could not download the installer. Check your connection and try again.
    pause
)
