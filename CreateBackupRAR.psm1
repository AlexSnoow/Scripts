<# file CreateBackupRAR.psm1
<#
.SYNOPSIS
    Модуль для архивации данных с помощью RAR

.DESCRIPTION
    Модуль для автоматической архивации файлов и папок с использованием RAR для запуска из другого сприпта.
    Модуль решает основные 3 задачи: создание архива, запись в файл всех файлов что были добавлены, сохранение в лог и передача управляющему скрипту информацию: Успешно или Были ошибки смотрите лог.
    Поддерживает добавление даты/времени в имя архива.
    Поддерживает добавление различные ключи архивации.

.PARAMETER RarPath
    Путь к исполняемому файлу RAR (есть проверка на существование, если нет ошибка и прерываение)

.PARAMETER SourcePath
    Источник: файл или папка для архивации (есть проверка на существование, если нет ошибка и прерываение)

.PARAMETER DestinationPath
    Папка назначения для сохранения архива (есть проверка на существование, если нет создание)

.PARAMETER ArchiveName
    Имя архива (может содержать плейсхолдеры {SourceFolder}, {Computer}, {Date}, {Time}, {DateTime})

.PARAMETER Keys
    Ключи и команды для RAR

.PARAMETER ArchiveExtension
    Расширение архива

.PARAMETER RarLogPath
    Путь для сохранения лога операций RAR

.PARAMETER RarLog
    Имя файла лога операций RAR (может содержать плейсхолдеры)

.EXAMPLE

.NOTES
    Автор: Иванов
    Версия: 4.2 (2025-08-25)
    Требуется: RAR установленный в системе
#>

function BackupWithRAR {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "RAR не найден по указанному пути: $_" }
            $true
        })]
        [string]$RarPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "Источник не существует: $_" }
            $true
        })]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [string]$ArchiveName = "backup_{SourceFolder}_{Computer}_{DateTime}",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

        [Parameter(Mandatory = $false)]
        [ValidateSet("rar", "zip")]
        [string]$ArchiveExtension = "rar",

        [Parameter(Mandatory = $false)]
        [string]$RarLogPath,

        [Parameter(Mandatory = $false)]
        [string]$RarLog
    )

    # Инициализация
    $SourcePath = (Resolve-Path $SourcePath -ErrorAction Stop).Path
    $DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    
    # Создание папки назначения если не существует
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        Write-Verbose "Создана папка назначения: $DestinationPath"
    }

    # Подготовка плейсхолдеров
    $placeholders = @{
        "{SourceFolder}" = (Split-Path -Leaf $SourcePath) -replace '[<>:"|?*]', '_'
        "{Computer}"     = $env:COMPUTERNAME
        "{Date}"         = (Get-Date -Format "yyyyMMdd")
        "{Time}"         = (Get-Date -Format "HHmmss")
        "{DateTime}"     = (Get-Date -Format "yyyyMMdd-HHmmss")
    }

    # Подстановка плейсхолдеров в имя архива
    $finalArchiveName = $ArchiveName
    foreach ($ph in $placeholders.Keys) {
        $finalArchiveName = $finalArchiveName -replace [regex]::Escape($ph), $placeholders[$ph]
    }
    $finalArchiveName = $finalArchiveName.Trim().TrimEnd('.', ' ', '-', '_')

    # Формирование путей архива
    $archivePath = Join-Path $DestinationPath "$finalArchiveName.$ArchiveExtension"
    
    # Определение пути и имени для лога
    if ([string]::IsNullOrEmpty($RarLogPath)) {
        $RarLogPath = $DestinationPath
    } else {
        # Создание папки для логов если не существует
        if (-not (Test-Path $RarLogPath)) {
            New-Item -ItemType Directory -Path $RarLogPath -Force | Out-Null
            Write-Verbose "Создана папка для логов: $RarLogPath"
        }
    }
    
    # Определение имени файла лога
    if ([string]::IsNullOrEmpty($RarLog)) {
        $logFileName = "$finalArchiveName.log"
    } else {
        # Подстановка плейсхолдеров в имя лога
        $logFileName = $RarLog
        foreach ($ph in $placeholders.Keys) {
            $logFileName = $logFileName -replace [regex]::Escape($ph), $placeholders[$ph]
        }
        $logFileName = $logFileName.Trim().TrimEnd('.', ' ', '-', '_')
    }
    
    # Полный путь к лог-файлу
    $logPath = Join-Path $RarLogPath $logFileName

    # Экранирование путей с пробелами
    $escapedArchivePath = '"{0}"' -f $archivePath
    $escapedSrcPath = '"{0}"' -f $SourcePath

    # Формирование командной строки
    $rarArgs = @(
        $Keys,
        $escapedArchivePath,
        $escapedSrcPath
    ) -join " "

    Write-Verbose "Команда: $RarPath $rarArgs"
    Write-Verbose "Лог будет сохранен в: $logPath"

    # Создание временных файлов для перехвата вывода
    $tempStdOut = [System.IO.Path]::GetTempFileName()
    $tempStdErr = [System.IO.Path]::GetTempFileName()

    # Таблица кодов ошибок RAR
    $rarErrorCodes = @{
        0 = "SUCCESS: Successful operation"
        1 = "WARNING: Non fatal error(s) occurred"
        2 = "FATAL ERROR: A fatal error occurred"
        3 = "CRC ERROR: A CRC error occurred when unpacking"
        4 = "LOCKED ARCHIVE: Attempt to modify an archive previously locked by the 'k' command"
        5 = "WRITE ERROR: Write to disk error"
        6 = "OPEN ERROR: Open file error"
        7 = "USER ERROR: Command line option error"
        8 = "MEMORY ERROR: Not enough memory for operation"
        9 = "CREATE ERROR: Create file error"
        255 = "USER BREAK: User stopped the process"
    }

    try {
        # Запуск процесса RAR
        $processInfo = @{
            FilePath               = $RarPath
            ArgumentList           = $rarArgs
            Wait                   = $true
            PassThru               = $true
            NoNewWindow            = $true
            RedirectStandardOutput = $tempStdOut
            RedirectStandardError  = $tempStdErr
        }

        $process = Start-Process @processInfo

        # Чтение и сохранение вывода
        $stdOut = Get-Content $tempStdOut -Raw
        $stdErr = Get-Content $tempStdErr -Raw

        # Определение описания ошибки по коду возврата
        $errorDescription = if ($rarErrorCodes.ContainsKey($process.ExitCode)) {
            $rarErrorCodes[$process.ExitCode]
        } else {
            "UNKNOWN ERROR: Unknown exit code $($process.ExitCode)"
        }

        # Сохранение лога
        $logContent = @"
[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Запуск команды: $RarPath $rarArgs
$stdOut
$stdErr
[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Процесс завершен с кодом: $($process.ExitCode) - $errorDescription
"@
        Set-Content -Path $logPath -Value $logContent -Encoding UTF8

        # Формирование результата
        $result = [PSCustomObject]@{
            Success          = $process.ExitCode -eq 0
            ExitCode         = $process.ExitCode
            ErrorDescription = $errorDescription
            ArchivePath      = $archivePath
            LogPath          = $logPath
            StandardOut      = $stdOut
            StandardError    = $stdErr
            CommandLine      = "$RarPath $rarArgs"
        }

        return $result

    } catch {
        # Обработка ошибок выполнения процесса
        $errorMsg = "Ошибка при выполнении архивации: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        return [PSCustomObject]@{
            Success          = $false
            ExitCode         = -1
            ErrorDescription = "PROCESS EXECUTION ERROR: $errorMsg"
            ArchivePath      = $archivePath
            LogPath          = $logPath
            StandardOut      = ""
            StandardError    = $errorMsg
            CommandLine      = "$RarPath $rarArgs"
        }
    } finally {
        # Очистка временных файлов
        Remove-Item $tempStdOut -Force -ErrorAction SilentlyContinue
        Remove-Item $tempStdErr -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function BackupWithRAR