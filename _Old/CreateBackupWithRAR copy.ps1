<# file CreateBackupWithRAR.ps1
.SYNOPSIS
    Выполняет архивацию данных с помощью RAR

.DESCRIPTION
    Скрипт для автоматической архивации файлов и папок с использованием RAR.
    Поддерживает добавление даты/времени в имя архива, ведение лога и различные ключи архивации.
    Может быть запущен самостоятельно или использован как функция в других скриптах.

.PARAMETER SourcePath
    Источник: файл или папка для архивации

.PARAMETER DestinationPath
    Папка назначения для сохранения архива

.PARAMETER ArchiveName
    Имя архива (может содержать плейсхолдеры {SourceFolder}, {Computer}, {Date}, {Time}, {DateTime})

.PARAMETER RarPath
    Путь к исполняемому файлу RAR

.PARAMETER Keys
    Ключи и команды для RAR

.PARAMETER ArchiveExtension
    Расширение архива

.PARAMETER WhatIf
    Показать, что будет сделано, без выполнения

.EXAMPLE
    BackupWithRAR -SourcePath "C:\test\backup2" -DestinationPath "C:\test\rar" -ArchiveName "Backup-{SourceFolder}_{Computer}_{DateTime}"

.EXAMPLE
    BackupWithRAR -SourcePath "C:\Data" -DestinationPath "D:\Backups" -WhatIf

.NOTES
    Автор: Иванов
    Версия: 4.0 (2025-08-24)
    Требуется: RAR установленный в системе
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default")]
    [ValidateScript({
            if (-not (Test-Path $_)) { throw "Источник не существует: $_" }
            $true
        })]
    [Alias("SRC")]
    [string]$SourcePath,

    [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Default")]
    [Alias("DST")]
    [string]$DestinationPath,

    [Parameter(Mandatory = $false, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Default")]
    [string]$ArchiveName = "backup_{SourceFolder}_{Computer}_{DateTime}",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if (-not (Test-Path $_)) { throw "RAR не найден по указанному пути: $_" }
            $true
        })]
    [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",

    [Parameter(Mandatory = $false)]
    [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

    [Parameter(Mandatory = $false)]
    [ValidateSet("rar", "zip")]
    [string]$ArchiveExtension = "rar",

    [Parameter(Mandatory = $false, ParameterSetName = "DirectCall")]
    [switch]$WhatIf
)

# Регистрируем функцию при импорте как модуля
function BackupWithRAR {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "Источник не существует: $_" }
                $true
            })]
        [Alias("SRC")]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [Alias("DST")]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [string]$ArchiveName = "backup_{SourceFolder}_{Computer}_{DateTime}",

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "RAR не найден по указанному пути: $_" }
                $true
            })]
        [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

        [Parameter(Mandatory = $false)]
        [ValidateSet("rar", "zip")]
        [string]$ArchiveExtension = "rar"
    )

    begin {
        Write-Verbose "Начало выполнения архивации"
        
        # Нормализация путей
        $SourcePath = (Resolve-Path $SourcePath -ErrorAction Stop).Path
        $DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)

        # Создание папки назначения если не существует
        if (-not (Test-Path $DestinationPath)) {
            if ($PSCmdlet.ShouldProcess($DestinationPath, "Создание папки назначения")) {
                Write-Verbose "Создание папки назначения: $DestinationPath"
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            }
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

        # Обрезка пробелов и служебных символов в конце
        $finalArchiveName = $finalArchiveName.Trim().TrimEnd('.', ' ', '-', '_')

        # Проверка итогового имени на недопустимые символы
        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
        $invalidPattern = '[' + [regex]::Escape(($invalidChars -join '')) + ']'
        if ($finalArchiveName -match $invalidPattern) {
            throw "Итоговое имя архива содержит недопустимые символы: '$finalArchiveName'. Измените имя архива или папку источника."
        }

        # Проверка на зарезервированные имена Windows
        $reserved = 'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
        if ($reserved -contains $finalArchiveName.ToUpperInvariant()) {
            throw "Итоговое имя архива зарезервировано системой: '$finalArchiveName'. Измените имя архива."
        }

        # Формирование полных путей
        $archivePath = Join-Path $DestinationPath "$finalArchiveName.$ArchiveExtension"
        $logPath = Join-Path $DestinationPath "$finalArchiveName.log.txt"
        $logErrPath = Join-Path $DestinationPath "$finalArchiveName.err.txt"

        # Ограничение длины пути (для Windows MAX_PATH)
        $maxPathLen = 250
        while ($archivePath.Length -gt $maxPathLen -or $logPath.Length -gt $maxPathLen -or $logErrPath.Length -gt $maxPathLen) {
            Write-Verbose "Путь слишком длинный. Усечём имя архива для корректной работы."
            # Укорачиваем имя архива на 5 символов
            $finalArchiveName = $finalArchiveName.Substring(0, [Math]::Max(0, $finalArchiveName.Length - 5)).TrimEnd('.', ' ', '-', '_')
            # Пересоздаём пути
            $archivePath = Join-Path $DestinationPath "$finalArchiveName.$ArchiveExtension"
            $logPath = Join-Path $DestinationPath "$finalArchiveName.log.txt"
            $logErrPath = Join-Path $DestinationPath "$finalArchiveName.err.txt"

            if ([string]::IsNullOrWhiteSpace($finalArchiveName)) {
                throw "Имя архива слишком длинное для указанного пути назначения. Измените папку или имя архива."
            }
        }

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
    }

    process {
        if (-not $PSCmdlet.ShouldProcess("Архив: $archivePath", "Создание архива")) {
            Write-Host "Превью операции: Будет создан архив $archivePath из $SourcePath"
            return 0
        }

        try {
            Write-Host "Запуск архивации..."
            
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
            } else {
                Write-Error "Архивация завершена с кодом ошибки: $($process.ExitCode)"
                if (Test-Path $logErrPath) {
                    Write-Error "Лог ошибок: $logErrPath"
                }
            }

            return $process.ExitCode
        } catch {
            Write-Error "Ошибка при выполнении архивации: $($_.Exception.Message)"
            return -1
        } finally {
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

    end {
        Write-Verbose "Завершение выполнения архивации"
    }
}

# --- Экспорт функции для модуля ---
if ($MyInvocation.ScriptName -like "*.psm1") {
    Export-ModuleMember -Function BackupWithRAR
}

# --- Запуск напрямую ---
if ($PSCmdlet.ParameterSetName -eq "DirectCall") {
    # Создаем хэш-таблицу параметров для передачи в функцию
    $params = @{
        SourcePath      = $SourcePath
        DestinationPath = $DestinationPath
    }

    # Добавляем необязательные параметры, если они указаны
    if ($PSBoundParameters.ContainsKey('ArchiveName')) { $params.ArchiveName = $ArchiveName }
    if ($PSBoundParameters.ContainsKey('RarPath')) { $params.RarPath = $RarPath }
    if ($PSBoundParameters.ContainsKey('Keys')) { $params.Keys = $Keys }
    if ($PSBoundParameters.ContainsKey('ArchiveExtension')) { $params.ArchiveExtension = $ArchiveExtension }
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $params.WhatIf = $WhatIf }

    # Вызываем функцию с параметрами
    BackupWithRAR @params
}