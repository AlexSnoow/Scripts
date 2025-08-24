<# file Create_Backup_Rar.ps1
.SYNOPSIS
    Выполняет архивацию данных с помощью RAR

.DESCRIPTION
    Скрипт для автоматической архивации файлов и папок с использованием RAR.
    Поддерживает добавление даты/времени в имя архива, ведение лога и различные ключи архивации.
    Может быть запущен самостоятельно или использован как функция в других скриптах.

.PARAMETER RarPath
    Путь к исполняемому файлу RAR (по умолчанию: стандартный путь установки)

.PARAMETER SRC
    Источник: файл или папка для архивации

.PARAMETER DST
    Папка назначения для сохранения архива

.PARAMETER ArchiveName
    Имя архива (может содержать плейсхолдеры {SRCfolder}, {computer}, {date}, {time}, {datetime}), имя может задаваться в ручную, или генерироваться автоматически.
    На основании имен: Имя ПК + имя папки + дата-время.
    Пример: backup_{SRCfolder}_{computer}_{datetime} создаст архив с именем backup_documents_pcname_20230819-153000.rar
    Write-Verbose "Команда: $RarPath $rarArgs"

.PARAMETER Keys
    Ключи и команды для RAR (по умолчанию: стандартные параметры архивации)

.PARAMETER ArchiveExtension
    Расширение архива (по умолчанию: "rar")

.EXAMPLE
    #Простой запуск .\Create_Backup_Rar.ps1 ключи по умолчанию
    .\Create_Backup_Rar.ps1 -SRC "C:\test\backup2" -DST "C:\test\rar" -ArchiveName "Backup-{SRCfolder}_{computer}_{datetime}"
.EXAMPLE
    #Простой запуск .\Create_Backup_Rar.ps1 ключи по умолчанию
    .\Create_Backup_Rar.ps1 -SRC "C:\\test\\backup2" -DST "C:\\test\\rar" -ArchiveName "Backup-{SRCfolder}_{computer}_{datetime}" -Verbose
.EXAMPLE
    # Использование из другого скрипта:
    . .\Create_Backup_Rar.ps1  # точка перед именем файла — импорт функции
    Backup-WithRAR -SRC "C:\Data" -DST "D:\Backups" -ArchiveName "Backup-{SRCfolder}_{computer}_{datetime}"
.NOTES
    Автор: Иванов
    Версия: 3.0 (2025-08-24)
    Требуется: RAR установленный в системе
#>
# --- Параметры при запуске напрямую ---

# param(
#     [string]$SRC,
#     [string]$DST,
#     [string]$ArchiveName = "backup_{SRCfolder}_{computer}_{datetime}",
#     [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",
#     [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",
#     [ValidateSet("rar","zip","7z")]
#     [string]$ArchiveExtension = "rar"
# )

function Backup-WithRAR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "RAR не найден по указанному пути: $_" }
                $true
            })]
        [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",

        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "Источник не существует: $_" }
                $true
            })]
        [string]$SRC,

        [Parameter(Mandatory = $true)]
        [string]$DST,

        [Parameter(Mandatory = $false)]
        [string]$ArchiveName = "backup_{SRCfolder}_{computer}_{datetime}",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

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

    # Подготовка плейсхолдеров
    $placeholders = @{
        "{SRCfolder}" = (Split-Path -Leaf $SRC) -replace '[<>:"|?*]', '_'
        "{computer}"  = $env:COMPUTERNAME
        "{date}"      = (Get-Date -Format "yyyyMMdd")
        "{time}"      = (Get-Date -Format "HHmmss")
        "{datetime}"  = (Get-Date -Format "yyyyMMdd-HHmmss")
    }

    # Подстановка плейсхолдеров в имя архива
    $finalArchiveName = $ArchiveName
    foreach ($ph in $placeholders.Keys) {
        $finalArchiveName = $finalArchiveName -replace [regex]::Escape($ph), $placeholders[$ph]
    }

    # Обрезка пробелов и служебных символов в конце
    $finalArchiveName = $finalArchiveName.Trim().TrimEnd('.', ' ', '-', '_')

    # Проверка итогового имени на недопустимые символы
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $invalidPattern = '[' + [regex]::Escape(($invalidChars -join '')) + ']'
    if ($finalArchiveName -match $invalidPattern) {
        throw "Итоговое имя архива содержит недопустимые символы: '$finalArchiveName'. Измените имя архива или папку источника."
    }

    # Проверка на зарезервированные имена Windows
    $reserved = 'CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'
    if ($reserved -contains $finalArchiveName.ToUpperInvariant()) {
        throw "Итоговое имя архива зарезервировано системой: '$finalArchiveName'. Измените имя архива."
    }

    # Формирование полных путей
    $archivePath = Join-Path $DST "$finalArchiveName.$ArchiveExtension"
    $logPath = Join-Path $DST "$finalArchiveName.log.txt"
    $logErrPath = Join-Path $DST "$finalArchiveName.err.txt"

    # Ограничение длины пути (для Windows MAX_PATH)
    $maxPathLen = 250
    while ($archivePath.Length -gt $maxPathLen -or $logPath.Length -gt $maxPathLen -or $logErrPath.Length -gt $maxPathLen) {
        Write-Verbose "Путь слишком длинный. Усечём имя архива для корректной работы."
        # Укорачиваем имя архива на 5 символов
        $finalArchiveName = $finalArchiveName.Substring(0, [Math]::Max(0, $finalArchiveName.Length - 5)).TrimEnd('.', ' ', '-', '_')
        # Пересоздаём пути
        $archivePath = Join-Path $DST "$finalArchiveName.$ArchiveExtension"
        $logPath = Join-Path $DST "$finalArchiveName.log.txt"
        $logErrPath = Join-Path $DST "$finalArchiveName.err.txt"

        if ([string]::IsNullOrWhiteSpace($finalArchiveName)) {
            throw "Имя архива слишком длинное для указанного пути назначения. Измените папку или имя архива."
        }
    }

    # Экранирование путей с пробелами
    $escapedArchivePath = '"{0}"' -f $archivePath
    $escapedSrcPath = '"{0}"' -f $SRC

    # Формирование командной строки
    $rarArgs = @(
        $Keys,
        $escapedArchivePath,
        $escapedSrcPath
    ) -join " "

    Write-Host "Запуск архивации..."
    Write-Verbose "Команда: $RarPath $rarArgs"

    # Выполнение архивации
    try {
        # Создаем временный файл для ошибок
        $tempErrFile = [System.IO.Path]::GetTempFileName()

        $processInfo = @{
            FilePath               = $RarPath
            ArgumentList           = $rarArgs
            Wait                   = $true
            PassThru               = $true
            NoNewWindow            = $true
            RedirectStandardOutput = $logPath
            RedirectStandardError  = $tempErrFile
        }

        $process = Start-Process @processInfo


        # Проверяем, есть ли ошибки
        $hasErrors = $process.ExitCode -ne 0
        $errorContent = if (Test-Path $tempErrFile) { 
            Get-Content $tempErrFile -Raw 
        } else { 
            $null 
        }

        # Если есть ошибки или содержимое в stderr, сохраняем лог ошибок
        if ($hasErrors -or (-not [string]::IsNullOrWhiteSpace($errorContent))) {
            Move-Item -Path $tempErrFile -Destination $logErrPath -Force
            Write-Verbose "Создан лог ошибок: $logErrPath"
        } else {
            # Если ошибок нет, удаляем временный файл
            Remove-Item $tempErrFile -Force -ErrorAction SilentlyContinue
        }

        # Проверка кода возврата
        if ($process.ExitCode -eq 0) {
            Write-Host "Архивация успешно завершена!"
            Write-Host "Архив: $archivePath"
            Write-Host "Лог: $logPath"

            # Вывод размера архива
            if (Test-Path $archivePath) {
                $archiveSize = (Get-Item $archivePath).Length / 1MB
                $sizeText = "Размер архива: {0:N2} МБ" -f $archiveSize
                Write-Host $sizeText
            } else {
                Write-Warning "Не удалось определить размер архива."
            }
        }
        else {
            Write-Error "Архивация завершена с кодом ошибки: $($process.ExitCode)"
            if (Test-Path $logErrPath) {
                Write-Error "Лог ошибок: $logErrPath"
            }
        }

        return $process.ExitCode
    }
    catch {
        Write-Error "Ошибка при выполнении архивации: $($_.Exception.Message)"
        return -1
    }
    finally {
        # Удаление временного файла ошибок, если он остался
        if (Test-Path $tempErrFile) {
            Remove-Item $tempErrFile -Force -ErrorAction SilentlyContinue
        }
        
        # Удаление старого временного файла ошибок, если существует
        if (Test-Path "RAR_errors.txt") {
            Remove-Item "RAR_errors.txt" -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Экспорт функции для модуля ---
if ($MyInvocation.ScriptName -like "*.psm1") {
    Export-ModuleMember -Function Backup-WithRAR
}

# --- Запуск напрямую ---
# Упрощенная и более надежная проверка на прямой запуск
if (($MyInvocation.InvocationName -eq '.') -or 
    ($MyInvocation.MyCommand.Name -eq $MyInvocation.InvocationName) -or
    (Test-Path -LiteralPath $MyInvocation.InvocationName -ErrorAction SilentlyContinue)) {
    
    # Если не указаны обязательные параметры, запрашиваем их
    if (-not $SRC) { $SRC = Read-Host "Укажите путь к источнику (SRC)" }
    if (-not $DST) { $DST = Read-Host "Укажите путь к папке назначения (DST)" }

    # Создаем хэш-таблицу параметров для передачи в функцию
    $params = @{
        SRC = $SRC
        DST = $DST
    }

    # Добавляем необязательные параметры, если они указаны
    if ($PSBoundParameters.ContainsKey('ArchiveName')) { $params.ArchiveName = $ArchiveName }
    if ($PSBoundParameters.ContainsKey('RarPath')) { $params.RarPath = $RarPath }
    if ($PSBoundParameters.ContainsKey('Keys')) { $params.Keys = $Keys }
    if ($PSBoundParameters.ContainsKey('ArchiveExtension')) { $params.ArchiveExtension = $ArchiveExtension }

    # Вызываем функцию с параметрами
    Backup-WithRAR @params
}