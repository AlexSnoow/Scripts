<#
.SYNOPSIS
    File Backup-rar-ps2-qw3.ps1
    Автономный скрипт резервного копирования (RAR Only, PS 2.0 Compatible)
.DESCRIPTION
    Единый файл для резервного копирования с использованием WinRAR.
    Версия: 100% совместимость с PowerShell 2.0 (.NET 3.5)
    Конфигурация загружается из Backup-Config-All.xml

    Поддерживаемые переменные для ArchivePattern:
    - {PCName} - Имя компьютера
    - {JobName} - Имя задания
    - {Date} - Дата в формате YYYYMMDD
    - {Time} - Время в формате HHMMSS
    - {Date_Time} - Дата и время в формате YYYYMMDD_HHMMSS

    Поддерживаемые режимы заданий:
    - Стандартная архивация (все файлы из Source)
    - Индивидуальная архивация каталогов (ArchiveIndividualFolders)
    - Индивидуальная архивация файлов по маске (ArchiveIndividualFiles)

.PARAMETER TestMode
    Запуск проверки конфигурации без выполнения архивации.

.EXAMPLE
    powershell.exe -executionpolicy RemoteSigned -file .\Backup-rar-ps2-qw3.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ===========================================================

if (-not (Test-Path variable:PSScriptRoot)) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false

Clear-Host

function IsNullOrWhiteSpace {
    param([string]$str)
    return ($null -eq $str) -or ($str.Trim().Length -eq 0)
}

# ===========================================================
#region CONFIG_BLOCK (XML)
# ===========================================================

$xmlPath = Join-Path $PSScriptRoot "Backup-Config-All.xml"
$Script:ConfigPath = $xmlPath

if (-not (Test-Path $xmlPath)) {
    $xmlPathAlt = Join-Path (Split-Path $PSScriptRoot -Parent) "common\Backup-Config-All.xml"
    if (Test-Path $xmlPathAlt) {
        $xmlPath = $xmlPathAlt
        $Script:ConfigPath = $xmlPath
    }
    else {
        Write-Host "КРИТИЧЕСКАЯ ОШИБКА: XML конфигурация не найдена: $xmlPath" -ForegroundColor Red
        exit 1
    }
}

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

    $defaultRarParams = @()
    foreach ($p in $b.General.DefaultRarParameters.Param) {
        $defaultRarParams += $p
    }
    $BackupConfig['DefaultRarParams'] = $defaultRarParams

    foreach ($jobNode in $b.Jobs.Job) {
        $jn = $jobNode.Name
        $job = @{
            Name                     = $jn
            Source                   = $jobNode.Source
            LocalDest                = $jobNode.LocalDest
            RemoteDest               = $jobNode.RemoteDest
            ArchivePattern           = $jobNode.ArchivePattern
            RemoveSourceFlag         = ($jobNode.RemoveSourceFlag -eq 'true')
            SourceDaysOld            = [int]$jobNode.SourceDaysOld
            SourceKeepCount          = [int]$jobNode.SourceKeepCount
            LocalDestDaysOld         = [int]$jobNode.LocalDestDaysOld
            LocalDestKeepCount       = [int]$jobNode.LocalDestKeepCount
            RemoveRemoteDestFlag     = ($jobNode.RemoveRemoteDestFlag -eq 'true')
            ArhLog                   = ($jobNode.ArhLog -eq 'true')
            ArchiveIndividualFiles   = ($jobNode.ArchiveIndividualFiles -eq 'true')
            ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
        }

        if ($jobNode.ListSourceFlag) {
            $job['ListSourceFlag'] = $jobNode.ListSourceFlag
        }

        if ($jobNode.FileFilter) {
            $job['FileFilter'] = $jobNode.FileFilter
        }

        if ($jobNode.ExcludeFilePattern) {
            $job['ExcludeFilePattern'] = $jobNode.ExcludeFilePattern
        }

        if ($jobNode.ExcludeFolderPattern) {
            $job['ExcludeFolderPattern'] = $jobNode.ExcludeFolderPattern
        }

        if ($jobNode.IndividualArchivePattern) {
            $job['IndividualArchivePattern'] = $jobNode.IndividualArchivePattern
        }

        if ($jobNode.ArhParameters) {
            $ap = @()
            foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
            $job['ArhParameters'] = $ap
        }

        if ($jobNode.SourceCheckMasks) {
            $sm = @()
            foreach ($m in $jobNode.SourceCheckMasks.Mask) { $sm += $m }
            $job['SourceCheckMasks'] = $sm
        }

        $BackupConfig.Jobs[$jn] = $job
    }

    Write-Host "Конфигурация загружена из XML: $xmlPath" -ForegroundColor Yellow
}
catch {
    Write-Host "ОШИБКА ЗАГРУЗКИ XML: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

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
#region SHA256 HASH (PS 2.0 Compatible)
# ===========================================================
function Get-FileHashCompat {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Файл не найден: $Path"
        }

        $hashAlgo = [System.Security.Cryptography.SHA256]::Create()
        $fileStream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $hashAlgo.ComputeHash($fileStream)
            $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
            $result = New-Object PSObject -Property @{
                Hash = $hashString.ToUpper()
                Path = $Path
            }
            return $result
        }
        finally {
            $fileStream.Close()
            $hashAlgo.Clear()
        }
    }
}

if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    New-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}
#endregion

# ===========================================================
#region INTEGRITY CHECK
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
        $actualHash = (Get-FileHash -Path $FilePath).Hash.ToUpper()
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

if (IsNullOrWhiteSpace $archiverPath) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Путь к RAR не указан в конфигурации." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $archiverPath)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: RAR не найден по пути: $archiverPath" -ForegroundColor Red
    exit 1
}

if (-not (IsNullOrWhiteSpace $archiverHash)) {
    if (-not (Test-FileIntegrity -FilePath $archiverPath -ExpectedHash $archiverHash -FileType "RAR.exe")) {
        Write-Host "ПРОВЕРКА АРХИВАТОРА ПРОВАЛЕНА." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Архиватор проверен: $archiverPath`n" -ForegroundColor Green
#endregion

# ===========================================================
#region LOGGING (PS 2.0 Compatible)
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

        [System.IO.File]::WriteAllText($fullLogPath, "", $Script:EncodingUTF8NoBOM)

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
            'ERROR'   { '[ERROR]  ' }
            'WARNING' { '[WARNING]' }
            'SUCCESS' { '[SUCCESS]' }
            default   { '[INFO]   ' }
        }

        $safeMessage = $Message -replace '\r?\n', ' '
        $logEntry = "[$timestamp] $levelPrefix $safeMessage"

        [System.IO.File]::AppendAllText($Script:MainLogFile, "$logEntry`r`n", $Script:EncodingUTF8NoBOM)

        if ($ResultKey) {
            $Script:ReportEntries += $logEntry
        }

        switch ($Level) {
            'ERROR'   { Write-Host $Message -ForegroundColor Red }
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
        [Parameter(Mandatory)][string]$StatusKey,
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
#region RAR OPERATIONS
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
        [string[]]$Parameters = @("a", "-m5", "-s", "-ep1", "-dh", "-rr1p", "-r"),
        [string]$LogPath,
        [string]$SourceFilter
    )

    $actualLogPath = $null
    if (-not (IsNullOrWhiteSpace $LogPath)) {
        $logDir = Split-Path $LogPath -Parent
        if (-not (IsNullOrWhiteSpace $logDir) -and (-not (Test-Path $logDir))) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $actualLogPath = $LogPath
    }

    $argsList = @($Parameters)
    if ($actualLogPath) { $argsList += '-ilog"' + $actualLogPath + '"' }

    $safeArchivePath = '"' + ($ArchivePath -replace '"', '\"') + '"'

    if (-not (IsNullOrWhiteSpace $SourceFilter)) {
        $filteredPath = Join-Path -Path $SourcePath -ChildPath $SourceFilter
        $safeSourcePath = '"' + ($filteredPath -replace '"', '\"') + '"'
    }
    else {
        $safeSourcePath = '"' + ($SourcePath -replace '"', '\"') + '"'
    }

    $argsList += @($safeArchivePath, $safeSourcePath)

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
        if (-not (IsNullOrWhiteSpace $ArchivePath) -and (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
            try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch {}
        }

        $result = New-Object PSObject -Property @{
            ExitCode    = $exitCode
            Duration    = $duration
            ArchiveSize = $archiveSizeMB
            LogPath     = $actualLogPath
        }
        return $result
    }
    catch {
        $result = New-Object PSObject -Property @{
            ExitCode = 255
            Duration = 0
        }
        return $result
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

    $result = New-Object PSObject -Property @{
        ExitCode = $process.ExitCode
        IsValid  = ($process.ExitCode -eq 0)
    }
    return $result
}
#endregion

# ===========================================================
#region HELPER FUNCTIONS (PS 2.0 Compatible)
# ===========================================================

function Get-FileList {
    param([string]$Path)
    $rootPath = (Resolve-Path -LiteralPath $Path).Path
    if ($rootPath.EndsWith('\')) { $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) }

    try {
        $items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue |
                 Where-Object { -not $_.PSIsContainer }

        foreach ($item in $items) {
            $relative = $item.FullName.Substring($rootPath.Length).TrimStart('\')

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
    return @($filtered)
}

function Get-FileArhListRar {
    param([string]$RarPath, [string]$ArchivePath)
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

        $files = @()
        $lines = $stdout -split "`r?`n"

        foreach ($line in $lines) {
            if ($line -match '^\s+Name:\s*(.+)$') {
                $obj = New-Object PSObject -Property @{
                    RelativePath = $matches[1].Trim()
                    Length       = 0
                }
                $files += $obj
            }
        }
        return $files
    }
    catch { return @() }
}

function Compare-FilesSourceArchive {
    param($SourceList, $ArchiveList)

    $sourceCount = ($SourceList | Measure-Object).Count
    $archiveCount = ($ArchiveList | Measure-Object).Count

    $report = "Source: $sourceCount, Archive: $archiveCount"
    $isIdentical = $true

    if ($sourceCount -ne $archiveCount) {
        $isIdentical = $false
        $report += " [MISMATCH]"
    }

    New-Object PSObject -Property @{
        IsIdentical = $isIdentical
        Report      = $report
    }
}

function Get-FileInfoDetails {
    param([string]$Path)
    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $fileCount = ($items | Measure-Object).Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum

        $result = New-Object PSObject -Property @{
            FileCount   = $fileCount
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
        }
        return $result
    }
    catch {
        $result = New-Object PSObject -Property @{
            FileCount   = 0
            TotalSizeMB = 0
        }
        return $result
    }
}

function Copy-BackupFile {
    param([string]$SourcePath, [string]$DestinationPath)
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $duration = [math]::Round(((Get-Date) - $copyStart).TotalSeconds, 2)

    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length

    New-Object PSObject -Property @{
        Success  = ($sourceSize -eq $destSize)
        Duration = $duration
    }
}

function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)

    if (-not (Test-Path -Path $Path -PathType Container)) { return }

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -ErrorAction Stop |
                      Where-Object { -not $_.PSIsContainer } |
                      Sort-Object LastWriteTime -Descending)

        if ($KeepCount -gt 0 -and $allFiles.Count -gt $KeepCount) {
            $filesToKeep = $allFiles | Select-Object -First $KeepCount
        }
        else {
            $filesToKeep = @()
        }

        $filesToDelete = @()
        foreach ($file in $allFiles) {
            if ($file.LastWriteTime -lt $cutoffDate) {
                $keep = $false
                foreach ($keepFile in $filesToKeep) {
                    if ($keepFile.FullName -eq $file.FullName) {
                        $keep = $true
                        break
                    }
                }
                if (-not $keep) {
                    $filesToDelete += $file
                }
            }
        }

        foreach ($file in $filesToDelete) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Удален: $($file.Name)"
        }
    }
    catch { Write-Log "Ошибка ротации: $_" -Level WARNING }
}

function Get-DiskSpaceReport {
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

function Expand-Pattern {
    param([string]$Pattern, [string]$PCName, [string]$JobName, [string]$Date, [string]$Time, [string]$Extra = "")

    $name = $Pattern
    $name = $name -replace '\{PCName\}', $PCName
    $name = $name -replace '\{JobName\}', $JobName
    $name = $name -replace '\{Date\}', $Date
    $name = $name -replace '\{Time\}', $Time
    $name = $name -replace '\{Date_Time\}', "${Date}_${Time}"
    if (-not (IsNullOrWhiteSpace $Extra)) {
        $name = $name -replace '\{SourceFolderName\}', $Extra
        $name = $name -replace '\{SourceFileName\}', $Extra
    }
    if (-not $name.EndsWith('.rar')) { $name += '.rar' }
    return $name
}
#endregion

# ===========================================================
#region EMAIL
# ===========================================================
function Send-Email {
    param([string]$SmtpServer, [string]$From, [string]$To, [string]$Subject, [string]$Body)
    try {
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
#region INDIVIDUAL FOLDER ARCHIVE
# ===========================================================
function Invoke-IndividualFolderArchive {
    param(
        $Job,
        [string]$PCName,
        [string]$ArchiverPath,
        [string]$CurrentDate,
        [string]$CurrentTime
    )

    $sourceDir = $Job.Source
    if (-not (Test-Path $sourceDir)) { return @() }

    $subFolders = Get-ChildItem -Path $sourceDir -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.PSIsContainer }

    $excludePattern = $null
    if ($Job.ContainsKey('ExcludeFolderPattern')) {
        $excludePattern = $Job['ExcludeFolderPattern']
    }

    $pattern = $Job.ArchivePattern
    if ($Job.ContainsKey('IndividualArchivePattern') -and (-not (IsNullOrWhiteSpace $Job['IndividualArchivePattern']))) {
        $pattern = $Job['IndividualArchivePattern']
    }

    $rarParams = $BackupConfig.DefaultRarParams
    if ($Job.ContainsKey('ArhParameters')) {
        $rarParams = $Job['ArhParameters']
    }

    $jobResults = @()

    foreach ($subFolder in $subFolders) {
        if (-not (IsNullOrWhiteSpace $excludePattern)) {
            if ($subFolder.Name -like $excludePattern) {
                Write-Log "Пропуск (exclude): $($subFolder.Name)" -Level WARNING
                continue
            }
        }

        $archiveName = Expand-Pattern -Pattern $pattern -PCName $PCName -JobName $Job.Name -Date $CurrentDate -Time $CurrentTime -Extra $subFolder.Name
        $archivePath = Join-Path $Job.LocalDest $archiveName

        Write-Log "Архивация папки: $($subFolder.Name) -> $archiveName"

        $rarLog = $null
        if ($Job.ArhLog) {
            $rarLog = Join-Path $Job.LocalDest "$($Job.Name)_$($subFolder.Name).rar.log"
        }

        $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $subFolder.FullName -Parameters $rarParams -LogPath $rarLog

        $folderResult = New-Object PSObject -Property @{
            FolderName   = $subFolder.Name
            ArchivePath  = $archivePath
            ExitCode     = $arhResult.ExitCode
            Duration     = $arhResult.Duration
            ArchiveSize  = $arhResult.ArchiveSize
            Success      = ($arhResult.ExitCode -eq 0)
        }
        $jobResults += $folderResult

        if ($arhResult.ExitCode -ne 0) {
            Write-Log "Ошибка RAR для $($subFolder.Name): $(Get-RarExitCodeMeaning $arhResult.ExitCode)" -Level ERROR
        }
        else {
            Write-Log "Размер: $($arhResult.ArchiveSize) MB"
        }
    }

    return $jobResults
}
#endregion

# ===========================================================
#region INDIVIDUAL FILE ARCHIVE
# ===========================================================
function Invoke-IndividualFileArchive {
    param(
        $Job,
        [string]$PCName,
        [string]$ArchiverPath,
        [string]$CurrentDate,
        [string]$CurrentTime
    )

    $sourceDir = $Job.Source
    if (-not (Test-Path $sourceDir)) { return @() }

    $fileFilter = "*"
    if ($Job.ContainsKey('FileFilter') -and (-not (IsNullOrWhiteSpace $Job['FileFilter']))) {
        $fileFilter = $Job['FileFilter']
    }

    $excludePattern = $null
    if ($Job.ContainsKey('ExcludeFilePattern')) {
        $excludePattern = $Job['ExcludeFilePattern']
    }

    $pattern = $Job.ArchivePattern
    if ($Job.ContainsKey('IndividualArchivePattern') -and (-not (IsNullOrWhiteSpace $Job['IndividualArchivePattern']))) {
        $pattern = $Job['IndividualArchivePattern']
    }

    $rarParams = $BackupConfig.DefaultRarParams
    if ($Job.ContainsKey('ArhParameters')) {
        $rarParams = $Job['ArhParameters']
    }

    $files = Get-ChildItem -Path $sourceDir -Filter $fileFilter -Force -ErrorAction SilentlyContinue |
             Where-Object { -not $_.PSIsContainer }

    $jobResults = @()

    foreach ($file in $files) {
        if (-not (IsNullOrWhiteSpace $excludePattern)) {
            if ($file.Name -like $excludePattern) {
                Write-Log "Пропуск (exclude): $($file.Name)" -Level WARNING
                continue
            }
        }

        $baseName = $file.Name
        $archiveName = Expand-Pattern -Pattern $pattern -PCName $PCName -JobName $Job.Name -Date $CurrentDate -Time $CurrentTime -Extra $baseName
        $archivePath = Join-Path $Job.LocalDest $archiveName

        Write-Log "Архивация файла: $($file.Name) -> $archiveName"

        $rarLog = $null
        if ($Job.ArhLog) {
            $rarLog = Join-Path $Job.LocalDest "$($Job.Name)_$($baseName).rar.log"
        }

        $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $file.FullName -Parameters $rarParams -LogPath $rarLog

        $fileResult = New-Object PSObject -Property @{
            FileName    = $file.Name
            ArchivePath = $archivePath
            ExitCode    = $arhResult.ExitCode
            Duration    = $arhResult.Duration
            ArchiveSize = $arhResult.ArchiveSize
            Success     = ($arhResult.ExitCode -eq 0)
        }
        $jobResults += $fileResult

        if ($arhResult.ExitCode -ne 0) {
            Write-Log "Ошибка RAR для $($file.Name): $(Get-RarExitCodeMeaning $arhResult.ExitCode)" -Level ERROR
        }
        else {
            Write-Log "Размер: $($arhResult.ArchiveSize) MB"
        }
    }

    return $jobResults
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
        if (-not (Test-Path $j.Source)) { $errors += "Источник $jn недоступен: $($j.Source)" }
        if (-not (Test-Path $j.LocalDest)) {
            $parentDest = Split-Path $j.LocalDest -Parent
            if (-not (Test-Path $parentDest)) {
                $errors += "Родительская папка Dest $jn недоступен"
            }
        }
    }

    if ($errors.Count -eq 0) {
        Write-Host "Тест пройден успешно." -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "Ошибки:" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "  - $e" -ForegroundColor Red }
        exit 1
    }
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

$currentDate = Get-Date -Format 'yyyyMMdd'
$currentTime = Get-Date -Format 'HHmmss'

# ЦИКЛ ЗАДАНИЙ
foreach ($jobName in $BackupConfig.Jobs.Keys) {
    $job = $BackupConfig.Jobs[$jobName]
    $jobStart = Get-Date

    Write-LogSection -Title "ЗАДАНИЕ: $jobName" -ResultKey
    Write-Log "Source: $($job.Source)" -ResultKey
    Write-Log "Dest: $($job.LocalDest)"

    try {
        if (-not (Test-Path $job.Source)) { throw "Источник не существует: $($job.Source)" }

        if (-not (Test-Path $job.LocalDest)) {
            New-Item -Path $job.LocalDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        if ($job.RemoteDest -and (-not (Test-Path $job.RemoteDest))) {
            New-Item -Path $job.RemoteDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $fileInfo = Get-FileInfoDetails -Path $job.Source
        Write-Log "Файлов: $($fileInfo.FileCount), Размер: $($fileInfo.TotalSizeMB) MB" -ResultKey

        $indivFolders = $false
        if ($job.ContainsKey('ArchiveIndividualFolders')) {
            $indivFolders = $job['ArchiveIndividualFolders']
        }
        $indivFiles = $false
        if ($job.ContainsKey('ArchiveIndividualFiles')) {
            $indivFiles = $job['ArchiveIndividualFiles']
        }

        if ($indivFolders) {
            $folderResults = Invoke-IndividualFolderArchive -Job $job -PCName $PCName -ArchiverPath $archiverPath -CurrentDate $currentDate -CurrentTime $currentTime

            $allSuccess = $true
            foreach ($fr in $folderResults) {
                if (-not $fr.Success) { $allSuccess = $false; break }
            }

            if ($folderResults.Count -eq 0) {
                Write-Log "Нет подкаталогов для архивации." -Level WARNING
            }
            else {
                $successFolders = 0
                $errorFolders = 0
                foreach ($fr in $folderResults) {
                    if ($fr.Success) { $successFolders++ } else { $errorFolders++ }

                    if ($fr.Success -and (Test-Path $fr.ArchivePath)) {
                        $testRes = Test-RarArchive -RarPath $archiverPath -ArchivePath $fr.ArchivePath
                        if (-not $testRes.IsValid) {
                            Write-Log "Тест архива FAILED: $($fr.ArchivePath)" -Level ERROR
                            $allSuccess = $false
                        }
                    }

                    if ($fr.Success -and $job.RemoteDest -and (Test-Path $job.RemoteDest)) {
                        $archiveBaseName = Split-Path $fr.ArchivePath -Leaf
                        $remotePath = Join-Path $job.RemoteDest $archiveBaseName
                        Write-Log "Копирование в: $remotePath"
                        $copyRes = Copy-BackupFile -SourcePath $fr.ArchivePath -DestinationPath $remotePath
                        if (-not $copyRes.Success) {
                            Write-Log "Ошибка копирования: $remotePath" -Level WARNING
                        }
                    }
                }
                Write-Log "Папок успешно: $successFolders, ошибок: $errorFolders" -ResultKey
                if (-not $allSuccess) { throw "Ошибки при индивидуальной архивации папок" }
            }
        }
        elseif ($indivFiles) {
            $fileResults = Invoke-IndividualFileArchive -Job $job -PCName $PCName -ArchiverPath $archiverPath -CurrentDate $currentDate -CurrentTime $currentTime

            $allSuccess = $true
            foreach ($fr in $fileResults) {
                if (-not $fr.Success) { $allSuccess = $false; break }
            }

            if ($fileResults.Count -eq 0) {
                Write-Log "Нет файлов по маске для архивации." -Level WARNING
            }
            else {
                $successFiles = 0
                $errorFiles = 0
                foreach ($fr in $fileResults) {
                    if ($fr.Success) { $successFiles++ } else { $errorFiles++ }

                    if ($fr.Success -and (Test-Path $fr.ArchivePath)) {
                        $testRes = Test-RarArchive -RarPath $archiverPath -ArchivePath $fr.ArchivePath
                        if (-not $testRes.IsValid) {
                            Write-Log "Тест архива FAILED: $($fr.ArchivePath)" -Level ERROR
                            $allSuccess = $false
                        }
                    }

                    if ($fr.Success -and $job.RemoteDest -and (Test-Path $job.RemoteDest)) {
                        $archiveBaseName = Split-Path $fr.ArchivePath -Leaf
                        $remotePath = Join-Path $job.RemoteDest $archiveBaseName
                        Write-Log "Копирование в: $remotePath"
                        $copyRes = Copy-BackupFile -SourcePath $fr.ArchivePath -DestinationPath $remotePath
                        if (-not $copyRes.Success) {
                            Write-Log "Ошибка копирования: $remotePath" -Level WARNING
                        }
                    }
                }
                Write-Log "Файлов успешно: $successFiles, ошибок: $errorFiles" -ResultKey
                if (-not $allSuccess) { throw "Ошибки при индивидуальной архивации файлов" }
            }
        }
        else {
            $archiveName = Expand-Pattern -Pattern $job.ArchivePattern -PCName $PCName -JobName $jobName -Date $currentDate -Time $currentTime
            $archivePath = Join-Path $job.LocalDest $archiveName
            Write-Log "Архив: $archiveName" -ResultKey

            $rarParams = $BackupConfig.DefaultRarParams
            if ($job.ContainsKey('ArhParameters')) {
                $rarParams = $job['ArhParameters']
            }

            $sourceFilter = $null
            if ($job.ContainsKey('SourceFilter')) {
                $sourceFilter = $job['SourceFilter']
            }

            $rarLog = $null
            if ($job.ArhLog) { $rarLog = Join-Path $job.LocalDest "$jobName.rar.log" }

            Write-Log "Запуск RAR..." -ResultKey
            $arhResult = Start-RarArchive -RarPath $archiverPath -ArchivePath $archivePath -SourcePath $job.Source -Parameters $rarParams -LogPath $rarLog -SourceFilter $sourceFilter

            Write-Log "Код возврата: $($arhResult.ExitCode), Время: $($arhResult.Duration) мин" -ResultKey

            if ($arhResult.ExitCode -ne 0) {
                throw "Ошибка RAR: $(Get-RarExitCodeMeaning $arhResult.ExitCode)"
            }
            if (-not (Test-Path $archivePath)) { throw "Архив не создан" }

            Write-Log "Размер архива: $($arhResult.ArchiveSize) MB" -ResultKey

            $testRes = Test-RarArchive -RarPath $archiverPath -ArchivePath $archivePath
            if (-not $testRes.IsValid) { throw "Ошибка теста архива" }
            Write-Log "Тест архива: OK" -ResultKey

            $srcFiles = Get-FileList -Path $job.Source
            $archFiles = Get-FileArhListRar -RarPath $archiverPath -ArchivePath $archivePath
            $verify = Compare-FilesSourceArchive -SourceList $srcFiles -ArchiveList $archFiles

            if (-not $verify.IsIdentical) {
                Write-Log "Внимание: Несовпадение списка файлов. $($verify.Report)" -Level WARNING -ResultKey
            }
            else {
                Write-Log "Верификация: OK" -ResultKey
            }

            if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
                $remotePath = Join-Path $job.RemoteDest $archiveName
                Write-Log "Копирование в: $remotePath"
                $copyRes = Copy-BackupFile -SourcePath $archivePath -DestinationPath $remotePath
                if ($copyRes.Success) {
                    Write-Log "Копирование: OK" -ResultKey
                }
                else {
                    throw "Ошибка копирования (размер не совпадает)"
                }
            }
        }

        Write-Log "Ротация..."
        Remove-OldFiles -Path $job.LocalDest -DaysOld $job.LocalDestDaysOld -KeepCount $job.LocalDestKeepCount -Filter "*.rar"

        if ($job.RemoveRemoteDestFlag -and $job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            Remove-OldFiles -Path $job.RemoteDest -DaysOld 7 -KeepCount 7 -Filter "*.rar"
        }

        if ($job.RemoveSourceFlag) {
            if ($job.SourceKeepCount -gt 0) {
                Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount $job.SourceKeepCount -Filter "*.*"
            }
            elseif ($job.SourceDaysOld -gt 0) {
                Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount 0 -Filter "*.*"
            }
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

if ($errorCount -gt 0) {
    $Subject = "$PCName $ParentJobName : ОШИБКИ"
}
else {
    $Subject = "$PCName $ParentJobName : УСПЕХ"
}

if ($errorCount -gt 0) {
    $To = "$AdminIS, $AdminOS"
}
else {
    $To = $AdminIS
}

if ($errorCount -gt 0) {
    Write-WinEventAppLog -StatusKey "Error" -MessageText "Завершено. Ошибок: $errorCount"
}
else {
    Write-WinEventAppLog -StatusKey "Success" -MessageText "Завершено. Ошибок: $errorCount"
}

if (-not (IsNullOrWhiteSpace $SmtpServer)) {
    Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $To -Subject $Subject -Body $EmailBody
}

Remove-OldFiles -Path $config.Settings.LogPath -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.log"

if ($errorCount -gt 0) { exit 1 } else { exit 0 }
#endregion
