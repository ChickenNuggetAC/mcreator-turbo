$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$mc = @($env:MCREATOR_HOME, "$env:ProgramFiles\Pylo\MCreator", "${env:ProgramFiles(x86)}\Pylo\MCreator", "$env:LOCALAPPDATA\Programs\MCreator") |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'jdk\bin\javac.exe')) } | Select-Object -First 1
if (-not $mc) { throw "MCreator not found. Set MCREATOR_HOME to your MCreator install folder." }
$jdk = Join-Path $mc 'jdk\bin'

$build = Join-Path $root 'build'
$classes = Join-Path $build 'classes'
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $classes | Out-Null

$src = Join-Path $root 'src\net\chickennuggetac\regenparallel\RegenParallelAgent.java'
& (Join-Path $jdk 'javac.exe') -proc:none -d $classes $src
if ($LASTEXITCODE) { throw "javac failed ($LASTEXITCODE)" }

$resources = Join-Path $root 'resources'

$manifest = Join-Path $build 'MANIFEST.MF'
$lines = @(
    'Manifest-Version: 1.0'
    'Premain-Class: net.chickennuggetac.regenparallel.RegenParallelAgent'
    'Agent-Class: net.chickennuggetac.regenparallel.RegenParallelAgent'
    ''
) -join "`r`n"
[System.IO.File]::WriteAllText($manifest, $lines, (New-Object System.Text.UTF8Encoding($false)))

$jar = Join-Path $root 'regen-parallel-agent.jar'
Remove-Item $jar -Force -ErrorAction SilentlyContinue
& (Join-Path $jdk 'jar.exe') -cfm $jar $manifest -C $classes . -C $resources .
if ($LASTEXITCODE) { throw "jar failed ($LASTEXITCODE)" }
Get-Item $jar
