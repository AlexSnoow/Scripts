<#
.SYNOPSIS
    Автономный скрипт резервного копирования (RAR Only, PS 2.0 Compatible)
    Версия: 3.1 Stable
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# НАСТРОЙКИ И ИНИЦИАЛИЗАЦИЯ PS 2.0
# ===========================================================

# Исправление для PowerShell 2.0 (переменная $PSScriptRoot отсутствует)
if (-not (Test-Path variable:PSScriptRoot)) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

 $Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
 $Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false

Clear-Host

# ===========================================================
#region CONFIG_BLOCK
# ===========================================================

# Путь к XML конфигурации
 $xmlPath = Join-Path $PSScriptRoot "Backup-Config-All.xml"
 $Script:ConfigPath = $xmlPath

# Попытка найти конфиг
if (-not (Test-Path $xmlPath)) {
    $xmlPathAlt = Join-Path (Split-Path $PSScriptRoot -Parent) "common\Backup-Config-All.xml"
    if (Test-Path $xmlPathAlt) {
        $xmlPath = $xmlPathAlt
        $Script:ConfigPath = $xmlPath
    }
    else {
        Write-Host "КРИТИЧЕСКАЯ ОШИБКА: XML конфигурация не найдена." -ForegroundColor Red
        exit 1
    }
}

# Загрузка и парсинг XML
 $BackupConfig = $null
try {
    [xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
    $b = $xmlDoc.BackupConfig
    
    $BackupConfig = @{
        General = @{
            JobName      = $b.General.JobName
            Domain       = $b.General.Domain
            SmtpServer   = $b.General.SmtpServer
            LogDaysOld   = [int]$b.General.LogDaysOld
            LogKeepCount = [int]$b.General.LogKeepCount
        }
        Paths = @{
            LogPathRoot = $b.Paths.LogPathRoot
            RarPath     = $b.Paths.RarPath
        }
        Recipients = @{
            AdminIS   = $b.Recipients.AdminIS
            AdminOS   = $b.Recipients.AdminOS
            AdminMail = $b.Recipients.AdminMail
        }
        Integrity = @{
            RarExeHash = $b.Integrity.RarExeHash
        }
        Jobs = @{}
    }

    # Парсинг заданий
    foreach ($jobNode in $b.Jobs.Job) {
        $jn = $jobNode.Name
        $BackupConfig.Jobs[$jn] = @{
            Name                    = $jn
            Source                  = $jobNode.Source
            LocalDest               = $jobNode.LocalDest
            RemoteDest              = $jobNode.RemoteDest
            ArchivePattern          = $jobNode.ArchivePattern
            RemoveSourceFlag        = ($jobNode.RemoveSourceFlag -eq 'true')
            SourceDaysOld           = [int]$jobNode.SourceDaysOld
            SourceKeepCount         = [int]$jobNode.SourceKeepCount
            LocalDestDaysOld        = [int]$jobNode.LocalDestDaysOld
            LocalDestKeepCount      = [int]$jobNode.LocalDestKeepCount
            RemoveRemoteDestFlag    = ($jobNode.RemoveRemoteDestFlag -eq 'true')
            RemoteDestDaysOld       = [int]$jobNode.RemoteDestDaysOld
            RemoteDestKeepCount     = [int]$jobNode.RemoteDestKeepCount
            ArhLog                  = ($jobNode.ArhLog -eq 'true')
            SourceFilter            = $jobNode.SourceFilter
        }
        
        # Параметры RAR
        if ($jobNode.ArhParameters) {
            $ap = @()
            foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
            $BackupConfig.Jobs[$jn]['ArhParameters'] = $ap
        }
    }
    
    Write-Host "Конфигурация загружена: $xmlPath" -ForegroundColor Yellow
}
catch {
    Write-Host "ОШИБКА ЗАГРУЗКИ XML: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Алиас для совместимости
 $config = @{
    Settings = @{
        PCName       = $env:COMPUTERNAME
        JobName      = $BackupConfig.General.JobName
        LogPath      = $BackupConfig.Paths.LogPathRoot
        ArchiverPath = $BackupConfig.Paths.RarPath
    }
    Jobs = $BackupConfig.Jobs
}

#endregion CONFIG_BLOCK

# ===========================================================
#region ФУНКЦИИ (PS 2.0 Compatible)
# ===========================================================

# --- Хеширование (аналог Get-FileHash) ---
function Get-FileHashCompat {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Файл не найден" }
            
            $hashAlgo = [System.Security.Cryptography.SHA256]::Create()
            $fileStream = [System.IO.File]::OpenRead($Path)
            
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                return [PSCustomObject]@{ Hash = $hashString.ToUpper(); Path = $Path }
            }
            finally {
                $fileStream.Dispose()
                $hashAlgo.Dispose()
            }
        }
        catch {
            Write-Warning "Ошибка хеша: $_"
            return $null
        }
    }
}

# --- Проверка целостности файла ---
function Test-FileIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-Host "Файл не найден: $FilePath" -ForegroundColor Red
        return $false
    }
    
    $actualHash = (Get-FileHashCompat -Path $FilePath).Hash
    if ($actualHash -eq $ExpectedHash.ToUpper()) {
        Write-Host "  [OK] Хеш RAR подтвержден." -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  [FAIL] Хеш не совпадает!" -ForegroundColor Red
        return $false
    }
}

# --- Логирование ---
 $Script:LogPath = $null
 $Script:MainLogFile = $null
 $Script:ReportEntries = @()

function Initialize-Logging {
    param([string]$LogPath, [string]$PCName, [string]$JobName)
    try {
        $safeName = ($PCName + "_" + $JobName) -replace '[\\/:*?"<>|]', '-'
        if (-not (Test-Path -LiteralPath $LogPath -PathType Container)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $logFileName = "${safeName}_${timestamp}.log"
        $Script:LogPath = $LogPath
        $Script:MainLogFile = Join-Path $LogPath $logFileName
        
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Script:MainLogFile, "", $utf8)
        return $true
    }
    catch { Write-Host "Ошибка логирования: $_" -ForegroundColor Red; return $false }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO", [switch]$ResultKey)
    if (-not $Script:MainLogFile) { return }
    
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) { "ERROR" { "[ERR]" } "WARNING" { "[WRN]" } "SUCCESS" { "[OK ]" } default { "[INF]" } }
    $line = "[$ts] $prefix $Message"
    
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::AppendAllText($Script:MainLogFile, "$line`r`n", $utf8)
    
    if ($ResultKey) { $Script:ReportEntries += $line }
    
    # Консоль
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
    }
}
function Write-LogSection { param([string]$Title); Write-Log "=== $Title ===" }

# --- RAR Операции ---
function Get-RarExitCode {
    param([int]$Code)
    switch ($Code) {
        0 { "OK" } 1 { "Warning" } 2 { "Fatal Error" } 3 { "CRC Error" } default { "Unknown Error $Code" }
    }
}

function Start-RarArchive {
    param([string]$RarPath, [string]$ArchivePath, [string]$SourcePath, [string[]]$Params, [string]$LogPath, [string]$Filter)
    
    $argsList = @($Params)
    if ($LogPath) { $argsList += '-ilog"' + $LogPath + '"' }
    
    $safeArchive = '"' + $ArchivePath + '"'
    $targetPath = if ($Filter) { Join-Path $SourcePath $Filter } else { $SourcePath }
    $safeSource = '"' + $targetPath + '"'
    
    $argsList += @($safeArchive, $safeSource)
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RarPath
    $psi.Arguments = $argsList -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Script:EncodingOEM
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.Start() | Out-Null
    $p.WaitForExit()
    
    $size = 0
    if (Test-Path $ArchivePath) { $size = [math]::Round((Get-Item $ArchivePath).Length / 1MB, 2) }
    
    return @{ ExitCode = $p.ExitCode; Size = $size }
}

function Test-RarArchive {
    param([string]$RarPath, [string]$ArchivePath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RarPath
    $psi.Arguments = "t `"$ArchivePath`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.Start() | Out-Null
    $p.WaitForExit()
    return ($p.ExitCode -eq 0)
}

# --- Файловые операции (PS 2.0 Safe) ---
function Get-FolderFiles {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    # PS 2.0: Нет -File, используем Where
    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
}

function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)
    if (-not (Test-Path $Path)) { return }
    
    $dateLimit = (Get-Date).AddDays(-$DaysOld)
    $files = Get-ChildItem -Path $Path -Filter $Filter -ErrorAction SilentlyContinue | 
             Where-Object { -not $_.PSIsContainer } | 
             Sort-Object LastWriteTime -Descending
    
    $keep = $files | Select-Object -First $KeepCount
    
    foreach ($f in $files) {
        if ($keep -notcontains $f -and $f.LastWriteTime -lt $dateLimit) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Deleted: $($f.Name)"
        }
    }
}

function Get-DiskSpace {
    # PS 2.0: Get-WmiObject вместо Get-CimInstance
    $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    $res = ""
    foreach ($d in $disks) {
        $free = [math]::Round($d.FreeSpace / 1GB, 1)
        $total = [math]::Round($d.Size / 1GB, 1)
        $res += "$($d.DeviceID)($free/$total GB) "
    }
    return $res
}

function Send-ReportMail {
    param([string]$To, [string]$Subject, [string]$Body)
    try {
        $msg = New-Object Net.Mail.MailMessage($PCNameMail, $To, $Subject, $Body)
        $msg.BodyEncoding = [System.Text.Encoding]::UTF8
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer)
        $smtp.Send($msg)
        return $true
    }
    catch { Write-Log "Mail Error: $_" -Level ERROR; return $false }
}

#endregion ФУНКЦИИ

# ===========================================================
#region ГЛАВНЫЙ БЛОК
# ===========================================================

# Извлечение переменных
 $PCName = $env:COMPUTERNAME
 $ParentJobName = $BackupConfig.General.JobName
 $NameDomain = $BackupConfig.General.Domain
 $PCNameMail = "$PCName@$NameDomain"
 $SmtpServer = $BackupConfig.General.SmtpServer
 $LogDaysOld = $BackupConfig.General.LogDaysOld
 $LogKeepCount = $BackupConfig.General.LogKeepCount
 $AdminIS = $BackupConfig.Recipients.AdminIS
 $AdminOS = $BackupConfig.Recipients.AdminOS

# --- ЭТАП 1: Проверка RAR ---
Write-Host "`n=== Проверка RAR ===" -ForegroundColor Yellow
 $archiverPath = $BackupConfig.Paths.RarPath
 $archiverHash = $BackupConfig.Integrity.RarExeHash

if (-not (Test-Path $archiverPath)) {
    Write-Host "RAR не найден: $archiverPath" -ForegroundColor Red; exit 1
}
if ($archiverHash) {
    if (-not (Test-FileIntegrity -FilePath $archiverPath -ExpectedHash $archiverHash)) { exit 1 }
}
Write-Host "RAR OK: $archiverPath" -ForegroundColor Green

# --- ТЕСТОВЫЙ РЕЖИМ ---
if ($TestMode) {
    Write-Host "`n=== TEST MODE ===" -ForegroundColor Cyan
    $err = 0
    foreach ($j in $BackupConfig.Jobs.Keys) {
        if (-not (Test-Path $BackupConfig.Jobs[$j].Source)) { Write-Host "FAIL Source: $j" -Red; $err++ }
    }
    if ($err -eq 0) { Write-Host "All OK" -Green; exit 0 } else { exit 1 }
}

# --- Инициализация ---
if (-not (Initialize-Logging -LogPath $config.Settings.LogPath -PCName $PCName -JobName $ParentJobName)) { exit 1 }

Write-LogSection "START BACKUP"
Write-Log "Computer: $PCName" -ResultKey
Write-Log "Config: $Script:ConfigPath"

 $results = @{}
 $errCount = 0
 $okCount = 0
 $start = Get-Date

# --- ЦИКЛ ЗАДАНИЙ ---
foreach ($jobName in $BackupConfig.Jobs.Keys) {
    $job = $BackupConfig.Jobs[$jobName]
    Write-LogSection "JOB: $jobName" -ResultKey
    
    try {
        # Проверка источника
        if (-not (Test-Path $job.Source)) { throw "Source missing: $($job.Source)" }
        
        # Папки
        if (-not (Test-Path $job.LocalDest)) { New-Item -Path $job.LocalDest -ItemType Directory -Force | Out-Null }
        if ($job.RemoteDest -and (-not (Test-Path $job.RemoteDest))) { New-Item -Path $job.RemoteDest -ItemType Directory -Force | Out-Null }

        # Статистика
        $files = Get-FolderFiles -Path $job.Source
        $cnt = ($files | Measure-Object).Count
        $sz = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        Write-Log "Files: $cnt, Size: $sz MB" -ResultKey

        # Имя архива
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        $archName = "{0}_{1}_{2}.rar" -f $PCName, $jobName, $date
        if ($job.ArchivePattern) {
            $archName = $job.ArchivePattern -replace '{PCName}', $PCName -replace '{JobName}', $jobName -replace '{Date}', $date
            if (-not $archName.EndsWith('.rar')) { $archName += '.rar' }
        }
        $archPath = Join-Path $job.LocalDest $archName
        Write-Log "Archive: $archName" -ResultKey

        # Параметры
        $params = $job.ArhParameters
        if (-not $params) { $params = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t") }
        $logRar = if ($job.ArhLog) { Join-Path $job.LocalDest "rar.log" } else { $null }

        # Архивация
        Write-Log "Running RAR..."
        $res = Start-RarArchive -RarPath $archiverPath -ArchivePath $archPath -SourcePath $job.Source -Params $params -LogPath $logRar -Filter $job.SourceFilter
        
        if ($res.ExitCode -ne 0) { throw "RAR Error: $(Get-RarExitCode $res.ExitCode)" }
        Write-Log "Archive created: $($res.Size) MB" -Level SUCCESS -ResultKey

        # Тест
        if (-not (Test-RarArchive -RarPath $archiverPath -ArchivePath $archPath)) { throw "Archive test failed" }
        Write-Log "Test OK" -ResultKey

        # Копирование
        if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            $dest = Join-Path $job.RemoteDest $archName
            Copy-Item -Path $archPath -Destination $dest -Force
            Write-Log "Copied to network" -ResultKey
        }

        # Ротация
        Remove-OldFiles -Path $job.LocalDest -DaysOld $job.LocalDestDaysOld -KeepCount $job.LocalDestKeepCount -Filter "*.rar"
        if ($job.RemoveRemoteDestFlag -and $job.RemoteDest) {
            Remove-OldFiles -Path $job.RemoteDest -DaysOld $job.RemoteDestDaysOld -KeepCount $job.RemoteDestKeepCount -Filter "*.rar"
        }
        if ($job.RemoveSourceFlag) {
            Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount $job.SourceKeepCount -Filter "*.*"
        }

        $results[$jobName] = "Success"
        $okCount++
    }
    catch {
        Write-Log "ERROR: $_" -Level ERROR -ResultKey
        $results[$jobName] = "Error: $_"
        $errCount++
    }
}

# --- ИТОГИ ---
 $dur = [math]::Round(((Get-Date) - $start).TotalMinutes, 2)
Write-LogSection "FINISH"
Write-Log "Duration: $dur min" -ResultKey
Write-Log "Success: $okCount, Errors: $errCount" -ResultKey
Write-Log "Disks: $(Get-DiskSpace)"

 $subj = "$PCName $ParentJobName : " + $(if ($errCount -gt 0) { "ERRORS" } else { "OK" })
 $body = ($Script:ReportEntries -join "`r`n") + "`r`n`r`nDisks: " + (Get-DiskSpace)
 $to = if ($errCount -gt 0) { "$AdminIS, $AdminOS" } else { $AdminIS }

if ($SmtpServer) { Send-ReportMail -To $to -Subject $subj -Body $body }

Remove-OldFiles -Path $config.Settings.LogPath -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.log"

if ($errCount -gt 0) { exit 1 } else { exit 0 }