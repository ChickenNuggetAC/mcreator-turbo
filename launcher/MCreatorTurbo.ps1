$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$AppDataDir     = Join-Path $env:LOCALAPPDATA 'MCreatorTurbo'
$SettingsPath   = Join-Path $AppDataDir 'settings.json'
$GradleHome     = Join-Path $env:USERPROFILE '.mcreator\gradle'
$GradleProps    = Join-Path $GradleHome 'gradle.properties'

function Resolve-Payload([string]$leaf) {
    foreach ($c in @((Join-Path $ScriptDir $leaf), (Join-Path $ScriptDir (Join-Path 'payload' $leaf)))) {
        if (Test-Path $c) { return $c }
    }
    return (Join-Path $ScriptDir $leaf)
}
$FastSaveJar = Resolve-Payload 'fastsave-agent.jar'

$Logical = [Environment]::ProcessorCount
if ($Logical -lt 1) { $Logical = 1 }
try {
    $TotalGB = [int][math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB)
} catch { $TotalGB = 8 }
if ($TotalGB -lt 2) { $TotalGB = 2 }

function Find-MCreatorExe {
    foreach ($p in @("$env:ProgramFiles\Pylo\MCreator", "${env:ProgramFiles(x86)}\Pylo\MCreator")) {
        if ($p -and (Test-Path (Join-Path $p 'mcreator.exe'))) { return (Join-Path $p 'mcreator.exe') }
    }
    return $null
}

function Get-MCreatorVersion([string]$mcExe) {
    if (-not $mcExe -or -not (Test-Path $mcExe)) { return $null }
    $instRoot = Split-Path $mcExe
    $jar = Join-Path $instRoot 'jdk\bin\jar.exe'
    if (-not (Test-Path $jar)) {
        $jar = (Get-Command jar.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    }
    if (-not $jar) { return $null }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mctv_" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Push-Location $tmp
        & $jar xf $mcExe 'META-INF/MANIFEST.MF' 2>$null
        Pop-Location
        $mf = Join-Path $tmp 'META-INF\MANIFEST.MF'
        if (-not (Test-Path $mf)) { return $null }
        $txt = Get-Content $mf -Raw
        $ver = [regex]::Match($txt, '(?m)^\s*MCreator-Version:\s*(\S+)')
        $bd  = [regex]::Match($txt, '(?m)^\s*Build-Date:\s*(\S+)')
        if ($ver.Success) {
            $v = $ver.Groups[1].Value.Trim()
            if ($bd.Success) { $v = "$v.$($bd.Groups[1].Value.Trim())" }
            return $v
        }
    } catch {
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    return $null
}

function Get-DefaultSettings {
    $combinedMax = $TotalGB - 4
    if ($combinedMax -lt 2) { $combinedMax = 2 }
    $sliderMax = $combinedMax - 1
    if ($sliderMax -lt 1) { $sliderMax = 1 }
    $recEditor = [int][math]::Round($TotalGB * 0.30)
    $recGradle = [int][math]::Round($TotalGB * 0.30)
    if ($recEditor -lt 1) { $recEditor = 1 }
    if ($recGradle -lt 1) { $recGradle = 1 }
    if ($recEditor -gt $sliderMax) { $recEditor = $sliderMax }
    if ($recGradle -gt $sliderMax) { $recGradle = $sliderMax }
    if (($recEditor + $recGradle) -gt $combinedMax) {
        $recGradle = $combinedMax - $recEditor
        if ($recGradle -lt 1) { $recGradle = 1; $recEditor = $combinedMax - 1 }
        if ($recEditor -lt 1) { $recEditor = 1 }
    }
    $recCpu = [int][math]::Floor($Logical * 0.75)
    if ($recCpu -lt 1) { $recCpu = 1 }
    if ($recCpu -gt $Logical) { $recCpu = $Logical }
    return [pscustomobject]@{
        EditorRamGB   = $recEditor
        GradleRamGB   = $recGradle
        CpuCores      = $recCpu
        FastSave      = $true
    }
}

function Load-Settings {
    $def = Get-DefaultSettings
    if (Test-Path $SettingsPath) {
        try {
            $j = Get-Content $SettingsPath -Raw | ConvertFrom-Json
            foreach ($p in 'EditorRamGB','GradleRamGB','CpuCores','FastSave') {
                if ($null -ne $j.$p) { $def.$p = $j.$p }
            }
        } catch { }
    }
    if (Test-Path $GradleProps) {
        try {
            $existing = Get-Content $GradleProps -Raw
            $mx = [regex]::Match($existing, '(?m)^\s*org\.gradle\.jvmargs\s*=.*?-Xmx(\d+)G')
            if ($mx.Success) { $def.GradleRamGB = [int]$mx.Groups[1].Value }
            $mw = [regex]::Match($existing, '(?m)^\s*org\.gradle\.workers\.max\s*=\s*(\d+)')
            if ($mw.Success -and [int]$mw.Groups[1].Value -le $Logical) { $def.CpuCores = [int]$mw.Groups[1].Value }
        } catch { }
    }
    return $def
}

function Save-Settings($s) {
    try {
        New-Item -ItemType Directory -Force -Path $AppDataDir | Out-Null
        ($s | ConvertTo-Json) | Set-Content -Path $SettingsPath -Encoding UTF8
        return $true
    } catch { return $false }
}

function Build-GradleProps([int]$gradleRam, [int]$cpu) {
    return ("# Managed by MCreator Turbo`r`n" +
            "org.gradle.jvmargs=-Xmx${gradleRam}G -Dfile.encoding=UTF-8`r`n" +
            "org.gradle.workers.max=$cpu`r`n" +
            "org.gradle.daemon=true`r`n" +
            "org.gradle.parallel=true`r`n" +
            "org.gradle.caching=true`r`n")
}

function Build-JavaOptions([int]$editorRam, [bool]$fastSave) {
    $a = ""
    if ($fastSave -and (Test-Path $FastSaveJar)) { $a += "-javaagent:$FastSaveJar " }
    return "$a-Xmx${editorRam}G"
}

function Write-GradleProps([int]$gradleRam, [int]$cpu, [scriptblock]$log) {
    $gp = Build-GradleProps $gradleRam $cpu
    try {
        New-Item -ItemType Directory -Force -Path $GradleHome | Out-Null
        [System.IO.File]::WriteAllText($GradleProps, $gp, (New-Object System.Text.UTF8Encoding($false)))
        & $log "Gradle: heap ${gradleRam}G, $cpu workers, parallel+caching."
    } catch {
        & $log "Could not write gradle.properties ($($_.Exception.Message))."
    }
}

$script:McExe   = Find-MCreatorExe
$script:Version = Get-MCreatorVersion $script:McExe

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$S = Load-Settings

$combinedMax = $TotalGB - 4
if ($combinedMax -lt 2) { $combinedMax = 2 }
$sliderMax = $combinedMax - 1
if ($sliderMax -lt 1) { $sliderMax = 1 }
if ($S.EditorRamGB -gt $sliderMax) { $sliderMax = $S.EditorRamGB }
if ($S.GradleRamGB -gt $sliderMax) { $sliderMax = $S.GradleRamGB }

$form = New-Object System.Windows.Forms.Form
$form.Text = "MCreator Turbo"
$form.Size = New-Object System.Drawing.Size(560, 690)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
try {
    $turboIco = Resolve-Payload 'turbo.ico'
    if ($turboIco) { $form.Icon = New-Object System.Drawing.Icon($turboIco) }
    elseif ($script:McExe) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:McExe) }
} catch {}

$title = New-Object System.Windows.Forms.Label
$title.Text = "MCreator Turbo"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(20, 12)
$title.AutoSize = $true
$form.Controls.Add($title)

$info = New-Object System.Windows.Forms.Label
$info.Location = New-Object System.Drawing.Point(20, 50)
$info.Size = New-Object System.Drawing.Size(510, 48)
$verText = if ($script:Version) { "MCreator $($script:Version)" } else { "MCreator (version unknown)" }
$mcText  = if ($script:McExe)   { $script:McExe } else { "<not found - use Browse>" }
$info.Text = "This PC: $TotalGB GB RAM, $Logical CPU threads.`r`n$verText  -  $mcText"
$form.Controls.Add($info)

$browseBtn = New-Object System.Windows.Forms.Button
$browseBtn.Text = "Browse..."
$browseBtn.Location = New-Object System.Drawing.Point(440, 50)
$browseBtn.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($browseBtn)

$editorLbl = New-Object System.Windows.Forms.Label
$editorLbl.Location = New-Object System.Drawing.Point(20, 105)
$editorLbl.Size = New-Object System.Drawing.Size(510, 22)
$editorLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$editorLbl.Text = "EDITOR RAM: $($S.EditorRamGB) GB"
$form.Controls.Add($editorLbl)
$editorBar = New-Object System.Windows.Forms.TrackBar
$editorBar.Location = New-Object System.Drawing.Point(18, 127)
$editorBar.Size = New-Object System.Drawing.Size(510, 40)
$editorBar.Minimum = 1; $editorBar.Maximum = $sliderMax; $editorBar.TickFrequency = 1
$editorBar.Value = [Math]::Min($S.EditorRamGB, $sliderMax)
$form.Controls.Add($editorBar)

$gradleLbl = New-Object System.Windows.Forms.Label
$gradleLbl.Location = New-Object System.Drawing.Point(20, 172)
$gradleLbl.Size = New-Object System.Drawing.Size(510, 22)
$gradleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$gradleLbl.Text = "GRADLE RAM (build engine): $($S.GradleRamGB) GB"
$form.Controls.Add($gradleLbl)
$gradleBar = New-Object System.Windows.Forms.TrackBar
$gradleBar.Location = New-Object System.Drawing.Point(18, 194)
$gradleBar.Size = New-Object System.Drawing.Size(510, 40)
$gradleBar.Minimum = 1; $gradleBar.Maximum = $sliderMax; $gradleBar.TickFrequency = 1
$gradleBar.Value = [Math]::Min($S.GradleRamGB, $sliderMax)
$form.Controls.Add($gradleBar)

$cpuLbl = New-Object System.Windows.Forms.Label
$cpuLbl.Location = New-Object System.Drawing.Point(20, 239)
$cpuLbl.Size = New-Object System.Drawing.Size(510, 22)
$cpuLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cpuLbl.Text = "CPU CORES (Gradle workers): $($S.CpuCores) of $Logical"
$form.Controls.Add($cpuLbl)
$cpuBar = New-Object System.Windows.Forms.TrackBar
$cpuBar.Location = New-Object System.Drawing.Point(18, 261)
$cpuBar.Size = New-Object System.Drawing.Size(510, 40)
$cpuBar.Minimum = 1; $cpuBar.Maximum = $Logical; $cpuBar.TickFrequency = 1
$cpuBar.Value = [Math]::Min([Math]::Max($S.CpuCores,1), $Logical)
$form.Controls.Add($cpuBar)

$budgetLbl = New-Object System.Windows.Forms.Label
$budgetLbl.Location = New-Object System.Drawing.Point(20, 304)
$budgetLbl.Size = New-Object System.Drawing.Size(510, 20)
$budgetLbl.ForeColor = [System.Drawing.Color]::DimGray
$budgetLbl.Text = "Tip: keep Editor + Gradle combined under $combinedMax GB to leave the OS room."
$form.Controls.Add($budgetLbl)

$fastChk = New-Object System.Windows.Forms.CheckBox
$fastChk.Text = "Fast-save agent (element saves skip the workspace-wide rebuild)"
$fastChk.Location = New-Object System.Drawing.Point(20, 330)
$fastChk.Size = New-Object System.Drawing.Size(510, 22)
$fastChk.Checked = [bool]$S.FastSave
$fastChk.Enabled = (Test-Path $FastSaveJar)
$form.Controls.Add($fastChk)

$launchBtn = New-Object System.Windows.Forms.Button
$launchBtn.Text = "Launch MCreator"
$launchBtn.Location = New-Object System.Drawing.Point(20, 466)
$launchBtn.Size = New-Object System.Drawing.Size(200, 44)
$launchBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($launchBtn)

$saveBtn = New-Object System.Windows.Forms.Button
$saveBtn.Text = "Save Settings"
$saveBtn.Location = New-Object System.Drawing.Point(232, 466)
$saveBtn.Size = New-Object System.Drawing.Size(150, 44)
$form.Controls.Add($saveBtn)

$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = "Close"
$closeBtn.Location = New-Object System.Drawing.Point(440, 466)
$closeBtn.Size = New-Object System.Drawing.Size(90, 44)
$form.Controls.Add($closeBtn)

$status = New-Object System.Windows.Forms.TextBox
$status.Location = New-Object System.Drawing.Point(20, 520)
$status.Size = New-Object System.Drawing.Size(510, 120)
$status.Multiline = $true
$status.ScrollBars = "Vertical"
$status.ReadOnly = $true
$status.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($status)
$log = { param($m) $status.AppendText($m + "`r`n") }

$editorBar.Add_ValueChanged({ $editorLbl.Text = "EDITOR RAM: $($editorBar.Value) GB" })
$gradleBar.Add_ValueChanged({ $gradleLbl.Text = "GRADLE RAM (build engine): $($gradleBar.Value) GB" })
$cpuBar.Add_ValueChanged({ $cpuLbl.Text = "CPU CORES (Gradle workers): $($cpuBar.Value) of $Logical" })

function Collect-Settings {
    return [pscustomobject]@{
        EditorRamGB   = [int]$editorBar.Value
        GradleRamGB   = [int]$gradleBar.Value
        CpuCores      = [int]$cpuBar.Value
        FastSave      = [bool]$fastChk.Checked
    }
}

$browseBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "mcreator.exe|mcreator.exe|All exe|*.exe"
    $dlg.Title = "Locate mcreator.exe"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:McExe = $dlg.FileName
        $script:Version = Get-MCreatorVersion $script:McExe
        $vt = if ($script:Version) { "MCreator $($script:Version)" } else { "MCreator (version unknown)" }
        $info.Text = "This PC: $TotalGB GB RAM, $Logical CPU threads.`r`n$vt  -  $($script:McExe)"
        & $log "Selected: $($script:McExe)  [$($script:Version)]"
    }
})

$saveBtn.Add_Click({
    $s = Collect-Settings
    if (Save-Settings $s) { & $log "Settings saved to $SettingsPath" } else { & $log "Could not save settings." }
})

$launchBtn.Add_Click({
    $s = Collect-Settings
    Save-Settings $s | Out-Null
    if (-not $script:McExe -or -not (Test-Path $script:McExe)) {
        & $log "ERROR: mcreator.exe not found - use Browse to locate it."
        [System.Windows.Forms.MessageBox]::Show("Could not find mcreator.exe. Use Browse to locate it.","MCreator Turbo",'OK','Warning') | Out-Null
        return
    }
    $mcOpen = @(Get-Process java,javaw,mcreator -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*MCreator*' })
    if ($mcOpen.Count -gt 0) {
        $titles = ($mcOpen | ForEach-Object { $_.MainWindowTitle }) -join ' | '
        "Launch BLOCKED: an MCreator editor window is already open ($titles)" | Set-Content -Path (Join-Path $AppDataDir 'launch.log') -Encoding ASCII
        & $log "MCreator is already open - close it completely, then Launch."
        [System.Windows.Forms.MessageBox]::Show("MCreator looks like it's already open.`r`n`r`nClose it completely, then Launch again.","MCreator Turbo",'OK','Information') | Out-Null
        return
    }
    Write-GradleProps $s.GradleRamGB $s.CpuCores $log
    $jo = Build-JavaOptions $s.EditorRamGB $s.FastSave
    & $log "_JAVA_OPTIONS = $jo"
    try {
        $mcDir     = Split-Path $script:McExe
        $launchLog = Join-Path $AppDataDir 'launch.log'
        ("Launch $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n_JAVA_OPTIONS=$jo`r`nmcreator=$($script:McExe)`r`nmethod=fresh-powershell Start-Process (no redirect)") | Set-Content -Path $launchLog -Encoding UTF8
        $tempPs = Join-Path $env:TEMP 'mcreator_turbo_launch.ps1'
        @(
            ('$env:_JAVA_OPTIONS = ' + "'" + $jo + "'"),
            ('Start-Process -FilePath ' + "'" + $script:McExe + "'" + ' -WorkingDirectory ' + "'" + $mcDir + "'")
        ) -join "`r`n" | Set-Content -Path $tempPs -Encoding UTF8
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tempPs)
        Add-Content -Path $launchLog "launcher spawned $(Get-Date -Format 'HH:mm:ss')"
        & $log "Launched MCreator."
    } catch {
        & $log "Launch failed: $($_.Exception.Message)"
        Add-Content -Path (Join-Path $AppDataDir 'launch.log') "ERROR: $($_.Exception.Message)"
    }
})

$closeBtn.Add_Click({ $form.Close() })

& $log "Ready. Adjust settings, then Launch MCreator."
[void]$form.ShowDialog()
