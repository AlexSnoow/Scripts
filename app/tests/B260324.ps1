<#
.SYNOPSIS
    File Backup-Main-All.ps1
    Автономный скрипт резервного копирования (Версия 2.5)
.DESCRIPTION
    Единый файл, включающий все функции модулей:
    - Backup-Logger.psm1 (логирование)
    - Backup-RAR.psm1 (операции с RAR)
    - Backup-7z.psm1 (операции с 7-Zip)
    - Backup-Verification.psm1 (верификация)
    - Remove-OldFiles.psm1 (ротация файлов)
    - MailSender.psm1 (отправка почты)

    Поддерживает несколько конфигурационных файлов:
    - Backup-Config-All-rar.json (по умолчанию, RAR)
    - Backup-Config-All-7z.json (7z архиватор)
    Для указания конфигурации по умолчанию используется:
    [string]$ConfigFile = 'Backup-Config-All-rar.json'

    Поддерживаемые архиваторы: RAR, 7z, ZIP

    Переменные для ArchivePattern:
    - {PCName} - Имя компьютера
    - {JobName} - Имя одного из дочерних задания
    - {Date} - Дата в формате YYYYMMDD
    - {Time} - Время в формате HHMMSS
    - {Date_Time} - Дата и время в формате YYYYMMDD_HHMMSS

    Параметры ротации для Jobs (опционально):
    - RemoveSourceFlag - Включить ротацию источника (true/false, по умолчанию false)
    - RemoveRemoteDestFlag - Включить ротацию удаленного хранилища (true/false, по умолчанию false)
    - SourceDaysOld - Возраст файлов источника для удаления (дни)
    - SourceKeepCount - Минимальное количество файлов источника для сохранения
    - RemoteDestDaysOld - Возраст файлов удаленного хранилища для удаления (дни)
    - RemoteDestKeepCount - Минимальное количество файлов удаленного хранилища для сохранения

.PARAMETER ConfigFile
    Имя конфигурационного файла (по умолчанию: Backup-Config-All-rar.json)
    Пример:
    7z конфигурация
    .\Backup-Main-All.ps1 -ConfigFile Backup-Config-All-7z.json
    RAR конфигурация
    .\Backup-Main-All.ps1 -ConfigFile Backup-Config-All-rar.json

.EXAMPLE
    powershell.exe -executionpolicy RemoteSigned -file .\Backup-Main-All.ps1

.NOTES
    Автор: Тюкавкин
    Версия: 2.5
    Дата: 2026-03-19

    ТРЕБОВАНИЯ БЕЗОПАСНОСТИ:
    1. Файл конфигурации должен лежать в той же папке.
    2. В секции НАСТРОЙКИ БЕЗОПАСНОСТИ должны быть прописаны хеши для всех конфигураций.
    Получается командой: (Get-FileHash -Path ".\Backup-Config-All-rar.json" -Algorithm SHA256).Hash
    3. При изменении конфигурации необходимо обновить соответствующий хеш.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Backup-Config-All-rar.json', 'Backup-Config-All-7z.json', 'Backup-Config-All.json')]
    [string]$ConfigFile = 'Backup-Config-All-rar.json',
    
    # НОВЫЙ ПАРАМЕТР: Режим тестирования
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ===========================================================
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
$Script:CultureInvariant = [System.Globalization.CultureInfo]::InvariantCulture

Clear-Host

# ===========================================================
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША (совместимость с PowerShell 5.1)
# ===========================================================
<#
.SYNOPSIS
    Вычисление SHA256 хеша файла
.DESCRIPTION
    Совместимая реализация для PowerShell 5.1 через .NET классы.
    Используется как замена cmdlet Get-FileHash если он недоступен.
    Поддерживает параметры оригинального cmdlet для полной совместимости.
.PARAMETER Path
    Путь к файлу
.PARAMETER LiteralPath
    Путь к файлу (без обработки подстановочных знаков)
.PARAMETER Algorithm
    Алгоритм хеширования (поддерживается только SHA256)
.OUTPUTS
    [PSCustomObject] Объект с хешем (совместимый с Get-FileHash)
.EXAMPLE
    Get-FileHashCompat -Path "C:\file.txt"
.EXAMPLE
    Get-FileHashCompat -LiteralPath "C:\file.txt" -Algorithm SHA256
#>
function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([PSCustomObject])]
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
            # Проверка существования файла
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Файл не найден: $filePath"
            }
            
            # Выбор алгоритма хеширования
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
                
                # Возвращаем объект совместимый с Get-FileHash
                return [PSCustomObject]@{
                    Hash      = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path      = (Resolve-Path -LiteralPath $filePath).Path
                }
            }
            finally {
                $fileStream.Dispose()
                $hashAlgo.Dispose()
            }
        }
        catch {
            throw "Ошибка вычисления хеша файла '$filePath': $($_.Exception.Message)"
        }
    }
}

# Создаем алиас Get-FileHash если cmdlet недоступен
if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    New-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}
#endregion /ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША (совместимость с PowerShell 5.1)

# ===========================================================
#region НАСТРОЙКИ БЕЗОПАСНОСТИ
# ===========================================================
# Словарь конфигураций: ИмяФайла = ОжидаемыйHash
$Script:ConfigHashes = @{
    'Backup-Config-All.json'     = 'DC6E9D71FF25F7933C2C123BB0C5809F7874FEFFB055A25F4E6830EA59EBC78C'  # По умолчанию конфигурация
    'Backup-Config-All-rar.json' = 'A6DF52F98E60E65D2D39E9DD1FCFB2BE4DB6FF4AE1D5C1A349618935E1CAA193'  # RAR конфигурация (обновите хеш после изменения файла)
    'Backup-Config-All-7z.json'  = 'A85F2E0342CD3FAE83F65317145762D072223E77C279C71834734E8A84328A56'  # 7z конфигурация
}

$Script:ConfigFileName = $ConfigFile
$Script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $Script:ConfigFileName
$Script:ConfigExpectedHash = $Script:ConfigHashes[$ConfigFile]

Write-Host "Используемая конфигурация: $ConfigFile" -ForegroundColor Cyan

#endregion /НАСТРОЙКИ БЕЗОПАСНОСТИ

# ===========================================================
#region ФУНКЦИЯ ПРОВЕРКИ ЦЕЛОСТНОСТИ
# ===========================================================
<#
.SYNOPSIS
    Проверка целостности файла по SHA256 хешу
.DESCRIPTION
    Вычисляет SHA256 хеш файла и сравнивает с ожидаемым значением.
    Используется для проверки безопасности исполняемых файлов и конфигураций.
.PARAMETER FilePath
    Полный путь к проверяемому файлу
.PARAMETER ExpectedHash
    Ожидаемый SHA256 хеш (64 шестнадцатеричных символа)
.PARAMETER FileType
    Описание типа файла для вывода (по умолчанию: "Файл")
.OUTPUTS
    [bool] True если хеш совпадает, False если не совпадает или ошибка
.EXAMPLE
    Test-FileIntegrity -FilePath "C:\work\rar.exe" -ExpectedHash "A7A155..." -FileType "Архиватор"
#>
function Test-FileIntegrity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-F0-9]{64}$')][string]$ExpectedHash,
        [Parameter(Mandatory = $false)][string]$FileType = "Файл"
    )

    process {
        # Проверка существования файла
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
ВОЗМОЖНО ВРЕДОНОСНОЕ ПО или ПОВРЕЖДЕНИЕ ФАЙЛА.
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
#endregion /ФУНКЦИЯ ПРОВЕРКИ ЦЕЛОСТНОСТИ

# ==============================================================================
#region ЭТАП 0: ЗАГРУЗКА И ПРОВЕРКА КОНФИГУРАЦИИ
# ==============================================================================
Write-Host "`n=== ЭТАП 0: ПРОВЕРКА ФАЙЛА КОНФИГУРАЦИИ ===" -ForegroundColor Yellow

if (-not (Test-Path -LiteralPath $Script:ConfigPath -PathType Leaf)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Файл конфигурации не найден: $Script:ConfigPath" -ForegroundColor Red
    exit 1
}

Write-Host "Проверка целостности файла конфигурации..." -ForegroundColor Cyan
$actualConfigHash = (Get-FileHash -LiteralPath $Script:ConfigPath -Algorithm SHA256).Hash.ToUpper()

if ($actualConfigHash -ne $Script:ConfigExpectedHash.ToUpper()) {
    $msg = @"
КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ!
Файл конфигурации был изменен или поврежден:
$($Script:ConfigPath)
Ожидаемый хеш: $($Script:ConfigExpectedHash)
Фактический хеш: $actualConfigHash
Запуск скрипта запрещен.
"@
    Write-Host $msg -ForegroundColor Red
    Write-Error $msg
    exit 1
}
Write-Host "Конфигурация подтверждена. Загрузка настроек..." -ForegroundColor Green

try {
    $jsonContent = Get-Content -LiteralPath $Script:ConfigPath -Raw -Encoding UTF8
    $BackupConfig = ConvertFrom-Json $jsonContent
}
catch {
    Write-Host "Ошибка парсинга JSON: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Извлечение базовых переменных из конфига
$PCName = $env:COMPUTERNAME
$NameDomain = $BackupConfig.General.Domain
$PCNameMail = "$PCName@head.$NameDomain"
$SmtpServer = $BackupConfig.General.SmtpServer
$ParentJobName = $BackupConfig.General.JobName
$LogDaysOld = $BackupConfig.General.LogDaysOld
$LogKeepCount = $BackupConfig.General.LogKeepCount
$AdminIS = $BackupConfig.Recipients.AdminIS
$AdminOS = $BackupConfig.Recipients.AdminOS
$AdminMail = $BackupConfig.Recipients.AdminMail

#endregion /ЭТАП 0: ЗАГРУЗКА И ПРОВЕРКА КОНФИГУРАЦИИ

# ==============================================================================
#region ЭТАП 1: ПРОВЕРКА АРХИВАТОРОВ
# ==============================================================================
Write-Host "`n=== ЭТАП 1: ПРОВЕРКА АРХИВАТОРОВ ===" -ForegroundColor Yellow

# Определение типа архиватора из конфигурации
$archiverType = $BackupConfig.General.ArchiverType
if ([string]::IsNullOrWhiteSpace($archiverType)) {
    $archiverType = "RAR" # По умолчанию
}
$archiverType = $archiverType.ToUpper()

$archiverPathValue = $null
$archiverHash = $null
$archiverFileType = $null

switch ($archiverType) {
    "RAR" {
        if ($BackupConfig.PSObject.Properties.Name -contains 'Paths') {
            if ($BackupConfig.Paths.PSObject.Properties.Name -contains 'RarPath') {
                $archiverPathValue = $BackupConfig.Paths.RarPath
            }
        }
        $archiverHash = $BackupConfig.Integrity.RarExeHash
        $archiverFileType = "RAR.exe"
    }
    "7Z" {
        if ($BackupConfig.PSObject.Properties.Name -contains 'Paths') {
            if ($BackupConfig.Paths.PSObject.Properties.Name -contains 'SevenZipPath') {
                $archiverPathValue = $BackupConfig.Paths.SevenZipPath
            }
        }
        $archiverHash = $BackupConfig.Integrity.SevenZipExeHash
        $archiverFileType = "7z.exe"
    }
    "ZIP" {
        # ZIP использует встроенные средства Windows, проверка не требуется
        $archiverPathValue = "builtin"
        $archiverFileType = "Windows ZIP"
    }
    default {
        Write-Host "КРИТИЧЕСКАЯ ОШИБКА КОНФИГУРАЦИИ: Неверный тип архиватора '$archiverType'. Допустимые: RAR, 7Z, ZIP" -ForegroundColor Red
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($archiverPathValue)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА КОНФИГУРАЦИИ: Не найден путь к архиватору ($archiverType)" -ForegroundColor Red
    exit 1
}

if ($archiverType -ne "ZIP") {
    if (-not (Test-FileIntegrity -FilePath $archiverPathValue -ExpectedHash $archiverHash -FileType "Архиватор $archiverFileType")) {
        Write-Host "ПРОВЕРКА АРХИВАТОРА ПРОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Архиватор ($archiverType) проверен: $archiverPathValue`n" -ForegroundColor Green

#endregion /ЭТАП 1: ПРОВЕРКА АРХИВАТОРОВ

# ==============================================================================
#region МОДУЛЬ ЛОГИРОВАНИЯ (Backup-Logger.psm1)
# ==============================================================================
$Script:LogPath = $null
$Script:MainLogFile = $null
$Script:ReportEntries = @()

<#
.SYNOPSIS
    Инициализация системы логирования
.DESCRIPTION
    Создает директорию логов, генерирует имя файла лога с временной меткой,
    инициализирует переменные для сбора отчётных записей.
.PARAMETER LogPath
    Путь к директории для хранения логов
.PARAMETER PCName
    Имя компьютера (для имени файла лога)
.PARAMETER JobName
    Имя задания (для имени файла лога)
.OUTPUTS
    [bool] True если инициализация успешна
#>
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
            # Очистка имени компьютера и задания от недопустимых символов
            $safePCName = $PCName -replace '[\\/:*?"<>|]', '-'
            $safeJobName = $JobName -replace '[\\/:*?"<>|]', '-'

            # Создание директории логов если не существует
            if (-not (Test-Path -LiteralPath $LogPath -PathType Container)) {
                New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            # Генерация имени файла лога с временной меткой
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $logFileName = "${safePCName}_${safeJobName}_${timestamp}.log"
            $fullLogPath = Join-Path -Path $LogPath -ChildPath $logFileName

            $Script:LogPath = $LogPath
            $Script:MainLogFile = $fullLogPath
            $Script:ReportEntries = @()

            # Создание пустого файла лога (UTF8 без BOM)
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($fullLogPath, "", $utf8NoBom)

            # Запись заголовка в лог
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

<#
.SYNOPSIS
    Запись сообщения в лог-файл
.DESCRIPTION
    Записывает сообщение в текущий лог-файл с временной меткой и уровнем важности.
    Поддерживает различные уровни: INFO, WARNING, ERROR, SUCCESS, DEBUG.
    При указании -ResultKey сообщение добавляется в коллекцию для отчёта.
.PARAMETER Message
    Текст сообщения для записи в лог
.PARAMETER Level
    Уровень важности: INFO, WARNING, ERROR, SUCCESS, DEBUG (по умолчанию: INFO)
.PARAMETER ResultKey
    Добавить сообщение в коллекцию отчётных записей
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter(Mandatory = $false, Position = 1)][ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')][string]$Level = 'INFO',
        [Parameter(Mandatory = $false)][switch]$ResultKey
    )

    process {
        try {
            if (-not $Script:MainLogFile) {
                throw "Логирование не инициализировано. Вызовите Initialize-Logging перед использованием Write-Log."
            }

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $levelPrefix = switch ($Level) {
                'ERROR' { '[ERROR]  ' }
                'WARNING' { '[WARNING]' }
                'SUCCESS' { '[SUCCESS]' }
                'DEBUG' { '[DEBUG]  ' }
                default { '[INFO]   ' }
            }

            # Удаление переносов строк из сообщения
            $safeMessage = $Message -replace '\r?\n', ' '
            $logEntry = "[$timestamp] $levelPrefix $safeMessage"

            # Запись в файл (UTF8 без BOM)
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$logEntry`r`n", $utf8NoBom)

            # Добавление в коллекцию отчётных записей
            if ($ResultKey) {
                $Script:ReportEntries += $logEntry
            }

            # Вывод в консоль в зависимости от уровня
            switch ($Level) {
                'ERROR' { Write-Error $Message -ErrorAction Continue }
                'WARNING' { Write-Warning $Message }
                'SUCCESS' { Write-Host $Message -ForegroundColor Green }
            }
        }
        catch {
            Write-Error "ПОЛНЫЙ ОТКАЗ ЛОГИРОВАНИЯ: $_" -ErrorAction Continue
        }
    }
}

<#
.SYNOPSIS
    Получение пути к текущему лог-файлу
.DESCRIPTION
    Возвращает полный путь к активному лог-файлу
.OUTPUTS
    [string] Полный путь к лог-файлу
#>
function Get-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $Script:MainLogFile
}

<#
.SYNOPSIS
    Запись разделителя секции в лог
.DESCRIPTION
    Создает визуальный разделитель в логе для выделения секций.
    Если указан Title, создает рамку с заголовком.
.PARAMETER Title
    Заголовок секции (опционально)
.PARAMETER ResultKey
    Добавить разделитель в коллекцию отчётных записей
#>
function Write-LogSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Title,
        [Parameter(Mandatory = $false)][switch]$ResultKey
    )

    process {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelPrefix = '[INFO]   '

        if ($Title) {
            $upperTitle = $Title.ToUpper()
            $line1 = "[$timestamp] $levelPrefix ========================================"
            $line2 = "[$timestamp] $levelPrefix $upperTitle"
            $line3 = "[$timestamp] $levelPrefix ========================================"

            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$line1`r`n$line2`r`n$line3`r`n", $utf8NoBom)

            if ($ResultKey) {
                $Script:ReportEntries += $line1, $line2, $line3
            }
        }
        else {
            $line = "[$timestamp] $levelPrefix ----------------------------------------"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::AppendAllText($Script:MainLogFile, "$line`r`n", $utf8NoBom)

            if ($ResultKey) {
                $Script:ReportEntries += $line
            }
        }
    }
}

<#
.SYNOPSIS
    Получение отчётных записей
.DESCRIPTION
    Возвращает все сообщения, отмеченные флагом -ResultKey, соединённые переводами строк.
.OUTPUTS
    [string] Текст отчёта
#>
function Get-LogResults {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($Script:ReportEntries.Count -eq 0) {
        return "Нет сообщений для отчёта. Используйте параметр -ResultKey в Write-Log для включения сообщений в отчёт."
    }

    return ($Script:ReportEntries -join "`r`n")
}

<#
.SYNOPSIS
    Запись события в журнал Windows Application
.DESCRIPTION
    Записывает событие в журнал Windows Application с указанным источником.
    Если источник не зарегистрирован, выводит предупреждение.
.PARAMETER StatusKey
    Тип события: Start, Success, Warning, Error, End
.PARAMETER MessageText
    Текст сообщения для записи в журнал
.PARAMETER Source
    Источник события (по умолчанию: значение $ParentJobName)
#>
function Write-WinEventAppLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet("Start", "Success", "Warning", "Error", "End")][string]$StatusKey,
        [Parameter(Mandatory)][string]$MessageText,
        [Parameter(Mandatory = $false)][string]$Source = $ParentJobName
    )

    $LogName = 'Application'

    try {
        # Проверка регистрации источника
        # ВАЖНО: Вторым аргументом должно быть имя компьютера ("." - локальный), а не имя лога!
        $existingLog = $null
        try {
            $existingLog = [System.Diagnostics.EventLog]::LogNameFromSourceName($Source, ".")
        }
        catch [System.Management.Automation.MethodInvocationException] {
            # Источник не найден - это нормальная ситуация
            Write-Log "Предупреждение: Источник '$Source' не зарегистрирован в журнале '$LogName'. Запись в Event Log невозможна." -Level WARNING
            Write-Log "Для регистрации источника выполните от имени администратора: New-EventLog -Source '$Source' -LogName '$LogName'" -Level WARNING
            return
        }

        # Если источник не найден, метод возвращает пустую строку
        if ([string]::IsNullOrEmpty($existingLog)) {
            Write-Log "Предупреждение: Источник '$Source' не зарегистрирован в журнале '$LogName'. Запись в Event Log невозможна." -Level WARNING
            Write-Log "Для регистрации источника выполните от имени администратора: New-EventLog -Source '$Source' -LogName '$LogName'" -Level WARNING
            return
        }

        # Проверяем, что источник привязан именно к нужному журналу
        if ($existingLog -ne $LogName) {
            Write-Log "Предупреждение: Источник '$Source' привязан к другому журналу ('$existingLog'), а не к '$LogName'. Запись невозможна." -Level WARNING
            return
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Log "Неожиданная ошибка при проверке EventLog: $errorMsg" -Level WARNING
        return
    }

    # Маппинг статусов на ID событий и типы записей
    $eventIdMap = @{ Start = 3000; Success = 3001; Warning = 3002; Error = 3003; End = 3004 }
    $entryTypeMap = @{
        Start   = [System.Diagnostics.EventLogEntryType]::Information
        Success = [System.Diagnostics.EventLogEntryType]::Information
        Warning = [System.Diagnostics.EventLogEntryType]::Warning
        Error   = [System.Diagnostics.EventLogEntryType]::Error
        End     = [System.Diagnostics.EventLogEntryType]::Information
    }

    try {
        $eventLog = New-Object System.Diagnostics.EventLog($LogName)
        $eventLog.Source = $Source
        $eventLog.WriteEntry($MessageText, $entryTypeMap[$StatusKey], $eventIdMap[$StatusKey])
    }
    catch { Write-Log "Ошибка записи в EventLog: $_" -Level ERROR }
}
#endregion /МОДУЛЬ ЛОГИРОВАНИЯ

# ==============================================================================
#region МОДУЛЬ RAR ОПЕРАЦИЙ (Backup-RAR.psm1)
# ==============================================================================
<#
.SYNOPSIS
    Расшифровка кода выхода RAR
.DESCRIPTION
    Возвращает текстовое описание кода выхода RAR.exe
.PARAMETER ExitCode
    Код возврата от RAR.exe
.OUTPUTS
    [string] Описание кода выхода
#>
function Get-RarExitCodeMeaning {
    param([int]$ExitCode)

    $errorDescriptions = @{
        0   = "Успешное выполнение"
        1   = "Произошла незначительная ошибка при создании архива"
        2   = "Произошла критическая ошибка при создании архива"
        3   = "Ошибка при проверке целостности архива"
        4   = "Ошибка при открытии файла"
        5   = "Ошибка записи файла"
        6   = "Невозможно прочитать файл: возможно, он открыт в другой программе или заблокирован"
        7   = "Недопустимая команда или параметр"
        8   = "Не хватает памяти для выполнения операции"
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

<#
.SYNOPSIS
    Создание RAR архива
.DESCRIPTION
    Запускает RAR.exe для создания архива из указанной директории.
    Поддерживает логирование процесса в отдельный файл.
.PARAMETER RarPath
    Путь к RAR.exe
.PARAMETER ArchivePath
    Полный путь к создаваемому архиву
.PARAMETER SourcePath
    Путь к исходной директории
.PARAMETER Parameters
    Параметры командной строки RAR (по умолчанию: a, -m3, -s, -ep1, -rr1p, -r, -dh, -t)
.PARAMETER LogPath
    Путь к файлу лога RAR (опционально)
.OUTPUTS
    [hashtable] Результат архивации: ExitCode, Duration, ArchiveSize, LogContent
#>
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
        if ($PSBoundParameters.ContainsKey('LogPath') -and -not [string]::IsNullOrEmpty($LogPath)) {
            $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
            if ([string]::IsNullOrEmpty($logDir)) { $logDir = "." }

            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
                try { $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop } catch {}
            }

            if (Test-Path -LiteralPath $logDir -PathType Container) {
                $actualLogPath = $LogPath
            }
        }

        # Формирование аргументов
        $argsList = @($Parameters)
        if ($actualLogPath) {
            $argsList += '-ilog"' + $actualLogPath + '"'
        }

        $safeArchivePath = '"' + ($ArchivePath -replace '"', '\"') + '"'
        
        # Применение фильтра SourceFilter если указан
        if (-not [string]::IsNullOrWhiteSpace($SourceFilter)) {
            $filteredPath = Join-Path -Path $SourcePath -ChildPath $SourceFilter
            $safeSourcePath = '"' + ($filteredPath -replace '"', '\"') + '"'
            Write-Verbose "Применён фильтр SourceFilter: $SourceFilter" -Verbose
        }
        else {
            $safeSourcePath = '"' + ($SourcePath -replace '"', '\"') + '"'
        }
        
        $argsList += @($safeArchivePath, $safeSourcePath)

        Write-Verbose "Аргументы RAR: $($argsList -join ' ')" -Verbose
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
            # Кодировка OEM866 для поддержки кириллицы в именах файлов
            $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(866)
            $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(866)

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null

            $null = $process.StandardOutput.ReadToEnd()
            $null = $process.StandardError.ReadToEnd()

            $process.WaitForExit()
            $exitCode = $process.ExitCode

            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)

            # Чтение лога RAR если он существует
            $logContent = @()
            $failedFiles = @()

            if ($actualLogPath -and (Test-Path -LiteralPath $actualLogPath)) {
                try {
                    $logContent = Get-Content -LiteralPath $actualLogPath -Encoding OEM -ErrorAction Stop
                }
                catch { Write-Warning "Не удалось прочитать лог: $($_.Exception.Message)" }
            }

            # Получение размера архива
            $archiveSizeMB = 0
            if (-not [string]::IsNullOrEmpty($ArchivePath) -and (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
                try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch { $archiveSizeMB = 0 }
            }

            return @{
                ExitCode    = $exitCode
                Duration    = $duration
                StartTime   = $processStart
                EndTime     = $processEnd
                LogPath     = $actualLogPath
                LogContent  = $logContent
                FailedFiles = $failedFiles
                ArchiveSize = $archiveSizeMB
            }
        }
        catch {
            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
            Write-Error "Критическая ошибка запуска RAR: $($_.Exception.Message)"
            Write-Verbose "Стек вызовов: $($_.ScriptStackTrace)" -Verbose

            return @{
                ExitCode    = 255
                Duration    = $duration
                StartTime   = $processStart
                EndTime     = $processEnd
                LogPath     = $actualLogPath
                LogContent  = @()
                FailedFiles = @()
                Exception   = $_.Exception
            }
        }
    }
}

<#
.SYNOPSIS
    Проверка целостности RAR архива
.DESCRIPTION
    Запускает RAR.exe с командой 't' для проверки целостности архива.
.PARAMETER RarPath
    Путь к RAR.exe
.PARAMETER ArchivePath
    Путь к проверяемому архиву
.OUTPUTS
    [hashtable] ExitCode, IsValid
#>
function Test-RarArchive {
    param(
        [Parameter(Mandatory = $true)][string]$RarPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $testArgs = @("t", "`"$ArchivePath`"")
    Write-Log "Проверка целостности архива: $ArchivePath"

    $process = Start-Process -FilePath $RarPath -ArgumentList $testArgs -Wait -PassThru -WindowStyle Hidden

    return @{
        ExitCode = $process.ExitCode
        IsValid  = ($process.ExitCode -eq 0)
    }
}
#endregion /МОДУЛЬ RAR ОПЕРАЦИЙ

# ==============================================================================
#region МОДУЛЬ 7Z ОПЕРАЦИЙ (Backup-7z.psm1)
# ==============================================================================
<#
.SYNOPSIS
    Расшифровка кода выхода 7-Zip
.DESCRIPTION
    Возвращает текстовое описание кода выхода 7z.exe
.PARAMETER ExitCode
    Код возврата от 7z.exe
.OUTPUTS
    [string] Описание кода выхода
#>
function Get-7zExitCodeMeaning {
    param([int]$ExitCode)

    $errorDescriptions = @{
        0   = "Успешное выполнение"
        1   = "Незначительная ошибка (некоторые файлы не были заархивированы)"
        2   = "Критическая ошибка"
        7   = "Ошибка командной строки"
        8   = "Недостаточно памяти"
        255 = "Операция прервана пользователем"
    }

    if ($errorDescriptions.ContainsKey($ExitCode)) {
        return $errorDescriptions[$ExitCode]
    }
    else {
        return "Неизвестный код возврата: $ExitCode"
    }
}

<#
.SYNOPSIS
    Создание 7z архива
.DESCRIPTION
    Запускает 7z.exe для создания архива из указанной директории.
    Поддерживает форматы: 7z, zip, tar, gzip.
    Использует кодировку UTF-8.
.PARAMETER SevenZipPath
    Путь к 7z.exe
.PARAMETER ArchivePath
    Полный путь к создаваемому архиву
.PARAMETER SourcePath
    Путь к исходной директории
.PARAMETER ArchiveType
    Тип архива: 7z, zip, tar, gzip (по умолчанию: 7z)
.PARAMETER Parameters
    Параметры командной строки 7z (по умолчанию: a, -t7z, -m0=lzma2, -mx=5, ...)
.PARAMETER LogPath
    Путь к файлу лога 7z (опционально)
.OUTPUTS
    [hashtable] Результат архивации: ExitCode, Duration, ArchiveSize, StdOut, StdErr
#>
function Start-7zArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $false)][string]$ArchiveType = "7z",
        [Parameter(Mandatory = $false)][string[]]$Parameters = @("a", "-t7z", "-m0=lzma2", "-mx=5", "-mfb=64", "-md=32m", "-ms=on", "-sdel-", "-r"),
        [Parameter(Mandatory = $false)][string]$LogPath,
        [Parameter(Mandatory = $false)][string]$SourceFilter
    )

    begin {
        $actualLogPath = $null
        if ($PSBoundParameters.ContainsKey('LogPath') -and -not [string]::IsNullOrEmpty($LogPath)) {
            $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
            if ([string]::IsNullOrEmpty($logDir)) { $logDir = "." }

            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
                try { $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop } catch {}
            }

            if (Test-Path -LiteralPath $logDir -PathType Container) {
                $actualLogPath = $LogPath
            }
        }

        # Формирование аргументов для 7z
        $argsList = @($Parameters)

        # Добавляем тип архива, если не указан в параметрах
        if ($Parameters -notmatch '^-t') {
            $archiveTypeSwitch = switch ($ArchiveType.ToLower()) {
                "7z" { "-t7z" }
                "zip" { "-tzip" }
                "tar" { "-ttar" }
                "gzip" { "-tgz" }
                default { "-t7z" }
            }
            if ($argsList -notcontains $archiveTypeSwitch) {
                $argsList = @("a", $archiveTypeSwitch) + ($argsList | Where-Object { $_ -notmatch '^-t' })
            }
        }

        $safeArchivePath = '"' + ($ArchivePath -replace '"', '\"') + '"'
        
        # Применение фильтра SourceFilter если указан
        if (-not [string]::IsNullOrWhiteSpace($SourceFilter)) {
            $filteredPath = Join-Path -Path $SourcePath -ChildPath $SourceFilter
            $safeSourcePath = '"' + ($filteredPath -replace '"', '\"') + '"'
            Write-Verbose "Применён фильтр SourceFilter: $SourceFilter" -Verbose
        }
        else {
            # Используем полный путь с * для сохранения структуры каталогов
            $fullSourcePath = (Join-Path $SourcePath '*') -replace '\\\\', '\'
            $safeSourcePath = '"' + $fullSourcePath + '"'
        }
        
        $argsList += @($safeArchivePath, $safeSourcePath)

        Write-Verbose "Аргументы 7z: $($argsList -join ' ')" -Verbose
        Write-Verbose "Рабочая директория: $SourcePath" -Verbose
    }

    process {
        $processStart = Get-Date

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SevenZipPath
            $psi.Arguments = $argsList -join ' '
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            # 7z использует OEM866 кодировку для вывода в Windows (поддержка кириллицы)
            $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(866)
            $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(866)

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null

            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            $process.WaitForExit()
            $exitCode = $process.ExitCode

            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)

            # Сохранение вывода в лог если указан путь
            $logContent = @()
            if ($actualLogPath) {
                try {
                    $logContent = @($stdout -split "`r?`n")
                    if ($stderr) {
                        $logContent += ($stderr -split "`r?`n")
                    }
                    [System.IO.File]::WriteAllLines($actualLogPath, $logContent, [System.Text.Encoding]::UTF8)
                }
                catch { Write-Warning "Не удалось записать лог 7z: $($_.Exception.Message)" }
            }

            # Получение размера архива
            $archiveSizeMB = 0
            if (-not [string]::IsNullOrEmpty($ArchivePath) -and (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
                try { $archiveSizeMB = [math]::Round((Get-Item -LiteralPath $ArchivePath).Length / 1MB, 2) } catch { $archiveSizeMB = 0 }
            }

            return @{
                ExitCode    = $exitCode
                Duration    = $duration
                StartTime   = $processStart
                EndTime     = $processEnd
                LogPath     = $actualLogPath
                LogContent  = $logContent
                StdOut      = $stdout
                StdErr      = $stderr
                ArchiveSize = $archiveSizeMB
            }
        }
        catch {
            $processEnd = Get-Date
            $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
            Write-Error "Критическая ошибка запуска 7z: $($_.Exception.Message)"
            Write-Verbose "Стек вызовов: $($_.ScriptStackTrace)" -Verbose

            return @{
                ExitCode   = 255
                Duration   = $duration
                StartTime  = $processStart
                EndTime    = $processEnd
                LogPath    = $actualLogPath
                LogContent = @()
                StdOut     = ""
                StdErr     = $_.Exception.Message
                Exception  = $_.Exception
            }
        }
    }
}

<#
.SYNOPSIS
    Проверка целостности 7z архива
.DESCRIPTION
    Запускает 7z.exe с командой 't' для проверки целостности архива.
.PARAMETER SevenZipPath
    Путь к 7z.exe
.PARAMETER ArchivePath
    Путь к проверяемому архиву
.OUTPUTS
    [hashtable] ExitCode, IsValid
#>
function Test-7zArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $testArgs = @("t", "`"$ArchivePath`"")
    Write-Log "Проверка целостности архива: $ArchivePath"

    $process = Start-Process -FilePath $SevenZipPath -ArgumentList $testArgs -Wait -PassThru -WindowStyle Hidden

    return @{
        ExitCode = $process.ExitCode
        IsValid  = ($process.ExitCode -eq 0)
    }
}

<#
.SYNOPSIS
    Получение списка файлов из 7z архива
.DESCRIPTION
    Запускает 7z.exe с командой 'l' для получения списка файлов в архиве.
    Парсит вывод и возвращает коллекцию объектов с информацией о файлах.
    Использует формат вывода -slt для надёжного парсинга.
    Преобразует полные пути в относительные.
.PARAMETER SevenZipPath
    Путь к 7z.exe
.PARAMETER ArchivePath
    Путь к архиву
.OUTPUTS
    [object[]] Коллекция объектов: RelativePath, Length, LastWriteTime
#>
function Get-7zArchiveFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SevenZipPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    Write-Verbose "Чтение содержимого архива 7z: $ArchivePath"

    try {
        # Используем формат -slt для подробного вывода
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $SevenZipPath
        $psi.Arguments = "l -slt `"$ArchivePath`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        # 7z использует OEM866 кодировку для вывода в Windows (поддержка кириллицы)
        $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(866)

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null

        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            throw "7z вернул код ошибки $($process.ExitCode)"
        }

        # Парсинг вывода 7z в формате -slt
        $files = @()
        $lines = $stdout -split "`r?`n"

        $currentFile = @{}

        foreach ($line in $lines) {
            $line = $line.Trim()
            if ([string]::IsNullOrEmpty($line)) {
                # Пустая строка - конец записи о файле
                if ($currentFile.ContainsKey('Path') -and $currentFile.ContainsKey('Size')) {
                    $path = $currentFile['Path']
                    # Пропускаем директории (проверка по атрибутам и пути)
                    $isDirectory = $false
                    if ($currentFile.ContainsKey('Attributes')) {
                        $attrs = $currentFile['Attributes']
                        # DI = Directory, D = Directory
                        if ($attrs -match 'D' -or $attrs -eq 'DI') {
                            $isDirectory = $true
                        }
                    }
                    if (-not $isDirectory -and -not $path.EndsWith('\')) {
                        $size = [int64]$currentFile['Size']
                        $date = if ($currentFile.ContainsKey('Modified')) {
                            [DateTime]::Parse($currentFile['Modified'], [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                        else { Get-Date }

                        # Нормализация пути: заменяем обратные слеши
                        $normalizedPath = $path -replace '/', '\'

                        $files += [PSCustomObject]@{
                            RelativePath  = $normalizedPath.ToLowerInvariant()
                            Length        = $size
                            LastWriteTime = $date
                            Source        = "Archive"
                            FullPath      = $path
                        }
                    }
                }
                $currentFile = @{}
                continue
            }
            
            # Парсинг строк вида "Path = C:\..."
            if ($line -match '^([^=]+)\s*=\s*(.+)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $currentFile[$key] = $value
            }
        }

        # Обработка последней записи
        if ($currentFile.ContainsKey('Path') -and $currentFile.ContainsKey('Size')) {
            $path = $currentFile['Path']
            # Пропускаем директории (проверка по атрибутам и пути)
            $isDirectory = $false
            if ($currentFile.ContainsKey('Attributes')) {
                $attrs = $currentFile['Attributes']
                if ($attrs -match 'D' -or $attrs -eq 'DI') {
                    $isDirectory = $true
                }
            }
            if (-not $isDirectory -and -not $path.EndsWith('\')) {
                $size = [int64]$currentFile['Size']
                $date = if ($currentFile.ContainsKey('Modified')) {
                    [DateTime]::Parse($currentFile['Modified'], [System.Globalization.CultureInfo]::InvariantCulture)
                }
                else { Get-Date }

                # Нормализация пути: заменяем обратные слеши
                $normalizedPath = $path -replace '/', '\'

                $files += [PSCustomObject]@{
                    RelativePath  = $normalizedPath.ToLowerInvariant()
                    Length        = $size
                    LastWriteTime = $date
                    Source        = "Archive"
                    FullPath      = $path
                }
            }
        }

        Write-Verbose "В архиве найдено файлов: $($files.Count)"
        return $files
    }
    catch {
        Write-Error "Ошибка при чтении архива 7z $ArchivePath : $($_.Exception.Message)"
        throw
    }
}
#endregion /МОДУЛЬ 7Z ОПЕРАЦИЙ

# ==============================================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ АРХИВАЦИИ
# ==============================================================================
<#
.SYNOPSIS
    Получение информации о файлах в директории
.DESCRIPTION
    Сканирует директорию и возвращает статистику: количество файлов, общий размер, примеры файлов.
.PARAMETER Path
    Путь к директории для сканирования
.OUTPUTS
    [hashtable] FileCount, TotalSizeMB, FileSamples, HasMoreFiles
#>
function Get-FileInfoDetails {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $fileCount = $items.Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum

        $fileSamples = $items | Select-Object -First 5 | ForEach-Object {
            @{
                Name     = $_.Name
                SizeKB   = [math]::Round($_.Length / 1KB, 2)
                FullPath = $_.FullName
            }
        }

        return @{
            FileCount      = $fileCount
            TotalSizeMB    = [math]::Round($totalSize / 1MB, 2)
            TotalSizeBytes = $totalSize
            FileSamples    = $fileSamples
            HasMoreFiles   = ($fileCount -gt 5)
            MoreFilesCount = ($fileCount - 5)
        }
    }
    catch {
        return @{
            FileCount      = 0
            TotalSizeMB    = 0
            TotalSizeBytes = 0
            FileSamples    = @()
            HasMoreFiles   = $false
            MoreFilesCount = 0
            Error          = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Копирование файла резервной копии
.DESCRIPTION
    Копирует файл из источника в назначение и проверяет совпадение размеров.
.PARAMETER SourcePath
    Путь к исходному файлу
.PARAMETER DestinationPath
    Путь к файлу назначения
.OUTPUTS
    [hashtable] Success, Duration, SourceSize, DestinationSize
#>
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

    return @{
        Success         = ($sourceSize -eq $destSize)
        Duration        = $duration
        SourceSize      = $sourceSize
        DestinationSize = $destSize
        StartTime       = $copyStart
        EndTime         = $copyEnd
    }
}

<#
.SYNOPSIS
Архивирование отдельных файлов по маске
.DESCRIPTION
Создаёт отдельный архив для каждого файла, соответствующего маске.
Имя архива формируется из имени исходного файла.
Поддерживает RAR и 7z архиваторы.
.PARAMETER ArchiverType
Тип архиватора: RAR, 7Z, ZIP
.PARAMETER ArchiverPath
Путь к исполняемому файлу архиватора
.PARAMETER SourcePath
Путь к исходной директории
.PARAMETER DestinationPath
Путь к директории назначения архивов
.PARAMETER FileFilter
Маска файлов для архивирования (например: *.log.20*)
.PARAMETER ArchivePattern
Шаблон имени архива: {PCName}, {JobName}, {SourceFileName}
.PARAMETER Parameters
Параметры командной строки архиватора
.PARAMETER LogPath
Путь к файлу лога (опционально)
.OUTPUTS
[object[]] Коллекция результатов архивирования для каждого файла
.EXAMPLE
$result = Start-IndividualFileArchive -ArchiverType "RAR" -ArchiverPath "C:\work\rar.exe" -SourcePath "C:\src" -DestinationPath "C:\dst" -FileFilter "*.log.20*" -ArchivePattern "{PCName}_{JobName}_{SourceFileName}.rar" -Parameters @("a", "-m3")
#>
function Start-IndividualFileArchive {
[CmdletBinding()]
[OutputType([object[]])]
param(
    [Parameter(Mandatory = $true)][ValidateSet('RAR', '7Z', 'ZIP')][string]$ArchiverType,
    [Parameter(Mandatory = $true)][string]$ArchiverPath,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$FileFilter,
    [Parameter(Mandatory = $true)][string]$ArchivePattern,
    [Parameter(Mandatory = $false)][string[]]$Parameters,
    [Parameter(Mandatory = $false)][string]$LogPath,
    [Parameter(Mandatory = $false)][string]$PCName,
    [Parameter(Mandatory = $false)][string]$JobName
)
process {
    $results = @()
    $archiveExtension = switch ($ArchiverType) {
        'RAR' { '.rar' }
        '7Z'  { '.7z' }
        'ZIP' { '.zip' }
        default { '.rar' }
    }
    
    Write-Log "Поиск файлов для индивидуальной архивации по маске: $FileFilter" -Level INFO -ResultKey
    
    $files = Get-FilterFileList -Path $SourcePath -Filter $FileFilter
    
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
        
        # Формирование имени архива
        $archiveName = $ArchivePattern
        $archiveName = $archiveName -replace '{PCName}', $PCName
        $archiveName = $archiveName -replace '{JobName}', $JobName
        $archiveName = $archiveName -replace '{SourceFileName}', $sourceFileName
        
        # Удаление недопустимых символов из имени архива
        $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
        
        if ($archiveName -notmatch '\.(rar|7z|zip)$') {
            $archiveName = $archiveName + $archiveExtension
        }
        
        $archivePath = Join-Path -Path $DestinationPath -ChildPath $archiveName
        
        Write-Log "Архивация файла: ${sourceFileName} -> $archiveName" -Level INFO
        
        try {
            $arhResult = $null
            
            switch ($ArchiverType) {
                'RAR' {
                    $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $sourceFilePath -Parameters $Parameters -LogPath $null
                }
                '7Z' {
                    $archiveType = [System.IO.Path]::GetExtension($archivePath).TrimStart('.')
                    $arhResult = Start-7zArchive -SevenZipPath $ArchiverPath -ArchivePath $archivePath -SourcePath $sourceFilePath -ArchiveType $archiveType -Parameters $Parameters -LogPath $null
                }
                'ZIP' {
                    try {
                        Compress-Archive -Path $sourceFilePath -DestinationPath $archivePath -Force -ErrorAction Stop
                        $arhResult = @{
                            ExitCode    = 0
                            Duration    = 0
                            ArchiveSize = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
                        }
                    }
                    catch {
                        $arhResult = @{
                            ExitCode  = 1
                            Duration  = 0
                            Exception = $_.Exception
                        }
                    }
                }
            }
            
            $fileEnd = Get-Date
            $fileDuration = [math]::Round(($fileEnd - $fileStart).TotalSeconds, 2)
            
            if ($arhResult.ExitCode -eq 0) {
                Write-Log "Успешно: $archiveName ($($arhResult.ArchiveSize) МБ, $($fileDuration) сек)" -Level SUCCESS -ResultKey
                $successCount++
                $results += [PSCustomObject]@{
                    SourceFile   = $sourceFileName
                    ArchivePath  = $archivePath
                    ArchiveSize  = $arhResult.ArchiveSize
                    Duration     = $fileDuration
                    Status       = 'Success'
                    ExitCode     = $arhResult.ExitCode
                }
            }
            else {
                $errorDesc = switch ($ArchiverType) {
                    'RAR' { Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode }
                    '7Z'  { Get-7zExitCodeMeaning -ExitCode $arhResult.ExitCode }
                    'ZIP' { 'Ошибка создания ZIP архива' }
                }
                # ✅ ИСПРАВЛЕНО: ${sourceFileName} вместо $sourceFileName:
                Write-Log "Ошибка архивации ${sourceFileName}: $errorDesc" -Level ERROR -ResultKey
                $errorCount++
                $results += [PSCustomObject]@{
                    SourceFile   = $sourceFileName
                    ArchivePath  = $archivePath
                    ArchiveSize  = 0
                    Duration     = $fileDuration
                    Status       = 'Error'
                    ExitCode     = $arhResult.ExitCode
                    ErrorMessage = $errorDesc
                }
            }
        }
        catch {
            $fileEnd = Get-Date
            $fileDuration = [math]::Round(($fileEnd - $fileStart).TotalSeconds, 2)
            # ✅ ИСПРАВЛЕНО: ${sourceFileName} вместо $sourceFileName:
            Write-Log "Критическая ошибка при архивации ${sourceFileName}: $($_.Exception.Message)" -Level ERROR -ResultKey
            $errorCount++
            $results += [PSCustomObject]@{
                SourceFile   = $sourceFileName
                ArchivePath  = $archivePath
                ArchiveSize  = 0
                Duration     = $fileDuration
                Status       = 'Error'
                ExitCode     = 255
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    Write-Log "Индивидуальная архивация завершена: Успешно=$successCount, Ошибки=$errorCount" -Level INFO -ResultKey
    
    return $results
}
}

<#
.SYNOPSIS
Архивирование отдельных подпапок по маске
.DESCRIPTION
Создаёт отдельный архив для каждой подпапки первого уровня в источнике.
Имя архива формируется из имени подпапки.
Поддерживает RAR, 7Z и ZIP архиваторы.
.PARAMETER ArchiverType
Тип архиватора: RAR, 7Z, ZIP
.PARAMETER ArchiverPath
Путь к исполняемому файлу архиватора
.PARAMETER SourcePath
Путь к исходной директории
.PARAMETER DestinationPath
Путь к директории назначения архивов
.PARAMETER FolderFilter
Маска для фильтрации подпапок (опционально, например: "20*")
.PARAMETER ArchivePattern
Шаблон имени архива: {PCName}, {JobName}, {SourceFolderName}
.PARAMETER Parameters
Параметры командной строки архиватора
.PARAMETER LogPath
Путь к файлу лога архиватора (опционально)
.PARAMETER PCName
Имя компьютера для подстановки в шаблон
.PARAMETER JobName
Имя задания для подстановки в шаблон
.OUTPUTS
[object[]] Коллекция результатов архивирования для каждой папки
.EXAMPLE
$result = Start-IndividualFolderArchive -ArchiverType "RAR" -ArchiverPath "C:\work\rar.exe" -SourcePath "C:\src\JOB3" -DestinationPath "C:\dst\JOB3" -ArchivePattern "{PCName}_{JobName}_{SourceFolderName}.rar" -Parameters @("a", "-m3", "-r") -PCName "SERVER01" -JobName "JOB3"
#>
function Start-IndividualFolderArchive {
[CmdletBinding()]
[OutputType([object[]])]
param(
    [Parameter(Mandatory = $true)][ValidateSet('RAR', '7Z', 'ZIP')][string]$ArchiverType,
    [Parameter(Mandatory = $true)][string]$ArchiverPath,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$ArchivePattern,
    [Parameter(Mandatory = $false)][string]$FolderFilter,
	[Parameter(Mandatory = $false)][string]$ExcludeFolderPattern,
    [Parameter(Mandatory = $false)][string[]]$Parameters,
    [Parameter(Mandatory = $false)][string]$LogPath,
    [Parameter(Mandatory = $false)][string]$PCName,
    [Parameter(Mandatory = $false)][string]$JobName
)
process {
    $results = @()
    $archiveExtension = switch ($ArchiverType) {
        'RAR' { '.rar' }
        '7Z'  { '.7z' }
        'ZIP' { '.zip' }
        default { '.rar' }
    }
    
    Write-Log "Поиск подпапок для индивидуальной архивации в: $SourcePath" -Level INFO -ResultKey
    
    # Получение списка подпапок первого уровня
    $folders = Get-ChildItem -Path $SourcePath -Directory -ErrorAction SilentlyContinue
    
    # Фильтрация по маске если указана
    if (-not [string]::IsNullOrWhiteSpace($FolderFilter)) {
        $folders = $folders | Where-Object { $_.Name -like $FolderFilter }
        Write-Log "Применён фильтр папок: $FolderFilter (найдено $($folders.Count))" -Level INFO
    }
        # === ИСКЛЮЧЕНИЕ ПАПОК (ВКЛЮЧАЯ "today") ===
        if (-not [string]::IsNullOrWhiteSpace($ExcludeFolderPattern)) {
            if ($ExcludeFolderPattern -eq 'today') {
                $todayDate = Get-Date -Format 'yyyyMMdd'
                $excludedFolders = $folders | Where-Object { $_.Name -eq $todayDate }
                if ($excludedFolders) {
                    Write-Log "Исключена папка с текущей датой: $todayDate" -Level INFO -ResultKey
                }
                $folders = $folders | Where-Object { $_.Name -ne $todayDate }
            }
            else {
                # Обычная маска для исключения
                $excludedCount = ($folders | Where-Object { $_.Name -like $ExcludeFolderPattern }).Count
                $folders = $folders | Where-Object { $_.Name -notlike $ExcludeFolderPattern }
                if ($excludedCount -gt 0) {
                    Write-Log "Исключено папок по маске '$ExcludeFolderPattern': $excludedCount" -Level INFO -ResultKey
                }
            }
        }
        # === /КОНЕЦ БЛОКА ИСКЛЮЧЕНИЯ today ===
		
    if ($folders.Count -eq 0) {
        Write-Log "Подпапки для архивации не найдены" -Level WARNING -ResultKey
        return $results
    }
    
    Write-Log "Найдено подпапок для архивации: $($folders.Count)" -Level INFO -ResultKey
    
    # Создание директории назначения если не существует
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    
    $successCount = 0
    $errorCount = 0
    
    foreach ($folder in $folders) {
        $folderStart = Get-Date
        $folderName = $folder.Name
        $folderPath = $folder.FullName
        
        # Формирование имени архива
        $archiveName = $ArchivePattern
        $archiveName = $archiveName -replace '{PCName}', $PCName
        $archiveName = $archiveName -replace '{JobName}', $JobName
        $archiveName = $archiveName -replace '{SourceFolderName}', $folderName
        
        # Удаление недопустимых символов из имени архива
        $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
        
        # Добавление расширения если отсутствует
        if ($archiveName -notmatch '\.(rar|7z|zip)$') {
            $archiveName = $archiveName + $archiveExtension
        }
        
        $archivePath = Join-Path -Path $DestinationPath -ChildPath $archiveName
        
        Write-Log "Архивация папки: ${folderName} -> $archiveName" -Level INFO
        
        try {
            $arhResult = $null
            
            switch ($ArchiverType) {
                'RAR' {
                    $arhResult = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $folderPath -Parameters $Parameters -LogPath $null
                }
                '7Z' {
                    $archiveType = [System.IO.Path]::GetExtension($archivePath).TrimStart('.')
                    $arhResult = Start-7zArchive -SevenZipPath $ArchiverPath -ArchivePath $archivePath -SourcePath $folderPath -ArchiveType $archiveType -Parameters $Parameters -LogPath $null
                }
                'ZIP' {
                    try {
                        Compress-Archive -Path (Join-Path $folderPath '*') -DestinationPath $archivePath -Force -ErrorAction Stop
                        $arhResult = @{
                            ExitCode    = 0
                            Duration    = 0
                            ArchiveSize = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
                        }
                    }
                    catch {
                        $arhResult = @{
                            ExitCode  = 1
                            Duration  = 0
                            Exception = $_.Exception
                        }
                    }
                }
            }
            
            $folderEnd = Get-Date
            $folderDuration = [math]::Round(($folderEnd - $folderStart).TotalSeconds, 2)
            
            if ($arhResult.ExitCode -eq 0) {
                Write-Log "Успешно: $archiveName ($($arhResult.ArchiveSize) МБ, $($folderDuration) сек)" -Level SUCCESS -ResultKey
                $successCount++
                $results += [PSCustomObject]@{
                    SourceFolder = $folderName
                    ArchivePath  = $archivePath
                    ArchiveSize  = $arhResult.ArchiveSize
                    Duration     = $folderDuration
                    Status       = 'Success'
                    ExitCode     = $arhResult.ExitCode
                }
            }
            else {
                $errorDesc = switch ($ArchiverType) {
                    'RAR' { Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode }
                    '7Z'  { Get-7zExitCodeMeaning -ExitCode $arhResult.ExitCode }
                    'ZIP' { 'Ошибка создания ZIP архива' }
                }
                Write-Log "Ошибка архивации ${folderName}: $errorDesc" -Level ERROR -ResultKey
                $errorCount++
                $results += [PSCustomObject]@{
                    SourceFolder = $folderName
                    ArchivePath  = $archivePath
                    ArchiveSize  = 0
                    Duration     = $folderDuration
                    Status       = 'Error'
                    ExitCode     = $arhResult.ExitCode
                    ErrorMessage = $errorDesc
                }
            }
        }
        catch {
            $folderEnd = Get-Date
            $folderDuration = [math]::Round(($folderEnd - $folderStart).TotalSeconds, 2)
            Write-Log "Критическая ошибка при архивации ${folderName}: $($_.Exception.Message)" -Level ERROR -ResultKey
            $errorCount++
            $results += [PSCustomObject]@{
                SourceFolder = $folderName
                ArchivePath  = $archivePath
                ArchiveSize  = 0
                Duration     = $folderDuration
                Status       = 'Error'
                ExitCode     = 255
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    Write-Log "Индивидуальная архивация папок завершена: Успешно=$successCount, Ошибки=$errorCount" -Level INFO -ResultKey
    
    return $results
}
}
#endregion /ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ АРХИВАЦИИ

# ==============================================================================
#region МОДУЛЬ ВЕРИФИКАЦИИ (Backup-Verification.psm1)
# ==============================================================================
<#
.SYNOPSIS
Нормализация относительного пути
.DESCRIPTION
Преобразует полный путь в относительный относительно корневой директории.
Удаляет общие префиксы путей для корректного сравнения.
.PARAMETER FullPath
Полный путь к файлу
.PARAMETER RootPath
Корневая директория
.OUTPUTS
[string] Относительный путь в нижнем регистре
.EXAMPLE
Get-CanonicalPath -FullPath "C:\Work\src\file.txt" -RootPath "C:\Work\src"
# Возвращает: "file.txt"
#>
function Get-CanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    process {
        # Нормализация разделителей
        $normalizedFull = $FullPath -replace '/', '\'
        $normalizedRoot = $RootPath -replace '/', '\'

        # Удаление завершающих слешей
        $normalizedFull = $normalizedFull.TrimEnd('\')
        $normalizedRoot = $normalizedRoot.TrimEnd('\')

        # Преобразование к нижнему регистру для сравнения
        $lowerFull = $normalizedFull.ToLowerInvariant()
        $lowerRoot = $normalizedRoot.ToLowerInvariant()

        # Удаление корневой части
        if ($lowerFull.StartsWith($lowerRoot)) {
            $relative = $normalizedFull.Substring($normalizedRoot.Length).TrimStart('\')
        }
        else {
            # Если путь не начинается с корня, используем как есть
            $relative = $normalizedFull
        }

        return $relative.ToLowerInvariant()
    }
}

<#
.SYNOPSIS
    Получение общего префикса путей
.DESCRIPTION
    Находит общую часть для набора путей.
.PARAMETER Paths
    Массив путей для анализа
.OUTPUTS
    [string] Общий префикс пути
#>
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

<#
.SYNOPSIS
    Получение списка файлов из директории
.DESCRIPTION
    Рекурсивно сканирует директорию и возвращает информацию о всех файлах.
    Исключает точки репарсинга (символические ссылки).
.PARAMETER Path
    Путь к директории для сканирования
.OUTPUTS
    [object[]] Коллекция объектов: RelativePath, Length, LastWriteTime, FullName
#>
function Get-FileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                    throw "Директория не существует: $_"
                }
                $true
            })]
        [string]$Path
    )

    begin {
        $rootPath = (Resolve-Path -LiteralPath $Path).Path
        if ($rootPath.EndsWith('\')) { $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) }
        Write-Verbose "Сканирование источника: $rootPath"
    }

    process {
        try {
            $items = Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) }

            foreach ($item in $items) {
                if (-not (Test-Path -LiteralPath $item.FullName -PathType Leaf)) { continue }

                $relative = Get-CanonicalPath -FullPath $item.FullName -RootPath $rootPath

                [PSCustomObject]@{
                    RelativePath  = $relative
                    Length        = $item.Length
                    LastWriteTime = $item.LastWriteTime
                    Source        = "FileSystem"
                    FullName      = $item.FullName
                }
            }
        }
        catch {
            Write-Error "Критическая ошибка при сканировании пути $Path : $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Фильтрация файлов по маске
.DESCRIPTION
    Возвращает файлы из директории, соответствующие указанной маске.
.PARAMETER Path
    Путь к директории
.PARAMETER Filter
    Маска файлов (например: ACQ*.* , ADV*.*)
.OUTPUTS
    [object[]] Отфильтрованная коллекция файлов
#>
function Get-FilterFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Filter
    )

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

<#
.SYNOPSIS
    Получение списка файлов из архива
.DESCRIPTION
    Универсальная функция для получения списка файлов из архива.
    Автоматически выбирает метод в зависимости от типа архиватора.
.PARAMETER ArchiverType
    Тип архиватора: RAR, 7Z, ZIP
.PARAMETER ArchiverPath
    Путь к исполняемому файлу архиватора
.PARAMETER ArchivePath
    Путь к архиву
.OUTPUTS
    [object[]] Коллекция объектов: RelativePath, Length, LastWriteTime
#>
function Get-FileArhList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchiverType,
        [Parameter(Mandatory = $true)][string]$ArchiverPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    Write-Verbose "Чтение содержимого архива: $ArchivePath (Тип: $ArchiverType)"

    switch ($ArchiverType) {
        "RAR" {
            return Get-FileArhListRar -RarPath $ArchiverPath -ArchivePath $ArchivePath
        }
        "7Z" {
            return Get-7zArchiveFileList -SevenZipPath $ArchiverPath -ArchivePath $ArchivePath
        }
        "ZIP" {
            # Для ZIP используем встроенные средства Windows
            try {
                $shell = New-Object -ComObject Shell.Application
                $zip = $shell.NameSpace($ArchivePath)
                $files = @()
                
                foreach ($item in $zip.Items()) {
                    if ($item.IsFolder) { continue }
                    
                    $files += [PSCustomObject]@{
                        RelativePath  = $item.Path
                        Length        = $item.Size
                        LastWriteTime = $item.Date
                        Source        = "Archive"
                    }
                }
                
                return $files
            }
            catch {
                Write-Error "Ошибка чтения ZIP архива: $($_.Exception.Message)"
                throw
            }
        }
        default {
            throw "Неподдерживаемый тип архиватора: $ArchiverType"
        }
    }
}

<#
.SYNOPSIS
    Получение списка файлов из RAR архива
.DESCRIPTION
    Запускает RAR.exe с командой 'vtb' для получения списка файлов.
    Парсит вывод и возвращает коллекцию объектов.
.PARAMETER RarPath
    Путь к RAR.exe
.PARAMETER ArchivePath
    Путь к архиву
.OUTPUTS
    [object[]] Коллекция объектов: RelativePath, Length, LastWriteTime
#>
function Get-FileArhListRar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$RarPath,
        [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ArchivePath
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
        $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(866)
        $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(866)

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

        if (-not $fileList) {
            $fileList = @()
        }

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

<#
.SYNOPSIS
    Парсинг вывода RAR
.DESCRIPTION
    Преобразует текстовый вывод RAR в коллекцию объектов файлов.
.PARAMETER RawOutput
    Сырой вывод от RAR.exe (строки или байты)
.OUTPUTS
    [object[]] Коллекция объектов: RelativePath, Length, LastWriteTime
#>
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
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*RAR\s+' -or $line -match '^\s*Copyright' -or $line -match '^\s*Registered') { continue }
        if ($line -match '^\s*Archive:' -or $line -match '^\s*Details:') { continue }

        if ($line -match '^\s+Name:\s*(.+)$') {
            if ($currentName -and $currentSize -and $currentDate) {
                $relativeName = ($currentName -replace '^\\+', '' -replace '/', '\').ToLowerInvariant()
                $files += [PSCustomObject]@{
                    RelativePath  = $relativeName
                    Length        = $currentSize
                    LastWriteTime = $currentDate
                    Source        = "Archive"
                }
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
        $files += [PSCustomObject]@{
            RelativePath  = $relativeName
            Length        = $currentSize
            LastWriteTime = $currentDate
            Source        = "Archive"
        }
    }

    return $files
}

<#
.SYNOPSIS
Сравнение файлов источника и архива с нормализацией символов
.DESCRIPTION
Сравнивает списки файлов, игнорируя разницу между визуально похожими символами (например, тире и дефис).
#>
function Compare-FilesSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$SourceList,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ArchiveList,
        [Parameter(Mandatory = $false)][string]$SourcePath
    )
    process {
        Write-Verbose "Начало сравнения: Источник ($($SourceList.Count)) vs Архив ($($ArchiveList.Count))"
        
        # Функция нормализации символов
        $NormalizeChars = {
            param([string]$Text)
            $res = $Text
            $res = $res -replace '[\u2013\u2014\u2015]', '-'   # Тире -> дефис
            $res = $res -replace '[\u201c\u201d\u00ab\u00bb]', '"' 
            $res = $res -replace '\u2026', '...'
            return $res
        }

        # Хеш-таблицы
        $sourceHash = @{}
        foreach ($item in $SourceList) {
            $key = & $NormalizeChars $item.RelativePath.ToLowerInvariant()
            if (-not $sourceHash.ContainsKey($key)) { $sourceHash[$key] = $item }
        }

        $archiveHash = @{}
        foreach ($item in $ArchiveList) {
            $path = $item.RelativePath
            $path = $path -replace '^[A-Z]:\\', '' -replace '^\\\\\?\\', ''
            $path = ($path -replace '/', '\').TrimStart('\').ToLowerInvariant()
            
            $item.RelativePath = $path
            
            $key = & $NormalizeChars $path
            if (-not $archiveHash.ContainsKey($key)) { $archiveHash[$key] = $item }
        }

        $missingInArchive = @()
        $sizeMismatch = @()
        $extraInArchive = @()
        $isIdentical = $true

        # 1. Проверка файлов источника
        foreach ($key in $sourceHash.Keys) {
            $srcItem = $sourceHash[$key]
            
            # ПРЯМОЙ ПОИСК
            if ($archiveHash.ContainsKey($key)) {
                $arhItem = $archiveHash[$key]
                if ($srcItem.Length -ne $arhItem.Length) {
                    $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                    $isIdentical = $false
                }
            }
            else {
                # УМНЫЙ ПОИСК (если прямой не удался)
                # Ищем в архиве путь, который ЗАКАНЧИВАЕТСЯ на наш относительный путь
                # Например: источник "file.txt", архив "folder\file.txt" -> Совпадение
                $foundKey = $archiveHash.Keys | Where-Object { $_.EndsWith("\$key") -or $_ -eq $key } | Select-Object -First 1
                
                if ($foundKey) {
                    $arhItem = $archiveHash[$foundKey]
                    if ($srcItem.Length -ne $arhItem.Length) {
                        $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                        $isIdentical = $false
                    }
                    # Помечаем, что этот файл архива уже обработан (удалять из extra не надо, но для логики это важно)
                    # Мы не удаляем из хеша, просто учитываем, что совпадение есть
                }
                else {
                    $missingInArchive += $srcItem
                    $isIdentical = $false
                }
            }
        }

        # 2. Поиск лишних файлов в архиве
        foreach ($key in $archiveHash.Keys) {
            # Проверяем прямое совпадение
            if ($sourceHash.ContainsKey($key)) { continue }
            
            # Проверяем умное совпадение (является ли этот архивный файл частью какого-то источника)
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

        # 3. Генерация отчета
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

        return [PSCustomObject]@{
            IsIdentical      = $isIdentical
            TotalSource      = $SourceList.Count
            TotalArchive     = $ArchiveList.Count
            MissingInArchive = $missingInArchive
            ExtraInArchive   = $extraInArchive
            SizeMismatch     = $sizeMismatch
            Report           = ($reportLines -join "`r`n")
        }
    }
}

#endregion /МОДУЛЬ ВЕРИФИКАЦИИ

# ==============================================================================
#region МОДУЛЬ РОТАЦИИ (Remove-OldFiles.psm1)
# ==============================================================================
<#
.SYNOPSIS
    Удаление старых файлов (ротация)
.DESCRIPTION
    Удаляет файлы старше указанного возраста, сохраняя минимальное количество.
    Используется для очистки старых архивов и логов.
.PARAMETER Path
    Путь к директории для очистки
.PARAMETER DaysOld
    Возраст файлов в днях для удаления (0 = без ограничения по возрасту)
.PARAMETER KeepCount
    Минимальное количество файлов для сохранения (0 = не сохранять)
.PARAMETER Filter
    Маска файлов для обработки (например: *.log, *.rar)
#>
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(0, 3650)][int]$DaysOld,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100000)][int]$KeepCount,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    Write-Log "Ротация файлов: $Path (DaysOld: $DaysOld, KeepCount: $KeepCount, Filter: $Filter)"

    if (-not (Test-Path -Path $Path -PathType Container)) {
        $errorMsg = "Директория $Path не существует"
        Write-Log $errorMsg
        throw $errorMsg
    }

    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending)

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
#endregion /МОДУЛЬ РОТАЦИИ

# ==============================================================================
#region МОДУЛЬ ОТПРАВКИ ПОЧТЫ (MailSender.psm1)
# ==============================================================================
<#
.SYNOPSIS
    Отправка email уведомления
.DESCRIPTION
    Отправляет email через SMTP сервер с анонимной аутентификацией.
.PARAMETER From
    Адрес отправителя
.PARAMETER To
    Адрес получателя (можно несколько через запятую)
.PARAMETER Subject
    Тема письма
.PARAMETER Body
    Текст письма
.OUTPUTS
    [bool] True если отправлено успешно
#>
function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SmtpServer,
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $Encoding = [System.Text.Encoding]::UTF8
    $BodyAsHtml = $false

    try {
        # ВАЖНО: Используем -ErrorAction Stop, чтобы ошибка попала в catch
        Send-MailMessage -From $From -To $To -Subject $Subject -Body $Body `
            -SmtpServer $SmtpServer -Encoding $Encoding -BodyAsHtml:$BodyAsHtml `
            -Credential (New-Object System.Management.Automation.PSCredential("NT AUTHORITY\ANONYMOUS LOGON", (New-Object System.Security.SecureString))) -ErrorAction Stop

        Write-Host "✓ Письмо отправлено: $Subject" -ForegroundColor Green
        return $true
    }
    catch {
        # Выводим полную информацию об ошибке
        $errorMsg = "Не удалось отправить письмо: $($_.Exception.Message)"
        Write-Host $errorMsg -ForegroundColor Red
        Write-Error "✗ Ошибка отправки почты: $($_.Exception.Message)"
        return $false
    }
}
#endregion /МОДУЛЬ ОТПРАВКИ ПОЧТЫ

# ==============================================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ КОНФИГУРАЦИИ
# ==============================================================================
<#
.SYNOPSIS
    Получение конфигурации резервного копирования
.DESCRIPTION
    Преобразует JSON конфигурацию в удобный для использования формат.
    Разрешает переменные в шаблонах имён архивов.
.PARAMETER LocalConfig
    Объект конфигурации (по умолчанию: $BackupConfig)
.OUTPUTS
    [hashtable] Settings, Jobs
#>
function Get-BackupConfiguration {
    param([Parameter(Mandatory = $false)][PSObject]$LocalConfig = $BackupConfig)

    $currentDate = Get-Date -Format 'yyyyMMdd'
    $currentTime = Get-Date -Format 'HHmmss'
    $resolvedJobs = @{}

    if (-not $LocalConfig.Jobs) {
        throw "В конфигурации не найдено раздела Jobs"
    }

    # Определение типа архиватора
    $archiverType = $LocalConfig.General.ArchiverType
    if ([string]::IsNullOrWhiteSpace($archiverType)) {
        $archiverType = "RAR"
    }
    $archiverType = $archiverType.ToUpper()

    foreach ($jobDef in $LocalConfig.Jobs) {
        $jobName = $jobDef.Name
        if ([string]::IsNullOrWhiteSpace($jobName)) { continue }

        $job = @{}
        $jobDef.PSObject.Properties | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_.Name)) {
                $job[$_.Name] = $_.Value
            }
        }

        # Определение расширения архива
        $archiveExtension = switch ($archiverType) {
            "RAR" { ".rar" }
            "7Z" { ".7z" }
            "ZIP" { ".zip" }
            default { ".rar" }
        }

        # Разрешение переменных в шаблоне имени архива
        if ($job.ArchivePattern) {
            $job.Archive = $job.ArchivePattern -replace '{PCName}', $PCName
            $job.Archive = $job.Archive -replace '{JobName}', $jobName
            $job.Archive = $job.Archive -replace '{Date}', $currentDate
            $job.Archive = $job.Archive -replace '{Time}', $currentTime
            $job.Archive = $job.Archive -replace '{Date_Time}', "${currentDate}_${currentTime}"
            # Замена расширения если указано в паттерне
            if ($job.Archive -notmatch '\.(rar|7z|zip)$') {
                $job.Archive = $job.Archive -replace '\.[^.]*$', $archiveExtension
            }
        }
        else {
            $job.Archive = "${PCName}_${jobName}_${currentDate}${archiveExtension}"
        }

        $resolvedJobs[$jobName] = $job
    }

    # Получение пути к архиватору
    $archiverPathValue = $null
    switch ($archiverType) {
        "RAR" {
            if ($LocalConfig.PSObject.Properties.Name -contains 'Paths') {
                if ($LocalConfig.Paths.PSObject.Properties.Name -contains 'RarPath') {
                    $archiverPathValue = $LocalConfig.Paths.RarPath
                }
            }
        }
        "7Z" {
            if ($LocalConfig.PSObject.Properties.Name -contains 'Paths') {
                if ($LocalConfig.Paths.PSObject.Properties.Name -contains 'SevenZipPath') {
                    $archiverPathValue = $LocalConfig.Paths.SevenZipPath
                }
            }
        }
        "ZIP" {
            $archiverPathValue = "builtin"
        }
    }

    if ([string]::IsNullOrWhiteSpace($archiverPathValue)) {
        throw "КРИТИЧЕСКАЯ ОШИБКА КОНФИГУРАЦИИ: Не найден архиватор ($archiverType) в разделе Paths"
    }

    $logPathValue = $LocalConfig.Paths.LogPathRoot
    if ([string]::IsNullOrWhiteSpace($logPathValue)) {
        $logPathValue = "C:\work\$ParentJobName\logs"
        Write-Warning "LogPathRoot не найден, используется значение по умолчанию: $logPathValue"
    }

    # Параметры по умолчанию для архиватора
    $defaultParams = $LocalConfig.General.DefaultRarParameters
    if ($archiverType -eq "7Z" -and $LocalConfig.General.Default7zParameters) {
        $defaultParams = $LocalConfig.General.Default7zParameters
    }

    $settings = @{
        PCName         = $PCName
        JobName        = $ParentJobName # Имя родительского задания (для лога и темы письма) 
        LogPath        = $logPathValue
        ArchiverType   = $archiverType
        ArchiverPath   = $archiverPathValue
        ArchiverParams = $defaultParams
        AdminIS        = $AdminIS
        AdminOS        = $AdminOS
    }

    return @{
        Settings = $settings
        Jobs     = $resolvedJobs
    }
}
<#
.SYNOPSIS
    Тестирование конфигурации
.DESCRIPTION
    Проверяет доступность архиватора и источников данных.
.OUTPUTS
    [hashtable] IsValid, Errors
#>
function Test-Configuration {
    param()

    $config = Get-BackupConfiguration
    $errors = @()

    # Проверка архиватора
    if ($config.Settings.ArchiverType -ne "ZIP") {
        if (-not (Test-Path $config.Settings.ArchiverPath)) {
            $errors += "Архиватор не найден: $($config.Settings.ArchiverPath)"
        }
    }

    # Проверка заданий
    foreach ($jobName in $config.Jobs.Keys) {
        $job = $config.Jobs[$jobName]
        if (-not (Test-Path $job.Source)) {
            $errors += "Источник не существует ($jobName): $($job.Source)"
        }
        if (-not $job.LocalDest) {
            $errors += "Не указан локальный путь назначения ($jobName)"
        }
    }

    return @{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors
    }
}

<#
.SYNOPSIS
    Отчёт о свободном месте на дисках
.DESCRIPTION
    Получает информацию о логических дисках: общий размер, свободное место.
.PARAMETER ComputerName
    Имя компьютера (по умолчанию: локальный)
.OUTPUTS
    [string] Текст отчёта о дисках
#>
function Get-DiskSpaceReport {
    [OutputType([string])]
    param([string]$ComputerName = $env:COMPUTERNAME)
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $ComputerName -ErrorAction Stop |
        Where-Object { $_.Size -gt 1GB } | Sort-Object DeviceID |
        ForEach-Object {
            [PSCustomObject]@{
                DeviceID    = $_.DeviceID
                SizeGB      = [math]::Round($_.Size / 1GB, 1)
                FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
                FreePercent = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            }
        }

        if (-not $disks) { return "Нет дисков > 1 ГБ" }

        $diskStrings = foreach ($disk in $disks) {
            "Диск {0} Всего(ГБ)={1:N1} Свободно(ГБ)={2:N1} Свободно={3:N1}%" -f $disk.DeviceID, $disk.SizeGB, $disk.FreeGB, $disk.FreePercent
        }
        return ($diskStrings -join " ; ")
    }
    catch { return "Ошибка дисков: $($_.Exception.Message)" }
}

<#
.SYNOPSIS
    Форматирование размера файла
.DESCRIPTION
    Возвращает человекочитаемый размер файла (байты, КБ, МБ, ГБ).
.PARAMETER Path
    Путь к файлу
.OUTPUTS
    [string] Форматированный размер
#>
function Format-FileSize {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Path)
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
#endregion /ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ КОНФИГУРАЦИИ

# ==============================================================================
#region ЭТАП 2: ОСНОВНОЙ ЗАПУСК
# ==============================================================================
$scriptStartTime = Get-Date
$config = Get-BackupConfiguration

# ==============================================================================
# region РЕЖИМ ТЕСТИРОВАНИЯ КОНФИГУРАЦИИ
# ==============================================================================
if ($TestMode) {
    Write-Host "`n=== РЕЖИМ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    Write-Host "Проверка конфигурации без выполнения резервного копирования`n" -ForegroundColor Cyan
    
    $testErrors = @()
    $testWarnings = @()
    
    # 1. Проверка архиватора
    Write-Host "[1/5] Проверка архиватора..." -NoNewline
    if ($config.Settings.ArchiverType -ne "ZIP") {
        if (Test-Path $config.Settings.ArchiverPath) {
            Write-Host " OK" -ForegroundColor Green
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $testErrors += "Архиватор не найден: $($config.Settings.ArchiverPath)"
        }
    }
    else {
        Write-Host " OK (ZIP встроенный)" -ForegroundColor Green
    }
    
    # 2. Проверка источников
    Write-Host "[2/5] Проверка источников данных..." -NoNewline
    $sourceCheck = $true
    foreach ($jobName in $config.Jobs.Keys) {
        $job = $config.Jobs[$jobName]
        if (-not (Test-Path $job.Source)) {
            $testErrors += "Источник не доступен [$jobName]: $($job.Source)"
            $sourceCheck = $false
        }
    }
    if ($sourceCheck) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " FAIL" -ForegroundColor Red }
    
    # 3. Проверка локальных назначений (права на запись)
    Write-Host "[3/5] Проверка прав записи (LocalDest)..." -NoNewline
    $destCheck = $true
    foreach ($jobName in $config.Jobs.Keys) {
        $job = $config.Jobs[$jobName]
        try {
            if (-not (Test-Path $job.LocalDest)) {
                New-Item -Path $job.LocalDest -ItemType Directory -Force -ErrorAction Stop | Remove-Item -Force
            }
        }
        catch {
            $testErrors += "Нет прав на запись [$jobName]: $($job.LocalDest)"
            $destCheck = $false
        }
    }
    if ($destCheck) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " FAIL" -ForegroundColor Red }
    
    # 4. Проверка SMTP
    Write-Host "[4/5] Проверка настроек SMTP..." -NoNewline
    if ([string]::IsNullOrWhiteSpace($SmtpServer)) {
        Write-Host " FAIL" -ForegroundColor Red
        $testErrors += "SMTP сервер не настроен"
    }
    else {
        Write-Host " OK ($SmtpServer)" -ForegroundColor Green
    }
    
    # 5. Проверка получателей
    Write-Host "[5/5] Проверка получателей почты..." -NoNewline
    if ([string]::IsNullOrWhiteSpace($AdminMail)) {
        Write-Host " WARNING" -ForegroundColor Yellow
        $testWarnings += "AdminMail не настроен в конфигурации"
    }
    else {
        Write-Host " OK ($AdminMail)" -ForegroundColor Green
    }
    
    # ИТОГИ ТЕСТА
    Write-Host "`n=== РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ ===" -ForegroundColor Cyan
    $totalDuration = [math]::Round(((Get-Date) - $scriptStartTime).TotalSeconds, 2)
    Write-Host "Время проверки: $totalDuration сек"
    Write-Host "Заданий проверено: $($config.Jobs.Count)"
    Write-Host "Ошибок: $($testErrors.Count)"
    Write-Host "Предупреждений: $($testWarnings.Count)"
    
    # ФОРМИРОВАНИЕ ОТЧЕТА
    $ReportBody = @"
РЕЖИМ: ТЕСТОВОЕ ЗАПУСК (Backup не выполнялся)
КОМПЬЮТЕР: $PCName
ЗАДАНИЕ: $ParentJobName
ВРЕМЯ: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

ПРОВЕРКИ:
- Архиватор: $(if ($config.Settings.ArchiverType -ne "ZIP" -and (Test-Path $config.Settings.ArchiverPath)) { "OK" } else { "OK (ZIP)" })
- Источники: $(if ($sourceCheck) { "OK" } else { "FAIL" })
- Назначения: $(if ($destCheck) { "OK" } else { "FAIL" })
- SMTP: $(if (-not [string]::IsNullOrWhiteSpace($SmtpServer)) { "OK" } else { "FAIL" })

"@
    
    if ($testErrors.Count -gt 0) {
        $ReportBody += "`nОШИБКИ:`n" + ($testErrors -join "`n")
    }
    if ($testWarnings.Count -gt 0) {
        $ReportBody += "`nПРЕДУПРЕЖДЕНИЯ:`n" + ($testWarnings -join "`n")
    }
    
    # ОТПРАВКА ПИСЬМА
    if ([string]::IsNullOrWhiteSpace($SmtpServer)) {
        Write-Host "`nSMTP не настроен. Письмо не отправлено." -ForegroundColor Yellow
    }
    elseif ([string]::IsNullOrWhiteSpace($AdminMail)) {
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
    
    # ЗАВЕРШЕНИЕ
    Write-Host "`nТестирование завершено." -ForegroundColor Cyan
    if ($testErrors.Count -gt 0) { exit 1 } else { exit 0 }
}
# ==============================================================================
# endregion РЕЖИМ ТЕСТИРОВАНИЯ КОНФИГУРАЦИИ
# ==============================================================================

try {
    Initialize-Logging -LogPath $config.Settings.LogPath -PCName $config.Settings.PCName -JobName $config.Settings.JobName
}
catch {
    Write-Host "Ошибка инициализации логирования: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-LogSection "ЗАПУСК СКРИПТА РЕЗЕРВНОГО КОПИРОВАНИЯ" -ResultKey
Write-Log "Компьютер: $($config.Settings.PCName)" -ResultKey
Write-Log "Время запуска: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ResultKey
Write-Log "Количество заданий: $($config.Jobs.Count)" -ResultKey
Write-Log "Конфигурация загружена из: $Script:ConfigPath" -ResultKey
Write-Log "Автономная версия (все модули встроены)." -Level SUCCESS -ResultKey
Write-Log "Тип архиватора: $($config.Settings.ArchiverType)" -ResultKey

$configTest = Test-Configuration
if (-not $configTest.IsValid) {
    Write-Log "Ошибки в конфигурации:`n$($configTest.Errors -join "`n")" -Level ERROR
    exit 1
}

$results = @{}
$successCount = 0
$errorCount = 0

Write-WinEventAppLog -StatusKey "Start" -MessageText "Начало работы скрипта: $ParentJobName"

foreach ($jobName in $config.Jobs.Keys) {
    $job = $config.Jobs[$jobName]
    $jobStart = Get-Date

    Write-LogSection "ОБРАБОТКА ЗАДАНИЯ: $($jobName)" -ResultKey
    Write-Log "Источник: $($job.Source)" -ResultKey
    Write-Log "Локальное назначение: $($job.LocalDest)"
    Write-Log "Сетевое назначение: $($job.RemoteDest)"
    Write-Log "Имя архива: $($job.Archive)"

    try {
        if (-not (Test-Path $job.Source)) {
            Write-Log "Источник не существует: $($job.Source)" -Level ERROR
            throw "Источник не существует"
        }

        # Создание каталога локального назначения если отсутствует
        if (-not (Test-Path $job.LocalDest)) {
            New-Item -Path $job.LocalDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан каталог локального назначения: $($job.LocalDest)" -Level INFO
        }

        # Создание каталога удаленного назначения если отсутствует (не источник!)
        if ($job.RemoteDest -and (-not (Test-Path $job.RemoteDest))) {
            New-Item -Path $job.RemoteDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создан каталог удаленного назначения: $($job.RemoteDest)" -Level INFO
        }

        $fileInfo = Get-FileInfoDetails -Path $job.Source
        Write-Log "Найдено файлов: $($fileInfo.FileCount)" -ResultKey
        $SourceFilesSize = if ($fileInfo.TotalSizeBytes -lt 1MB) { "{0:N0} Bytes" -f $fileInfo.TotalSizeBytes } else { "{0:N1} MB" -f $fileInfo.TotalSizeMB }
        Write-Log "Общий размер: $SourceFilesSize" -ResultKey
        
        # === БЛОК: Проверка файлов по маскам (SourceCheckMasks) ===
        # ИСПРАВЛЕНО: Используем ContainsKey для Hashtable
        if ($job.ContainsKey('SourceCheckMasks') -and $job.SourceCheckMasks) {
            Write-Log "Проверка наличия файлов по маскам..." -Level INFO
            
            foreach ($mask in $job.SourceCheckMasks) {
                try {
                    # Вызываем функцию фильтрации
                    $filteredFiles = Get-FilterFileList -Path $job.Source -Filter $mask
                    
                    if ($filteredFiles.Count -eq 0) {
                        # Если файлов нет - это ошибка (согласно требованию)
                        Write-Log "ОШИБКА МАСКИ: Файлы по маске '$mask' не найдены!" -Level ERROR -ResultKey
                    }
                    else {
                        # Если файлы есть - записываем информацию
                        Write-Log "Маска '$mask': найдено $($filteredFiles.Count) шт." -ResultKey
                    }
                }
                catch {
                    Write-Log "Ошибка при проверке маски '$mask': $($_.Exception.Message)" -Level ERROR -ResultKey
                }
            }
        }
        # === КОНЕЦ БЛОКА БЛОК: Проверка файлов по маскам (SourceCheckMasks) ===

        # === БЛОК: Формирование списка файлов источника (TXT или CSV) ===
        # Проверяем наличие параметра и его значение
        $listFlag = $job.ListSourceFlag
        if (-not [string]::IsNullOrWhiteSpace($listFlag)) {
            $listType = $listFlag.ToLower()
            
            if ($listType -in @("txt", "csv")) {
                Write-Log "Формирование списка файлов ($($listType.ToUpper()))..."
                
                try {
                    # 1. Получаем список файлов источника
                    $sourceFilesList = Get-FileList -Path $job.Source
                    
                    # 2. Формируем имя файла: ИмяАрхива + расширение списка
                    # Например: PC_JOB1_2026.rar -> PC_JOB1_2026.txt
                    $listFileName = [System.IO.Path]::ChangeExtension($job.Archive, ".$listType")
                    
                    # Полный путь к файлу списка (в папке логов)
                    $listFilePath = Join-Path -Path $config.Settings.LogPath -ChildPath $listFileName
                    
                    # 3. Сохранение в нужном формате
                    if ($listType -eq "csv") {
                        # CSV (разделитель ";" для корректного открытия в русском Excel)
                        $sourceFilesList | Select-Object RelativePath, Length, LastWriteTime | 
                        Export-Csv -Path $listFilePath -NoTypeInformation -Encoding UTF8 -Delimiter ";"
                    }
                    else {
                        # TXT (форматированная таблица для чтения)
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
        # === КОНЕЦ БЛОКА БЛОК: Формирование списка файлов источника (TXT или CSV) ===

        #region
        # === БЛОК: Индивидуальная архивация файлов ===
        $archiveIndividual = $false
        if ($job.ContainsKey('ArchiveIndividualFiles')) {
            $archiveIndividual = [System.Convert]::ToBoolean($job.ArchiveIndividualFiles)
        }

        if ($archiveIndividual) {
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ФАЙЛОВ" -ResultKey
            Write-Log "Режим: Каждый файл в отдельный архив" -ResultKey
            
            # Проверка обязательных параметров
            if ([string]::IsNullOrWhiteSpace($job.SourceFilter)) {
                Write-Log "ОШИБКА: Для индивидуальной архивации требуется параметр SourceFilter" -Level ERROR -ResultKey
                throw "Для индивидуальной архивации требуется параметр SourceFilter"
            }
            
            # Определение параметров архивации
            $archiverParams = if ($job.ArhParameters) { $job.ArhParameters } else { $config.Settings.ArchiverParams }
            
            # Формирование шаблона имени архива
            $individualArchivePattern = "{PCName}_{JobName}_{SourceFileName}.rar"
            if ($job.ContainsKey('IndividualArchivePattern') -and -not [string]::IsNullOrWhiteSpace($job.IndividualArchivePattern)) {
                $individualArchivePattern = $job.IndividualArchivePattern
            }
            
            # Запуск индивидуальной архивации
            $individualResults = Start-IndividualFileArchive `
                -ArchiverType $config.Settings.ArchiverType `
                -ArchiverPath $config.Settings.ArchiverPath `
                -SourcePath $job.Source `
                -DestinationPath $job.LocalDest `
                -FileFilter $job.SourceFilter `
                -ArchivePattern $individualArchivePattern `
                -Parameters $archiverParams `
                -PCName $config.Settings.PCName `
                -JobName $jobName `
                -LogPath $(if ($job.ArhLog) { Join-Path $job.LocalDest "individual_archiver.log" } else { $null })
            
            # Обработка результатов
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
            
            # Копирование в сеть (если включено)
            if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
                Write-Log "Копирование архивов в сетевое хранилище..." -Level INFO
                
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -eq 'Success' -and (Test-Path $archiveResult.ArchivePath)) {
                        $remotePath = Join-Path $job.RemoteDest (Split-Path $archiveResult.ArchivePath -Leaf)
                        try {
                            $copyResult = Copy-BackupFile -SourcePath $archiveResult.ArchivePath -DestinationPath $remotePath
                            if ($copyResult.Success) {
                                Write-Log "Копирование успешно: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level SUCCESS
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
                
                # Ротация удалённого хранилища
                if ($job.RemoveRemoteDestFlag) {
                    Write-Log "Ротация удалённого хранилища..." -Level INFO
                    try {
                        Remove-OldFiles -Path $job.RemoteDest -DaysOld $job.RemoteDestDaysOld -KeepCount $job.RemoteDestKeepCount -Filter "*.*"
                    }
                    catch {
                        Write-Log "Ошибка ротации удалённого хранилища: $_" -Level WARNING
                    }
                }
            }
            
            # Ротация источника (если включено)
            if ($job.RemoveSourceFlag) {
                Write-Log "Ротация источника..." -Level INFO
                try {
                    Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount $job.SourceKeepCount -Filter $job.SourceFilter
                }
                catch {
                    Write-Log "Ошибка ротации источника: $_" -Level WARNING
                }
            }
            
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ЗАВЕРШЕНА" -ResultKey
            
            # Пропускаем стандартную архивацию для этого задания
            continue
        }
        # === КОНЕЦ БЛОКА: Индивидуальная архивация файлов ===
        #endregion
        
		#region
		# === БЛОК: Индивидуальная архивация подпапок ===
        $archiveIndividualFolders = $false
        if ($job.ContainsKey('ArchiveIndividualFolders')) {
            $archiveIndividualFolders = [System.Convert]::ToBoolean($job.ArchiveIndividualFolders)
        }

        if ($archiveIndividualFolders) {
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ПОДПАПОК" -ResultKey
            Write-Log "Режим: Каждая подпапка в отдельный архив" -ResultKey
            
            # Определение параметров архивации
            $archiverParams = if ($job.ArhParameters) { $job.ArhParameters } else { $config.Settings.ArchiverParams }
            
            # Формирование шаблона имени архива
            $individualArchivePattern = "{PCName}_{JobName}_{SourceFolderName}.rar"
            if ($job.ContainsKey('IndividualArchivePattern') -and -not [string]::IsNullOrWhiteSpace($job.IndividualArchivePattern)) {
                $individualArchivePattern = $job.IndividualArchivePattern
            }
            
            # Получение фильтра папок (опционально)
            $folderFilter = if ($job.ContainsKey('SourceFilter') -and -not [string]::IsNullOrWhiteSpace($job.SourceFilter)) {
                $job.SourceFilter
            }
            else {
                $null
            }
            
			# ПОЛУЧЕНИЕ ПАРАМЕТРА ExcludeFolderPattern
			$excludeFolderPattern = if ($job.ContainsKey('ExcludeFolderPattern') -and -not [string]::IsNullOrWhiteSpace($job.ExcludeFolderPattern)) {
				$job.ExcludeFolderPattern
			}
			else {
				$null
			}
    
			
            # Запуск индивидуальной архивации подпапок
            $individualResults = Start-IndividualFolderArchive `
                -ArchiverType $config.Settings.ArchiverType `
                -ArchiverPath $config.Settings.ArchiverPath `
                -SourcePath $job.Source `
                -DestinationPath $job.LocalDest `
                -ArchivePattern $individualArchivePattern `
                -FolderFilter $folderFilter `
				-ExcludeFolderPattern $excludeFolderPattern `
                -Parameters $archiverParams `
                -PCName $config.Settings.PCName `
                -JobName $jobName `
                -LogPath $(if ($job.ArhLog) { Join-Path $job.LocalDest "folder_archiver.log" } else { $null })
            
            # Обработка результатов
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
            
            # Копирование в сеть (если включено)
            if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
                Write-Log "Копирование архивов в сетевое хранилище..." -Level INFO
                
                foreach ($archiveResult in $individualResults) {
                    if ($archiveResult.Status -eq 'Success' -and (Test-Path $archiveResult.ArchivePath)) {
                        $remotePath = Join-Path $job.RemoteDest (Split-Path $archiveResult.ArchivePath -Leaf)
                        try {
                            $copyResult = Copy-BackupFile -SourcePath $archiveResult.ArchivePath -DestinationPath $remotePath
                            if ($copyResult.Success) {
                                Write-Log "Копирование успешно: $(Split-Path $archiveResult.ArchivePath -Leaf)" -Level SUCCESS
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
                
                # Ротация удалённого хранилища
                if ($job.RemoveRemoteDestFlag) {
                    Write-Log "Ротация удалённого хранилища..." -Level INFO
                    try {
                        Remove-OldFiles -Path $job.RemoteDest -DaysOld $job.RemoteDestDaysOld -KeepCount $job.RemoteDestKeepCount -Filter "*.*"
                    }
                    catch {
                        Write-Log "Ошибка ротации удалённого хранилища: $_" -Level WARNING
                    }
                }
            }
            
            # Ротация локального хранилища
            Write-Log "Ротация локального хранилища..." -Level INFO
            try {
                Remove-OldFiles -Path $job.LocalDest -DaysOld $job.LocalDestDaysOld -KeepCount $job.LocalDestKeepCount -Filter "*.*"
            }
            catch {
                Write-Log "Ошибка ротации локального хранилища: $_" -Level WARNING
            }
            
            # Ротация источника (если включено)
            if ($job.RemoveSourceFlag) {
                Write-Log "Ротация источника..." -Level INFO
                try {
                    # Удаляем только заархивированные папки
                    foreach ($archiveResult in $individualResults) {
                        if ($archiveResult.Status -eq 'Success') {
                            $folderPath = Join-Path $job.Source $archiveResult.SourceFolder
                            if (Test-Path $folderPath) {
                                Remove-Item -Path $folderPath -Recurse -Force
                                Write-Log "Удалена папка источника: $($archiveResult.SourceFolder)" -Level INFO
                            }
                        }
                    }
                }
                catch {
                    Write-Log "Ошибка ротации источника: $_" -Level WARNING
                }
            }
            
            Write-LogSection "ИНДИВИДУАЛЬНАЯ АРХИВАЦИЯ ПОДПАПОК ЗАВЕРШЕНА" -ResultKey
            
            # Пропускаем стандартную архивацию для этого задания
            continue
        }
        # === КОНЕЦ БЛОКА: Индивидуальная архивация подпапок ===
        #endregion

        $archivePath = Join-Path $job.LocalDest $job.Archive

        # Определение параметров архивации
        $archiverParams = if ($job.ArhParameters) { $job.ArhParameters } else { $config.Settings.ArchiverParams }
        
        # Определение типа архива из имени файла
        $archiveType = [System.IO.Path]::GetExtension($archivePath).TrimStart('.')
        if ([string]::IsNullOrEmpty($archiveType)) {
            $archiveType = switch ($config.Settings.ArchiverType) {
                "RAR" { "rar" }
                "7Z" { "7z" }
                "ZIP" { "zip" }
            }
        }

        # Лог архиватора
        $ArhLogPath = $null
        if ($job.ArhLog) {
            $archiveDir = Split-Path -Path $archivePath -Parent
            $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($archivePath)
            $ArhLogPath = Join-Path -Path $archiveDir -ChildPath "${archiveName}_archiver.log"
        }

        Write-Log "Начало архивации (Тип: $archiveType)..." -ResultKey
        
        # Получение фильтра SourceFilter из конфигурации (если указан)
        $sourceFilter = if ($job.ContainsKey('SourceFilter') -and -not [string]::IsNullOrWhiteSpace($job.SourceFilter)) {
            $job.SourceFilter
        }
        else {
            $null
        }
        
        # Архивация в зависимости от типа архиватора
        $arhResult = $null
        switch ($config.Settings.ArchiverType) {
            "RAR" {
                $arhResult = Start-RarArchive -RarPath $config.Settings.ArchiverPath -ArchivePath $archivePath -SourcePath $job.Source -Parameters $archiverParams -LogPath $ArhLogPath -SourceFilter $sourceFilter
            }
            "7Z" {
                $arhResult = Start-7zArchive -SevenZipPath $config.Settings.ArchiverPath -ArchivePath $archivePath -SourcePath $job.Source -ArchiveType $archiveType -Parameters $archiverParams -LogPath $ArhLogPath -SourceFilter $sourceFilter
            }
            "ZIP" {
                # Используем встроенные средства Windows для ZIP
                try {
                    $zipSourcePath = if ($sourceFilter) {
                        Join-Path $job.Source $sourceFilter
                    }
                    else {
                        Join-Path $job.Source '*'
                    }
                    Compress-Archive -Path $zipSourcePath -DestinationPath $archivePath -Force -ErrorAction Stop
                    $arhResult = @{
                        ExitCode    = 0
                        Duration    = 0
                        ArchiveSize = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
                    }
                }
                catch {
                    $arhResult = @{
                        ExitCode  = 1
                        Duration  = 0
                        Exception = $_.Exception
                    }
                }
            }
        }

        Write-Log "Архивация завершена за $($arhResult.Duration) мин. Код: $($arhResult.ExitCode)" -ResultKey

        if ($arhResult.ExitCode -ne 0) {
            $errorDesc = switch ($config.Settings.ArchiverType) {
                "RAR" { Get-RarExitCodeMeaning -ExitCode $arhResult.ExitCode }
                "7Z" { Get-7zExitCodeMeaning -ExitCode $arhResult.ExitCode }
                "ZIP" { "Ошибка создания ZIP архива" }
            }
            Write-Log "Ошибка архиватора: $errorDesc" -Level ERROR
            if ($ArhLogPath -and (Test-Path $ArhLogPath)) {
                $logContent = Get-Content -Path $ArhLogPath -Raw
                Write-Log "Лог архиватора:`n$logContent" -Level ERROR
            }
            throw "Ошибка архиватора: $errorDesc"
        }

        if (-not (Test-Path $archivePath)) { throw "Архив не создан" }

        Write-Log "Архив создан: $(Format-FileSize -Path $archivePath)" -ResultKey

        # Проверка целостности архива
        $testResult = $null
        switch ($config.Settings.ArchiverType) {
            "RAR" {
                $testResult = Test-RarArchive -RarPath $config.Settings.ArchiverPath -ArchivePath $archivePath
            }
            "7Z" {
                $testResult = Test-7zArchive -SevenZipPath $config.Settings.ArchiverPath -ArchivePath $archivePath
            }
            "ZIP" {
                # Для ZIP проверяем через встроенные средства
                try {
                    $shell = New-Object -ComObject Shell.Application
                    $zip = $shell.NameSpace($archivePath)
                    $testResult = @{
                        IsValid  = ($null -ne $zip)
                        ExitCode = (if ($zip) { 0 } else { 1 })
                    }
                }
                catch {
                    $testResult = @{ IsValid = $false; ExitCode = 1 }
                }
            }
        }
        
        if (-not $testResult.IsValid) { throw "Ошибка проверки целостности архива" }

        # ВЕРИФИКАЦИЯ ЦЕЛОСТНОСТИ АРХИВА
        try {
            # Получение фильтра SourceFilter из конфигурации (если указан)
            $sourceFilter = if ($job.ContainsKey('SourceFilter') -and -not [string]::IsNullOrWhiteSpace($job.SourceFilter)) {
                $job.SourceFilter
            }
            else {
                $null
            }

            # Если указан SourceFilter, верифицируем только файлы по маске
            if ($sourceFilter) {
                Write-Log "ВЕРИФИКАЦИЯ по маске SourceFilter: $sourceFilter" -ResultKey
                $sourceFiles = Get-FilterFileList -Path $job.Source -Filter $sourceFilter
            }
            else {
                Write-Log "ВЕРИФИКАЦИЯ всех файлов источника" -ResultKey
                $sourceFiles = Get-FileList -Path $job.Source
            }

            $archiveFiles = Get-FileArhList -ArchiverType $config.Settings.ArchiverType -ArchiverPath $config.Settings.ArchiverPath -ArchivePath $archivePath

            if (-not $archiveFiles -or $archiveFiles.Count -eq 0) {
                Write-Log "Архив пуст или не содержит файлов!" -Level ERROR
                throw "Архив пуст или не содержит файлов"
            }

            $verifyResult = Compare-FilesSourceArchive -SourceList $sourceFiles -ArchiveList $archiveFiles -SourcePath $job.Source

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

        #Write-LogSection "ВЕРИФИКАЦИЯ ЗАВЕРШЕНА" -ResultKey

        # Копирование в сеть
        if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            $remotePath = Join-Path $job.RemoteDest $job.Archive
            Write-Log "Старт копирование из $archivePath в $remotePath"
            $copyResult = Copy-BackupFile -SourcePath $archivePath -DestinationPath $remotePath

            if ($copyResult.Success) {
                Write-Log "Копирование успешно." -ResultKey
                Remove-OldFiles -Path $job.LocalDest -DaysOld $job.LocalDestDaysOld -KeepCount $job.LocalDestKeepCount -Filter "*.*"
                $results[$jobName] = "Успешно скопировано из $archivePath в  $remotePath "
                $successCount++
            }
            else { throw "Контрольная сумма при копировании не совпадает" }
        }
        else {
            $remotePath = Join-Path $job.RemoteDest $job.Archive
            Write-Log " $remotePath недоступен, сохранено локально." -Level WARNING
            $results[$jobName] = "ВНИМАНИЕ $archivePath сохранен только ЛОКАЛЬНО - Скопировать в Ручную!!! "
            $errorCount++
        }

        # Ротация источника (если включено в конфигурации)
        if ($job.RemoveSourceFlag) {
            Write-Log "Ротация источника: $($job.Source) (DaysOld: $($job.SourceDaysOld), KeepCount: $($job.SourceKeepCount))"
            try {
                Remove-OldFiles -Path $job.Source -DaysOld $job.SourceDaysOld -KeepCount $job.SourceKeepCount -Filter $job.SourceFilter
            }
            catch { Write-Log "Ошибка ротации источника: $_" -Level WARNING }
        }

        # Ротация удаленного хранилища (если включено в конфигурации)
        if ($job.RemoveRemoteDestFlag -and $job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            Write-Log "Ротация удаленного хранилища: $($job.RemoteDest) (DaysOld: $($job.RemoteDestDaysOld), KeepCount: $($job.RemoteDestKeepCount))"
            try {
                Remove-OldFiles -Path $job.RemoteDest -DaysOld $job.RemoteDestDaysOld -KeepCount $job.RemoteDestKeepCount -Filter "*.*"
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
}

# Очистка логов
Write-LogSection "ОЧИСТКА СТАРЫХ ЛОГОВ"
try {
    Remove-OldFiles -Path $config.Settings.LogPath -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.*"
}
catch { Write-Log "Ошибка очистки логов: $_" -Level WARNING }

#endregion /ЭТАП 2: ОСНОВНОЙ ЗАПУСК

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

$EmailTextBody = Get-LogResults
$EmailTextBody += "`nПодробнее в логе: $(Get-LogFilePath)"

# Отправка почты
if ($errorCount -gt 0) {
    $AdminMailList = @($AdminIS, $AdminOS)
    $Subject = "$PCName $ParentJobName : ОБНАРУЖЕНЫ ОШИБКИ"
    $Body = "Ошибки в процессе:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Error" -MessageText "СКРИПТ ЗАВЕРШЕН С ОШИБКАМИ"
}
else {
    $AdminMailList = @($AdminIS)
    $Subject = "$PCName $ParentJobName : УСПЕХ"
    $Body = "Задание выполнено успешно:`n$EmailTextBody"
    Write-WinEventAppLog -StatusKey "Success" -MessageText "СКРИПТ ЗАВЕРШЕН УСПЕШНО"
}

# Проверка переменных перед отправкой
#Write-Host "Проверка параметров почты:" -ForegroundColor Cyan
#Write-Host "  SmtpServer : $SmtpServer"
#Write-Host "  From       : $PCNameMail"
#Write-Host "  To         : $($AdminMailList -join ", ")"
#Write-Host "  Subject    : $Subject"

if ([string]::IsNullOrWhiteSpace($SmtpServer)) {
    Write-Log "Ошибка: Переменная SmtpServer пуста. Проверьте JSON конфигурацию (General.SmtpServer)." -Level ERROR
}
elseif ([string]::IsNullOrWhiteSpace($PCNameMail)) {
    Write-Log "Ошибка: Переменная From (PCNameMail) пуста." -Level ERROR
}
else {
    try {
        # Используем функцию Send-Email
        $mailResult = Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To ($AdminMailList -join ", ") -Subject $Subject -Body $Body
        
        if (-not $mailResult) {
            # Если функция вернула false, ошибка уже залогирована внутри функции
        }
    }
    catch {
        Write-Log "Критическая ошибка при вызове функции отправки почты: $_" -Level ERROR
    }
}

#Запись в Windows журнал
Write-WinEventAppLog -StatusKey "End" -MessageText "Завершение скрипта: $ParentJobName"

if ($errorCount -gt 0) { exit 1 } else { exit 0 }
#endregion /ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ
