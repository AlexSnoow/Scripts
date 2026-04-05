<#
.SYNOPSIS
    File Backup-Main-rar-ps2-GLM.ps1
    Автономный скрипт резервного копирования ( RAR Only, PS 2.0 Compatible)
.DESCRIPTION
    Единый файл для резервного копирования с использованием WinRAR.
    Включает функции: логирование, архивация (RAR), верификация, ротация, отправка почты.

    Поддерживаемые переменные для ArchivePattern:
    - {PCName} - Имя компьютера
    - {JobName} - Имя одного из дочерних задания
    - {Date} - Дата в формате YYYYMMDD
    - {Time} - Время в формате HHMMSS
    - {Date_Time} - Дата и время в формате YYYYMMDD_HHMMSS

.PARAMETER TestMode
    Запуск проверки конфигурации без выполнения архивации.

.EXAMPLE
    powershell.exe -executionpolicy RemoteSigned -file .\Backup-Main-All.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ===========================================================

# Исправление для PowerShell 2.0: определение $PSScriptRoot
if (-not (Test-Path variable:PSScriptRoot)) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

 $Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
 $Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
 $Script:CultureInvariant = [System.Globalization.CultureInfo]::InvariantCulture

Clear-Host

# ===========================================================
#region CONFIG_BLOCK (XML Only)
# ===========================================================

# Путь к XML конфигурации
 $xmlPath = Join-Path $PSScriptRoot "Backup-Config-All.xml"
 $Script:ConfigPath = $xmlPath

if (-not (Test-Path $xmlPath)) {
    # Попытка найти в родительской папке (опционально)
    $xmlPathAlt = Join-Path (Split-Path $PSScriptRoot -Parent) "common\Backup-Config-All.xml"
    if (Test-Path $xmlPathAlt) {
        $xmlPath = $xmlPathAlt
        $Script:ConfigPath = $xmlPath
    }
    else {
        Write-Host "КРИТИЧЕСКАЯ ОШИБКА: XML конфигурация не найдена по пути: $xmlPath" -ForegroundColor Red
        exit 1
    }
}

# Загрузка XML
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
            ArchiveIndividualFiles  = ($jobNode.ArchiveIndividualFiles -eq 'true')
            ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
            SourceFilter            = $jobNode.SourceFilter
            ExcludeFolderPattern    = $jobNode.ExcludeFolderPattern
            IndividualArchivePattern = $jobNode.IndividualArchivePattern
        }
        
        # Параметры архивации
        if ($jobNode.ArhParameters) {
            $ap = @()
            foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
            $BackupConfig.Jobs[$jn]['ArhParameters'] = $ap
        }
        
        # Маски проверки
        if ($jobNode.SourceCheckMasks) {
            $sm = @()
            foreach ($m in $jobNode.SourceCheckMasks.Mask) { $sm += $m }
            $BackupConfig.Jobs[$jn]['SourceCheckMasks'] = $sm
        }
    }
    
    Write-Host "Конфигурация загружена из XML: $xmlPath" -ForegroundColor Yellow
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
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША (PS 2.0 Compatible)
# ===========================================================
function Get-FileHashCompat {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Algorithm = 'SHA256'
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
        catch { throw "Ошибка вычисления хеша: $($_.Exception.Message)" }
    }
}

if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    New-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}
#endregion

# ===========================================================
#region ФУНКЦИЯ ПРОВЕРКИ ЦЕЛОСТНОСТИ
# ===========================================================
function Test-FileIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [string]$FileType = "Файл"
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-Host "ОШИБКА: Файл не найден: $FilePath" -ForegroundColor Red
        return $false
    }
    try {
        Write-Host "Проверка целостности ($FileType): $FilePath..." -ForegroundColor Cyan
        $actualHash = (Get-FileHash -LiteralPath $FilePath).Hash.ToUpper()
        $expectedHashUpper = $ExpectedHash.ToUpper()

        if ($actualHash -eq $expectedHashUpper) {
            Write-Host "  [OK] Хеш подтвержден." -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Хеш НЕ СОВПАДАЕТ!" -ForegroundColor Red
            return $false
        }
    }
    catch { return $false }
}
#endregion

# ===========================================================
#region ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR
# ===========================================================
Write-Host "`n=== ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR ===" -ForegroundColor Yellow

 $archiverPath = $BackupConfig.Paths.RarPath
 $archiverHash = $BackupConfig.Integrity.RarExeHash

if ([string]::IsNullOrWhiteSpace($archiverPath) -or -not (Test-Path $archiverPath)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: RAR не найден по пути: $archiverPath" -ForegroundColor Red
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($archiverHash)) {
    if (-not (Test-FileIntegrity -FilePath $archiverPath -ExpectedHash $archiverHash -FileType "RAR.exe")) {
        Write-Host "ПРОВЕРКА АРХИВАТОРА ПРОВАЛЕНА." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: Хеш RAR не указан в конфигурации, проверка целостности пропущена." -ForegroundColor Yellow
}

Write-Host "Архиватор проверен: $archiverPath`n" -ForegroundColor Green

#endregion

# ===========================================================
#region МОДУЛЬ ЛОГИРОВАНИЯ (PS 2.0 Compatible)
# ===========================================================
 $Script:LogPath = $null
 $Script:MainLogFile = $null
 $Script:ReportEntries = @()

function Initialize-Logging {
    param([string]$LogPath, [string]$PCName, [string]$JobName)
    try {
        $safePCName = $PCName -replace '[\\/:*?"<>|]', '-'
        $safeJobName = $JobName -replace '[\\/:*?"<>|]', '-'

        if (-not (Test-Path -LiteralPath $LogPath -PathType Container)) {
            New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $logFileName = "${safePCName}_${safeJobName}_${timestamp}.log"
        $fullLogPath = Join-Path -Path $LogPath -ChildPath $logFileName

        $Script:LogPath = $LogPath
        $Script:MainLogFile = $fullLogPath
        
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($fullLogPath, "", $utf8NoBom)
        
        Write-LogSection -Title "СТАРТ"
        Write-Log "Компьютер: $safePCName"
        Write-Log "Задание: $safeJobName"
        return $true
    }
    catch { throw "Ошибка инициализации логирования: $_" }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO',
        [switch]$ResultKey
    )
    try {
        if (-not $Script:MainLogFile) { return }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelPrefix = switch ($Level) {
            'ERROR' { '[ERROR]  ' }
            'WARNING' { '[WARNING]' }
            'SUCCESS' { '[SUCCESS]' }
            default { '[INFO]   ' }
        }
        
        $safeMessage = $Message -replace '\r?\n', ' '
        $logEntry = "[$timestamp] $levelPrefix $safeMessage"
        
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::AppendAllText($Script:MainLogFile, "$logEntry`r`n", $utf8NoBom)
        
        if ($ResultKey) { $Script:ReportEntries += $logEntry }
        
        # Консольный вывод
        switch ($Level) {
            'ERROR' { Write-Host $Message -ForegroundColor Red }
            'WARNING' { Write-Host $Message -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        }
    }
    catch { Write-Error "ОШИБКА ЛОГИРОВАНИЯ: $_" }
}

function Write-LogSection {
    param([string]$Title)
    $line = "========================================"
    if ($Title) {
        Write-Log $line
        Write-Log $Title.ToUpper()
        Write-Log $line
    }
    else {
        Write-Log "----------------------------------------"
    }
}

function Get-LogResults {
    if ($Script:ReportEntries.Count -eq 0) { return "Нет данных." }
    return ($Script:ReportEntries -join "`r`n")
}

function Write-WinEventAppLog {
    param (
        [Parameter(Mandatory)][ValidateSet("Start", "Success", "Warning", "Error", "End")][string]$StatusKey,
        [Parameter(Mandatory)][string]$MessageText,
        [string]$Source = $BackupConfig.General.JobName
    )
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) { return }
        
        $eventIdMap = @{ Start = 3000; Success = 3001; Warning = 3002; Error = 3003; End = 3004 }
        $entryTypeMap = @{
            Start   = [System.Diagnostics.EventLogEntryType]::Information
            Success = [System.Diagnostics.EventLogEntryType]::Information
            Warning = [System.Diagnostics.EventLogEntryType]::Warning
            Error   = [System.Diagnostics.EventLogEntryType]::Error
            End     = [System.Diagnostics.EventLogEntryType]::Information
        }
        
        $eventLog = New-Object System.Diagnostics.EventLog("Application")
        $eventLog.Source = $Source
        $eventLog.WriteEntry($MessageText, $entryTypeMap[$StatusKey], $eventIdMap[$StatusKey])
    }
    catch { Write-Log "Ошибка записи в EventLog: $_" -Level WARNING }
}
#endregion

# ===========================================================
#region МОДУЛЬ RAR ОПЕРАЦИЙ
# ===========================================================
function Get-RarExitCodeMeaning {
    param([int]$ExitCode)
    $errorDescriptions = @{
        0   = "Успешное выполнение"
        1   = "Незначительная ошибка"
        2   = "Критическая ошибка"
        3   = "Ошибка проверки целостности"
        255 = "Прервано пользователем"
    }
    if ($errorDescriptions.ContainsKey($ExitCode)) { return $errorDescriptions[$ExitCode] }
    return "Неизвестный код: $ExitCode"
}

function Start-RarArchive {
    param(
        [Parameter(Mandatory = $true)][string]$RarPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string[]]$Parameters = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t"),
        [string]$LogPath,
        [string]$SourceFilter
    )

    begin {
        $actualLogPath = $null
        if (-not [string]::IsNullOrEmpty($LogPath)) {
            $logDir = Split-Path $LogPath -Parent
            if ((-not [string]::IsNullOrEmpty($logDir)) -and (-not (Test-Path $logDir))) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            $actualLogPath = $LogPath
        }

        $argsList = @($Parameters)
        if ($actualLogPath) { $argsList += '-ilog"' + $actualLogPath + '"' }

        $safeArchivePath = '"' + ($ArchivePath -replace '"', '\"') + '"'
        
        if (-not [string]::IsNullOrWhiteSpace($SourceFilter)) {
            $filteredPath = Join-Path -Path $SourcePath -ChildPath $SourceFilter
            $safeSourcePath = '"' + ($filteredPath -replace '"', '\"') + '"'
        }
        else {
            $safeSourcePath = '"' + ($SourcePath -replace '"', '\"') + '"'
        }
        
        $argsList += @($safeArchivePath, $safeSourcePath)
    }

    process {
        $processStart = Get-Date
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $RarPath
            $psi.Arguments = $argsList -join ' '
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = $Script:EncodingOEM
            $psi.StandardErrorEncoding = $Script:EncodingOEM

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null

            $null = $process.StandardOutput.ReadToEnd()
            $null = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $exitCode = $process.ExitCode

            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)

            $archiveSizeMB = 0
            if (-not [string]::IsNullOrEmpty($ArchivePath) -and (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
                try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch {}
            }

            return @{
                ExitCode    = $exitCode
                Duration    = $duration
                ArchiveSize = $archiveSizeMB
                LogPath     = $actualLogPath
            }
        }
        catch {
            return @{ ExitCode = 255; Duration = 0; Exception = $_.Exception }
        }
    }
}

function Test-RarArchive {
    param([string]$RarPath, [string]$ArchivePath)
    $testArgs = @("t", "`"$ArchivePath`"")
    Write-Log "Проверка целостности RAR: $ArchivePath"
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RarPath
    $psi.Arguments = $testArgs -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = $Script:EncodingOEM
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
    $null = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    
    return @{ ExitCode = $process.ExitCode; IsValid = ($process.ExitCode -eq 0) }
}
#endregion

# ===========================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (PS 2.0 Compatible)
# ===========================================================

# Функция получения списка файлов (без -File параметра)
function Get-FileList {
    param([string]$Path)
    $rootPath = (Resolve-Path -LiteralPath $Path).Path
    if ($rootPath.EndsWith('\')) { $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) }
    
    try {
        # PS 2.0: Используем Where-Object вместо -File
        $items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue | 
                 Where-Object { -not $_.PSIsContainer }
        
        foreach ($item in $items) {
            $relative = $item.FullName.Substring($rootPath.Length).TrimStart('\')
            
            # PS 2.0: Проверка ReparsePoint через битную маску
            $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
            if ($isReparse) { continue }
            
            New-Object PSObject -Property @{
                RelativePath  = $relative
                Length        = $item.Length
                LastWriteTime = $item.LastWriteTime
                FullName      = $item.FullName
            }
        }
    }
    catch { Write-Error "Ошибка сканирования: $_" }
}

function Get-FilterFileList {
    param([string]$Path, [string]$Filter)
    $allFiles = Get-FileList -Path $Path
    if ($allFiles.Count -eq 0) { return @() }
    
    $filtered = $allFiles | Where-Object {
        $name = Split-Path -Path $_.RelativePath -Leaf
        $name -like $Filter
    }
    return $filtered
}

function Get-FileArhListRar {
    param([string]$RarPath, [string]$ArchivePath)
    Write-Verbose "Чтение RAR: $ArchivePath"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $RarPath
        $psi.Arguments = "vtb -cfg- `"$ArchivePath`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.StandardOutputEncoding = $Script:EncodingOEM

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) { return @() }

        # Простой парсинг вывода RAR vtb
        $files = @()
        $lines = $stdout -split "`r?`n"
        
        foreach ($line in $lines) {
            # Простая эвристика для PS 2.0: ищем строки с данными
            # Это сильно упрощенный парсер по сравнению с оригиналом, но надежный для базовых случаев
            if ($line -match '^\s+Name:\s*(.+)$') {
                $files += New-Object PSObject -Property @{ RelativePath = $matches[1].Trim(); Length = 0 }
            }
        }
        return $files
    }
    catch { return @() }
}

function Compare-FilesSourceArchive {
    param($SourceList, $ArchiveList)
    
    # Простое сравнение количества и имен
    $sourceCount = ($SourceList | Measure-Object).Count
    $archiveCount = ($ArchiveList | Measure-Object).Count
    
    $report = "Source: $sourceCount, Archive: $archiveCount"
    $isIdentical = $true
    
    if ($sourceCount -ne $archiveCount) {
        $isIdentical = $false
        $report += " [MISMATCH]"
    }
    
    return New-Object PSObject -Property @{
        IsIdentical = $isIdentical
        Report      = $report
    }
}

function Get-FileInfoDetails {
    param([string]$Path)
    try {
        # PS 2.0 fix: Where-Object
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $fileCount = ($items | Measure-Object).Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
        
        return @{
            FileCount   = $fileCount
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
        }
    }
    catch { return @{ FileCount = 0; TotalSizeMB = 0 } }
}

function Copy-BackupFile {
    param([string]$SourcePath, [string]$DestinationPath)
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $duration = [math]::Round(((Get-Date) - $copyStart).TotalSeconds, 2)
    
    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length
    
    return @{ Success = ($sourceSize -eq $destSize); Duration = $duration }
}

function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)
    
    if (-not (Test-Path -Path $Path -PathType Container)) { return }
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        # PS 2.0 fix: Where-Object
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -ErrorAction Stop | 
                      Where-Object { -not $_.PSIsContainer } | 
                      Sort-Object LastWriteTime -Descending)

        $filesToKeep = $allFiles | Select-Object -First $KeepCount
        
        $filesToDelete = $allFiles | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and 
            ($filesToKeep -eq $null -or $filesToKeep.FullName -notcontains $_.FullName)
        }

        foreach ($file in $filesToDelete) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Удален: $($file.Name)"
        }
    }
    catch { Write-Log "Ошибка ротации: $_" -Level WARNING }
}

function Get-DiskSpaceReport {
    # PS 2.0 fix: Get-WmiObject вместо Get-CimInstance
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
                 Where-Object { $_.Size -gt 1GB } | Sort-Object DeviceID
        
        $result = ""
        foreach ($d in $disks) {
            $freeP = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
            $result += "{0}({1:N0}GB/{2:N0}GB/{3}%) " -f $d.DeviceID, ($d.Size/1GB), ($d.FreeSpace/1GB), $freeP
        }
        return $result.Trim()
    }
    catch { return "Ошибка дисков" }
}
#endregion

# ===========================================================
#region МОДУЛЬ ОТПРАВКИ ПОЧТЫ
# ===========================================================
function Send-Email {
    param([string]$SmtpServer, [string]$From, [string]$To, [string]$Subject, [string]$Body)
    try {
        # PS 2.0 compatible
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer)
        $msg = New-Object Net.Mail.MailMessage($From, $To, $Subject, $Body)
        $msg.BodyEncoding = [System.Text.Encoding]::UTF8
        $smtp.Send($msg)
        return $true
    }
    catch {
        Write-Host "Ошибка отправки почты: $_" -ForegroundColor Red
        return $false
    }
}
#endregion

# ===========================================================
#region ЭТАП 2: ОСНОВНОЙ ЗАПУСК
# ===========================================================
 $PCName = $env:COMPUTERNAME
 $ParentJobName = $BackupConfig.General.JobName
 $NameDomain = $BackupConfig.General.Domain
 $PCNameMail = "$PCName@$NameDomain"
 $SmtpServer = $BackupConfig.General.SmtpServer
 $LogDaysOld = $BackupConfig.General.LogDaysOld
 $LogKeepCount = $BackupConfig.General.LogKeepCount
 $AdminIS = $BackupConfig.Recipients.AdminIS
 $AdminOS = $BackupConfig.Recipients.AdminOS
 $AdminMail = $BackupConfig.Recipients.AdminMail

# ТЕСТОВЫЙ РЕЖИМ
if ($TestMode) {
    Write-Host "`n=== РЕЖИМ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    $errors = @()
    
    if (-not (Test-Path $archiverPath)) { $errors += "RAR не найден" }
    foreach ($jn in $BackupConfig.Jobs.Keys) {
        $j = $BackupConfig.Jobs[$jn]
        if (-not (Test-Path $j.Source)) { $errors += "Источник $jn недоступен" }
    }
    
    if ($errors.Count -eq 0) { Write-Host "Тест пройден успешно." -ForegroundColor Green; exit 0 }
    else { Write-Host "Ошибки:`n$($errors -join '`n')" -ForegroundColor Red; exit 1 }
}

# ИНИЦИАЛИЗАЦИЯ
try {
    Initialize-Logging -LogPath $config.Settings.LogPath -PCName $PCName -JobName $ParentJobName
}
catch {
    Write-Host "FATAL: $_" -ForegroundColor Red
    exit 1
}

Write-LogSection -Title "ЗАПУСК RAR BACKUP"
Write-Log "Конфигурация: $Script:ConfigPath" -ResultKey
Write-WinEventAppLog -StatusKey "Start" -MessageText "Запуск: $ParentJobName"

 $results = @{}
 $successCount = 0
 $errorCount = 0
 $scriptStartTime = Get-Date

# ЦИКЛ ЗАДАНИЙ
foreach ($jobName in $BackupConfig.Jobs.Keys) {
    $job = $BackupConfig.Jobs[$jobName]
    $jobStart = Get-Date

    Write-LogSection -Title "ЗАДАНИЕ: $jobName" -ResultKey
    Write-Log "Source: $($job.Source)" -ResultKey
    Write-Log "Dest: $($job.LocalDest)"

    try {
        # Проверки
        if (-not (Test-Path $job.Source)) { throw "Источник не существует" }
        
        # Создание папок
        if (-not (Test-Path $job.LocalDest)) {
            New-Item -Path $job.LocalDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        if ($job.RemoteDest -and (-not (Test-Path $job.RemoteDest))) {
            New-Item -Path $job.RemoteDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $fileInfo = Get-FileInfoDetails -Path $job.Source
        Write-Log "Файлов: $($fileInfo.FileCount), Размер: $($fileInfo.TotalSizeMB) MB" -ResultKey

        # Формирование имени архива
        $currentDate = Get-Date -Format 'yyyyMMdd'
        $currentTime = Get-Date -Format 'HHmmss'
        $archiveName = $job.ArchivePattern
        if ([string]::IsNullOrWhiteSpace($archiveName)) { $archiveName = "{PCName}_{JobName}_{Date}.rar" }
        
        $archiveName = $archiveName -replace '{PCName}', $PCName
        $archiveName = $archiveName -replace '{JobName}', $jobName
        $archiveName = $archiveName -replace '{Date}', $currentDate
        $archiveName = $archiveName -replace '{Time}', $currentTime
        $archiveName = $archiveName -replace '{Date_Time}', "${currentDate}_${currentTime}"
        
        # Гарантируем расширение .rar
        if (-not $archiveName.EndsWith('.rar')) { $archiveName += '.rar' }
        
        $archivePath = Join-Path $job.LocalDest $archiveName
        Write-Log "Архив: $archiveName" -ResultKey

        # Параметры RAR
        $rarParams = $job.ArhParameters
        if ($rarParams -eq $null) { $rarParams = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t") }

        # Лог архиватора
        $rarLog = $null
        if ($job.ArhLog) { $rarLog = Join-Path $job.LocalDest "$jobName.rar.log" }

        # АРХИВАЦИЯ
        Write-Log "Запуск RAR..." -ResultKey
        $arhResult = Start-RarArchive -RarPath $archiverPath -ArchivePath $archivePath -SourcePath $job.Source -Parameters $rarParams -LogPath $rarLog -SourceFilter $job.SourceFilter
        
        Write-Log "Код возврата: $($arhResult.ExitCode), Время: $($arhResult.Duration) мин" -ResultKey

        if ($arhResult.ExitCode -ne 0) {
            throw "Ошибка RAR: $(Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode)"
        }
        if (-not (Test-Path $archivePath)) { throw "Архив не создан" }
        
        Write-Log "Размер архива: $($arhResult.ArchiveSize) MB" -ResultKey

        # Проверка целостности (Test)
        $testRes = Test-RarArchive -RarPath $archiverPath -ArchivePath $archivePath
        if (-not $testRes.IsValid) { throw "Ошибка теста архива" }
        Write-Log "Тест архива: OK" -ResultKey

        # Верификация содержимого (сравнение списков)
        $srcFiles = Get-FileList -Path $job.Source
        $archFiles = Get-FileArhListRar -RarPath $archiverPath -ArchivePath $archivePath
        $verify = Compare-FilesSourceArchive -SourceList $srcFiles -ArchiveList $archFiles
        
        if (-not $verify.IsIdentical) {
            Write-Log "Внимание: Несовпадение списка файлов. $($verify.Report)" -Level WARNING -ResultKey
        } else {
            Write-Log "Верификация: OK" -ResultKey
        }

        # Копирование в сеть
        if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            $remotePath = Join-Path $job.RemoteDest $archiveName
            Write-Log "Копирование в: $remotePath"
            $copyRes = Copy-BackupFile -SourcePath $archivePath -DestinationPath $remotePath
            if ($copyRes.Success) {
                Write-Log "Копирование: OK" -ResultKey
            } else {
                throw "Ошибка копирования (размер не совпадает)"
            }
        }

        # Ротация
        Write-Log "Ротация..."
        # Ротация локального назначения
        Remove-OldFiles -Path $job.LocalDest -DaysOld $job.LocalDestDaysOld -KeepCount $job.LocalDestKeepCount -Filter "*.rar"
        # Ротация сети
        if ($job.RemoveRemoteDestFlag -and $job.RemoteDest) {
            Remove-OldFiles -Path $job.RemoteDest -DaysOld $job.RemoteDestDaysOld -KeepCount $job.RemoteDestKeepCount -Filter "*.rar"
        }
        # Ротация источника
        if ($job.RemoveSourceFlag) {
            Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount $job.SourceKeepCount -Filter "*.*"
        }

        $results[$jobName] = "Успешно"
        $successCount++
    }
    catch {
        Write-Log "ОШИБКА: $_" -Level ERROR
        $results[$jobName] = "Ошибка: $_"
        $errorCount++
    }
    
    $jobDur = [math]::Round(((Get-Date) - $jobStart).TotalMinutes, 2)
    Write-Log "Завершено за $jobDur мин." -ResultKey
}

# ФИНАЛ
Write-LogSection -Title "ИТОГИ"
 $totalDur = [math]::Round(((Get-Date) - $scriptStartTime).TotalMinutes, 2)
Write-Log "Всего: $totalDur мин. Успешно: $successCount, Ошибок: $errorCount" -ResultKey
Write-Log "Диски: $(Get-DiskSpaceReport)" -ResultKey

 $DiskSpaceInfo = Get-DiskSpaceReport
 $EmailBody = Get-LogResults
 $EmailBody += "`n`nДиски: $DiskSpaceInfo"

 $Subject = "$PCName $ParentJobName : " + $(if ($errorCount -gt 0) { "ОШИБКИ" } else { "УСПЕХ" })
 $To = if ($errorCount -gt 0) { "$AdminIS, $AdminOS" } else { $AdminIS }

Write-WinEventAppLog -StatusKey $(if ($errorCount -gt 0) { "Error" } else { "Success" }) -MessageText "Завершено. Ошибок: $errorCount"

if (-not [string]::IsNullOrWhiteSpace($SmtpServer)) {
    Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $To -Subject $Subject -Body $EmailBody
}

# Очистка логов
Remove-OldFiles -Path $config.Settings.LogPath -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.log"

if ($errorCount -gt 0) { exit 1 } else { exit 0 }