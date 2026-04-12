<#
.SYNOPSIS
    File Backup-rar-ps2.ps1
    Автономный скрипт резервного копирования (Версия 2.5 RAR-only)
.DESCRIPTION
    Поддерживает XML-конфигурацию: Backup-Config-All.xml
    Архиватор: только RAR
	Получение HASH передзапуском PS5
	(Get-FileHash -Path ".\Backup-Config-All.xml" -Algorithm SHA256).Hash
	(Get-FileHash -Path ".\rar.exe" -Algorithm SHA256).Hash
    Переменные для ArchivePattern:
    - {PCName} - Имя компьютера
    - {JobName} - Имя одного из дочерних задания
    - {Date} - Дата в формате YYYYMMDD
    - {Time} - Время в формате HHMMSS
    - {Date_Time} - Дата и время в формате YYYYMMDD_HHMMSS

.PARAMETER TestMode
    Тестовый запуск без выполнения резервного копирования

.EXAMPLE
    powershell.exe -executionpolicy RemoteSigned -file .\Backup-rar-ps2.ps1

.NOTES
    Версия: 
    Дата: 2026-04-10
    Совместимость: PowerShell 2.0 для Windows 7
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ===========================================================
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
$Script:CultureInvariant = [System.Globalization.CultureInfo]::InvariantCulture
$XmlFile="Backup-Config-All.xml"
$XmlHash = "CC8208F592E4345ED57510759981D0C0DDD39B18FDAF4CDF2E2DB47B67626F27"

Clear-Host

# ===========================================================
# Функция-заменитель для [string]::IsNullOrWhiteSpace (отсутствует в PS 2.0)
# ===========================================================
function Test-StringIsNullOrWhiteSpace {
    param([string]$Value)
    if ($Value -eq $null) { return $true }
    if ($Value -eq '') { return $true }
    if ($Value -match '^\s*$') { return $true }
    return $false
}

# ===========================================================
# Определение корневой директории скрипта для PS 2.0
# ===========================================================
if ($MyInvocation.MyCommand.Path) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $ScriptRoot = (Get-Location).Path
}

# ===========================================================
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША
# ===========================================================
function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Path', Position=0, ValueFromPipeline=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true, ParameterSetName='LiteralPath')]
        [string]$LiteralPath,
        [Parameter(Mandatory=$false)]
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )
    process {
        $filePath = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        try {
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Файл не найден: $filePath"
            }
            $hashAlgo = switch ($Algorithm.ToUpper()) {
                'SHA1'   { [System.Security.Cryptography.SHA1]::Create() }
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
                'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
                'MD5'    { [System.Security.Cryptography.MD5]::Create() }
                default  { [System.Security.Cryptography.SHA256]::Create() }
            }
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                $obj = New-Object PSObject -Property @{
                    Hash = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path = (Resolve-Path -LiteralPath $filePath).Path
                }
                return $obj
            }
            finally {
				$fileStream.Dispose()
			}
        }
        catch {
            throw "Ошибка вычисления хеша файла '$filePath': $($_.Exception.Message)"
        }
    }
}

if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    Set-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}
#endregion
# ===========================================================
#region ФУНКЦИЯ ПРОВЕРКИ ЦЕЛОСТНОСТИ
# ===========================================================
function Test-FileIntegrity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-F0-9]{64}$')][string]$ExpectedHash,
        [Parameter(Mandatory=$false)][string]$FileType = "Файл"
    )
    process {
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            $msg = "ОШИБКА: Файл не найден: $FilePath"
            Write-Host $msg -ForegroundColor Red
            Write-Error $msg
            return $false
        }
        try {
            Write-Host "Проверка целостности ($FileType): $FilePath..." -ForegroundColor Cyan
            $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpper()
            $expectedHashUpper = $ExpectedHash.ToUpper()
            Write-Host "  Ожидаемый    : $expectedHashUpper"
            Write-Host "  Фактический  : $actualHash"
            if ($actualHash -eq $expectedHashUpper) {
                Write-Host "  [OK] Хеш подтвержден. Файл безопасен." -ForegroundColor Green
                return $true
            }
            else {
                $errorMessage = @"
КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ!
Хеш файла НЕ СОВПАДАЕТ!
Тип: $FileType
Путь: $FilePath
Ожидаемый: $expectedHashUpper
Фактический: $actualHash
"@
                Write-Host $errorMessage -ForegroundColor Red
                Write-Error $errorMessage
                return $false
            }
        }
        catch {
            $errorMsg = "Ошибка вычисления хеша для $FileType`: $($_.Exception.Message)"
            Write-Host $errorMsg -ForegroundColor Red
            Write-Error $errorMsg
            return $false
        }
    }
}
#endregion

# ==============================================================================
#region ЭТАП 0: ПРОВЕРКА XML и Загрузка конфигурации из XML
# ==============================================================================
Write-Host "`n=== ЭТАП 0: ПРОВЕРКА XML ===" -ForegroundColor Yellow

$xmlPath = Join-Path $ScriptRoot $XmlFile

if (Test-StringIsNullOrWhiteSpace($xmlPath)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Не найден путь к $xmlPath`n" -ForegroundColor Red
    exit 1
}

if (-not (Test-FileIntegrity -FilePath $xmlPath -ExpectedHash $XmlHash -FileType $XmlFile)) {
    Write-Host "ПРОВЕРКА XML ПРОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
    exit 1
}

Write-Host "XML проверен: $xmlPath`n" -ForegroundColor Green
#endregion

# ===========================================================
#region CONFIG_BLOCK
# Загрузка конфигурации из XML

[xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
$b = $xmlDoc.BackupConfig

# Проверка типа архиватора
$archiverType = $b.General.ArchiverType
if ($archiverType -ne "RAR") {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Скрипт настроен только на RAR, в конфигурации указан '$archiverType'" -ForegroundColor Red
    exit 1
}

# Создание хеш-таблицы конфигурации
$Script:EmbeddedConfig = @{
    General = @{
        JobName      = $b.General.JobName
        Domain       = $b.General.Domain
        SmtpServer   = $b.General.SmtpServer
        LogDaysOld   = [int]$b.General.LogDaysOld
        LogKeepCount = [int]$b.General.LogKeepCount
        ArchiverType = $b.General.ArchiverType
    }
    Paths = @{
        LogPathRoot = $b.Paths.LogPathRoot
        NetLogPath  = $b.Paths.NetLogPath
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
    $Script:EmbeddedConfig['Jobs'][$jn] = @{
        Name = $jn
        Source = $jobNode.Source
        LocalDest = $jobNode.LocalDest
        RemoteDest = $jobNode.RemoteDest
        ArchivePattern = $jobNode.ArchivePattern
        RemoveSourceFlag = ($jobNode.RemoveSourceFlag -eq 'true')
        SourceDaysOld = [int]$jobNode.SourceDaysOld
        SourceKeepCount = [int]$jobNode.SourceKeepCount
        LocalDestDaysOld = [int]$jobNode.LocalDestDaysOld
        LocalDestKeepCount = [int]$jobNode.LocalDestKeepCount
        RemoveRemoteDestFlag = ($jobNode.RemoveRemoteDestFlag -eq 'true')
        RemoteDestDaysOld = [int]$jobNode.RemoteDestDaysOld
        RemoteDestKeepCount = [int]$jobNode.RemoteDestKeepCount
        ArhLog = ($jobNode.ArhLog -eq 'true')
        ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
        ArchiveIndividualFiles = ($jobNode.ArchiveIndividualFiles -eq 'true')
    }
    if ($jobNode.ArhParameters) {
        $ap = @()
        foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
        $Script:EmbeddedConfig['Jobs'][$jn]['ArhParameters'] = $ap
    }
    if ($jobNode.SourceCheckMasks) {
        $sm = @()
        foreach ($m in $jobNode.SourceCheckMasks.Mask) { $sm += $m }
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceCheckMasks'] = $sm
    }
    if ($jobNode.SourceFilter) {
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceFilter'] = $jobNode.SourceFilter
    }
    if ($jobNode.FileFilter) {
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceFilter'] = $jobNode.FileFilter
    }
    if ($jobNode.IndividualArchivePattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['IndividualArchivePattern'] = $jobNode.IndividualArchivePattern
    }
    if ($jobNode.ExcludeFolderPattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ExcludeFolderPattern'] = $jobNode.ExcludeFolderPattern
    }
    if ($jobNode.ExcludeFilePattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ExcludeFilePattern'] = $jobNode.ExcludeFilePattern
    }
    if ($jobNode.ListSourceFlag) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ListSourceFlag'] = $jobNode.ListSourceFlag
    }
}

$BackupConfig = $Script:EmbeddedConfig

$config = @{
    Settings = @{
        PCName         = $env:COMPUTERNAME
        JobName        = $BackupConfig['General']['JobName']
        Domain         = $BackupConfig['General']['Domain']
        LogPath        = $BackupConfig['Paths']['LogPathRoot']
        ArchiverType   = $BackupConfig['General']['ArchiverType']
        ArchiverPath   = $BackupConfig['Paths']['RarPath']
        ArchiverHash   = $BackupConfig['Integrity']['RarExeHash']
        ArchiverParams = $BackupConfig['General']['DefaultRarParameters']
        SmtpServer     = $BackupConfig['General']['SmtpServer']
    }
    Jobs = $BackupConfig['Jobs']
}
#endregion CONFIG_BLOCK

# ===========================================================
# Извлечение базовых переменных
# ===========================================================
$PCName = $env:COMPUTERNAME
$NameDomain = $BackupConfig['General']['Domain']
$PCNameMail = "$PCName@head.$NameDomain"
$SmtpServer = $BackupConfig['General']['SmtpServer']
$ParentJobName = $BackupConfig['General']['JobName']
$LogDaysOld = $BackupConfig['General']['LogDaysOld']
$LogKeepCount = $BackupConfig['General']['LogKeepCount']
$AdminIS = $BackupConfig['Recipients']['AdminIS']
$AdminOS = $BackupConfig['Recipients']['AdminOS']
$AdminMail = $BackupConfig['Recipients']['AdminMail']

# ==============================================================================
#region ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR
# ==============================================================================
Write-Host "`n=== ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR ===" -ForegroundColor Yellow

$archiverPathValue = $BackupConfig['Paths']['RarPath']
$archiverHash = $BackupConfig['Integrity']['RarExeHash']

if (Test-StringIsNullOrWhiteSpace($archiverPathValue)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Не найден путь к RAR.exe" -ForegroundColor Red
    exit 1
}

if (-not (Test-FileIntegrity -FilePath $archiverPathValue -ExpectedHash $archiverHash -FileType "RAR.exe")) {
    Write-Host "ПРОВЕРКА АРХИВАТОРА ПРОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
    exit 1
}

Write-Host "Архиватор RAR проверен: $archiverPathValue`n" -ForegroundColor Green
#endregion

# ==============================================================================
#region МОДУЛЬ ЛОГИРОВАНИЯ (Backup-Logger.psm1)
# ==============================================================================
$Script:LogPath = $null
$Script:MainLogFile = $null
$Script:ReportEntries = @()

function Initialize-Logging {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true, Position=0)][string]$LogPath,
        [Parameter(Mandatory=$true, Position=1)][string]$PCName,
        [Parameter(Mandatory=$true, Position=2)][string]$JobName
    )
    process {
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
            $Script:ReportEntries = @()
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($fullLogPath, "", $utf8NoBom)
            Write-LogSection -Title "СИСТЕМА ЛОГИРОВАНИЯ ИНИЦИАЛИЗИРОВАНА"
            Write-Log -Message "Компьютер: $safePCName"
            Write-Log -Message "Общее Задание: $safeJobName"
            Write-Log -Message "Лог-файл: $fullLogPath"
            Write-Log -Message "Время начала: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-LogSection
            return $true
        }
        catch {
            $errorMsg = "Критическая ошибка инициализации логирования: $($_.Exception.Message)"
            throw $errorMsg
        }
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][ValidateNotNull()][string]$Message,
        [Parameter(Mandatory=$false, Position=1)][ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')][string]$Level = 'INFO',
        [Parameter(Mandatory=$false)][switch]$ResultKey
    )
    process {
        if (Test-StringIsNullOrWhiteSpace($Message)) {
            throw "Сообщение не может быть пустым"
        }
        try {
            if (-not ($Script:MainLogFile)) {
                throw "Логирование не инициализировано."
            }
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $levelPrefix = switch ($Level) {
                'ERROR'   { '[ERROR]  ' }
                'WARNING' { '[WARNING]' }
                'SUCCESS' { '[SUCCESS]' }
                'DEBUG'   { '[DEBUG]  ' }
                default   { '[INFO]   ' }
            }
            $safeMessage = $Message -replace '\r?\n', ' '
            $logEntry = "[$timestamp] $levelPrefix $safeMessage"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$logEntry`r`n", $utf8NoBom)
            if ($ResultKey) {
                $Script:ReportEntries += $logEntry
            }
            switch ($Level) {
                'ERROR'   { Write-Error $Message -ErrorAction Continue }
                'WARNING' { Write-Warning $Message }
                'SUCCESS' { Write-Host $Message -ForegroundColor Green }
            }
        }
        catch {
            Write-Error "ПОЛНЫЙ ОТКАЗ ЛОГИРОВАНИЯ: $_" -ErrorAction Continue
        }
    }
}

function Get-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $Script:MainLogFile
}

function Write-LogSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Title,
        [Parameter(Mandatory=$false)][switch]$ResultKey
    )
    process {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelPrefix = '[INFO]   '
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        if ($Title) {
            $upperTitle = $Title.ToUpper()
            $line1 = "[$timestamp] $levelPrefix ========================================"
            $line2 = "[$timestamp] $levelPrefix $upperTitle"
            $line3 = "[$timestamp] $levelPrefix ========================================"
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$line1`r`n$line2`r`n$line3`r`n", $utf8NoBom)
            if ($ResultKey) {
                $Script:ReportEntries += $line1, $line2, $line3
            }
        }
        else {
            $line = "[$timestamp] $levelPrefix ----------------------------------------"
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$line`r`n", $utf8NoBom)
            if ($ResultKey) {
                $Script:ReportEntries += $line
            }
        }
    }
}

function Get-LogResults {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($Script:ReportEntries.Count -eq 0) {
        return "Нет сообщений для отчёта."
    }
    return ($Script:ReportEntries -join "`r`n")
}

function Write-WinEventAppLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateSet("Start", "Success", "Warning", "Error", "End")][string]$StatusKey,
        [Parameter(Mandatory=$true)][string]$MessageText,
        [Parameter(Mandatory=$false)][string]$Source = $ParentJobName
    )
    $LogName = 'Application'
    try {
        if (-not ([System.Diagnostics.EventLog]::SourceExists($Source))) {
            Write-Log "EventLog: источник '$Source' не зарегистрирован." -Level WARNING
            return
        }
        $eventIdMap = @{ Start = 3000; Success = 3001; Warning = 3002; Error = 3003; End = 3004 }
        $entryTypeMap = @{
            Start   = [System.Diagnostics.EventLogEntryType]::Information
            Success = [System.Diagnostics.EventLogEntryType]::Information
            Warning = [System.Diagnostics.EventLogEntryType]::Warning
            Error   = [System.Diagnostics.EventLogEntryType]::Error
            End     = [System.Diagnostics.EventLogEntryType]::Information
        }
        $eventLog = New-Object System.Diagnostics.EventLog($LogName)
        $eventLog.Source = $Source
        $eventLog.WriteEntry($MessageText, $entryTypeMap[$StatusKey], $eventIdMap[$StatusKey])
    }
    catch {
        Write-Log "Ошибка записи в EventLog: $_" -Level WARNING
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ RAR ОПЕРАЦИЙ (Backup-RAR.psm1)
# ==============================================================================
function Get-RarExitCodeMeaning {
    param([int]$ExitCode)
    $errorDescriptions = @{
        0   = "Успешное выполнение"
        1   = "Незначительная ошибка при создании архива"
        2   = "Критическая ошибка при создании архива"
        3   = "Ошибка при проверке целостности архива"
        4   = "Ошибка при открытии файла"
        5   = "Ошибка записи файла"
        6   = "Невозможно прочитать файл"
        7   = "Недопустимая команда или параметр"
        8   = "Не хватает памяти"
        9   = "Невозможно создать временный файл"
        10  = "Невозможно создать архив"
        11  = "Невозможно открыть файл для чтения"
        255 = "Пользователь прервал операцию"
    }
    if ($errorDescriptions.ContainsKey($ExitCode)) {
        return $errorDescriptions[$ExitCode]
    }
    else {
        return "Неизвестный код возврата: $ExitCode"
    }
}

function Start-RarArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RarPath,
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$false)][string[]]$Parameters = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t"),
        [Parameter(Mandatory=$false)][string]$LogPath,
        [Parameter(Mandatory=$false)][string]$SourceFilter
    )
    begin {
        $actualLogPath = $null
        if ($PSBoundParameters.ContainsKey('LogPath') -and -not ([string]::IsNullOrEmpty($LogPath))) {
            $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
            if ([string]::IsNullOrEmpty($logDir)) { $logDir = "." }
            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
                try { $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop } catch {}
            }
            if (Test-Path -LiteralPath $logDir -PathType Container) {
                $actualLogPath = $LogPath
            }
        }
        $argsList = @($Parameters)
        if ($actualLogPath) {
            $argsList += '-ilog"' + $actualLogPath + '"'
        }
        $safeArchivePath = '"' + ($ArchivePath -replace '"', '\"') + '"'
        if (-not (Test-StringIsNullOrWhiteSpace($SourceFilter))) {
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
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null
            $null = $process.StandardOutput.ReadToEnd()
            $null = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
            $logContent = @()
            if ($actualLogPath -and (Test-Path -LiteralPath $actualLogPath)) {
                try {
                    $logContent = Get-Content -LiteralPath $actualLogPath -Encoding OEM -ErrorAction Stop
                }
                catch { Write-Warning "Не удалось прочитать лог: $($_.Exception.Message)" }
            }
            $archiveSizeMB = 0
            if (-not ([string]::IsNullOrEmpty($ArchivePath) -and (Test-Path -LiteralPath $ArchivePath -PathType Leaf))) {
                try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch { $archiveSizeMB = 0 }
            }
            $result = New-Object PSObject -Property @{
                ExitCode = $exitCode
                Duration = $duration
                StartTime = $processStart
                EndTime = $processEnd
                LogPath = $actualLogPath
                LogContent = $logContent
                FailedFiles = @()
                ArchiveSize = $archiveSizeMB
            }
            return $result
        }
        catch {
            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
            Write-Error "Критическая ошибка запуска RAR: $($_.Exception.Message)"
            $result = New-Object PSObject -Property @{
                ExitCode = 255
                Duration = $duration
                StartTime = $processStart
                EndTime = $processEnd
                LogPath = $actualLogPath
                LogContent = @()
                FailedFiles = @()
                Exception = $_.Exception
            }
            return $result
        }
    }
}

function Test-RarArchive {
    param(
        [Parameter(Mandatory=$true)][string]$RarPath,
        [Parameter(Mandatory=$true)][string]$ArchivePath
    )
    $testArgs = @("t", "`"$ArchivePath`"")
    Write-Log "Проверка целостности архива: $ArchivePath"
    $process = Start-Process -FilePath $RarPath -ArgumentList $testArgs -Wait -PassThru -WindowStyle Hidden
    $result = New-Object PSObject -Property @{
        ExitCode = $process.ExitCode
        IsValid = ($process.ExitCode -eq 0)
    }
    return $result
}
#endregion

# ==============================================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ АРХИВАЦИИ
# ==============================================================================
function Get-FileInfoDetails {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not ($_.PSIsContainer) }
        $fileCount = $items.Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
        $fileSamples = $items | Select-Object -First 5 | ForEach-Object {
            $obj = New-Object PSObject -Property @{
                Name = $_.Name
                SizeKB = [math]::Round($_.Length / 1KB, 2)
                FullPath = $_.FullName
            }
            $obj
        }
        $result = New-Object PSObject -Property @{
            FileCount = $fileCount
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
            TotalSizeBytes = $totalSize
            FileSamples = $fileSamples
            HasMoreFiles = ($fileCount -gt 5)
            MoreFilesCount = ($fileCount - 5)
        }
        return $result
    }
    catch {
        $result = New-Object PSObject -Property @{
            FileCount = 0
            TotalSizeMB = 0
            TotalSizeBytes = 0
            FileSamples = @()
            HasMoreFiles = $false
            MoreFilesCount = 0
            Error = $_.Exception.Message
        }
        return $result
    }
}

function Copy-BackupFile {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $copyEnd = Get-Date
    $duration = [math]::Round(($copyEnd - $copyStart).TotalSeconds, 2)
    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length
    $result = New-Object PSObject -Property @{
        Success = ($sourceSize -eq $destSize)
        Duration = $duration
        SourceSize = $sourceSize
        DestinationSize = $destSize
        StartTime = $copyStart
        EndTime = $copyEnd
    }
    return $result
}

function Start-IndividualFileArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArchiverType,
        [Parameter(Mandatory=$true)][string]$ArchiverPath,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [Parameter(Mandatory=$true)][string]$FileFilter,
        [Parameter(Mandatory=$false)][string]$ExcludeFilePattern,
        [Parameter(Mandatory=$true)][string]$ArchivePattern,
        [Parameter(Mandatory=$false)][string[]]$Parameters,
        [Parameter(Mandatory=$false)][string]$LogPath,
        [Parameter(Mandatory=$false)][string]$PCName,
        [Parameter(Mandatory=$false)][string]$JobName
    )
    process {
        $results = @()
        if ($ArchiverType -ne "RAR") {
            Write-Log "Ошибка: поддерживается только RAR" -Level ERROR
            return $results
        }
        $archiveExtension = '.rar'
        Write-Log "Поиск файлов для индивидуальной архивации по маске: $FileFilter" -Level INFO -ResultKey
        $files = Get-FilterFileList -Path $SourcePath -Filter $FileFilter
        if ($ExcludeFilePattern) {
            $files = $files | Where-Object {
                $name = Split-Path $_.RelativePath -Leaf
                ($_.RelativePath -notlike $ExcludeFilePattern) -and ($name -notlike $ExcludeFilePattern)
            }
            Write-Log "После исключения по маске '$ExcludeFilePattern' осталось файлов: $($files.Count)" -Level INFO
        }
        if ($files.Count -eq 0) {
            Write-Log "Файлы по маске '$FileFilter' не найдены" -Level WARNING -ResultKey
            return $results
        }
        Write-Log "Найдено файлов для архивации: $($files.Count)" -Level INFO -ResultKey
        if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $successCount = 0
        $errorCount = 0
        foreach ($file in $files) {
            $fileStart = Get-Date
            $sourceFileName = Split-Path -Path $file.RelativePath -Leaf
            $sourceFilePath = $file.FullName
            $archiveName = $ArchivePattern
            $archiveName = $archiveName -replace '{PCName}', $PCName
            $archiveName = $archiveName -replace '{JobName}', $JobName
            $archiveName = $archiveName -replace '{SourceFileName}', $sourceFileName
            $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
            if ($archiveName -notmatch '\.rar$') {
                $archiveName = $archiveName + $archiveExtension
            }
            $archivePath = Join-Path -Path $DestinationPath -ChildPath $archiveName
            Write-Log "Архивация файла: ${sourceFileName} -> $archiveName" -Level INFO
            try {
                $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $sourceFilePath -Parameters $Parameters -LogPath $null
                $fileEnd = Get-Date
                $fileDuration = [math]::Round(($fileEnd - $fileStart).TotalSeconds, 2)
                if ($arhResult.ExitCode -eq 0) {
                    Write-Log "Успешно: $archiveName ($($arhResult.ArchiveSize) МБ, $($fileDuration) сек)" -Level SUCCESS -ResultKey
                    $successCount++
                    $obj = New-Object PSObject -Property @{
                        SourceFile = $sourceFileName
                        SourceFileFullName = $sourceFilePath
                        ArchivePath = $archivePath
                        ArchiveSize = $arhResult.ArchiveSize
                        Duration = $fileDuration
                        Status = 'Success'
                        ExitCode = $arhResult.ExitCode
                    }
                    $results += $obj
                }
                else {
                    $errorDesc = Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode
                    Write-Log "Ошибка архивации ${sourceFileName}: $errorDesc" -Level ERROR -ResultKey
                    $errorCount++
                    $obj = New-Object PSObject -Property @{
                        SourceFile = $sourceFileName
                        SourceFileFullName = $sourceFilePath
                        ArchivePath = $archivePath
                        ArchiveSize = 0
                        Duration = $fileDuration
                        Status = 'Error'
                        ExitCode = $arhResult.ExitCode
                        ErrorMessage = $errorDesc
                    }
                    $results += $obj
                }
            }
            catch {
                $fileEnd = Get-Date
                $fileDuration = [math]::Round(($fileEnd - $fileStart).TotalSeconds, 2)
                Write-Log "Критическая ошибка при архивации ${sourceFileName}: $($_.Exception.Message)" -Level ERROR -ResultKey
                $errorCount++
                $obj = New-Object PSObject -Property @{
                    SourceFile = $sourceFileName
                    SourceFileFullName = $sourceFilePath
                    ArchivePath = $archivePath
                    ArchiveSize = 0
                    Duration = $fileDuration
                    Status = 'Error'
                    ExitCode = 255
                    ErrorMessage = $_.Exception.Message
                }
                $results += $obj
            }
        }
        Write-Log "Индивидуальная архивация завершена: Успешно=$successCount, Ошибки=$errorCount" -Level INFO -ResultKey
        return $results
    }
}

function Start-IndividualFolderArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArchiverType,
        [Parameter(Mandatory=$true)][string]$ArchiverPath,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [Parameter(Mandatory=$true)][string]$ArchivePattern,
        [Parameter(Mandatory=$false)][string]$FolderFilter,
        [Parameter(Mandatory=$false)][string]$ExcludeFolderPattern,
        [Parameter(Mandatory=$false)][string[]]$Parameters,
        [Parameter(Mandatory=$false)][string]$LogPath,
        [Parameter(Mandatory=$false)][string]$PCName,
        [Parameter(Mandatory=$false)][string]$JobName
    )
    process {
        $results = @()
        if ($ArchiverType -ne "RAR") {
            Write-Log "Ошибка: поддерживается только RAR" -Level ERROR
            return $results
        }
        $archiveExtension = '.rar'
        Write-Log "Поиск подпапок для индивидуальной архивации в: $SourcePath" -Level INFO -ResultKey
        $folders = Get-ChildItem -Path $SourcePath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
        if (-not (Test-StringIsNullOrWhiteSpace($FolderFilter))) {
            $folders = $folders | Where-Object { $_.Name -like $FolderFilter }
            Write-Log "Применён фильтр папок: $FolderFilter (найдено $($folders.Count))" -Level INFO
        }
        if (-not (Test-StringIsNullOrWhiteSpace($ExcludeFolderPattern))) {
            if ($ExcludeFolderPattern -eq 'today') {
                $todayDate = Get-Date -Format 'yyyyMMdd'
                $folders = $folders | Where-Object { $_.Name -ne $todayDate }
                Write-Log "Исключена папка с текущей датой: $todayDate" -Level INFO -ResultKey
            }
            else {
                $excludedCount = ($folders | Where-Object { $_.Name -like $ExcludeFolderPattern }).Count
                $folders = $folders | Where-Object { $_.Name -notlike $ExcludeFolderPattern }
                if ($excludedCount -gt 0) {
                    Write-Log "Исключено папок по маске '$ExcludeFolderPattern': $excludedCount" -Level INFO -ResultKey
                }
            }
        }
        if ($folders.Count -eq 0) {
            Write-Log "Подпапки для архивации не найдены" -Level WARNING -ResultKey
            return $results
        }
        Write-Log "Найдено подпапок для архивации: $($folders.Count)" -Level INFO -ResultKey
        if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $successCount = 0
        $errorCount = 0
        foreach ($folder in $folders) {
            $folderStart = Get-Date
            $folderName = $folder.Name
            $folderPath = $folder.FullName
            $archiveName = $ArchivePattern
            $archiveName = $archiveName -replace '{PCName}', $PCName
            $archiveName = $archiveName -replace '{JobName}', $JobName
            $archiveName = $archiveName -replace '{SourceFolderName}', $folderName
            $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
            if ($archiveName -notmatch '\.rar$') {
                $archiveName = $archiveName + $archiveExtension
            }
            $archivePath = Join-Path -Path $DestinationPath -ChildPath $archiveName
            Write-Log "Архивация папки: ${folderName} -> $archiveName" -Level INFO
            try {
                $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $folderPath -Parameters $Parameters -LogPath $null
                $folderEnd = Get-Date
                $folderDuration = [math]::Round(($folderEnd - $folderStart).TotalSeconds, 2)
                if ($arhResult.ExitCode -eq 0) {
                    Write-Log "Успешно: $archiveName ($($arhResult.ArchiveSize) МБ, $($folderDuration) сек)" -Level SUCCESS -ResultKey
                    $successCount++
                    $obj = New-Object PSObject -Property @{
                        SourceFolder = $folderName
                        SourceFolderFullPath = $folderPath
                        ArchivePath = $archivePath
                        ArchiveSize = $arhResult.ArchiveSize
                        Duration = $folderDuration
                        Status = 'Success'
                        ExitCode = $arhResult.ExitCode
                    }
                    $results += $obj
                }
                else {
                    $errorDesc = Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode
                    Write-Log "Ошибка архивации ${folderName}: $errorDesc" -Level ERROR -ResultKey
                    $errorCount++
                    $obj = New-Object PSObject -Property @{
                        SourceFolder = $folderName
                        SourceFolderFullPath = $folderPath
                        ArchivePath = $archivePath
                        ArchiveSize = 0
                        Duration = $folderDuration
                        Status = 'Error'
                        ExitCode = $arhResult.ExitCode
                        ErrorMessage = $errorDesc
                    }
                    $results += $obj
                }
            }
            catch {
                $folderEnd = Get-Date
                $folderDuration = [math]::Round(($folderEnd - $folderStart).TotalSeconds, 2)
                Write-Log "Критическая ошибка при архивации ${folderName}: $($_.Exception.Message)" -Level ERROR -ResultKey
                $errorCount++
                $obj = New-Object PSObject -Property @{
                    SourceFolder = $folderName
                    SourceFolderFullPath = $folderPath
                    ArchivePath = $archivePath
                    ArchiveSize = 0
                    Duration = $folderDuration
                    Status = 'Error'
                    ExitCode = 255
                    ErrorMessage = $_.Exception.Message
                }
                $results += $obj
            }
        }
        Write-Log "Индивидуальная архивация папок завершена: Успешно=$successCount, Ошибки=$errorCount" -Level INFO -ResultKey
        return $results
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ ВЕРИФИКАЦИИ (Backup-Verification.psm1)
# ==============================================================================
function Get-CanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)][string]$FullPath,
        [Parameter(Mandatory=$true)][string]$RootPath
    )
    process {
        $normalizedFull = $FullPath -replace '/', '\'
        $normalizedRoot = $RootPath -replace '/', '\'
        $normalizedFull = $normalizedFull.TrimEnd('\')
        $normalizedRoot = $normalizedRoot.TrimEnd('\')
        $lowerFull = $normalizedFull.ToLowerInvariant()
        $lowerRoot = $normalizedRoot.ToLowerInvariant()
        if ($lowerFull.StartsWith($lowerRoot)) {
            $relative = $normalizedFull.Substring($normalizedRoot.Length).TrimStart('\')
        }
        else {
            $relative = $normalizedFull
        }
        return $relative.ToLowerInvariant()
    }
}

function Get-CommonPathPrefix {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory=$true)][string[]]$Paths)
    if ($Paths.Count -eq 0) { return "" }
    if ($Paths.Count -eq 1) {
        $parts = $Paths[0] -split '\\'
        if ($parts.Count -gt 1) {
            return ($parts[0..($parts.Count - 2)] -join '\') + '\'
        }
        return ""
    }
    $splitPaths = $Paths | ForEach-Object { $_ -split '\\' }
    $minParts = ($splitPaths | ForEach-Object { $_.Count } | Measure-Object -Minimum).Minimum
    $commonComponents = @()
    for ($i = 0; $i -lt $minParts; $i++) {
        $first = [System.Char]::ToLower($splitPaths[0][$i])
        $allSame = $true
        for ($j = 1; $j -lt $splitPaths.Count; $j++) {
            if ([System.Char]::ToLower($splitPaths[$j][$i]) -ne $first) {
                $allSame = $false
                break
            }
        }
        if ($allSame) {
            $commonComponents += $splitPaths[0][$i]
        }
        else {
            break
        }
    }
    if ($commonComponents.Count -gt 0) {
        return ($commonComponents -join '\') + '\'
    }
    return ""
}

function Get-FileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({if (-not (Test-Path -LiteralPath $_ -PathType Container)) { throw "Не папка: $_" }; $true})]
        [string]$Path
    )
    
    begin {
        $rootPath = (Resolve-Path -LiteralPath $Path).Path
        if ($rootPath.EndsWith('\')) { 
            $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) 
        }
        Write-Verbose "Сканируем: $rootPath"
    }
    
    process {
        try {
            # PS2: получаем файлы БЕЗ рекурсии HasFlag
            $items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue |
                     Where-Object { -not $_.PSIsContainer }
            
            # PS2: исключаем символические ссылки БИТОВЫМИ операциями
            $items = $items | Where-Object { 
                # -band вместо .HasFlag()
                (-not (($_.Attributes.Value -band [System.IO.FileAttributes]::ReparsePoint)))
            }
            
            $result = @()
            foreach ($item in $items) {
                if (-not (Test-Path -LiteralPath $item.FullName -PathType Leaf)) { 
                    continue 
                }
                
                $relative = Get-CanonicalPath -FullPath $item.FullName -RootPath $rootPath
                $obj = New-Object PSObject -Property @{
                    RelativePath = $relative
                    Length = $item.Length
                    LastWriteTime = $item.LastWriteTime
                    Source = "FileSystem"
                    FullName = $item.FullName
                }
                $result += $obj
            }
            Write-Verbose "Найдено файлов: $($result.Count)"
            return $result
        }
        catch {
            Write-Error "Критическая ошибка при сканировании пути '$Path`: $($_.Exception.Message)"
            throw
        }
    }
}

function Get-FilterFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateNotNull()][string]$Filter
    )
    if (Test-StringIsNullOrWhiteSpace($Filter)) {
        throw "Фильтр не может быть пустым"
    }
    Write-Verbose "Поиск файлов по маске '$Filter' в '$Path'"
    $allFiles = Get-FileList -Path $Path
    if ($allFiles.Count -eq 0) {
        Write-Warning "В источнике '$Path' файлов не найдено."
        return @()
    }
    $lowerFilter = $Filter.ToLowerInvariant()
    $filtered = $allFiles | Where-Object {
        $path = $_.RelativePath
        $name = Split-Path -Path $path -Leaf
        if ($Filter.Contains('\') -or $Filter.Contains('/')) {
            return $path -like $lowerFilter
        }
        else {
            return $name -like $lowerFilter
        }
    }
    if ($filtered.Count -eq 0) {
        Write-Warning "Файлы по маске '$Filter' в источнике '$Path' не найдены."
        return @()
    }
    Write-Verbose "Найдено файлов: $($filtered.Count)"
    return $filtered
}

function Get-FileArhListRar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$RarPath,
        [Parameter(Mandatory=$true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ArchivePath
    )
    Write-Verbose "Чтение содержимого RAR архива: $ArchivePath"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $RarPath
        $psi.Arguments = "vtb -cfg- `"$ArchivePath`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "RAR вернул код ошибки $($process.ExitCode). Детали: $stderr"
        }
        $fileList = ConvertFrom-RarListOutput -RawOutput $stdout
        if (-not ($fileList)) { $fileList = @() }
        if ($fileList.Count -eq 0) {
            Write-Warning "Архив пуст или не удалось извлечь список файлов."
        }
        else {
            Write-Verbose "В архиве найдено файлов: $($fileList.Count)"
        }
        return $fileList
    }
    catch {
        Write-Error "Ошибка при чтении архива $ArchivePath : $($_.Exception.Message)"
        throw
    }
}

function ConvertFrom-RarListOutput {
    param([Parameter(Mandatory=$true)][object]$RawOutput)
    $files = @()
    $content = ""
    if ($RawOutput -is [byte[]]) {
        $utf8Encoding = New-Object System.Text.UTF8Encoding
        $content = $utf8Encoding.GetString($RawOutput)
    }
    else {
        $content = $RawOutput -join "`r`n"
    }
    $lines = $content -split "`r`n"
    $currentName = $null
    $currentSize = $null
    $currentDate = $null
    foreach ($line in $lines) {
        if (Test-StringIsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*RAR\s+' -or $line -match '^\s*Copyright' -or $line -match '^\s*Registered') { continue }
        if ($line -match '^\s*Archive:' -or $line -match '^\s*Details:') { continue }
        if ($line -match '^\s+Name:\s*(.+)$') {
            if ($currentName -and $currentSize -and $currentDate) {
                $relativeName = ($currentName -replace '^\\+', '' -replace '/', '\').ToLowerInvariant()
                $obj = New-Object PSObject -Property @{
                    RelativePath = $relativeName
                    Length = $currentSize
                    LastWriteTime = $currentDate
                    Source = "Archive"
                }
                $files += $obj
            }
            $currentName = $matches[1].Trim()
            $currentSize = $null
            $currentDate = $null
            continue
        }
        if ($line -match '^\s+Size:\s*(\d+)') {
            $currentSize = [int64]$matches[1]
            continue
        }
        if ($line -match '^\s+Modified:\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})') {
            $dateStr = "$($matches[1]) $($matches[2])"
            $currentDate = [DateTime]::Parse($dateStr, [System.Globalization.CultureInfo]::InvariantCulture)
            continue
        }
        if ($line -match '^\s+Type:\s*Directory') {
            $currentName = $null
            $currentSize = $null
            $currentDate = $null
            continue
        }
    }
    if ($currentName -and $currentSize -and $currentDate) {
        $relativeName = ($currentName -replace '^\\+', '' -replace '/', '\').ToLowerInvariant()
        $obj = New-Object PSObject -Property @{
            RelativePath = $relativeName
            Length = $currentSize
            LastWriteTime = $currentDate
            Source = "Archive"
        }
        $files += $obj
    }
    return $files
}

function Compare-FilesSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$SourceList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ArchiveList,
        [Parameter(Mandatory=$false)][string]$SourcePath
    )
    process {
        Write-Verbose "Начало сравнения: Источник ($($SourceList.Count)) vs Архив ($($ArchiveList.Count))"
        $NormalizeChars = {
            param([string]$Text)
            $res = $Text
            $res = $res -replace '[\u2013\u2014\u2015]', '-'
            $res = $res -replace '[\u201c\u201d\u00ab\u00bb]', '"'
            $res = $res -replace '\u2026', '...'
            return $res
        }
        $sourceHash = @{}
        foreach ($item in $SourceList) {
            $key = & $NormalizeChars $item.RelativePath.ToLowerInvariant()
            if (-not ($sourceHash.ContainsKey($key))) { $sourceHash[$key] = $item }
        }
        $archiveHash = @{}
        foreach ($item in $ArchiveList) {
            $path = $item.RelativePath
            $path = $path -replace '^[A-Z]:\\', '' -replace '^\\\\\?\\', ''
            $path = ($path -replace '/', '\').TrimStart('\').ToLowerInvariant()
            $item.RelativePath = $path
            $key = & $NormalizeChars $path
            if (-not ($archiveHash.ContainsKey($key))) { $archiveHash[$key] = $item }
        }
        $missingInArchive = @()
        $sizeMismatch = @()
        $extraInArchive = @()
        $isIdentical = $true
        foreach ($key in $sourceHash.Keys) {
            $srcItem = $sourceHash[$key]
            if ($archiveHash.ContainsKey($key)) {
                $arhItem = $archiveHash[$key]
                if ($srcItem.Length -ne $arhItem.Length) {
                    $mismatchObj = New-Object PSObject -Property @{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                    $sizeMismatch += $mismatchObj
                    $isIdentical = $false
                }
            }
            else {
                $foundKey = $archiveHash.Keys | Where-Object { $_.EndsWith("\$key") -or $_ -eq $key } | Select-Object -First 1
                if ($foundKey) {
                    $arhItem = $archiveHash[$foundKey]
                    if ($srcItem.Length -ne $arhItem.Length) {
                        $mismatchObj = New-Object PSObject -Property @{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                        $sizeMismatch += $mismatchObj
                        $isIdentical = $false
                    }
                }
                else {
                    $missingInArchive += $srcItem
                    $isIdentical = $false
                }
            }
        }
        foreach ($key in $archiveHash.Keys) {
            if ($sourceHash.ContainsKey($key)) { continue }
            $isExtra = $true
            foreach ($srcKey in $sourceHash.Keys) {
                if ($key.EndsWith("\$srcKey") -or $key -eq $srcKey) {
                    $isExtra = $false
                    break
                }
            }
            if ($isExtra) {
                $extraInArchive += $archiveHash[$key]
                $isIdentical = $false
            }
        }
        $reportLines = @()
        if ($isIdentical) {
            $reportLines += "SUCCESS: Полное совпадение файлов ($($SourceList.Count) шт)."
        }
        else {
            if ($missingInArchive.Count -gt 0) {
                $reportLines += "ERROR: Отсутствуют в архиве ($($missingInArchive.Count)):"
                $missingInArchive | Select-Object -First 10 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
                if ($missingInArchive.Count -gt 10) { $reportLines += "  ... и еще $($missingInArchive.Count - 10)" }
            }
            if ($sizeMismatch.Count -gt 0) {
                $reportLines += "ERROR: Не совпадает размер ($($sizeMismatch.Count)):"
                $sizeMismatch | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.Path)" }
            }
            if ($extraInArchive.Count -gt 0) {
                $reportLines += "WARNING: В архиве есть лишние файлы ($($extraInArchive.Count)):"
                $extraInArchive | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
            }
        }
        $result = New-Object PSObject -Property @{
            IsIdentical = $isIdentical
            TotalSource = $SourceList.Count
            TotalArchive = $ArchiveList.Count
            MissingInArchive = $missingInArchive
            ExtraInArchive = $extraInArchive
            SizeMismatch = $sizeMismatch
            Report = ($reportLines -join "`r`n")
        }
        return $result
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ XML-ОТЧЁТОВ (Backup-XmlReport.psm1)
# ==============================================================================
function Write-BackupXmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JobName,
        [Parameter(Mandatory=$true)][ValidateSet('Success', 'Error', 'Warning')][string]$JobStatus,
        [Parameter(Mandatory=$true)][string]$Duration,
        [Parameter(Mandatory=$false)][int]$SourceFiles = 0,
        [Parameter(Mandatory=$false)][double]$ArchiveSizeMB = 0,
        [Parameter(Mandatory=$false)][string]$Verification = 'Skipped',
        [Parameter(Mandatory=$false)][string[]]$Errors = @(),
        [Parameter(Mandatory=$false)][string[]]$Warnings = @(),
        [Parameter(Mandatory=$false)][string]$LogPath = ''
    )
    process {
        try {
            $reportPath = $config['Settings']['LogPath']
            if (-not ($reportPath)) {
                $reportPath = $BackupConfig['Paths']['LogPathRoot']
            }
            if (-not (Test-Path -LiteralPath $reportPath -PathType Container)) {
                New-Item -Path $reportPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $reportFile = Join-Path $reportPath "${PCName}_${JobName}_${timestamp}.xml"
            $xml = New-Object System.Text.StringBuilder
            [void]$xml.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
            [void]$xml.AppendLine('<BackupReport>')
            [void]$xml.AppendLine("    <Host>$PCName</Host>")
            [void]$xml.AppendLine("    <Job>$JobName</Job>")
            [void]$xml.AppendLine("    <Timestamp>$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</Timestamp>")
            [void]$xml.AppendLine("    <Status>$JobStatus</Status>")
            [void]$xml.AppendLine("    <Duration>$Duration</Duration>")
            [void]$xml.AppendLine("    <SourceFiles>$SourceFiles</SourceFiles>")
            [void]$xml.AppendLine("    <ArchiveSizeMB>$ArchiveSizeMB</ArchiveSizeMB>")
            [void]$xml.AppendLine("    <Verification>$Verification</Verification>")
            if ($Errors.Count -gt 0) {
                [void]$xml.AppendLine('    <Errors>')
                foreach ($err in $Errors) {
                    $safeErr = $err -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                    [void]$xml.AppendLine("        <Error>$safeErr</Error>")
                }
                [void]$xml.AppendLine('    </Errors>')
            }
            else {
                [void]$xml.AppendLine('    <Errors/>')
            }
            if ($Warnings.Count -gt 0) {
                [void]$xml.AppendLine('    <Warnings>')
                foreach ($warn in $Warnings) {
                    $safeWarn = $warn -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                    [void]$xml.AppendLine("        <Warning>$safeWarn</Warning>")
                }
                [void]$xml.AppendLine('    </Warnings>')
            }
            else {
                [void]$xml.AppendLine('    <Warnings/>')
            }
            [void]$xml.AppendLine("    <LogPath>$LogPath</LogPath>")
            [void]$xml.AppendLine('</BackupReport>')
            [System.IO.File]::WriteAllText($reportFile, $xml.ToString(), [System.Text.Encoding]::UTF8)
            Write-Log "XML-отчёт сохранён: $reportFile" -Level DEBUG
        }
        catch {
            Write-Log "Ошибка создания XML-отчёта: $_" -Level WARNING
        }
    }
}

function Write-HostSummary {
    [CmdletBinding()]
    param(
        [hashtable]$Results,
        [string]$TotalDuration,
        [int]$SuccessCount,
        [int]$ErrorCount
    )
    process {
        try {
            $reportPath = $config['Settings']['LogPath']
            if (-not ($reportPath)) { $reportPath = $BackupConfig['Paths']['LogPathRoot'] }
            $summaryFile = Join-Path $reportPath "${PCName}_summary.xml"
            $xml = New-Object System.Text.StringBuilder
            [void]$xml.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
            [void]$xml.AppendLine('<HostSummary>')
            [void]$xml.AppendLine("    <Host>$PCName</Host>")
            [void]$xml.AppendLine("    <LastRun>$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</LastRun>")
            [void]$xml.AppendLine("    <TotalDuration>$TotalDuration</TotalDuration>")
            [void]$xml.AppendLine("    <SuccessCount>$SuccessCount</SuccessCount>")
            [void]$xml.AppendLine("    <ErrorCount>$ErrorCount</ErrorCount>")
            foreach ($k in $Results.Keys) {
                $status = 'Success'
                $errorMsg = ''
                $val = $Results[$k]
                if ($val -match 'Ошибка|Error') { $status = 'Error'; $errorMsg = $val }
                elseif ($val -match 'ВНИМАНИЕ|WARNING') { $status = 'Warning' }
                $safeErr = $errorMsg -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                if ($errorMsg) {
                    [void]$xml.AppendLine("    <Job name=`"$k`" status=`"$status`" error=`"$safeErr`"/>")
                }
                else {
                    [void]$xml.AppendLine("    <Job name=`"$k`" status=`"$status`"/>")
                }
            }
            [void]$xml.AppendLine('</HostSummary>')
            [System.IO.File]::WriteAllText($summaryFile, $xml.ToString(), [System.Text.Encoding]::UTF8)
            Write-Log "Сводный отчёт сохранён: $summaryFile" -Level DEBUG
        }
        catch {
            Write-Log "Ошибка создания сводного отчёта: $_" -Level WARNING
        }
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ РОТАЦИИ (Remove-OldFiles.psm1)
# ==============================================================================
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateRange(0, 3650)][int]$DaysOld,
        [Parameter(Mandatory=$true)][ValidateRange(0, 100000)][int]$KeepCount,
        [Parameter(Mandatory=$true)][string]$Filter
    )
    Write-Log "Ротация файлов: $Path (DaysOld: $DaysOld, KeepCount: $KeepCount, Filter: $Filter)"
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $errorMsg = "Директория $Path не существует"
        Write-Log $errorMsg
        throw $errorMsg
    }
    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -ErrorAction Stop | Where-Object { -not ($_.PSIsContainer) } | Sort-Object LastWriteTime -Descending)
        if ($allFiles.Count -eq 0) {
            Write-Log "Нет файлов для обработки"
        }
        Write-Log "Найдено файлов: $($allFiles.Count)"
        $filesToKeep = if ($KeepCount -gt 0) { $allFiles | Select-Object -First $KeepCount } else { @() }
        $filesToDelete = $allFiles | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and
            $filesToKeep.FullName -notcontains $_.FullName
        }
        $deletedCount = 0
        if ($filesToDelete.Count -gt 0) {
            Write-Log "Файлов для удаления: $($filesToDelete.Count)"
            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Удаление файла")) {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    Write-Log "Удален: $($file.Name)"
                }
            }
        }
        else {
            Write-Log "Нет файлов для удаления"
        }
        $keptCount = $allFiles.Count - $deletedCount
        Write-Log "Сохранено файлов: $keptCount"
    }
    catch {
        $errorMsg = "Ошибка ротации файлов: $_"
        Write-Log $errorMsg
        throw $errorMsg
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ ОТПРАВКИ ПОЧТЫ (MailSender.psm1)
# ==============================================================================
function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SmtpServer,
        [Parameter(Mandatory=$true)][string]$From,
        [Parameter(Mandatory=$true)][string]$To,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body,
        [Parameter(Mandatory=$false)][int]$Port = 25,
        [Parameter(Mandatory=$false)][bool]$UseSSL = $false,
        [Parameter(Mandatory=$false)][string]$Username = $null,
        [Parameter(Mandatory=$false)][string]$Password = $null,
        [Parameter(Mandatory=$false)][bool]$IsBodyHtml = $false
    )

    try {
        $msg = New-Object -ComObject CDO.Message
        $msg.From = $From
        $msg.To = $To
        $msg.Subject = $Subject
        
        if ($IsBodyHtml) {
            $msg.HTMLBody = $Body
        } else {
            $msg.TextBody = $Body
        }

        $config = $msg.Configuration
        $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserver") = $SmtpServer
        $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = $Port
        $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2  # cdoSendUsingPort
        $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpconnectiontimeout") = 60

        if ($UseSSL) {
            $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = $true
        }

        if ($Username -and $Password) {
            $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 1  # basic auth
            $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusername") = $Username
            $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendpassword") = $Password
        } else {
            $config.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 0  # anonymous
        }

        $config.Fields.Update()
        $msg.Send()

        Write-Host "Письмо успешно отправлено: $Subject" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Ошибка отправки письма: $($_.Exception.Message)" -ForegroundColor Red
        Write-Error "Не удалось отправить письмо: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($msg) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($msg) | Out-Null }
    }
}
#endregion

# ==============================================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ КОНФИГУРАЦИИ
# ==============================================================================
function Get-BackupConfiguration {
    param([Parameter(Mandatory=$false)][hashtable]$LocalConfig = $BackupConfig)
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $currentTime = Get-Date -Format 'HHmmss'
    $resolvedJobs = @{}
    if (-not ($LocalConfig.ContainsKey('Jobs'))) {
        throw "В конфигурации не найдено раздела Jobs"
    }
    $archiverType = $LocalConfig['General']['ArchiverType']
    if (Test-StringIsNullOrWhiteSpace($archiverType)) {
        $archiverType = "RAR"
    }
    $archiverType = $archiverType.ToUpper()
    foreach ($jobDef in $LocalConfig['Jobs'].Keys) {
        $jobDefHash = $LocalConfig['Jobs'][$jobDef]
        $jobName = $jobDefHash['Name']
        if (Test-StringIsNullOrWhiteSpace($jobName)) { continue }
        $job = @{}
        foreach ($prop in $jobDefHash.Keys) {
            $job[$prop] = $jobDefHash[$prop]
        }
        $archiveExtension = ".rar"
        if ($job.ContainsKey('ArchivePattern') -and $job['ArchivePattern']) {
            $job['Archive'] = $job['ArchivePattern'] -replace '{PCName}', $PCName
            $job['Archive'] = $job['Archive'] -replace '{JobName}', $jobName
            $job['Archive'] = $job['Archive'] -replace '{Date}', $currentDate
            $job['Archive'] = $job['Archive'] -replace '{Time}', $currentTime
            $job['Archive'] = $job['Archive'] -replace '{Date_Time}', "${currentDate}_${currentTime}"
            if ($job['Archive'] -notmatch '\.rar$') {
                $job['Archive'] = $job['Archive'] -replace '\.[^.]*$', $archiveExtension
            }
        }
        else {
            $job['Archive'] = "${PCName}_${jobName}_${currentDate}${archiveExtension}"
        }
        $resolvedJobs[$jobName] = $job
    }
    $archiverPathValue = $LocalConfig['Paths']['RarPath']
    if (Test-StringIsNullOrWhiteSpace($archiverPathValue)) {
        throw "КРИТИЧЕСКАЯ ОШИБКА КОНФИГУРАЦИИ: Не найден RAR.exe"
    }
    $logPathValue = $LocalConfig['Paths']['LogPathRoot']
    if (Test-StringIsNullOrWhiteSpace($logPathValue)) {
        $logPathValue = "C:\work\$ParentJobName\logs"
        Write-Warning "LogPathRoot не найден, используется значение по умолчанию: $logPathValue"
    }
    $defaultParams = $LocalConfig['General']['DefaultRarParameters']
    if (-not ($defaultParams)) {
        $defaultParams = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t")
    }
    $settings = @{
        PCName = $PCName
        JobName = $ParentJobName
        LogPath = $logPathValue
        ArchiverType = $archiverType
        ArchiverPath = $archiverPathValue
        ArchiverParams = $defaultParams
        AdminIS = $AdminIS
        AdminOS = $AdminOS
    }
    $result = @{
        Settings = $settings
        Jobs = $resolvedJobs
    }
    return $result
}

function Test-Configuration {
    param()
    $configLocal = Get-BackupConfiguration
    $errors = @()
    if ($configLocal['Settings']['ArchiverType'] -ne "RAR") {
        $errors += "Неподдерживаемый тип архиватора: $($configLocal['Settings']['ArchiverType'])"
    }
    if (-not (Test-Path $configLocal['Settings']['ArchiverPath'])) {
        $errors += "Архиватор не найден: $($configLocal['Settings']['ArchiverPath'])"
    }
    foreach ($jobName in $configLocal['Jobs'].Keys) {
        $job = $configLocal['Jobs'][$jobName]
        if (-not (Test-Path $job['Source'])) {
            $errors += "Источник не существует ($jobName): $($job['Source'])"
        }
        if (-not ($job['LocalDest'])) {
            $errors += "Не указан локальный путь назначения ($jobName)"
        }
    }
    $result = @{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
    return $result
}

function Get-DiskSpaceReport {
    [OutputType([string])]
    param([string]$ComputerName = $env:COMPUTERNAME)
    try {
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { 
            $_.IsReady -and 
            $_.DriveType -eq 'Fixed' -and 
            $_.TotalSize -gt 1GB 
        }
        $diskStrings = @()
        foreach ($drive in $drives) {
            $sizeGB = [math]::Round($drive.TotalSize / 1GB, 1)
            $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
            $freePercent = [math]::Round(($drive.AvailableFreeSpace / $drive.TotalSize) * 100, 1)
            $diskStrings += "Диск {0} Всего(ГБ)={1:N1} Свободно(ГБ)={2:N1} Свободно={3:N1}%" -f $drive.Name.TrimEnd('\'), $sizeGB, $freeGB, $freePercent
        }
        if ($diskStrings.Count -eq 0) { 
            return "Нет локальных жёстких дисков > 1 ГБ" 
        }
        return ($diskStrings -join " ; ")
    }
    catch {
        return "Ошибка получения информации о дисках: $($_.Exception.Message)"
    }
}

function Format-FileSize {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$Path)
    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "Файл не найден" }
        $size = (Get-Item -LiteralPath $Path).Length
        switch ($size) {
            { $_ -lt 1KB } { "$_ байт"; break }
            { $_ -lt 1MB } { '{0:N2} КБ' -f ($_ / 1KB); break }
            { $_ -lt 1GB } { '{0:N2} МБ' -f ($_ / 1MB); break }
            default { '{0:N2} ГБ' -f ($_ / 1GB) }
        }
    }
}
#endregion

# ==============================================================================
#region ЭТАП 2: ОСНОВНОЙ ЗАПУСК
# ==============================================================================
$scriptStartTime = Get-Date
$config = Get-BackupConfiguration

if ($TestMode) {
    Write-Host "`n=== РЕЖИМ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    Write-Host "Проверка конфигурации без выполнения резервного копирования`n" -ForegroundColor Cyan
    $testErrors = @()
    $testWarnings = @()
    Write-Host "[1/5] Проверка архиватора..." -NoNewline
    if (Test-Path $config['Settings']['ArchiverPath']) {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $testErrors += "Архиватор не найден: $($config['Settings']['ArchiverPath'])"
    }
    Write-Host "[2/5] Проверка источников данных..." -NoNewline
    $sourceCheck = $true
    foreach ($jobName in $config['Jobs'].Keys) {
        $job = $config['Jobs'][$jobName]
        if (-not (Test-Path $job['Source'])) {
            $testErrors += "Источник не доступен [$jobName]: $($job['Source'])"
            $sourceCheck = $false
        }
    }
    if ($sourceCheck) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " FAIL" -ForegroundColor Red }
    Write-Host "[3/5] Проверка прав записи (LocalDest)..." -NoNewline
    $destCheck = $true
    foreach ($jobName in $config['Jobs'].Keys) {
        $job = $config['Jobs'][$jobName]
        try {
            if (-not (Test-Path $job['LocalDest'])) {
                New-Item -Path $job['LocalDest'] -ItemType Directory -Force -ErrorAction Stop | Remove-Item -Force
            }
        }
        catch {
            $testErrors += "Нет прав на запись [$jobName]: $($job['LocalDest'])"
            $destCheck = $false
        }
    }
    if ($destCheck) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " FAIL" -ForegroundColor Red }
    Write-Host "[4/5] Проверка настроек SMTP..." -NoNewline
    if (Test-StringIsNullOrWhiteSpace($SmtpServer)) {
        Write-Host " FAIL" -ForegroundColor Red
        $testErrors += "SMTP сервер не настроен"
    }
    else {
        Write-Host " OK ($SmtpServer)" -ForegroundColor Green
    }
    Write-Host "[5/5] Проверка получателей почты..." -NoNewline
    if (Test-StringIsNullOrWhiteSpace($AdminMail)) {
        Write-Host " WARNING" -ForegroundColor Yellow
        $testWarnings += "AdminMail не настроен в конфигурации"
    }
    else {
        Write-Host " OK ($AdminMail)" -ForegroundColor Green
    }
    Write-Host "`n=== РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    $totalDuration = [math]::Round(((Get-Date) - $scriptStartTime).TotalSeconds, 2)
    Write-Host "Время проверки: $totalDuration сек"
    Write-Host "Заданий проверено: $($config['Jobs'].Count)"
    Write-Host "Ошибок: $($testErrors.Count)"
    Write-Host "Предупреждений: $($testWarnings.Count)"
    $ReportBody = @"
РЕЖИМ: ТЕСТОВОЕ ЗАПУСК (Backup не выполнялся)
КОМПЬЮТЕР: $PCName
ЗАДАНИЕ: $ParentJobName
ВРЕМЯ: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

ПРОВЕРКИ:
- Архиватор: $(if (Test-Path $config['Settings']['ArchiverPath']) { "OK" } else { "FAIL" })
- Источники: $(if ($sourceCheck) { "OK" } else { "FAIL" })
- Назначения: $(if ($destCheck) { "OK" } else { "FAIL" })


"@
    if ($testErrors.Count -gt 0) {
        $ReportBody += "`nОШИБКИ:`n" + ($testErrors -join "`n")
    }
    if ($testWarnings.Count -gt 0) {
        $ReportBody += "`nПРЕДУПРЕЖДЕНИЯ:`n" + ($testWarnings -join "`n")
    }
    if (Test-StringIsNullOrWhiteSpace($SmtpServer)) {
        Write-Host "`nSMTP не настроен. Письмо не отправлено." -ForegroundColor Yellow
    }
    elseif (Test-StringIsNullOrWhiteSpace($AdminMail)) {
        Write-Host "`nAdminMail не настроен. Письмо не отправлено." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nОтправка тестового письма на $AdminMail..." -NoNewline
        try {
            if ($testErrors.Count -eq 0) {
                $Subject = "$PCName $ParentJobName : ТЕСТ УСПЕШЕН"
				Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $AdminMail -Subject $Subject -Body $ReportBody
                Write-Host " OK" -ForegroundColor Green
                Write-WinEventAppLog -StatusKey "Success" -MessageText "ТЕСТОВЫЙ ЗАПУСК УСПЕШЕН"
            }
            else {
                $Subject = "$PCName $ParentJobName : ТЕСТ ПРОВАЛЕН"
                Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To ($AdminIS, $AdminOS -join ", ") -Subject $Subject -Body $ReportBody
                Write-Host " OK (отчет об ошибках)" -ForegroundColor Yellow
                Write-WinEventAppLog -StatusKey "Error" -MessageText "ТЕСТОВЫЙ ЗАПУСК ПРОВАЛЕН"
            }
        }
        catch {
            Write-Host " FAIL" -ForegroundColor Red
            Write-Host "Ошибка отправки: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`nТестирование завершено." -ForegroundColor Cyan
    if ($testErrors.Count -gt 0) { exit 1 } else { exit 0 }
}

try {
    Initialize-Logging -LogPath $config['Settings']['LogPath'] -PCName $config['Settings']['PCName'] -JobName $config['Settings']['JobName']
}
catch {
    Write-Host "Ошибка инициализации логирования: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-LogSection "ЗАПУСК СКРИПТА РЕЗЕРВНОГО КОПИРОВАНИЯ" -ResultKey
Write-Log "Компьютер: $($config['Settings']['PCName'])" -ResultKey
Write-Log "Время запуска: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ResultKey
Write-Log "Количество заданий: $($config['Jobs'].Count)" -ResultKey
Write-Log "Автономная версия (только RAR)." -Level SUCCESS -ResultKey
Write-Log "Тип архиватора: RAR" -ResultKey

$configTest = Test-Configuration
if (-not ($configTest.IsValid)) {
    Write-Log "Ошибки в конфигурации:`n$($configTest.Errors -join "`n")" -Level ERROR
    exit 1
}

$results = @{}
$successCount = 0
$errorCount = 0

Write-WinEventAppLog -StatusKey "Start" -MessageText "Начало работы скрипта: $ParentJobName"

foreach ($jobName in $config['Jobs'].Keys) {
    $job = $config['Jobs'][$jobName]
    $jobStart = Get-Date
    Write-LogSection "ОБРАБОТКА ЗАДАНИЯ: $($jobName)" -ResultKey
    Write-Log "Источник: $($job['Source'])" -ResultKey
    Write-Log "Локальное назначение: $($job['LocalDest'])"
    Write-Log "Сетевое назначение: $($job['RemoteDest'])"
    Write-Log "Имя архива: $($job['Archive'])"
    try {
        if (-not (Test-Path $job['Source'])) {
            Write-Log "Источник не существует: $($job['Source'])" -Level ERROR
            throw "Источник не существует"
        }
        if (-not (Test-Path $job['LocalDest'])) {
            New-Item -Path $job['LocalDest'] -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан каталог локального назначения: $($job['LocalDest'])" -Level INFO
        }
        if ($job['RemoteDest'] -and (-not (Test-Path $job['RemoteDest']))) {
            New-Item -Path $job['RemoteDest'] -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан каталог удаленного назначения: $($job['RemoteDest'])" -Level INFO
        }
        $fileInfo = Get-FileInfoDetails -Path $job['Source']
        Write-Log "Найдено файлов: $($fileInfo.FileCount)" -ResultKey
        $SourceFilesSize = if ($fileInfo.TotalSizeBytes -lt 1MB) { "{0:N0} Bytes" -f $fileInfo.TotalSizeBytes } else { "{0:N1} MB" -f $fileInfo.TotalSizeMB }
        Write-Log "Общий размер: $SourceFilesSize" -ResultKey
        
        if ($job.ContainsKey('SourceCheckMasks') -and $job['SourceCheckMasks']) {
            Write-Log "Проверка наличия файлов по маскам..." -Level INFO
            foreach ($mask in $job['SourceCheckMasks']) {
                try {
                    $filteredFiles = Get-FilterFileList -Path $job['Source'] -Filter $mask
                    if ($filteredFiles.Count -eq 0) {
                        Write-Log "ОШИБКА МАСКИ: Файлы по маске '$mask' не найдены!" -Level ERROR -ResultKey
                    }
                    else {
                        Write-Log "Маска '$mask': найдено $($filteredFiles.Count) шт." -ResultKey
                    }
                }
                catch {
                    Write-Log "Ошибка при проверке маски '$mask': $($_.Exception.Message)" -Level ERROR -ResultKey
                }
            }
        }
        
        if ($job.ContainsKey('ListSourceFlag') -and $job['ListSourceFlag']) {
            $listFlag = $job['ListSourceFlag']
            $listType = $listFlag.ToLower()
            if ($listType -eq "txt" -or $listType -eq "csv") {
                Write-Log "Формирование списка файлов ($($listType.ToUpper()))..."
                try {
                    $sourceFilesList = Get-FileList -Path $job['Source']
                    $listFileName = [System.IO.Path]::ChangeExtension($job['Archive'], ".$listType")
                    $listFilePath = Join-Path -Path $config['Settings']['LogPath'] -ChildPath $listFileName
                    if ($listType -eq "csv") {
                        $sourceFilesList | Select-Object RelativePath, Length, LastWriteTime |
                            Export-Csv -Path $listFilePath -NoTypeInformation -Encoding UTF8 -Delimiter ";"
                    }
                    else {
                        $sourceFilesList | Select-Object RelativePath, Length, LastWriteTime |
                            Format-Table -AutoSize | Out-File -FilePath $listFilePath -Encoding UTF8
                    }
                    Write-Log "Список файлов сохранен: $listFilePath ($($sourceFilesList.Count) шт.)" -ResultKey
                }
                catch {
                    Write-Log "Ошибка при формировании списка файлов: $_" -Level WARNING
                }
            }
            else {
                Write-Log "Неизвестное значение ListSourceFlag: '$listFlag'. Допустимо: txt, csv." -Level WARNING
            }
        }

        #region Блок Архивации файлов в отдельный архив
        $archiveIndividual = $false
        if ($job.ContainsKey('ArchiveIndividualFiles')) {
            $archiveIndividual = [System.Convert]::ToBoolean($job['ArchiveIndividualFiles'])
        }
        if ($archiveIndividual) {
            $jobStartInd = Get-Date
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ФАЙЛОВ" -ResultKey
            Write-Log "Режим: Каждый файл в отдельный архив" -ResultKey
            if (Test-StringIsNullOrWhiteSpace($job['SourceFilter'])) {
                Write-Log "ОШИБКА: Для индивидуальной архивации требуется параметр SourceFilter" -Level ERROR -ResultKey
                throw "Для индивидуальной архивации требуется параметр SourceFilter"
            }
            $archiverParams = if ($job.ContainsKey('ArhParameters')) { $job['ArhParameters'] } else { $config['Settings']['ArchiverParams'] }
            $individualArchivePattern = "{PCName}_{JobName}_{SourceFileName}.rar"
            if ($job.ContainsKey('IndividualArchivePattern') -and -not (Test-StringIsNullOrWhiteSpace($job['IndividualArchivePattern']))) {
                $individualArchivePattern = $job['IndividualArchivePattern']
            }
            $individualResults = Start-IndividualFileArchive `
                -ArchiverType $config['Settings']['ArchiverType'] `
                -ArchiverPath $config['Settings']['ArchiverPath'] `
                -SourcePath $job['Source'] `
                -DestinationPath $job['LocalDest'] `
                -FileFilter $job['SourceFilter'] `
                -ArchivePattern $individualArchivePattern `
                -Parameters $archiverParams `
                -PCName $config['Settings']['PCName'] `
                -JobName $jobName `
                -LogPath $(if ($job['ArhLog']) { Join-Path $job['LocalDest'] "individual_archiver.log" } else { $null }) `
                -ExcludeFilePattern $job['ExcludeFilePattern']
            $successFiles = ($individualResults | Where-Object { $_.Status -eq 'Success' }).Count
            $errorFiles = ($individualResults | Where-Object { $_.Status -eq 'Error' }).Count
            if ($errorFiles -gt 0) {
                Write-Log "Индивидуальная архивация завершена с ошибками: $errorFiles из $($individualResults.Count)" -Level ERROR -ResultKey
                $errorCount += $errorFiles
                $results[$jobName] = "Частичный успех: $successFiles/$($individualResults.Count) файлов"
            }
            else {
                Write-Log "Индивидуальная архивация завершена успешно: $($individualResults.Count) файлов" -Level SUCCESS -ResultKey
                $successCount++
                $results[$jobName] = "Успешно: $($individualResults.Count) архивов"
            }
            if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
                Write-Log "Копирование архивов в сетевое хранилище..." -Level INFO
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -eq 'Success' -and (Test-Path $archiveResult.ArchivePath)) {
                        $remotePath = Join-Path $job['RemoteDest'] (Split-Path $archiveResult.ArchivePath -Leaf)
                        try {
                            $copyResult = Copy-BackupFile -SourcePath $archiveResult.ArchivePath -DestinationPath $remotePath
                            if ($copyResult.Success) {
                                Write-Log "Копирование успешно: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level SUCCESS
                                $results[$jobName] = "Успешно скопировано из $(Split-Path $archiveResult.ArchivePath -Leaf) в $remotePath "
                            }
                            else {
                                Write-Log "Ошибка копирования: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level ERROR
                            }
                        }
                        catch {
                            Write-Log "Ошибка копирования $($_.Exception.Message)" -Level ERROR
                        }
                    }
                }
                if ($job.ContainsKey('RemoveRemoteDestFlag') -and $job['RemoveRemoteDestFlag']) {
                    Write-Log "Ротация удалённого хранилища..." -Level INFO
                    try {
                        Remove-OldFiles -Path $job['RemoteDest'] -DaysOld $job['RemoteDestDaysOld'] -KeepCount $job['RemoteDestKeepCount'] -Filter "*.*"
                    }
                    catch {
                        Write-Log "Ошибка ротации удалённого хранилища: $_" -Level WARNING
                    }
                }
            }
            Write-Log "Ротация локального хранилища..." -Level INFO
            try {
                Remove-OldFiles -Path $job['LocalDest'] -DaysOld $job['LocalDestDaysOld'] -KeepCount $job['LocalDestKeepCount'] -Filter "*.*"
            }
            catch {
                Write-Log "Ошибка ротации локального хранилища: $_" -Level WARNING
            }
            if ($job.ContainsKey('RemoveSourceFlag') -and $job['RemoveSourceFlag']) {
                Write-LogSection "ВЕРИФИКАЦИЯ ПЕРЕД УДАЛЕНИЕМ ИСТОЧНИКА" -ResultKey
                $verifiedForDeletion = @()
                $verificationFailed = 0
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -ne 'Success' -or -not (Test-Path $archiveResult.ArchivePath)) {
                        Write-Log "Пропуск удаления (архив не создан): $($archiveResult.SourceFile)" -Level WARNING -ResultKey
                        continue
                    }
                    try {
                        $sourceFileItem = Get-Item $archiveResult.SourceFileFullName -ErrorAction Stop
                        $sourceFileInfo = @(
                            New-Object PSObject -Property @{
                                RelativePath = $archiveResult.SourceFile
                                Length = $sourceFileItem.Length
                                LastWriteTime = $sourceFileItem.LastWriteTime
                                FullName = $sourceFileItem.FullName
                            }
                        )
                        $archiveFiles = Get-FileArhListRar -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archiveResult.ArchivePath
                        $verifyResult = Compare-FilesSourceArchive -SourceList $sourceFileInfo -ArchiveList $archiveFiles -SourcePath $job['Source']
                        if ($verifyResult.IsIdentical) {
                            Write-Log "ВЕРИФИКАЦИЯ ОК: $($archiveResult.SourceFile)" -Level SUCCESS -ResultKey
                            $verifiedForDeletion += $archiveResult
                        }
                        else {
                            Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА: $($archiveResult.SourceFile) — $($verifyResult.Report)" -Level ERROR -ResultKey
                            $verificationFailed++
                        }
                    }
                    catch {
                        Write-Log "Ошибка верификации $($archiveResult.SourceFile): $_" -Level ERROR -ResultKey
                        $verificationFailed++
                    }
                }
                if ($verificationFailed -gt 0) {
                    Write-Log "ВНИМАНИЕ: $verificationFailed файл(ов) не прошли верификацию — удаление ОТМЕНЕНО" -Level ERROR -ResultKey
                }
                else {
                    foreach ($item in $verifiedForDeletion) {
                        $fullPath = $item.SourceFileFullName
                        if (Test-Path $fullPath) {
                            Remove-Item -LiteralPath $fullPath -Force -ErrorAction Stop
                            Write-Log "Удалён источник: $fullPath" -ResultKey
                        }
                    }
                    Write-Log "Удалено файлов после верификации: $($verifiedForDeletion.Count)" -Level SUCCESS -ResultKey
                }
            }
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ЗАВЕРШЕНА" -ResultKey
            
            # Формирование XML-отчёта
            $jobDurationInd = [math]::Round(((Get-Date) - $jobStartInd).TotalMinutes, 2)
            if ($errorFiles -gt 0) {
                $jobStatusInd = 'Error'
            } elseif ($successFiles -gt 0) {
                $jobStatusInd = 'Success'
            } else {
                $jobStatusInd = 'Warning'
            }
            $totalArchiveSize = ($individualResults | Where-Object { $_.Status -eq 'Success' } | Measure-Object -Property ArchiveSize -Sum).Sum
            if ($job.ContainsKey('RemoveSourceFlag') -and $job['RemoveSourceFlag']) {
                if ($verificationFailed -eq 0 -and $successFiles -eq $individualResults.Count) {
                    $verificationStatus = 'Passed'
                } else {
                    $verificationStatus = 'Failed'
                }
            } else {
                $verificationStatus = 'Skipped'
            }
            Write-BackupXmlReport -JobName $jobName -JobStatus $jobStatusInd -Duration "$jobDurationInd мин" `
                -SourceFiles $fileInfo.FileCount -ArchiveSizeMB $totalArchiveSize -Verification $verificationStatus `
                -Errors @() -LogPath $(Get-LogFilePath)
            continue
        }
        #endregion

        #region Блок Архивации каталогов в отдельный архив
        $archiveIndividualFolders = $false
        if ($job.ContainsKey('ArchiveIndividualFolders')) {
            $archiveIndividualFolders = [System.Convert]::ToBoolean($job['ArchiveIndividualFolders'])
        }
        if ($archiveIndividualFolders) {
            $jobStartInd = Get-Date
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ПОДПАПОК" -ResultKey
            Write-Log "Режим: Каждая подпапка в отдельный архив" -ResultKey
            $archiverParams = if ($job.ContainsKey('ArhParameters')) { $job['ArhParameters'] } else { $config['Settings']['ArchiverParams'] }
            $individualArchivePattern = "{PCName}_{JobName}_{SourceFolderName}.rar"
            if ($job.ContainsKey('IndividualArchivePattern') -and -not (Test-StringIsNullOrWhiteSpace($job['IndividualArchivePattern']))) {
                $individualArchivePattern = $job['IndividualArchivePattern']
            }
            $folderFilter = if ($job.ContainsKey('SourceFilter') -and -not (Test-StringIsNullOrWhiteSpace($job['SourceFilter']))) { $job['SourceFilter'] } else { $null }
            $excludeFolderPattern = if ($job.ContainsKey('ExcludeFolderPattern') -and -not (Test-StringIsNullOrWhiteSpace($job['ExcludeFolderPattern']))) { $job['ExcludeFolderPattern'] } else { $null }
            $individualResults = Start-IndividualFolderArchive `
                -ArchiverType $config['Settings']['ArchiverType'] `
                -ArchiverPath $config['Settings']['ArchiverPath'] `
                -SourcePath $job['Source'] `
                -DestinationPath $job['LocalDest'] `
                -ArchivePattern $individualArchivePattern `
                -FolderFilter $folderFilter `
                -ExcludeFolderPattern $excludeFolderPattern `
                -Parameters $archiverParams `
                -PCName $config['Settings']['PCName'] `
                -JobName $jobName `
                -LogPath $(if ($job['ArhLog']) { Join-Path $job['LocalDest'] "folder_archiver.log" } else { $null })
            $successFolders = ($individualResults | Where-Object { $_.Status -eq 'Success' }).Count
            $errorFolders = ($individualResults | Where-Object { $_.Status -eq 'Error' }).Count
            if ($errorFolders -gt 0) {
                Write-Log "Индивидуальная архивация завершена с ошибками: $errorFolders из $($individualResults.Count)" -Level ERROR -ResultKey
                $errorCount += $errorFolders
                $results[$jobName] = "Частичный успех: $successFolders/$($individualResults.Count) папок"
            }
            else {
                Write-Log "Индивидуальная архивация завершена успешно: $($individualResults.Count) папок" -Level SUCCESS -ResultKey
                $successCount++
                $results[$jobName] = "Успешно: $($individualResults.Count) архивов"
            }
            if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
                Write-Log "Копирование архивов в сетевое хранилище..." -Level INFO
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -eq 'Success' -and (Test-Path $archiveResult.ArchivePath)) {
                        $remotePath = Join-Path $job['RemoteDest'] (Split-Path $archiveResult.ArchivePath -Leaf)
                        try {
                            $copyResult = Copy-BackupFile -SourcePath $archiveResult.ArchivePath -DestinationPath $remotePath
                            if ($copyResult.Success) {
                                Write-Log "Копирование успешно: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level SUCCESS
                                $results[$jobName] = "Успешно скопировано из $(Split-Path $archiveResult.ArchivePath -Leaf) в $remotePath "
                            }
                            else {
                                Write-Log "Ошибка копирования: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level ERROR
                            }
                        }
                        catch {
                            Write-Log "Ошибка копирования $($_.Exception.Message)" -Level ERROR
                        }
                    }
                }
                if ($job.ContainsKey('RemoveRemoteDestFlag') -and $job['RemoveRemoteDestFlag']) {
                    Write-Log "Ротация удалённого хранилища..." -Level INFO
                    try {
                        Remove-OldFiles -Path $job['RemoteDest'] -DaysOld $job['RemoteDestDaysOld'] -KeepCount $job['RemoteDestKeepCount'] -Filter "*.*"
                    }
                    catch {
                        Write-Log "Ошибка ротации удалённого хранилища: $_" -Level WARNING
                    }
                }
            }
            Write-Log "Ротация локального хранилища..." -Level INFO
            try {
                Remove-OldFiles -Path $job['LocalDest'] -DaysOld $job['LocalDestDaysOld'] -KeepCount $job['LocalDestKeepCount'] -Filter "*.*"
            }
            catch {
                Write-Log "Ошибка ротации локального хранилища: $_" -Level WARNING
            }
            if ($job.ContainsKey('RemoveSourceFlag') -and $job['RemoveSourceFlag']) {
                Write-LogSection "ВЕРИФИКАЦИЯ ПЕРЕД УДАЛЕНИЕМ ПАПОК ИСТОЧНИКА" -ResultKey
                $verifiedFoldersForDeletion = @()
                $verificationFailed = 0
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -ne 'Success' -or -not (Test-Path $archiveResult.ArchivePath)) {
                        Write-Log "Пропуск удаления папки (архив не создан): $($archiveResult.SourceFolder)" -Level WARNING -ResultKey
                        continue
                    }
                    try {
                        $folderPath = $archiveResult.SourceFolderFullPath
                        $sourceFiles = Get-FileList -Path $folderPath
                        $archiveFiles = Get-FileArhListRar -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archiveResult.ArchivePath
                        if ($sourceFiles.Count -eq 0) {
                            Write-Log "Папка пуста, пропуск верификации: $($archiveResult.SourceFolder)" -Level WARNING -ResultKey
                            $verifiedFoldersForDeletion += $archiveResult
                            continue
                        }
                        $verifyResult = Compare-FilesSourceArchive -SourceList $sourceFiles -ArchiveList $archiveFiles -SourcePath $folderPath
                        if ($verifyResult.IsIdentical) {
                            Write-Log "ВЕРИФИКАЦИЯ ОК: $($archiveResult.SourceFolder) ($($sourceFiles.Count) файлов)" -Level SUCCESS -ResultKey
                            $verifiedFoldersForDeletion += $archiveResult
                        }
                        else {
                            Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА: $($archiveResult.SourceFolder) — $($verifyResult.Report)" -Level ERROR -ResultKey
                            $verificationFailed++
                        }
                    }
                    catch {
                        Write-Log "Ошибка верификации $($archiveResult.SourceFolder): $_" -Level ERROR -ResultKey
                        $verificationFailed++
                    }
                }
                if ($verificationFailed -gt 0) {
                    Write-Log "ВНИМАНИЕ: $verificationFailed папок не прошли верификацию — удаление ОТМЕНЕНО" -Level ERROR -ResultKey
                }
                else {
                    foreach ($item in $verifiedFoldersForDeletion) {
                        $folderPath = $item.SourceFolderFullPath
                        if (Test-Path $folderPath) {
                            Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                            Write-Log "Удалена папка источника: $($item.SourceFolder)" -Level INFO -ResultKey
                        }
                    }
                    Write-Log "Удалено папок после верификации: $($verifiedFoldersForDeletion.Count)" -Level SUCCESS -ResultKey
                }
            }
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ПОДПАПОК ЗАВЕРШЕНА" -ResultKey
            
            # Формирование XML-отчёта
            $jobDurationInd = [math]::Round(((Get-Date) - $jobStartInd).TotalMinutes, 2)
            if ($errorFolders -gt 0) {
                $jobStatusInd = 'Error'
            } elseif ($successFolders -gt 0) {
                $jobStatusInd = 'Success'
            } else {
                $jobStatusInd = 'Warning'
            }
            $totalArchiveSize = ($individualResults | Where-Object { $_.Status -eq 'Success' } | Measure-Object -Property ArchiveSize -Sum).Sum
            if ($job.ContainsKey('RemoveSourceFlag') -and $job['RemoveSourceFlag']) {
                if ($verificationFailed -eq 0 -and $successFolders -eq $individualResults.Count) {
                    $verificationStatus = 'Passed'
                } else {
                    $verificationStatus = 'Failed'
                }
            } else {
                $verificationStatus = 'Skipped'
            }
            Write-BackupXmlReport -JobName $jobName -JobStatus $jobStatusInd -Duration "$jobDurationInd мин" `
                -SourceFiles $fileInfo.FileCount -ArchiveSizeMB $totalArchiveSize -Verification $verificationStatus `
                -Errors @() -LogPath $(Get-LogFilePath)
            continue
        }
        #endregion

        $archivePath = Join-Path $job['LocalDest'] $job['Archive']
        $archiverParams = if ($job.ContainsKey('ArhParameters')) { $job['ArhParameters'] } else { $config['Settings']['ArchiverParams'] }
        $archiveType = "rar"
        $ArhLogPath = $null
        if ($job['ArhLog']) {
            $archiveDir = Split-Path -Path $archivePath -Parent
            $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($archivePath)
            $ArhLogPath = Join-Path -Path $archiveDir -ChildPath "${archiveName}_archiver.log"
        }
        Write-Log "Начало архивации (Тип: $archiveType)..." -ResultKey
        $sourceFilter = if ($job.ContainsKey('SourceFilter') -and -not (Test-StringIsNullOrWhiteSpace($job['SourceFilter']))) { $job['SourceFilter'] } else { $null }
        $arhResult = Start-RarArchive -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archivePath -SourcePath $job['Source'] -Parameters $archiverParams -LogPath $ArhLogPath -SourceFilter $sourceFilter
        Write-Log "Архивация завершена за $($arhResult.Duration) мин. Код: $($arhResult.ExitCode)" -ResultKey
        if ($arhResult.ExitCode -ne 0) {
            $errorDesc = Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode
            Write-Log "Ошибка архиватора: $errorDesc" -Level ERROR
            if ($ArhLogPath -and (Test-Path $ArhLogPath)) {
                $logContent = Get-Content -Path $ArhLogPath -Raw
                Write-Log "Лог архиватора:`n$logContent" -Level ERROR
            }
            throw "Ошибка архиватора: $errorDesc"
        }
        if (-not (Test-Path $archivePath)) { throw "Архив не создан" }
        Write-Log "Архив создан: $(Format-FileSize -Path $archivePath)" -ResultKey
        $testResult = Test-RarArchive -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archivePath
        if (-not $testResult.IsValid) { throw "Ошибка проверки целостности архива" }
        try {
            if ($sourceFilter) {
                Write-Log "ВЕРИФИКАЦИЯ по маске SourceFilter: $sourceFilter" -ResultKey
                $sourceFiles = Get-FilterFileList -Path $job['Source'] -Filter $sourceFilter
            }
            else {
                Write-Log "ВЕРИФИКАЦИЯ всех файлов источника" -ResultKey
                $sourceFiles = Get-FileList -Path $job['Source']
            }
            $archiveFiles = Get-FileArhListRar -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archivePath
            if (-not ($archiveFiles) -or $archiveFiles.Count -eq 0) {
                Write-Log "Архив пуст или не содержит файлов!" -Level ERROR
                throw "Архив пуст или не содержит файлов"
            }
            $verifyResult = Compare-FilesSourceArchive -SourceList $sourceFiles -ArchiveList $archiveFiles -SourcePath $job['Source']
            if ($verifyResult.IsIdentical) {
                Write-Log "ВЕРИФИКАЦИЯ ПРОЙДЕНА: $($verifyResult.Report)" -Level SUCCESS -ResultKey
            }
            else {
                Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА!" -Level ERROR -ResultKey
                Write-Log $verifyResult.Report -Level ERROR -ResultKey
                throw "Нарушение целостности архива. Файлы не совпадают с источником."
            }
        }
        catch {
            Write-Log "Критическая ошибка этапа верификации: $($_.Exception.Message)" -Level ERROR
            throw
        }
        if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
            $remotePath = Join-Path $job['RemoteDest'] $job['Archive']
            Write-Log "Старт копирование из $archivePath в $remotePath"
            $copyResult = Copy-BackupFile -SourcePath $archivePath -DestinationPath $remotePath
            if ($copyResult.Success) {
                Write-Log "Копирование успешно." -ResultKey
                Remove-OldFiles -Path $job['LocalDest'] -DaysOld $job['LocalDestDaysOld'] -KeepCount $job['LocalDestKeepCount'] -Filter "*.*"
                $results[$jobName] = "Успешно скопировано из $archivePath в  $remotePath "
                $successCount++
            }
            else { throw "Контрольная сумма при копировании не совпадает" }
        }
        else {
            Write-Log " $($job['RemoteDest']) недоступен, сохранено локально." -Level WARNING
            $results[$jobName] = "ВНИМАНИЕ $archivePath сохранен только ЛОКАЛЬНО - Скопировать в Ручную!!! "
            $errorCount++
        }
        if ($job.ContainsKey('RemoveSourceFlag') -and $job['RemoveSourceFlag']) {
            Write-Log "Ротация источника: $($job['Source']) (DaysOld: $($job['SourceDaysOld']), KeepCount: $($job['SourceKeepCount']))"
            try {
                $filterForRemove = if ($sourceFilter) { $sourceFilter } else { "*" }
                Remove-OldFiles -Path $job['Source'] -DaysOld $job['SourceDaysOld'] -KeepCount $job['SourceKeepCount'] -Filter $filterForRemove
            }
            catch { Write-Log "Ошибка ротации источника: $_" -Level WARNING }
        }
        if ($job.ContainsKey('RemoveRemoteDestFlag') -and $job['RemoveRemoteDestFlag'] -and $job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
            Write-Log "Ротация удаленного хранилища: $($job['RemoteDest']) (DaysOld: $($job['RemoteDestDaysOld']), KeepCount: $($job['RemoteDestKeepCount']))"
            try {
                Remove-OldFiles -Path $job['RemoteDest'] -DaysOld $job['RemoteDestDaysOld'] -KeepCount $job['RemoteDestKeepCount'] -Filter "*.*"
            }
            catch { Write-Log "Ошибка ротации удаленного хранилища: $_" -Level WARNING }
        }
    }
    catch {
        Write-Log "ОШИБКА: $_" -Level ERROR
        $results[$jobName] = "Ошибка: $_"
        $errorCount++
    }
    $jobDuration = [math]::Round(((Get-Date) - $jobStart).TotalMinutes, 2)
    Write-Log "Задание завершено за $jobDuration мин. Результат: $($results[$jobName])" -ResultKey
    $jobStatus = if ($results[$jobName] -match 'Ошибка|Error') { 'Error' } elseif ($results[$jobName] -match 'ВНИМАНИЕ|WARNING') { 'Warning' } else { 'Success' }
    Write-BackupXmlReport -JobName $jobName -JobStatus $jobStatus -Duration "$jobDuration мин" -SourceFiles $fileInfo.FileCount -ArchiveSizeMB $(if ($arhResult) { $arhResult.ArchiveSize } else { 0 }) -Verification $(if ($verifyResult -and $verifyResult.IsIdentical) { 'Passed' } elseif ($verifyResult) { 'Failed' } else { 'Skipped' }) -Errors $(if ($jobStatus -eq 'Error') { @($results[$jobName]) } else { @() }) -LogPath $(Get-LogFilePath)
}

Write-Log "=== ДИАГНОСТИКА ОЧИСТКИ ЛОГОВ ===" -Level INFO
$logDir = $config['Settings']['LogPath']
if (Test-Path $logDir) {
    $allLogs = Get-ChildItem -Path $logDir | Where-Object { -not ($_.PSIsContainer) } | Sort-Object LastWriteTime -Descending
    Write-Log "Всего файлов в '$logDir': $($allLogs.Count)" -Level INFO
    $cutoff = (Get-Date).AddDays(-$LogDaysOld)
    Write-Log "Cutoff date (старше $LogDaysOld дней): $cutoff" -Level INFO
    $oldFiles = $allLogs | Where-Object { $_.LastWriteTime -lt $cutoff }
    Write-Log "Файлов старше $LogDaysOld дней: $($oldFiles.Count)" -Level INFO
    if ($oldFiles.Count -gt 0) {
        Write-Log "Примеры:" -Level INFO
        $oldFiles | Select-Object -First 3 | ForEach-Object {
            Write-Log "  $($_.Name) : $($_.LastWriteTime)" -Level INFO
        }
    }
    Write-Log "KeepCount = $LogKeepCount, будет сохранено первых $LogKeepCount файлов из $($allLogs.Count)" -Level INFO
}

Write-LogSection "ОЧИСТКА СТАРЫХ ЛОГОВ"
try {
    Remove-OldFiles -Path $config['Settings']['LogPath'] -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.*"
}
catch { Write-Log "Ошибка очистки логов: $_" -Level WARNING }

#endregion

# ==============================================================================
#region ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ
# ==============================================================================
$scriptEndTime = Get-Date
$totalDuration = [math]::Round(($scriptEndTime - $scriptStartTime).TotalMinutes, 2)
$DiskSpaceInfo = Get-DiskSpaceReport

Write-LogSection "ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ" -ResultKey
Write-Log "Время выполнения: $totalDuration мин" -ResultKey
Write-Log "Успешно: $successCount | Ошибки: $errorCount" -ResultKey
Write-Log "Диски: $DiskSpaceInfo" -ResultKey
foreach ($k in $results.Keys) { Write-Log "  $k : $($results[$k])" }

Write-HostSummary -Results $results -TotalDuration "$totalDuration мин" -SuccessCount $successCount -ErrorCount $errorCount

$EmailTextBody = Get-LogResults
$EmailTextBody += "`nПодробнее в логе: $(Get-LogFilePath)"

if ($errorCount -gt 0) {
    $AdminMailList = @($AdminIS, $AdminOS)
    $Subject = "ТЕСТ $PCName $ParentJobName : ОБНАРУЖЕНЫ ОШИБКИ"
    $Body = "Ошибки в процессе:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Error" -MessageText "СКРИПТ ЗАВЕРШЕН С ОШИБКАМИ"
}
else {
    $AdminMailList = @($AdminIS, $AdminMail)
    $Subject = "$PCName $ParentJobName : УСПЕХ"
    $Body = "ТЕСТ Задание выполнено успешно:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Success" -MessageText "СКРИПТ ЗАВЕРШЕН УСПЕШНО"
}

if (Test-StringIsNullOrWhiteSpace($SmtpServer)) {
    Write-Log "Ошибка: Переменная SmtpServer пуста. Проверьте XML конфигурацию (General.SmtpServer)." -Level ERROR
}
elseif (Test-StringIsNullOrWhiteSpace($PCNameMail)) {
    Write-Log "Ошибка: Переменная From (PCNameMail) пуста." -Level ERROR
}
else {
    try {
        $mailResult = Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To ($AdminMailList -join ", ") -Subject $Subject -Body $Body
        if (-not ($mailResult)) { }
    }
    catch {
        Write-Log "Критическая ошибка при вызове функции отправки почты: $_" -Level ERROR
    }
}

Write-WinEventAppLog -StatusKey "End" -MessageText "Завершение скрипта: $ParentJobName"

if ($errorCount -gt 0) { exit 1 } else { exit 0 }
#endregion