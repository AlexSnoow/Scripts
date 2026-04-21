<#
.SYNOPSIS
    Автономный скрипт резервного копирования
.DESCRIPTION
    Унифицированная логика архивации без дублирования кода.
    Поддерживает XML-конфигурацию: Backup-Config-All.xml
    Архиватор: только RAR

    Единый конвейер для всех режимов:
      1) Подготовка списка элементов архивации (файлы/папки/всё)
      2) Архивация единым механизмом
      3) Верификация (включая файлы 0 байт)
      4) Пост-операции (копирование, ротация, удаление источника)
      5) Сохранение отчётов (XML, CSV) по сетевому пути (NetLogPath)

    Переменные для ArchivePattern:
    - {PCName} - Имя компьютера
    - {JobName} - Имя одного из дочерних задания
    - {Date} - Дата в формате YYYYMMDD
    - {Time} - Время в формате HHMMSS
    - {Date_Time} - Дата и время в формате YYYYMMDD_HHMMSS
    - {SourceFileName} - Имя исходного файла
    - {SourceFolderName} - Имя исходной папки

.PARAMETER TestMode
    Тестовый запуск без выполнения резервного копирования

.EXAMPLE
    powershell.exe -executionpolicy RemoteSigned -file .\<ИМЯ скрипта>.ps1

.NOTES
    Версия: 3.2 (Сетевые отчёты XML/CSV через NetLogPath)
    Дата: 2026-04-12
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
$XmlFile = "Backup-Config-All.xml"
$XmlHash = "3C5930C2C8B5948675F9B2E7E42EF40ADC0F130B183A810B170BDF580CC64965"

Clear-Host

# ===========================================================
# PS 2.0 совместимость: [string]::IsNullOrWhiteSpace
# ===========================================================
function Test-StringIsNullOrWhiteSpace {
    param([string]$Value)
    if ($Value -eq $null) { return $true }
    if ($Value -eq '') { return $true }
    if ($Value -match '^\s*$') { return $true }
    return $false
}

# ===========================================================
# Корневая директория скрипта (PS 2.0)
# ===========================================================
if ($MyInvocation.MyCommand.Path) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $ScriptRoot = (Get-Location).Path
}

# ===========================================================
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША
# ===========================================================
function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0, ValueFromPipeline = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'LiteralPath')]
        [string]$LiteralPath,
        [Parameter(Mandatory = $false)]
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
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
                'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
                default { [System.Security.Cryptography.SHA256]::Create() }
            }
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                $obj = New-Object PSObject -Property @{
                    Hash      = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path      = (Resolve-Path -LiteralPath $filePath).Path
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
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $false)][string]$FileType = "Файл"
    )
    process {
        # Проверка формата хеша ВНУТРИ функции (ValidatePattern бросает исключение до тела)
        if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) {
            Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Неверный формат хеша (ожидается 64 hex символа)" -ForegroundColor Red
            Write-Error "Неверный формат хеша для $FileType"
            return $false
        }
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
            Write-Host "  Ожидаемый   : $expectedHashUpper"
            Write-Host "  Фактический : $actualHash"
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
#region ЭТАП 0: ПРОВЕРКА XML и загрузка конфигурации
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
#region CONFIG_BLOCK: Загрузка конфигурации из XML
# ===========================================================
[xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
$b = $xmlDoc.BackupConfig

$archiverType = $b.General.ArchiverType
if ($archiverType -ne "RAR") {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Скрипт настроен только на RAR, в конфигурации указан '$archiverType'" -ForegroundColor Red
    exit 1
}

$Script:EmbeddedConfig = @{
    General    = @{
        JobName      = $b.General.JobName
        Domain       = $b.General.Domain
        SmtpServer   = $b.General.SmtpServer
        LogDaysOld   = [int]$b.General.LogDaysOld
        LogKeepCount = [int]$b.General.LogKeepCount
        ArchiverType = $b.General.ArchiverType
    }
    Paths      = @{
        LogPathRoot = $b.Paths.LogPathRoot
        NetLogPath  = $b.Paths.NetLogPath
        RarPath     = $b.Paths.RarPath
    }
    Recipients = @{
        AdminIS   = $b.Recipients.AdminIS
        AdminOS   = $b.Recipients.AdminOS
        AdminMail = $b.Recipients.AdminMail
    }
    Integrity  = @{
        RarExeHash = $b.Integrity.RarExeHash
    }
    Jobs       = @{}
}

foreach ($jobNode in $b.Jobs.Job) {
    $jn = $jobNode.Name
    $Script:EmbeddedConfig['Jobs'][$jn] = @{
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
        RemoteDestDaysOld        = [int]$jobNode.RemoteDestDaysOld
        RemoteDestKeepCount      = [int]$jobNode.RemoteDestKeepCount
        ArhLog                   = ($jobNode.ArhLog -eq 'true')
        ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
        ArchiveIndividualFiles   = ($jobNode.ArchiveIndividualFiles -eq 'true')
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
    Jobs     = $BackupConfig['Jobs']
}
#endregion

# ===========================================================
# Базовые переменные
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
$NetLogPath = $BackupConfig['Paths']['NetLogPath']

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
#region МОДУЛЬ ЛОГИРОВАНИЯ
# ==============================================================================
$Script:LogPath = $null
$Script:MainLogFile = $null
$Script:ReportEntries = @()

function Initialize-Logging {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$LogPath,
        [Parameter(Mandatory = $true, Position = 1)][string]$PCName,
        [Parameter(Mandatory = $true, Position = 2)][string]$JobName
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
            throw "Критическая ошибка инициализации логирования: $($_.Exception.Message)"
        }
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][ValidateNotNull()][string]$Message,
        [Parameter(Mandatory = $false, Position = 1)][ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')][string]$Level = 'INFO',
        [Parameter(Mandatory = $false)][switch]$ResultKey
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
                'ERROR' { '[ERROR]  ' }
                'WARNING' { '[WARNING]' }
                'SUCCESS' { '[SUCCESS]' }
                'DEBUG' { '[DEBUG]  ' }
                default { '[INFO]   ' }
            }
            $safeMessage = $Message -replace '\r?\n', ' '
            $logEntry = "[$timestamp] $levelPrefix $safeMessage"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$logEntry`r`n", $utf8NoBom)
            if ($ResultKey) {
                $Script:ReportEntries += $logEntry
            }
            switch ($Level) {
                'ERROR' { Write-Error $Message   -ErrorAction Continue }
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
        [Parameter(Mandatory = $false)][string]$Title,
        [Parameter(Mandatory = $false)][switch]$ResultKey
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

# ==============================================================================
#region СОХРАНЕНИЕ ОТЧЁТОВ ПО СЕТЕВОМУ ПУТИ (NetLogPath)
# ==============================================================================

<#
.SYNOPSIS
    Сохраняет XML и CSV отчёты по сетевому пути (NetLogPath).
.DESCRIPTION
    Для централизованного сбора отчётов со всех ПК.
    Все файлы сохраняются прямо в корень NetLogPath (без подкаталогов):
    - Отчёт XML: <PCName>_<JobName>_<timestamp>.xml
    - Список файлов CSV: <PCName>_<JobName>_<timestamp>.csv
    - Сводный отчёт: <PCName>_summary.xml (обновляется при каждом запуске)
    Примеры:
      \\server\share\NetLogs\HOME-PC_JOB1_20260412_205449.xml
      \\server\share\NetLogs\HOME-PC_summary.xml
      \\server\share\NetLogs\WORK-PC_JOB3_20260412_210000.xml
      \\server\share\NetLogs\WORK-PC_summary.xml
#>
function Save-RemoteReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PCName,
        [Parameter(Mandatory = $true)][string]$JobName,
        [Parameter(Mandatory = $true)][string]$JobStatus,
        [Parameter(Mandatory = $true)][string]$Duration,
        [Parameter(Mandatory = $false)][int]$SourceFiles = 0,
        [Parameter(Mandatory = $false)][double]$ArchiveSizeMB = 0,
        [Parameter(Mandatory = $false)][string]$Verification = 'Skipped',
        [Parameter(Mandatory = $false)][string[]]$Errors = @(),
        [Parameter(Mandatory = $false)][string[]]$Warnings = @(),
        [Parameter(Mandatory = $false)][string]$LocalLogPath = '',
        [Parameter(Mandatory = $false)][object[]]$SourceFileList = @(),
        [Parameter(Mandatory = $false)][string]$NetPath = ''
    )
    process {
        $targetPath = $NetPath
        if (Test-StringIsNullOrWhiteSpace($targetPath)) {
            $targetPath = $NetLogPath
        }
        if (Test-StringIsNullOrWhiteSpace($targetPath)) {
            Write-Log "NetLogPath не указан — сетевые отчёты пропущены" -Level DEBUG
            return
        }

        $safePC = $PCName -replace '[\\/:*?"<>|]', '-'
        $safeJob = $JobName -replace '[\\/:*?"<>|]', '-'

        try {
            if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
                New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            Write-Log "Ошибка создания сетевой директории $targetPath`: $_" -Level WARNING
            return
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        # === XML отчёт ===
        try {
            $xmlFile = Join-Path $targetPath "${safePC}_${safeJob}_${timestamp}.xml"
            $xml = New-Object System.Text.StringBuilder
            [void]$xml.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
            [void]$xml.AppendLine('<BackupReport>')
            [void]$xml.AppendLine("    <Host>" + $PCName + "</Host>")
            [void]$xml.AppendLine("    <Job>" + $JobName + "</Job>")
            [void]$xml.AppendLine("    <Timestamp>" + $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') + "</Timestamp>")
            [void]$xml.AppendLine("    <Status>" + $JobStatus + "</Status>")
            [void]$xml.AppendLine("    <Duration>" + $Duration + "</Duration>")
            [void]$xml.AppendLine("    <SourceFiles>" + $SourceFiles + "</SourceFiles>")
            [void]$xml.AppendLine("    <ArchiveSizeMB>" + $ArchiveSizeMB + "</ArchiveSizeMB>")
            [void]$xml.AppendLine("    <Verification>" + $Verification + "</Verification>")
            [void]$xml.AppendLine("    <LocalLogPath>" + $LocalLogPath + "</LocalLogPath>")
            if ($Errors.Count -gt 0) {
                [void]$xml.AppendLine('    <Errors>')
                foreach ($err in $Errors) {
                    $safeErr = $err -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                    [void]$xml.AppendLine("        <Error>" + $safeErr + "</Error>")
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
                    [void]$xml.AppendLine("        <Warning>" + $safeWarn + "</Warning>")
                }
                [void]$xml.AppendLine('    </Warnings>')
            }
            else {
                [void]$xml.AppendLine('    <Warnings/>')
            }
            [void]$xml.AppendLine('</BackupReport>')
            [System.IO.File]::WriteAllText($xmlFile, $xml.ToString(), [System.Text.Encoding]::UTF8)
            Write-Log "Сетевой XML-отчёт: $xmlFile" -Level DEBUG
        }
        catch {
            Write-Log "Ошибка сохранения сетевого XML-отчёта: $_" -Level WARNING
        }

        # === CSV список файлов ===
        if ($SourceFileList -and $SourceFileList.Count -gt 0) {
            try {
                $csvFile = Join-Path $targetPath "${safePC}_${safeJob}_${timestamp}.csv"
                #$SourceFileList | Select-Object RelativePath, Length, LastWriteTime |
				#Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
				$tempCsv = Join-Path $targetPath "temp_${timestamp}.csv"
				$SourceFileList | Select-Object RelativePath, Length, LastWriteTime | 
					Export-Csv -Path $tempCsv -Encoding UTF8 -Delimiter ";"
				# Удаляем заголовок #TYPE
				$lines = Get-Content -Path $tempCsv -Encoding UTF8 | Where-Object { $_ -notmatch '^#TYPE' }
				[System.IO.File]::WriteAllLines($csvFile, $lines, $Script:EncodingUTF8NoBOM)
				Remove-Item -Path $tempCsv -Force -ErrorAction SilentlyContinue
                Write-Log "Сетевой CSV-отчёт: $csvFile ($($SourceFileList.Count) файлов)" -Level DEBUG
            }
            catch {
                Write-Log "Ошибка сохранения сетевого CSV-отчёта: $_" -Level WARNING
            }
        }

        # === Сводный отчёт ПК (прямо в корне NetLogPath) ===
        try {
            $summaryFile = Join-Path $targetPath "${safePC}_summary.xml"

            $existingJobs = @{}
            if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
                try {
                    [xml]$sumXml = Get-Content $summaryFile -Encoding UTF8
                    foreach ($j in $sumXml.HostSummary.Job) {
                        $existingJobs[$j.name] = @{
                            status = $j.status
                            error  = if ($j.error) { $j.error } else { '' }
                        }
                    }
                }
                catch {}
            }

            $xmlS = New-Object System.Text.StringBuilder
            [void]$xmlS.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
            [void]$xmlS.AppendLine('<HostSummary>')
            [void]$xmlS.AppendLine("    <Host>$PCName</Host>")
            [void]$xmlS.AppendLine("    <LastRun>$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</LastRun>")
            [void]$xmlS.AppendLine("    <LastDuration>$Duration</LastDuration>")

            $existingJobs[$JobName] = @{
                status = $JobStatus
                error  = if ($Errors.Count -gt 0) { $Errors[0] } else { '' }
            }

            foreach ($k in $existingJobs.Keys) {
                $v = $existingJobs[$k]
                $safeE = $v.error -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                if ($v.error) {
                    [void]$xmlS.AppendLine("    <Job name=`"$k`" status=`"$($v.status)`" error=`"$safeE`"/>")
                }
                else {
                    [void]$xmlS.AppendLine("    <Job name=`"$k`" status=`"$($v.status)`"/>")
                }
            }

            [void]$xmlS.AppendLine('</HostSummary>')
            [System.IO.File]::WriteAllText($summaryFile, $xmlS.ToString(), [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Log "Ошибка сохранения сводного отчёта: $_" -Level WARNING
        }
    }
}

#endregion

function Write-WinEventAppLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][ValidateSet("Start", "Success", "Warning", "Error", "End")][string]$StatusKey,
        [Parameter(Mandatory = $true)][string]$MessageText,
        [Parameter(Mandatory = $false)][string]$Source = $ParentJobName
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
#region МОДУЛЬ RAR ОПЕРАЦИЙ
# ==============================================================================
function Get-RarExitCodeMeaning {
    param([int]$ExitCode)
    $descriptions = @{
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
    if ($descriptions.ContainsKey($ExitCode)) {
        return $descriptions[$ExitCode]
    }
    return "Неизвестный код возврата: $ExitCode"
}

function Start-RarArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RarPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $false)][string[]]$Parameters = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t"),
        [Parameter(Mandatory = $false)][string]$LogPath,
        [Parameter(Mandatory = $false)][string]$SourceFilter
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
            if (Test-Path -LiteralPath $ArchivePath -PathType Leaf) {
                try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch { $archiveSizeMB = 0 }
            }
            return (New-Object PSObject -Property @{
                    ExitCode    = $exitCode
                    Duration    = $duration
                    StartTime   = $processStart
                    EndTime     = $processEnd
                    LogPath     = $actualLogPath
                    LogContent  = $logContent
                    FailedFiles = @()
                    ArchiveSize = $archiveSizeMB
                })
        }
        catch {
            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
            Write-Error "Критическая ошибка запуска RAR: $($_.Exception.Message)"
            return (New-Object PSObject -Property @{
                    ExitCode    = 255
                    Duration    = $duration
                    StartTime   = $processStart
                    EndTime     = $processEnd
                    LogPath     = $actualLogPath
                    LogContent  = @()
                    FailedFiles = @()
                    Exception   = $_.Exception
                    ArchiveSize = 0
                })
        }
    }
}

function Test-RarArchive {
    param(
        [Parameter(Mandatory = $true)][string]$RarPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )
    $testArgs = @("t", "`"$ArchivePath`"")
    Write-Log "Проверка целостности архива: $ArchivePath"
    $process = Start-Process -FilePath $RarPath -ArgumentList $testArgs -Wait -PassThru -WindowStyle Hidden
    return (New-Object PSObject -Property @{
            ExitCode = $process.ExitCode
            IsValid  = ($process.ExitCode -eq 0)
        })
}
#endregion

# ==============================================================================
#region МОДУЛЬ ВЕРИФИКАЦИИ
# ==============================================================================
function Get-CanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$RootPath
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
    param([Parameter(Mandatory = $true)][string[]]$Paths)
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
    $common = @()
    for ($i = 0; $i -lt $minParts; $i++) {
        $first = [System.Char]::ToLower($splitPaths[0][$i])
        $allSame = $true
        for ($j = 1; $j -lt $splitPaths.Count; $j++) {
            if ([System.Char]::ToLower($splitPaths[$j][$i]) -ne $first) {
                $allSame = $false
                break
            }
        }
        if ($allSame) { $common += $splitPaths[0][$i] } else { break }
    }
    if ($common.Count -gt 0) { return ($common -join '\') + '\' }
    return ""
}

function Get-FileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ if (-not (Test-Path -LiteralPath $_ -PathType Container)) { throw "Не папка: $_" }; $true })]
        [string]$Path
    )
    begin {
        $rootPath = (Resolve-Path -LiteralPath $Path).Path
        if ($rootPath.EndsWith('\')) { $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) }
        Write-Verbose "Сканируем: $rootPath"
    }
    process {
        try {
            $items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer }
            # Исключаем символические ссылки (PS 2.0 -bitwise)
            $items = $items | Where-Object {
                -not ($_.Attributes.Value -band [System.IO.FileAttributes]::ReparsePoint)
            }
            $result = @()
            foreach ($item in $items) {
                if (-not (Test-Path -LiteralPath $item.FullName -PathType Leaf)) { continue }
                $relative = Get-CanonicalPath -FullPath $item.FullName -RootPath $rootPath
                $result += (New-Object PSObject -Property @{
                        RelativePath  = $relative
                        Length        = $item.Length
                        LastWriteTime = $item.LastWriteTime
                        Source        = "FileSystem"
                        FullName      = $item.FullName
                    })
            }
            Write-Verbose "Найдено файлов: $($result.Count)"
            return $result
        }
        catch {
            Write-Error "Критическая ошибка при сканировании '$Path`: $($_.Exception.Message)"
            throw
        }
    }
}

function Get-FilterFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNull()][string]$Filter
    )
    if (Test-StringIsNullOrWhiteSpace($Filter)) { throw "Фильтр не может быть пустым" }
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
        Write-Warning "Файлы по маске '$Filter' в '$Path' не найдены."
        return @()
    }
    Write-Verbose "Найдено файлов: $($filtered.Count)"
    return $filtered
}

function Get-FileArhListRar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$RarPath,
        [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ArchivePath
    )
    Write-Verbose "Чтение содержимого RAR: $ArchivePath"
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
            throw "RAR вернул код $($process.ExitCode). Детали: $stderr"
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
    param([Parameter(Mandatory = $true)][object]$RawOutput)
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
            if ($currentName -and ($currentSize -ne $null) -and $currentDate) {
                $relName = ($currentName -replace '^\\+', '' -replace '/', '\').ToLowerInvariant()
                $files += (New-Object PSObject -Property @{
                        RelativePath  = $relName
                        Length        = $currentSize
                        LastWriteTime = $currentDate
                        Source        = "Archive"
                    })
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
            $currentName = $null; $currentSize = $null; $currentDate = $null
            continue
        }
    }
    if ($currentName -and ($currentSize -ne $null) -and $currentDate) {
        $relName = ($currentName -replace '^\\+', '' -replace '/', '\').ToLowerInvariant()
        $files += (New-Object PSObject -Property @{
                RelativePath  = $relName
                Length        = $currentSize
                LastWriteTime = $currentDate
                Source        = "Archive"
            })
    }
    return $files
}

function Compare-FilesSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$SourceList,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ArchiveList,
        [Parameter(Mandatory = $false)][string]$SourcePath
    )
    process {
        Write-Verbose "Сравнение: Источник ($($SourceList.Count)) vs Архив ($($ArchiveList.Count))"
        # Нормализация типографских символов
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

        # Сравнение: файлы источника vs архива (ВКЛЮЧАЯ 0-БАЙТОВЫЕ)
        foreach ($key in $sourceHash.Keys) {
            $srcItem = $sourceHash[$key]
            if ($archiveHash.ContainsKey($key)) {
                $arhItem = $archiveHash[$key]
                # Сравниваем размеры — 0 == 0 считается совпадением
                if ($srcItem.Length -ne $arhItem.Length) {
                    $sizeMismatch += (New-Object PSObject -Property @{
                            Path        = $key
                            SourceSize  = $srcItem.Length
                            ArchiveSize = $arhItem.Length
                        })
                    $isIdentical = $false
                }
            }
            else {
                # Пробуем найти по суффиксу
                $foundKey = $archiveHash.Keys | Where-Object { $_.EndsWith("\$key") -or $_ -eq $key } | Select-Object -First 1
                if ($foundKey) {
                    $arhItem = $archiveHash[$foundKey]
                    if ($srcItem.Length -ne $arhItem.Length) {
                        $sizeMismatch += (New-Object PSObject -Property @{
                                Path        = $key
                                SourceSize  = $srcItem.Length
                                ArchiveSize = $arhItem.Length
                            })
                        $isIdentical = $false
                    }
                }
                else {
                    $missingInArchive += $srcItem
                    $isIdentical = $false
                }
            }
        }

        # Лишние файлы в архиве
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
            $reportLines += "SUCCESS: Полное совпадение файлов ($($SourceList.Count) шт). Включая файлы размером 0 байт."
        }
        else {
            if ($missingInArchive.Count -gt 0) {
                $reportLines += "ERROR: Отсутствуют в архиве ($($missingInArchive.Count)):"
                $missingInArchive | Select-Object -First 10 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
                if ($missingInArchive.Count -gt 10) { $reportLines += "  ... и ещё $($missingInArchive.Count - 10)" }
            }
            if ($sizeMismatch.Count -gt 0) {
                $reportLines += "ERROR: Не совпадает размер ($($sizeMismatch.Count)):"
                $sizeMismatch | Select-Object -First 5 | ForEach-Object {
                    $reportLines += "  - $($_.Path) (источник=$($_.SourceSize), архив=$($_.ArchiveSize))"
                }
            }
            if ($extraInArchive.Count -gt 0) {
                $reportLines += "WARNING: В архиве есть лишние файлы ($($extraInArchive.Count)):"
                $extraInArchive | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
            }
        }

        return (New-Object PSObject -Property @{
                IsIdentical      = $isIdentical
                TotalSource      = $SourceList.Count
                TotalArchive     = $ArchiveList.Count
                MissingInArchive = $missingInArchive
                ExtraInArchive   = $extraInArchive
                SizeMismatch     = $sizeMismatch
                Report           = ($reportLines -join "`r`n")
            })
    }
}
#endregion

# ==============================================================================
#region МОДУЛЬ ОТЧЁТОВ
# ==============================================================================
#endregion

# ==============================================================================
#region РОТАЦИЯ ФАЙЛОВ
# ==============================================================================
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(0, 3650)][int]$DaysOld,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100000)][int]$KeepCount,
        [Parameter(Mandatory = $true)][string]$Filter
    )
    Write-Log "Ротация: $Path (DaysOld: $DaysOld, KeepCount: $KeepCount, Filter: $Filter)"
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $msg = "Директория $Path не существует"
        Write-Log $msg
        throw $msg
    }
    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -ErrorAction Stop |
            Where-Object { -not ($_.PSIsContainer) } |
            Sort-Object LastWriteTime -Descending)
        if ($allFiles.Count -eq 0) { Write-Log "Нет файлов для обработки"; return }
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
                    Write-Log "Удалён: $($file.Name)"
                }
            }
        }
        else {
            Write-Log "Нет файлов для удаления"
        }
        Write-Log "Сохранено файлов: $($allFiles.Count - $deletedCount)"
    }
    catch {
        $msg = "Ошибка ротации файлов: $_"
        Write-Log $msg
        throw $msg
    }
}
#endregion

# ==============================================================================
#region ОТПРАВКА ПОЧТЫ
# ==============================================================================
function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SmtpServer,
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $false)][int]$Port = 25,
        [Parameter(Mandatory = $false)][bool]$UseSSL = $false,
        [Parameter(Mandatory = $false)][string]$Username = $null,
        [Parameter(Mandatory = $false)][string]$Password = $null,
        [Parameter(Mandatory = $false)][bool]$IsBodyHtml = $false
    )
    try {
        $msg = New-Object -ComObject CDO.Message
        $msg.From = $From
        $msg.To = $To
        $msg.Subject = $Subject
        if ($IsBodyHtml) { $msg.HTMLBody = $Body } else { $msg.TextBody = $Body }
        $cfg = $msg.Configuration
        $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserver") = $SmtpServer
        $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = $Port
        $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
        $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpconnectiontimeout") = 60
        if ($UseSSL) {
            $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = $true
        }
        if ($Username -and $Password) {
            $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 1
            $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusername") = $Username
            $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendpassword") = $Password
        }
        else {
            $cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = 0
        }
        $cfg.Fields.Update()
        $msg.Send()
        Write-Host "Письмо отправлено: $Subject" -ForegroundColor Green
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
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================
function Get-FileInfoDetails {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not ($_.PSIsContainer) }
        $fileCount = $items.Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
        $samples = $items | Select-Object -First 5 | ForEach-Object {
            New-Object PSObject -Property @{
                Name     = $_.Name
                SizeKB   = [math]::Round($_.Length / 1KB, 2)
                FullPath = $_.FullName
            }
        }
        return (New-Object PSObject -Property @{
                FileCount      = $fileCount
                TotalSizeMB    = [math]::Round($totalSize / 1MB, 2)
                TotalSizeBytes = $totalSize
                FileSamples    = $samples
                HasMoreFiles   = ($fileCount -gt 5)
                MoreFilesCount = ($fileCount - 5)
            })
    }
    catch {
        return (New-Object PSObject -Property @{
                FileCount = 0; TotalSizeMB = 0; TotalSizeBytes = 0
                FileSamples = @(); HasMoreFiles = $false; MoreFilesCount = 0
                Error = $_.Exception.Message
            })
    }
}

function Copy-BackupFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $copyEnd = Get-Date
    $duration = [math]::Round(($copyEnd - $copyStart).TotalSeconds, 2)
    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length
    return (New-Object PSObject -Property @{
            Success         = ($sourceSize -eq $destSize)
            Duration        = $duration
            SourceSize      = $sourceSize
            DestinationSize = $destSize
            StartTime       = $copyStart
            EndTime         = $copyEnd
        })
}

function Format-FileSize {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$Path)
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

function Get-DiskSpaceReport {
    [OutputType([string])]
    param([string]$ComputerName = $env:COMPUTERNAME)
    try {
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object {
            $_.IsReady -and $_.DriveType -eq 'Fixed' -and $_.TotalSize -gt 1GB
        }
        $diskStrings = @()
        foreach ($drive in $drives) {
            $sizeGB = [math]::Round($drive.TotalSize / 1GB, 1)
            $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
            $freePct = [math]::Round(($drive.AvailableFreeSpace / $drive.TotalSize) * 100, 1)
            $diskStrings += "Диск {0} Всего(ГБ)={1:N1} Свободно(ГБ)={2:N1} Свободно={3:N1}%" -f `
                $drive.Name.TrimEnd('\'), $sizeGB, $freeGB, $freePct
        }
        if ($diskStrings.Count -eq 0) { return "Нет локальных жёстких дисков > 1 ГБ" }
        return ($diskStrings -join " ; ")
    }
    catch {
        return "Ошибка получения информации о дисках: $($_.Exception.Message)"
    }
}

function Get-BackupConfiguration {
    param([Parameter(Mandatory = $false)][hashtable]$LocalConfig = $BackupConfig)
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $currentTime = Get-Date -Format 'HHmmss'
    $resolvedJobs = @{}
    if (-not ($LocalConfig.ContainsKey('Jobs'))) { throw "В конфигурации не найдено раздела Jobs" }
    $archiverType = $LocalConfig['General']['ArchiverType']
    if (Test-StringIsNullOrWhiteSpace($archiverType)) { $archiverType = "RAR" }
    $archiverType = $archiverType.ToUpper()
    foreach ($jobDef in $LocalConfig['Jobs'].Keys) {
        $jobDefHash = $LocalConfig['Jobs'][$jobDef]
        $jobName = $jobDefHash['Name']
        if (Test-StringIsNullOrWhiteSpace($jobName)) { continue }
        $job = @{}
        foreach ($prop in $jobDefHash.Keys) { $job[$prop] = $jobDefHash[$prop] }
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
    if (Test-StringIsNullOrWhiteSpace($archiverPathValue)) { throw "КРИТИЧЕСКАЯ ОШИБКА: Не найден RAR.exe" }
    $logPathValue = $LocalConfig['Paths']['LogPathRoot']
    if (Test-StringIsNullOrWhiteSpace($logPathValue)) {
        $logPathValue = "C:\work\$ParentJobName\logs"
        Write-Warning "LogPathRoot не найден, используется: $logPathValue"
    }
    $defaultParams = $LocalConfig['General']['DefaultRarParameters']
    if (-not ($defaultParams)) { $defaultParams = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t") }
    $settings = @{
        PCName         = $PCName
        JobName        = $ParentJobName
        LogPath        = $logPathValue
        ArchiverType   = $archiverType
        ArchiverPath   = $archiverPathValue
        ArchiverParams = $defaultParams
        AdminIS        = $AdminIS
        AdminOS        = $AdminOS
    }
    return @{ Settings = $settings; Jobs = $resolvedJobs }
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
            $errors += "Не указан LocalDest ($jobName)"
        }
    }
    return @{ IsValid = ($errors.Count -eq 0); Errors = $errors }
}
#endregion

# ==============================================================================
#region ============================================================
# UNIFIED PIPELINE: Формирование элементов архивации
# ============================================================
# Все режимы архивации сводятся к единому списку "ArchiveItem":
#   SourcePath      — что архивировать (файл или папка)
#   SourceName      — отображаемое имя
#   ArchiveName     — имя выходного .rar файла
#   SourceType      — 'File', 'Folder', 'Directory'
#   SourceRoot      — корень для верификации (для File=source, для Folder=folder itself)
# ============================================================

function Resolve-ArchivePattern {
    param(
        [string]$Pattern,
        [string]$PCName,
        [string]$JobName,
        [string]$SourceFileName = '',
        [string]$SourceFolderName = ''
    )
    $name = $Pattern
    $name = $name -replace '{PCName}', $PCName
    $name = $name -replace '{JobName}', $JobName
    $name = $name -replace '{SourceFileName}', $SourceFileName
    $name = $name -replace '{SourceFolderName}', $SourceFolderName
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $currentTime = Get-Date -Format 'HHmmss'
    $name = $name -replace '{Date}', $currentDate
    $name = $name -replace '{Time}', $currentTime
    $name = $name -replace '{Date_Time}', "${currentDate}_${currentTime}"
    $name = $name -replace '[\\/:*?"<>|]', '_'
    if ($name -notmatch '\.rar$') { $name = $name + '.rar' }
    return $name
}

function Get-ArchiveItems_Normal {
    [OutputType([object[]])]
    param(
        [hashtable]$Job,
        [string]$PCName
    )
    # Обычный режим: ОДНА архивная единица — весь источник
    $archiveName = $Job['Archive']
    $item = New-Object PSObject -Property @{
        SourcePath   = $Job['Source']
        SourceName   = $Job['Name']
        ArchiveName  = $archiveName
        SourceType   = 'Directory'
        SourceRoot   = $Job['Source']
        SourceFilter = if ($Job.ContainsKey('SourceFilter') -and -not (Test-StringIsNullOrWhiteSpace($Job['SourceFilter']))) {
            $Job['SourceFilter']
        }
        else { $null }
    }
    return @($item)
}

function Get-ArchiveItems_IndividualFiles {
    [OutputType([object[]])]
    param(
        [hashtable]$Job,
        [string]$PCName,
        [string]$JobName
    )
    # Индивидуальная файловая: ОДИН элемент = ОДИН файл
    $filter = $Job['SourceFilter']
    if (Test-StringIsNullOrWhiteSpace($filter)) {
        throw "Для индивидуальной архивации файлов требуется SourceFilter"
    }
    $files = Get-FilterFileList -Path $Job['Source'] -Filter $filter
    if ($Job.ContainsKey('ExcludeFilePattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['ExcludeFilePattern']))) {
        $exc = $Job['ExcludeFilePattern']
        $files = $files | Where-Object {
            $nm = Split-Path $_.RelativePath -Leaf
            ($_.RelativePath -notlike $exc) -and ($nm -notlike $exc)
        }
    }
    if ($files.Count -eq 0) {
        Write-Log "Файлы по маске '$filter' не найдены" -Level WARNING
        return @()
    }
    Write-Log "Подготовлено файлов для архивации: $($files.Count)" -Level INFO

    $pattern = "{PCName}_{JobName}_{SourceFileName}.rar"
    if ($Job.ContainsKey('IndividualArchivePattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['IndividualArchivePattern']))) {
        $pattern = $Job['IndividualArchivePattern']
    }

    $items = @()
    foreach ($f in $files) {
        $archiveName = Resolve-ArchivePattern -Pattern $pattern -PCName $PCName -JobName $JobName -SourceFileName $f.RelativePath
        $items += (New-Object PSObject -Property @{
                SourcePath   = $f.FullName
                SourceName   = $f.RelativePath
                ArchiveName  = $archiveName
                SourceType   = 'File'
                SourceRoot   = $Job['Source']
                SourceFilter = $null
            })
    }
    return $items
}

function Get-ArchiveItems_IndividualFolders {
    [OutputType([object[]])]
    param(
        [hashtable]$Job,
        [string]$PCName,
        [string]$JobName
    )
    # Индивидуальная папочная: ОДИН элемент = ОДНА подпапка
    $folders = Get-ChildItem -Path $Job['Source'] -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }

    # Фильтр по имени папки
    if ($Job.ContainsKey('SourceFilter') -and -not (Test-StringIsNullOrWhiteSpace($Job['SourceFilter']))) {
        $ff = $Job['SourceFilter']
        $folders = $folders | Where-Object { $_.Name -like $ff }
        Write-Log "Фильтр папок: $ff (найдено $($folders.Count))" -Level INFO
    }

    # Исключение папок
    if ($Job.ContainsKey('ExcludeFolderPattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['ExcludeFolderPattern']))) {
        $exc = $Job['ExcludeFolderPattern']
        if ($exc -eq 'today') {
            $todayDate = Get-Date -Format 'yyyyMMdd'
            $folders = $folders | Where-Object { $_.Name -ne $todayDate }
            Write-Log "Исключена папка с текущей датой: $todayDate" -Level INFO
        }
        else {
            $folders = $folders | Where-Object { $_.Name -notlike $exc }
        }
    }

    if ($folders.Count -eq 0) {
        Write-Log "Подпапки для архивации не найдены" -Level WARNING
        return @()
    }
    Write-Log "Подготовлено папок для архивации: $($folders.Count)" -Level INFO

    $pattern = "{PCName}_{JobName}_{SourceFolderName}.rar"
    if ($Job.ContainsKey('IndividualArchivePattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['IndividualArchivePattern']))) {
        $pattern = $Job['IndividualArchivePattern']
    }

    $items = @()
    foreach ($fld in $folders) {
        $archiveName = Resolve-ArchivePattern -Pattern $pattern -PCName $PCName -JobName $JobName -SourceFolderName $fld.Name
        $items += (New-Object PSObject -Property @{
                SourcePath   = $fld.FullName
                SourceName   = $fld.Name
                ArchiveName  = $archiveName
                SourceType   = 'Folder'
                SourceRoot   = $fld.FullName
                SourceFilter = $null
            })
    }
    return $items
}

# ============================================================
# Универсальный определитель режима
# ============================================================
function Get-ArchiveMode {
    param([hashtable]$Job)
    $indFiles = $false
    $indFolders = $false
    if ($Job.ContainsKey('ArchiveIndividualFiles')) { $indFiles = [System.Convert]::ToBoolean($Job['ArchiveIndividualFiles']) }
    if ($Job.ContainsKey('ArchiveIndividualFolders')) { $indFolders = [System.Convert]::ToBoolean($Job['ArchiveIndividualFolders']) }
    if ($indFiles) { return 'IndividualFiles' }
    if ($indFolders) { return 'IndividualFolders' }
    return 'Normal'
}

# ============================================================
# Единая функция подготовки элементов: Prepare-ArchiveItems
# ============================================================
function Prepare-ArchiveItems {
    [OutputType([object[]])]
    param(
        [hashtable]$Job,
        [string]$PCName
    )
    $mode = Get-ArchiveMode -Job $Job
    switch ($mode) {
        'IndividualFiles' { return Get-ArchiveItems_IndividualFiles   -Job $Job -PCName $PCName -JobName $Job['Name'] }
        'IndividualFolders' { return Get-ArchiveItems_IndividualFolders -Job $Job -PCName $PCName -JobName $Job['Name'] }
        default { return Get-ArchiveItems_Normal            -Job $Job -PCName $PCName }
    }
}

#endregion

# ==============================================================================
#region ============================================================
# UNIFIED PIPELINE: Архивация — единый механизм для всех режимов
# ============================================================

function Invoke-ArchivePipeline {
    [OutputType([hashtable])]
    param(
        [object[]]$ArchiveItems,
        [hashtable]$Job,
        [hashtable]$Config,
        [string]$LogDir
    )
    $rarPath = $Config['Settings']['ArchiverPath']
    $rarParams = if ($Job.ContainsKey('ArhParameters')) { $Job['ArhParameters'] }
    else { $Config['Settings']['ArchiverParams'] }
    $destPath = $Job['LocalDest']
    $mode = Get-ArchiveMode -Job $Job

    # Лог архиватора
    $arhLogPath = $null
    if ($Job['ArhLog']) {
        $logName = if ($mode -eq 'IndividualFiles') { "individual_archiver.log" }
        elseif ($mode -eq 'IndividualFolders') { "folder_archiver.log" }
        else { $null }
        if ($logName) { $arhLogPath = Join-Path $destPath $logName }
    }

    $results = @()
    $successCount = 0
    $errorCount = 0

    foreach ($item in $ArchiveItems) {
        $archivePath = Join-Path $destPath $item.ArchiveName
        $itemStart = Get-Date

        # Определяем параметры для Start-RarArchive
        $srcFilter = $null
        if ($item.SourceType -eq 'Directory' -and $item.SourceFilter) {
            $srcFilter = $item.SourceFilter
        }

        Write-Log "Архивация: $($item.SourceName) -> $($item.ArchiveName)" -Level INFO
        $arhResult = Start-RarArchive `
            -RarPath $rarPath `
            -ArchivePath $archivePath `
            -SourcePath $item.SourcePath `
            -Parameters $rarParams `
            -LogPath $arhLogPath `
            -SourceFilter $srcFilter

        $itemEnd = Get-Date
        $itemDuration = [math]::Round(($itemEnd - $itemStart).TotalSeconds, 2)

        if ($arhResult.ExitCode -eq 0) {
            $archiveSizeStr = Format-FileSize -Path $archivePath
            Write-Log "Успешно: $archivePath ($archiveSizeStr, $itemDuration сек)" -Level SUCCESS -ResultKey
            $successCount++
            $status = 'Success'
        }
        else {
            $errDesc = Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode
            Write-Log "Ошибка $($item.SourceName): $errDesc" -Level ERROR -ResultKey
            $errorCount++
            $status = 'Error'
        }

        $resProps = @{
            SourcePath  = $item.SourcePath
            SourceName  = $item.SourceName
            SourceType  = $item.SourceType
            SourceRoot  = $item.SourceRoot
            ArchivePath = $archivePath
            ArchiveSize = $arhResult.ArchiveSize
            Duration    = $itemDuration
            Status      = $status
            ExitCode    = $arhResult.ExitCode
        }
        if ($status -eq 'Error') {
            $resProps['ErrorMessage'] = $errDesc
        }
        $results += (New-Object PSObject -Property $resProps)
    }

    Write-Log "Архивация завершена: Успешно=$successCount, Ошибки=$errorCount" -Level INFO -ResultKey
    return @{
        Results      = $results
        SuccessCount = $successCount
        ErrorCount   = $errorCount
    }
}

#endregion

# ======================================================================
#region ================================================================
# UNIFIED PIPELINE: Верификация — единый механизм (включая 0-байтовые)
# ======================================================================

function Invoke-Verification {
    <#
.SYNOPSIS
    Выполняет нативную проверку целостности архива через команду RAR "t".
.DESCRIPTION
    Запускает архиватор с параметром 't' для каждого успешного архива.
    Проверяет только код выхода процесса ($process.ExitCode -eq 0).
    Не парсит текстовый вывод, что обеспечивает высокую скорость и надёжность на больших объёмах данных.
    Совместимо с PowerShell 2.0 и Windows 7.
.PARAMETER ArchiveResults
    Массив объектов с результатами успешной архивации (из Invoke-ArchivePipeline).
.PARAMETER Job
    Конфигурация текущего задания.
.PARAMETER Config
    Глобальная конфигурация скрипта.
.EXAMPLE
    $successArchives = $pipelineResult.Results | Where-Object { $_.Status -eq 'Success' }
    $verifyResult = Invoke-Verification -ArchiveResults $successArchives -Job $job -Config $config
    if ($verifyResult.AllPassed) { Write-Host "Проверка пройдена" }
.LINK
    https://internal/wiki/verification-step1
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][object[]]$ArchiveResults,
        [Parameter(Mandatory = $true)][hashtable]$Job,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )
    process {
        $rarPath = $Config['Settings']['ArchiverPath']
        $verified = @()
        $failed = 0
        $totalItems = $ArchiveResults.Count

        foreach ($res in $ArchiveResults) {
            if ($res.Status -ne 'Success' -or -not (Test-Path -LiteralPath $res.ArchivePath -PathType Leaf)) {
                Write-Log "Пропуск проверки: $($res.SourceName) (архив не создан)" -Level WARNING -ResultKey
                continue
            }

            Write-Log "Проверка целостности (rar t): $($res.ArchiveName)" -Level INFO
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $rarPath
                $psi.Arguments = "t `"$($res.ArchivePath)`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                $proc.Start() | Out-Null
                $null = $proc.StandardOutput.ReadToEnd()
                $null = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()

                if ($proc.ExitCode -eq 0) {
                    Write-Log "ВЕРИФИКАЦИЯ ОК: $($res.SourceName) (CRC32 OK)" -Level SUCCESS -ResultKey
                    $verified += $res
                }
                else {
                    Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА: $($res.SourceName) (RAR ExitCode: $($proc.ExitCode))" -Level ERROR -ResultKey
                    $failed++
                }
            }
            catch {
                Write-Log "Ошибка запуска проверки: $($res.SourceName) — $_" -Level ERROR -ResultKey
                $failed++
            }
        }

        return @{
            Verified    = $verified
            FailedCount = $failed
            TotalCount  = $totalItems
            AllPassed   = (($failed -eq 0) -and ($verified.Count -gt 0)) -or ($totalItems -eq 0)
        }
    }
}

#endregion

# ==============================================================================
#region ============================================================
# UNIFIED PIPELINE: Пост-операции — единый механизм
# ============================================================

function Invoke-PostOperations {
    param(
        [object[]]$ArchiveResults,
        [hashtable]$Job,
        [hashtable]$Config,
        [hashtable]$VerificationResult,
        [int]$PipelineSuccessCount,
        [int]$PipelineErrorCount
    )
    $jobName = $Job['Name']

    # === 1. Копирование в удалённое хранилище ===
    if ($Job['RemoteDest'] -and (Test-Path $Job['RemoteDest'])) {
        Write-Log "Копирование архивов в сетевое хранилище..." -Level INFO
        foreach ($res in $ArchiveResults) {
            if ($res.Status -eq 'Success' -and (Test-Path -LiteralPath $res.ArchivePath -PathType Leaf)) {
                $remotePath = Join-Path $Job['RemoteDest'] (Split-Path $res.ArchivePath -Leaf)
                try {
                    $copyResult = Copy-BackupFile -SourcePath $res.ArchivePath -DestinationPath $remotePath
                    if ($copyResult.Success) {
                        Write-Log "Копирование OK: $remotePath" -Level SUCCESS
                    }
                    else {
                        Write-Log "Ошибка копирования: $remotePath" -Level ERROR
                    }
                }
                catch {
                    Write-Log "Ошибка копирования: $_" -Level ERROR
                }
            }
        }

        # Ротация удалённого хранилища
        if ($Job.ContainsKey('RemoveRemoteDestFlag') -and $Job['RemoveRemoteDestFlag']) {
            try {
                Remove-OldFiles -Path $Job['RemoteDest'] -DaysOld $Job['RemoteDestDaysOld'] `
                    -KeepCount $Job['RemoteDestKeepCount'] -Filter "*.*"
            }
            catch { Write-Log "Ошибка ротации удалённого: $_" -Level WARNING }
        }
    }
    else {
        Write-Log "RemoteDest недоступен, сохранено только локально." -Level WARNING
    }

    # === 2. Ротация локального хранилища ===
    try {
        Remove-OldFiles -Path $Job['LocalDest'] -DaysOld $Job['LocalDestDaysOld'] `
            -KeepCount $Job['LocalDestKeepCount'] -Filter "*.*"
    }
    catch { Write-Log "Ошибка ротации локального: $_" -Level WARNING }

    # === 3. Удаление источника после верификации ===
    if ($Job.ContainsKey('RemoveSourceFlag') -and $Job['RemoveSourceFlag']) {
        Write-LogSection "ВЕРИФИКАЦИЯ ПЕРЕД УДАЛЕНИЕМ ИСТОЧНИКА" -ResultKey

        if ($VerificationResult.FailedCount -gt 0) {
            Write-Log "Удаление источника ОТМЕНЕНО: $($VerificationResult.FailedCount) элемент(ов) не прошли верификацию" -Level ERROR -ResultKey
        }
        else {
            foreach ($res in $VerificationResult.Verified) {
                if ($res.SourceType -eq 'File') {
                    if (Test-Path -LiteralPath $res.SourcePath) {
                        Remove-Item -LiteralPath $res.SourcePath -Force -ErrorAction Stop
                        Write-Log "Удалён файл: $($res.SourcePath)" -Level INFO -ResultKey
                    }
                }
                elseif ($res.SourceType -eq 'Folder') {
                    if (Test-Path -LiteralPath $res.SourceRoot) {
                        Remove-Item -Path $res.SourceRoot -Recurse -Force -ErrorAction Stop
                        Write-Log "Удалена папка: $($res.SourceName)" -Level INFO -ResultKey
                    }
                }
                else {
                    # Normal mode — ротация источника (не удаление)
                    $filterForRemove = if ($res.SourceFilter) { $res.SourceFilter } else { "*" }
                    try {
                        Remove-OldFiles -Path $res.SourceRoot -DaysOld $Job['SourceDaysOld'] `
                            -KeepCount $Job['SourceKeepCount'] -Filter $filterForRemove
                    }
                    catch { Write-Log "Ошибка ротации источника: $_" -Level WARNING }
                }
            }
            if ($VerificationResult.Verified.Count -gt 0) {
                $delType = if ($VerificationResult.Verified[0].SourceType -eq 'File') { "файлов" }
                elseif ($VerificationResult.Verified[0].SourceType -eq 'Folder') { "папок" }
                else { "операций ротации" }
                Write-Log "Обработано после верификации: $($VerificationResult.Verified.Count) $delType" -Level SUCCESS -ResultKey
            }
        }
    }
}

function Write-JobReport {
    param(
        [string]$JobName,
        [object[]]$ArchiveResults,
        [int]$SuccessCount,
        [int]$ErrorCount,
        [int]$TotalFileCount,
        [hashtable]$VerificationResult,
        [int]$PipelineSuccessCount,
        [int]$PipelineErrorCount,
        [double]$JobDurationMin
    )
    # Статус задания
    if ($PipelineErrorCount -gt 0) { $jobStatus = 'Error' }
    elseif ($PipelineSuccessCount -gt 0) { $jobStatus = 'Success' }
    else { $jobStatus = 'Warning' }

    # Размер архивов
    $totalArchiveSize = ($ArchiveResults | Where-Object { $_.Status -eq 'Success' } |
        Measure-Object -Property ArchiveSize -Sum).Sum

    # Статус верификации
    $removeSrc = $false  # заглушка, определяется вызывающим
    $verificationStatus = 'Skipped'
}

#endregion

# ==============================================================================
#region ЭТАП 2: ОСНОВНОЙ ЗАПУСК
# ==============================================================================
$scriptStartTime = Get-Date
$config = Get-BackupConfiguration

# ----------------------------------------------------------
# TestMode
# ----------------------------------------------------------
if ($TestMode) {
    Write-Host "`n=== РЕЖИМ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    Write-Host "Проверка конфигурации без выполнения резервного копирования`n" -ForegroundColor Cyan
    $testErrors = @()
    $testWarnings = @()

    Write-Host "[1/5] Проверка архиватора..." -NoNewline
    if (Test-Path $config['Settings']['ArchiverPath']) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " FAIL" -ForegroundColor Red; $testErrors += "Архиватор не найден: $($config['Settings']['ArchiverPath'])" }

    Write-Host "[2/5] Проверка источников..." -NoNewline
    $sourceCheck = $true
    foreach ($jn in $config['Jobs'].Keys) {
        if (-not (Test-Path $config['Jobs'][$jn]['Source'])) {
            $testErrors += "Источник недоступ [$jn]: $($config['Jobs'][$jn]['Source'])"
            $sourceCheck = $false
        }
    }
    if ($sourceCheck) { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }

    Write-Host "[3/5] Проверка прав записи (LocalDest)..." -NoNewline
    $destCheck = $true
    foreach ($jn in $config['Jobs'].Keys) {
        try {
            if (-not (Test-Path $config['Jobs'][$jn]['LocalDest'])) {
                New-Item -Path $config['Jobs'][$jn]['LocalDest'] -ItemType Directory -Force -ErrorAction Stop | Remove-Item -Force
            }
        }
        catch { $testErrors += "Нет прав записи [$jn]: $($config['Jobs'][$jn]['LocalDest'])"; $destCheck = $false }
    }
    if ($destCheck) { Write-Host " OK" -ForegroundColor Green } else { Write-Host " FAIL" -ForegroundColor Red }

    Write-Host "[4/5] SMTP..." -NoNewline
    if (Test-StringIsNullOrWhiteSpace($SmtpServer)) {
        Write-Host " FAIL" -ForegroundColor Red; $testErrors += "SMTP не настроен"
    }
    else { Write-Host " OK ($SmtpServer)" -ForegroundColor Green }

    Write-Host "[5/5] Получатели почты..." -NoNewline
    if (Test-StringIsNullOrWhiteSpace($AdminMail)) {
        Write-Host " WARNING" -ForegroundColor Yellow; $testWarnings += "AdminMail не настроен"
    }
    else { Write-Host " OK ($AdminMail)" -ForegroundColor Green }

    Write-Host "`n=== РЕЗУЛЬТАТЫ ===" -ForegroundColor Cyan
    $totalDuration = [math]::Round(((Get-Date) - $scriptStartTime).TotalSeconds, 2)
    Write-Host "Время: $totalDuration сек | Заданий: $($config['Jobs'].Count) | Ошибок: $($testErrors.Count) | Предупреждений: $($testWarnings.Count)"

    $ReportBody = @"
РЕЖИМ: ТЕСТ (Backup не выполнялся)
КОМПЬЮТЕР: $PCName
ЗАДАНИЕ: $ParentJobName
ВРЕМЯ: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
ПРОВЕРКИ: Архиватор=$(if(Test-Path $config['Settings']['ArchiverPath']){"OK"}else{"FAIL"}) Источники=$(if($sourceCheck){"OK"}else{"FAIL"}) Назначения=$(if($destCheck){"OK"}else{"FAIL"})
"@
    if ($testErrors.Count -gt 0) { $ReportBody += "`nОШИБКИ:`n" + ($testErrors -join "`n") }
    if ($testWarnings.Count -gt 0) { $ReportBody += "`nПРЕДУПРЕЖДЕНИЯ:`n" + ($testWarnings -join "`n") }

    if (-not (Test-StringIsNullOrWhiteSpace($SmtpServer)) -and -not (Test-StringIsNullOrWhiteSpace($AdminMail))) {
        try {
            if ($testErrors.Count -eq 0) {
                Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $AdminMail -Subject "$PCName $ParentJobName : ТЕСТ УСПЕШЕН" -Body $ReportBody
                Write-WinEventAppLog -StatusKey "Success" -MessageText "ТЕСТ УСПЕШЕН"
            }
            else {
                Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $AdminMail -Subject "$PCName $ParentJobName : ТЕСТ ПРОВАЛЕН" -Body $ReportBody
                Write-WinEventAppLog -StatusKey "Error" -MessageText "ТЕСТ ПРОВАЛЕН"
            }
        }
        catch { Write-Host "Ошибка отправки: $($_.Exception.Message)" -ForegroundColor Red }
    }
    Write-Host "`nТестирование завершено." -ForegroundColor Cyan
    if ($testErrors.Count -gt 0) { exit 1 } else { exit 0 }
}

# ----------------------------------------------------------
# Основной запуск
# ----------------------------------------------------------
try {
    Initialize-Logging -LogPath $config['Settings']['LogPath'] -PCName $config['Settings']['PCName'] -JobName $config['Settings']['JobName']
}
catch {
    Write-Host "Ошибка инициализации логирования: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-LogSection "ЗАПУСК СКРИПТА РЕЗЕРВНОГО КОПИРОВАНИЯ" -ResultKey
Write-Log "Компьютер: $($config['Settings']['PCName'])" -ResultKey
Write-Log "Время: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ResultKey
Write-Log "Заданий: $($config['Jobs'].Count)" -ResultKey
Write-Log "Unified Pipeline v3.0 (только RAR)" -Level SUCCESS -ResultKey

$configTest = Test-Configuration
if (-not ($configTest.IsValid)) {
    Write-Log "Ошибки конфигурации:`n$($configTest.Errors -join "`n")" -Level ERROR
    exit 1
}

$results = @{}
$successCount = 0
$errorCount = 0

Write-WinEventAppLog -StatusKey "Start" -MessageText "Начало: $ParentJobName"

foreach ($jobName in $config['Jobs'].Keys) {
    $job = $config['Jobs'][$jobName]
    $jobStart = Get-Date
    Write-LogSection "ЗАДАНИЕ: $jobName" -ResultKey
    Write-Log "Источник: $($job['Source'])" -ResultKey
    Write-Log "Локальное назначение: $($job['LocalDest'])"
    Write-Log "Сетевое назначение: $($job['RemoteDest'])"
    Write-Log "Архив: $($job['Archive'])"

    try {
        # --- Проверка/создание директорий ---
        if (-not (Test-Path $job['Source'])) {
            Write-Log "Источник не существует: $($job['Source'])" -Level ERROR
            throw "Источник не существует"
        }
        if (-not (Test-Path $job['LocalDest'])) {
            New-Item -Path $job['LocalDest'] -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан LocalDest: $($job['LocalDest'])"
        }
        if ($job['RemoteDest'] -and (-not (Test-Path $job['RemoteDest']))) {
            New-Item -Path $job['RemoteDest'] -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан RemoteDest: $($job['RemoteDest'])"
        }

        # --- Анализ источника ---
        $fileInfo = Get-FileInfoDetails -Path $job['Source']
        Write-Log "Файлов в источнике: $($fileInfo.FileCount)" -ResultKey
        $sizeStr = if ($fileInfo.TotalSizeBytes -lt 1MB) {
            "{0:N0} Bytes" -f $fileInfo.TotalSizeBytes
        }
        else {
            "{0:N1} MB" -f $fileInfo.TotalSizeMB
        }
        Write-Log "Размер: $sizeStr" -ResultKey

        # --- SourceCheckMasks ---
        if ($job.ContainsKey('SourceCheckMasks') -and $job['SourceCheckMasks']) {
            Write-Log "Проверка масок..." -Level INFO
            foreach ($mask in $job['SourceCheckMasks']) {
                try {
                    $ff = Get-FilterFileList -Path $job['Source'] -Filter $mask
                    if ($ff.Count -eq 0) { Write-Log "Маска '$mask': НЕ НАЙДЕНО!" -Level ERROR -ResultKey }
                    else { Write-Log "Маска '$mask': $($ff.Count) шт." -ResultKey }
                }
                catch { Write-Log "Ошибка маски '$mask': $_" -Level ERROR -ResultKey }
            }
        }

        # --- ListSourceFlag ---
        if ($job.ContainsKey('ListSourceFlag') -and $job['ListSourceFlag']) {
            $listType = $job['ListSourceFlag'].ToLower()
            if ($listType -eq "txt" -or $listType -eq "csv") {
                try {
                    $sfl = Get-FileList -Path $job['Source']
                    $lf = [System.IO.Path]::ChangeExtension($job['Archive'], ".$listType")
                    $lfp = Join-Path $config['Settings']['LogPath'] $lf
                    if ($listType -eq "csv") {
                        $sfl | Select-Object RelativePath, Length, LastWriteTime |
                        Export-Csv -Path $lfp -NoTypeInformation -Encoding UTF8 -Delimiter ";"
                    }
                    else {
                        $sfl | Select-Object RelativePath, Length, LastWriteTime |
                        Format-Table -AutoSize | Out-File -FilePath $lfp -Encoding UTF8
                    }
                    Write-Log "Список сохранён: $lfp ($($sfl.Count) шт.)" -ResultKey
                }
                catch { Write-Log "Ошибка списка файлов: $_" -Level WARNING }
            }
        }

        # ========================================================
        # UNIFIED PIPELINE: Шаг 1 — Подготовка элементов
        # ========================================================
        Write-LogSection "ШАГ 1: ПОДГОТОВКА ЭЛЕМЕНТОВ АРХИВАЦИИ" -ResultKey
        $mode = Get-ArchiveMode -Job $job
        Write-Log "Режим архивации: $mode" -Level INFO -ResultKey
        $archiveItems = Prepare-ArchiveItems -Job $job -PCName $config['Settings']['PCName']

        if ($archiveItems.Count -eq 0) {
            Write-Log "Нет элементов для архивации. Задание пропущено." -Level WARNING -ResultKey
            $results[$jobName] = "Пропущено: нет элементов"
            continue
        }

        Write-Log "Элементов подготовлено: $($archiveItems.Count)" -ResultKey

        # ========================================================
        # UNIFIED PIPELINE: Шаг 2 — Архивация (единый механизм)
        # ========================================================
        Write-LogSection "ШАГ 2: АРХИВАЦИЯ" -ResultKey
        $pipelineResult = Invoke-ArchivePipeline `
            -ArchiveItems $archiveItems `
            -Job $job `
            -Config $config `
            -LogDir $config['Settings']['LogPath']

        $pipelineResults = $pipelineResult['Results']
        $pipelineSuccess = $pipelineResult['SuccessCount']
        $pipelineErrors = $pipelineResult['ErrorCount']

        # Проверяем, что хотя бы один архив создан
        $successfulArchives = $pipelineResults | Where-Object { $_.Status -eq 'Success' }
        if ($successfulArchives.Count -eq 0) {
            throw "Все архивы созданы с ошибками"
        }

        # ========================================================
        # UNIFIED PIPELINE: Шаг 3 — Верификация (включая 0 байт)
        # ========================================================
        Write-LogSection "ШАГ 3: ВЕРИФИКАЦИЯ (включая файлы 0 байт)" -ResultKey
        $verifyResult = Invoke-Verification `
            -ArchiveResults $successfulArchives `
            -Job $job `
            -Config $config

        # Проверяем корректность результата верификации
        if ($verifyResult.FailedCount -gt 0) {
            # Реальные ошибки верификации
            Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА: $($verifyResult.FailedCount) элемент(ов) не прошли проверку" -Level ERROR -ResultKey
        }
        elseif ($verifyResult.AllPassed) {
            # Все прошли — успех
            Write-Log "Верификация пройдена успешно: $($verifyResult.Verified.Count) элемент(ов), включая файлы 0 байт" -Level SUCCESS -ResultKey
        }
        else {
            # Нет ошибок, но не все прошли (пропущены пустые и т.д.)
            $skipped = $verifyResult.TotalCount - $verifyResult.Verified.Count - $verifyResult.FailedCount
            Write-Log "Верификация завершена: $($verifyResult.Verified.Count) OK, пропущено: $skipped" -Level INFO -ResultKey
        }

        # ========================================================
        # UNIFIED PIPELINE: Шаг 4 — Пост-операции
        # ========================================================
        Write-LogSection "ШАГ 4: ПОСТ-ОПЕРАЦИИ" -ResultKey
        Invoke-PostOperations `
            -ArchiveResults $pipelineResults `
            -Job $job `
            -Config $config `
            -VerificationResult $verifyResult `
            -PipelineSuccessCount $pipelineSuccess `
            -PipelineErrorCount $pipelineErrors

        # --- Итоги задания ---
        if ($verifyResult.FailedCount -gt 0) {
            # Верификация провалена — это ошибка
            $errorCount += $verifyResult.FailedCount
            $results[$jobName] = "Верификация провалена: $($verifyResult.FailedCount)/$($verifyResult.TotalCount) элементов"
        }
        elseif ($pipelineErrors -gt 0) {
            $errorCount += $pipelineErrors
            $results[$jobName] = "Частичный успех: $pipelineSuccess/$($archiveItems.Count) элементов"
        }
        else {
            $successCount++
            $results[$jobName] = "Успешно: $($pipelineSuccess) архивов"
        }

        $jobDuration = [math]::Round(((Get-Date) - $jobStart).TotalMinutes, 2)
        Write-Log "Задание завершено за $jobDuration мин. Результат: $($results[$jobName])" -ResultKey

        # Сетевые отчёты (XML + CSV) — только в NetLogPath, локально не сохраняем
        $totalArchiveSize = ($pipelineResults | Where-Object { $_.Status -eq 'Success' } |
            Measure-Object -Property ArchiveSize -Sum).Sum
        if ($verifyResult.FailedCount -gt 0) { $js = 'Error' }
        elseif ($pipelineErrors -gt 0) { $js = 'Error' }
        elseif ($pipelineSuccess -gt 0) { $js = 'Success' }
        else { $js = 'Warning' }
        $vs = if ($verifyResult.AllPassed -and $verifyResult.FailedCount -eq 0) { 'Passed' } else { 'Failed' }

        # Получаем список файлов источника для CSV-отчёта
        $sourceFileList = @()
        try {
            $srcRaw = $job['Source']
            if (-not [string]::IsNullOrEmpty($srcRaw)) {
                $srcPath = $srcRaw.TrimEnd('\', '/')
                if (-not [string]::IsNullOrEmpty($srcPath)) {
                    $eaOld = $ErrorActionPreference
                    $ErrorActionPreference = 'SilentlyContinue'
                    if (Test-Path -LiteralPath $srcPath -PathType Container) {
                        $items = @(Get-ChildItem -LiteralPath $srcPath -Recurse -Force | Where-Object { -not $_.PSIsContainer })
                        foreach ($item in $items) {
                            $rootResolved = (Resolve-Path -LiteralPath $srcPath).Path.TrimEnd('\')
                            $relPath = $item.FullName.Substring($rootResolved.Length + 1)
                            $sourceFileList += (New-Object PSObject -Property @{
                                    RelativePath  = $relPath
                                    Length        = $item.Length
                                    LastWriteTime = $item.LastWriteTime
                                })
                        }
                    }
                    $ErrorActionPreference = $eaOld
                }
            }
        }
        catch {
            $ErrorActionPreference = 'Continue'
            # CSV-отчёт необязателен — игнорируем ошибки
        }
        #!!!Запись в удаленный лог  TODO переделать из D:\Backup\<путь> в \\<PCNAME>\D$\Backup\<путь>
        Save-RemoteReports -PCName $PCName -JobName $jobName -JobStatus $js `
            -Duration "$jobDuration мин" -SourceFiles $fileInfo.FileCount `
            -ArchiveSizeMB $totalArchiveSize -Verification $vs `
            -LocalLogPath $(Get-LogFilePath) -SourceFileList $sourceFileList

    }
    catch {
        Write-Log "ОШИБКА: $_" -Level ERROR
        $results[$jobName] = "Ошибка: $_"
        $errorCount++
        $jobDuration = [math]::Round(((Get-Date) - $jobStart).TotalMinutes, 2)

        # Сетевой отчёт об ошибке
        #!!!Запись в удаленный лог  TODO переделать из D:\Backup\<путь> в \\<PCNAME>\D$\Backup\<путь>
        Save-RemoteReports -PCName $PCName -JobName $jobName -JobStatus 'Error' `
            -Duration "$jobDuration мин" -Errors @("$_") `
            -LocalLogPath $(Get-LogFilePath)
    }
}

#endregion

# ==============================================================================
#region ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ
# ==============================================================================
Write-Log "=== ДИАГНОСТИКА ОЧИСТКИ ЛОГОВ ===" -Level INFO
$logDir = $config['Settings']['LogPath']
if (Test-Path $logDir) {
    $allLogs = Get-ChildItem -Path $logDir | Where-Object { -not ($_.PSIsContainer) } | Sort-Object LastWriteTime -Descending
    Write-Log "Всего файлов в '$logDir': $($allLogs.Count)" -Level INFO
}

Write-LogSection "ОЧИСТКА СТАРЫХ ЛОГОВ"
try {
    Remove-OldFiles -Path $config['Settings']['LogPath'] -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.*"
}
catch { Write-Log "Ошибка очистки логов: $_" -Level WARNING }

$scriptEndTime = Get-Date
$totalDuration = [math]::Round(($scriptEndTime - $scriptStartTime).TotalMinutes, 2)
$DiskSpaceInfo = Get-DiskSpaceReport

Write-LogSection "ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ" -ResultKey
Write-Log "Время выполнения: $totalDuration мин" -ResultKey
Write-Log "Успешно: $successCount | Ошибки: $errorCount" -ResultKey
Write-Log "Диски: $DiskSpaceInfo" -ResultKey
foreach ($k in $results.Keys) { Write-Log "  $k : $($results[$k])" }

$EmailTextBody = Get-LogResults
$EmailTextBody += "`nПодробнее в логе: $(Get-LogFilePath)"

if ($errorCount -gt 0) {
    $AdminMailList = @($AdminIS, $AdminOS)
    $Subject = "$PCName $ParentJobName : ОБНАРУЖЕНЫ ОШИБКИ"
    $Body = "Ошибки в процессе:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Error" -MessageText "СКРИПТ ЗАВЕРШЁН С ОШИБКАМИ"
}
else {
    $AdminMailList = @($AdminIS, $AdminMail)
    $Subject = "$PCName $ParentJobName : УСПЕХ"
    $Body = "Задание выполнено успешно:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Success" -MessageText "СКРИПТ ЗАВЕРШЁН УСПЕШНО"
}

if (Test-StringIsNullOrWhiteSpace($SmtpServer)) {
    Write-Log "SmtpServer не настроен" -Level ERROR
}
elseif (Test-StringIsNullOrWhiteSpace($PCNameMail)) {
    Write-Log "PCNameMail пуст" -Level ERROR
}
else {
    try {
        Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To ($AdminMailList -join ", ") `
            -Subject $Subject -Body $Body
    }
    catch {
        Write-Log "Ошибка отправки почты: $_" -Level ERROR
    }
}

Write-WinEventAppLog -StatusKey "End" -MessageText "Завершение: $ParentJobName"

if ($errorCount -gt 0) { exit 1 } else { exit 0 }
#endregion
