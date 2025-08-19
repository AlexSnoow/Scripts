<#
.SYNOPSIS
    Выполняет архивацию данных с помощью RAR

.DESCRIPTION
    Функция для автоматической архивации файлов и папок с использованием RAR.
    Поддерживает добавление даты/времени в имя архива, ведение лога и различные ключи архивации.

.PARAMETER RarPath
    Путь к исполняемому файлу RAR (по умолчанию: стандартный путь установки)

.PARAMETER SRC
    Источник: файл или папка для архивации

.PARAMETER DST
    Папка назначения для сохранения архива

.PARAMETER ArchiveName
    Имя архива (может содержать плейсхолдеры {date}, {time}, {datetime})

.PARAMETER Keys
    Ключи и команды для RAR (по умолчанию: стандартные параметры архивации)

.PARAMETER ArchiveExtension
    Расширение архива (по умолчанию: "rar")

.EXAMPLE
    Backup-WithRAR -SRC "C:\Data" -DST "D:\Backups" -ArchiveName "DataBackup-{date}"

.EXAMPLE
    Backup-WithRAR -SRC "C:\Logs" -DST "\\server\backups" -ArchiveName "Logs" -Keys "a -r -m5 -dh -ep1"

.EXAMPLE
    # С дополнительными плейсхолдерами
    Backup-WithRAR -SRC "C:\Data" -DST "D:\Backups" -ArchiveName "Backup-{datetime}"

.EXAMPLE
    # С выбором формата ZIP
    Backup-WithRAR -SRC "C:\Logs" -DST "E:\Archives" -ArchiveName "Logs-{date}" -ArchiveExtension "zip" -Verbose

.EXAMPLE
    # С проверкой свободного места
    Backup-WithRAR -SRC "D:\Database" -DST "F:\Backups" -ArchiveName "DB-{date}" -Keys "a -r -m5 -hp -ep1"

.NOTES
    Автор: Иванов
    Версия: 2.0 (2025-08-19)
    Требуется: RAR установленный в системе
#>
function Backup-WithRAR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "RAR не найден по указанному пути: $_" }
            $true
        })]
        [string]$RarPath = "C:\Program Files\RAR\Rar.exe",

        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "Источник не существует: $_" }
            $true
        })]
        [string]$SRC,

        [Parameter(Mandatory = $true)]
        [string]$DST,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if ($_ -match '[<>:|"?*]') { throw "Имя архива содержит недопустимые символы" }
            $true
        })]
        [string]$ArchiveName,

        [Parameter(Mandatory = $false)]
        [string]$Keys = "a -r -m3 -dh -ep1 -ilog",

        [Parameter(Mandatory = $false)]
        [ValidateSet("rar", "zip", "7z")]
        [string]$ArchiveExtension = "rar"
    )

    # Нормализация путей
    $SRC = (Resolve-Path $SRC -ErrorAction Stop).Path
    $DST = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DST)

    # Создание папки назначения если не существует
    if (-not (Test-Path $DST)) {
        Write-Verbose "Создание папки назначения: $DST"
        New-Item -ItemType Directory -Path $DST -Force | Out-Null
    }

    # Проверка доступности места на диске
    $srcSize = (Get-ChildItem $SRC -Recurse -File | Measure-Object Length -Sum).Sum
    $dstFreeSpace = (Get-PSDrive -Name (Split-Path $DST -Qualifier).TrimEnd(':')).Free
    if ($srcSize -gt $dstFreeSpace * 0.9) {
        Write-Warning "Мало свободного места в папке назначения. Возможны ошибки архивации."
    }

    # Замена плейсхолдеров
    $dateString = Get-Date -Format "yyyyMMdd"
    $timeString = Get-Date -Format "HHmmss"
    $dateTimeString = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $finalArchiveName = $ArchiveName `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # Формирование полных путей
    $archivePath = Join-Path $DST "$finalArchiveName.$ArchiveExtension"
    $logPath = Join-Path $DST "$finalArchiveName.log"

    # Экранирование путей с пробелами
    $escapedArchivePath = '"{0}"' -f $archivePath
    $escapedSrcPath = '"{0}"' -f $SRC
    $escapedLogPath = '"{0}"' -f $logPath

    # Добавление лог-файла в ключи
    $keysWithLog = if ($Keys -match "-ilog") {
        $Keys -replace "-ilog", "-ilog$escapedLogPath"
    } else {
        "$Keys -ilog$escapedLogPath"
    }

    # Формирование командной строки
    $rarArgs = @(
        $keysWithLog,
        $escapedArchivePath,
        $escapedSrcPath
    ) -join " "

    Write-Host "Запуск архивации..."
    Write-Verbose "Команда: $RarPath $rarArgs"

    # Выполнение архивации
    try {
        $processInfo = @{
            FilePath = $RarPath
            ArgumentList = $rarArgs
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardError = "RAR_errors.txt"
        }
        
        $process = Start-Process @processInfo
        
        # Проверка кода возврата
        if ($process.ExitCode -eq 0) {
            Write-Host "Архивация успешно завершена!"
            Write-Host "Архив: $archivePath"
            Write-Host "Лог: $logPath"
            
            # Вывод размера архива
            $archiveSize = (Get-Item $archivePath).Length / 1MB
            Write-Host "Размер архива: {0:N2} MB" -f $archiveSize
        }
        else {
            $errorContent = if (Test-Path "RAR_errors.txt") {
                Get-Content "RAR_errors.txt" -Raw
                Remove-Item "RAR_errors.txt" -Force
            } else {
                "Неизвестная ошибка RAR"
            }
            
            Write-Error "Архивация завершена с кодом ошибки: $($process.ExitCode)"
            Write-Error "Ошибка: $errorContent"
        }
        
        return $process.ExitCode
    }
    catch {
        Write-Error "Ошибка при выполнении архивации: $($_.Exception.Message)"
        return -1
    }
    finally {
        # Удаление временного файла ошибок, если существует
        if (Test-Path "RAR_errors.txt") {
            Remove-Item "RAR_errors.txt" -Force -ErrorAction SilentlyContinue
        }
    }
}

# Экспорт функции для использования в других скриптах
if ($MyInvocation.ScriptName -like "*.psm1") {
    Export-ModuleMember -Function Backup-WithRAR
}