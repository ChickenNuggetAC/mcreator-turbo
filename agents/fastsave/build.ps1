$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$mc = @($env:MCREATOR_HOME, "$env:ProgramFiles\Pylo\MCreator", "${env:ProgramFiles(x86)}\Pylo\MCreator", "$env:LOCALAPPDATA\Programs\MCreator") |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'jdk\bin\javac.exe')) } | Select-Object -First 1
if (-not $mc) { throw "MCreator not found. Set MCREATOR_HOME to your MCreator install folder." }
$jdk = Join-Path $mc 'jdk\bin'

$javassist = Get-ChildItem (Join-Path $mc 'lib') -Filter 'javassist-*.jar' | Select-Object -First 1
if (-not $javassist) { throw "javassist not found under $mc\lib" }
Copy-Item $javassist.FullName (Join-Path $root $javassist.Name) -Force

$classes = Join-Path $root 'build\classes'
Remove-Item (Join-Path $root 'build') -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $classes | Out-Null

$src = Join-Path $root 'src\net\chickennuggetac\fastsave\FastSaveAgent.java'
& (Join-Path $jdk 'javac.exe') -cp $javassist.FullName -d $classes $src
if ($LASTEXITCODE) { throw "javac failed ($LASTEXITCODE)" }

$manifest = Join-Path $root 'build\MANIFEST.MF'
$lines = @(
    'Manifest-Version: 1.0'
    'Premain-Class: net.chickennuggetac.fastsave.FastSaveAgent'
    'Agent-Class: net.chickennuggetac.fastsave.FastSaveAgent'
    'Main-Class: net.chickennuggetac.fastsave.FastSaveAgent'
    "Class-Path: $($javassist.Name)"
    ''
) -join "`r`n"
[System.IO.File]::WriteAllText($manifest, $lines, (New-Object System.Text.UTF8Encoding($false)))

$jar = Join-Path $root 'fastsave-agent.jar'
Remove-Item $jar -Force -ErrorAction SilentlyContinue
& (Join-Path $jdk 'jar.exe') -cfm $jar $manifest -C $classes .
if ($LASTEXITCODE) { throw "jar failed ($LASTEXITCODE)" }
Get-Item $jar
