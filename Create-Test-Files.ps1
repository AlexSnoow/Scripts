<#
.SYNOPSIS
    Скрипт создания тестовых файлов для проверки архивации и ротации логов.

.DESCRIPTION
    Создает тестовые файлы в директориях, указанных в Backup-Config-All-rar.json.
    Поддерживает создание файлов с разными датами модификации для тестирования ротации.

.PARAMETER ConfigPath
    Путь к файлу конфигурации JSON. По умолчанию: Backup-Config-All-rar.json

.PARAMETER DaysBack
    Количество дней назад для создания файлов с разными датами. По умолчанию: 40

.PARAMETER FilesPerDay
    Количество файлов создаваемых для каждого дня. По умолчанию: 2

.PARAMETER JobName
    Имя задания из конфигурации для создания файлов. Если не указано, создаются файлы для всех заданий.

.PARAMETER Clear
    Очистить существующие тестовые файлы перед созданием новых.

.EXAMPLE
    .\Create-Test-Files.ps1
    Создание файлов для всех заданий с параметрами по умолчанию.

.EXAMPLE
    .\Create-Test-Files.ps1 -JobName JOB1 -DaysBack 30 -FilesPerDay 3
    Создание 3 файлов в день за последние 30 дней для задания JOB1.

.EXAMPLE
    .\Create-Test-Files.ps1 -Clear
    Очистить и создать новые тестовые файлы для всех заданий.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = ".\Backup-Config-All-rar.json",
    [int]$DaysBack = 40,
    [int]$FilesPerDay = 2,
    [ValidateSet("JOB1", "JOB2", "JOB3", "JOB4")]
    [string[]]$JobName,
    [switch]$Clear
)

# Проверка существования файла конфигурации
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Файл конфигурации не найден: $ConfigPath"
    exit 1
}

# Загрузка конфигурации
try {
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Конфигурация загружена: $ConfigPath" -ForegroundColor Green
}
catch {
    Write-Error "Ошибка загрузки конфигурации: $_"
    exit 1
}

# Функция создания тестового файла с указанной датой
function New-TestFile {
    param(
        [string]$Path,
        [string]$FileName,
        [DateTime]$Date,
        [string]$Content = ""
    )

    $fullPath = Join-Path $Path $FileName

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    if ([string]::IsNullOrEmpty($Content)) {
        $Content = @"
Тестовый файл для проверки архивации
Создан: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")
Имя файла: $FileName
Дата модификации: $($Date.ToString("dd.MM.yyyy HH:mm:ss"))
"@
    }

    Set-Content -Path $fullPath -Value $Content -Encoding UTF8 -Force
    (Get-Item $fullPath).LastWriteTime = $Date
    (Get-Item $fullPath).CreationTime = $Date

    return $fullPath
}

# Функция очистки директории
function Clear-TestDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Write-Host "  Очистка: $Path" -ForegroundColor Yellow
        Get-ChildItem -Path $Path -File -Force | Remove-Item -Force
    }
}

# Обработка заданий
$jobsToProcess = if ($JobName) {
    $config.Jobs | Where-Object { $JobName -contains $_.Name }
} else {
    $config.Jobs
}

if ($jobsToProcess.Count -eq 0) {
    Write-Warning "Задания для обработки не найдены."
    exit 0
}

Write-Host "`nНачало создания тестовых файлов..." -ForegroundColor Cyan
Write-Host "Дней назад: $DaysBack, Файлов в день: $FilesPerDay" -ForegroundColor Cyan

foreach ($job in $jobsToProcess) {
    Write-Host "`n[ $($job.Name) ]" -ForegroundColor Magenta

    $sourcePath = $job.Source

    # Создание директории источника, если не существует
    if (-not (Test-Path $sourcePath)) {
        Write-Host "  Создание директории: $sourcePath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    }

    # Очистка при необходимости
    if ($Clear) {
        Clear-TestDirectory -Path $sourcePath
    }

    # Создание файлов с разными датами
    Write-Host "  Директория: $sourcePath" -ForegroundColor Gray

    for ($i = 0; $i -lt $DaysBack; $i++) {
        $fileDate = (Get-Date).AddDays(-$i).Date
        $dateString = $fileDate.ToString("yyyy-MM-dd")

        for ($f = 0; $f -lt $FilesPerDay; $f++) {
            # Определение типа файла на основе конфигурации
            $extension = ".txt"
            $prefix = "File"

            if ($job.Name -eq "JOB1") {
                # JOB1: File_0*.*, ADV*.*, *.xml
                if ($f -eq 0) {
                    $prefix = "File_0"
                    $extension = ".dat"
                } elseif ($f -eq 1) {
                    $prefix = "ADV"
                    $extension = ".log"
                } else {
                    $prefix = "Data"
                    $extension = ".xml"
                }
            }
            elseif ($job.Name -eq "JOB2") {
                # JOB2: *.log
                $prefix = "Log"
                $extension = ".log"
            }
            elseif ($job.Name -eq "JOB3") {
                # JOB3: любые файлы
                $prefix = "Backup"
                $extension = ".bak"
            }
            elseif ($job.Name -eq "JOB4") {
                # JOB4: любые файлы
                $prefix = "Archive"
                $extension = ".tmp"
            }

            $fileName = "${prefix}_${dateString}_$(('{0:D2}' -f $f))${extension}"

            try {
                $filePath = New-TestFile -Path $sourcePath -FileName $fileName -Date $fileDate
                if ($i -lt 3 -or $i -eq ($DaysBack - 1)) {
                    Write-Host "    Создан: $fileName ( $($fileDate.ToString("dd.MM.yyyy")) )" -ForegroundColor Gray
                }
            }
            catch {
                Write-Warning "Ошибка создания файла $fileName : $_"
            }
        }
    }

    # Создание дополнительных файлов для проверки масок (только для JOB1)
    if ($job.Name -eq "JOB1") {
        Write-Host "  Создание дополнительных файлов для масок..." -ForegroundColor Gray

        # Файлы для проверки маски File_0*.*
        1..3 | ForEach-Object {
            $fileName = "File_0Test$_${dateString}.dat"
            New-TestFile -Path $sourcePath -FileName $fileName -Date (Get-Date) | Out-Null
        }

        # Файлы для проверки маски ADV*.*
        1..3 | ForEach-Object {
            $fileName = "ADV_Report$_${dateString}.log"
            New-TestFile -Path $sourcePath -FileName $fileName -Date (Get-Date) | Out-Null
        }

        # XML файлы
        1..3 | ForEach-Object {
            $fileName = "Config$_${dateString}.xml"
            New-TestFile -Path $sourcePath -FileName $fileName -Date (Get-Date) | Out-Null
        }
    }

    # Подсчет созданных файлов
    $fileCount = (Get-ChildItem -Path $sourcePath -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Итого файлов: $fileCount" -ForegroundColor Green
}

# Создание файлов для проверки ротации в LocalDest
Write-Host "`n[ LocalDest - файлы для проверки ротации ]" -ForegroundColor Magenta

foreach ($job in $jobsToProcess) {
    $localDest = $job.LocalDest

    if ($Clear) {
        Clear-TestDirectory -Path $localDest
    }

    Write-Host "  Директория: $localDest" -ForegroundColor Gray

    # Создание архивов с разными датами для проверки ротации
    $keepCount = $job.LocalDestKeepCount
    $daysOld = $job.LocalDestDaysOld

    for ($i = 0; $i -lt ([Math]::Max($keepCount, $daysOld) + 5); $i++) {
        $fileDate = (Get-Date).AddDays(-$i).Date
        $dateString = $fileDate.ToString("yyyyMMdd_HHmmss")

        $archiveName = "$($env:COMPUTERNAME)_$($job.Name)_${dateString}.rar"

        try {
            New-TestFile -Path $localDest -FileName $archiveName -Date $fileDate -Content "Тестовый архив для проверки ротации" | Out-Null
        }
        catch {
            Write-Warning "Ошибка создания архива $archiveName : $_"
        }
    }

    $fileCount = (Get-ChildItem -Path $localDest -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Итого файлов: $fileCount" -ForegroundColor Green
}

# Создание тестовых логов для проверки ротации (LogPathRoot)
Write-Host "`n[ LogPathRoot - тестовые логи для ротации ]" -ForegroundColor Magenta

$logPathRoot = $config.Paths.LogPathRoot
$logDaysOld = $config.General.LogDaysOld
$logKeepCount = $config.General.LogKeepCount

# Создание директории логов, если не существует
if (-not (Test-Path $logPathRoot)) {
    Write-Host "  Создание директории: $logPathRoot" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $logPathRoot -Force | Out-Null
}

if ($Clear) {
    Clear-TestDirectory -Path $logPathRoot
}

Write-Host "  Директория: $logPathRoot" -ForegroundColor Gray
Write-Host "  LogDaysOld: $logDaysOld, LogKeepCount: $logKeepCount" -ForegroundColor Gray

# Создание логов с разными датами для проверки ротации
$logCount = [Math]::Max($logDaysOld, $logKeepCount) + 10

for ($i = 0; $i -lt $logCount; $i++) {
    $fileDate = (Get-Date).AddDays(-$i).Date
    $dateString = $fileDate.ToString("yyyyMMdd")
    
    # Создание основного лога
    $logName = "${config.General.JobName}_${dateString}.log"
    
    $logContent = @"
================================================================================
Лог выполнения задания: $($config.General.JobName)
Дата: $($fileDate.ToString("dd.MM.yyyy"))
Время начала: $($fileDate.ToString("HH:mm:ss"))
================================================================================

[INFO] Начало выполнения задания...
[INFO] Проверка исходных файлов...
[INFO] Архивация данных...
[INFO] Копирование в пункт назначения...
[INFO] Задание выполнено успешно.

================================================================================
Время завершения: $($fileDate.ToString("HH:mm:ss"))
Статус: SUCCESS
================================================================================
"@

    try {
        New-TestFile -Path $logPathRoot -FileName $logName -Date $fileDate -Content $logContent | Out-Null
        
        # Создание дополнительного лога архивации для каждого задания
        foreach ($job in $jobsToProcess) {
            if ($job.ArhLog) {
                $archLogName = "${config.General.JobName}_$($job.Name)_Arch_${dateString}.log"
                $archLogContent = @"
================================================================================
Лог архивации: $($job.Name)
Дата: $($fileDate.ToString("dd.MM.yyyy"))
================================================================================

[INFO] Источник: $($job.Source)
[INFO] Назначение: $($job.LocalDest)
[INFO] Параметры: $($job.ArhParameters -join ' ')

[INFO] Архивация выполнена.
[INFO] Файлов обработано: $((Get-Random -Minimum 10 -Maximum 100))
[INFO] Размер архива: $((Get-Random -Minimum 1 -Maximum 500)) МБ

================================================================================
Статус: SUCCESS
================================================================================
"@
                New-TestFile -Path $logPathRoot -FileName $archLogName -Date $fileDate -Content $archLogContent | Out-Null
            }
        }
        
        if ($i -lt 3 -or $i -eq ($logCount - 1)) {
            Write-Host "    Создан: $logName ( $($fileDate.ToString("dd.MM.yyyy")) )" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Ошибка создания лога $logName : $_"
    }
}

$logFileCount = (Get-ChildItem -Path $logPathRoot -File -ErrorAction SilentlyContinue).Count
Write-Host "  Итого логов: $logFileCount" -ForegroundColor Green

Write-Host "`nГотово!" -ForegroundColor Green
Write-Host "Всего создано файлов для тестирования архивации и ротации логов." -ForegroundColor Cyan
