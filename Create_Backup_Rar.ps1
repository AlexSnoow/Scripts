<# file Create_Backup_Rar.ps1
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
    Имя архива (может содержать плейсхолдеры {date}, {time}, {datetime}), имя может задаваться в ручную, или генерироваться автоматически.
    На основании имен: Имя ПК + имя папки + дата-время.
    Пример: ИмяПК-ИмяПапки-{datetime} создаст архив с именем workpc-documents-20230819-153000.rar
    Write-Verbose "Команда: $RarPath $rarArgs"

.PARAMETER Keys
    Ключи и команды для RAR (по умолчанию: стандартные параметры архивации)

.PARAMETER ArchiveExtension
    Расширение архива (по умолчанию: "rar")

.EXAMPLE
    #Простой запуск
    Backup-WithRAR -SRC "C:\test\backup1" -DST "C:\test\rar" -ArchiveName "DataBackup-{datetime}"

.EXAMPLE
    Backup-WithRAR -SRC "C:\Logs" -DST "\\server\backups" -ArchiveName "Logs" -Keys "a -r -m5 -dh -ep1"

.EXAMPLE
    # С дополнительными плейсхолдерами
    Backup-WithRAR -SRC "C:\Data" -DST "D:\Backups" -ArchiveName "Backup-{datetime}"

.EXAMPLE
    # С выбором формата ZIP
    Backup-WithRAR -SRC "C:\Logs" -DST "E:\Archives" -ArchiveName "Logs-{date}" -ArchiveExtension "zip" -Verbose

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
        [string]$Keys = "a -r -m5 -dh -ep1",

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
        "{SRCfolder}" = (Split-Path -Leaf $SRC) -replace '[<>:"|?*]', '_'   # заменяем недопустимые символы на '_' имя исходного каталога
        "{computer}"  = $env:COMPUTERNAME                                   # имя компьютера       
        "{date}"      = (Get-Date -Format "yyyyMMdd")                       # 20250824
        "{time}"      = (Get-Date -Format "HHmmss")                         # 153045
        "{datetime}"  = (Get-Date -Format "yyyyMMdd-HHmmss")                # 20250824-153045
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

        # Если имя архива полностью сжато до нуля, выдаём ошибку
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
        $processInfo = @{
            FilePath              = $RarPath
            ArgumentList          = $rarArgs
            Wait                  = $true
            PassThru              = $true
            NoNewWindow           = $true
            RedirectStandardOutput = $logPath
            RedirectStandardError  = $logErrPath
        }

        $process = Start-Process @processInfo

        # Проверка кода возврата
        if ($process.ExitCode -eq 0) {
            Write-Host "Архивация успешно завершена!"
            Write-Host "Архив: $archivePath"
            Write-Host "Лог: $logPath"

            # Вывод размера архива
            $archiveSize = (Get-Item $archivePath).Length / 1MB
            if ($archiveSize -is [double] -and $archiveSize -ge 0) {
                $sizeText = "Размер архива: {0:N2} МБ" -f $archiveSize
                Write-Host $sizeText
            } else {
                Write-Warning "Не удалось определить размер архива."
            }
        }
        else {
            Write-Error "Архивация завершена с кодом ошибки: $($process.ExitCode)"
            Write-Error "Полный лог находится по адресу: $logPath"
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