<#
.SYNOPSIS
    Выполняет архивацию нескольких источников данных с помощью RAR

.DESCRIPTION
    Скрипт для пакетной архивации нескольких папок/файлов с индивидуальными настройками для каждого источника.

.PARAMETER ConfigPath
    Путь к JSON-файлу с конфигурацией архивации (опционально)

.EXAMPLE
    # Используя встроенную конфигурацию
    .\MultiBackup.ps1

.EXAMPLE
    # Используя внешний конфигурационный файл
    .\MultiBackup.ps1 -ConfigPath "C:\my_config.json"
.EXAMPLE
    #Настройте планировщик заданий для автоматического запуска:
    Program: powershell.exe
    Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\MultiBackup.ps1" -ConfigPath "C:\BackupConfigs\daily.json"

.NOTES
    Автор: Иванов
    Версия: 1.0 (2025-08-19)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

# Импорт функции архивации
try {
    . .\Create_Backup_rar.ps1
    Write-Host "Функция Backup-WithRAR успешно импортирована" -ForegroundColor Green
}
catch {
    Write-Error "Не удалось импортировать функцию Backup-WithRAR: $($_.Exception.Message)"
    exit 1
}

# Определение конфигурации архивации
$backupConfig = @(
    @{
        Name             = "Резервная копия веб-сайтов"
        SRC              = "C:\Websites"
        DST              = "D:\Backups\Web"
        ArchiveName      = "Websites-{datetime}"
        Keys             = "a -r -m5 -dh -ep1"
        ArchiveExtension = "rar"
        Enabled          = $true
    },
    @{
        Name             = "Резервная копия баз данных"
        SRC              = "C:\Databases"
        DST              = "D:\Backups\DB"
        ArchiveName      = "Databases-{date}"
        Keys             = "a -r -m3 -dh -ep2"
        ArchiveExtension = "rar"
        Enabled          = $true
    },
    @{
        Name             = "Резервная копия конфигураций"
        SRC              = "C:\Configs"
        DST              = "D:\Backups\Config"
        ArchiveName      = "Configs-{date}"
        Keys             = "a -r -m1"
        ArchiveExtension = "rar"
        Enabled          = $true
    },
    @{
        Name             = "Резервная копия логов"
        SRC              = "C:\Logs"
        DST              = "D:\Backups\Logs"
        ArchiveName      = "Logs-{date}"
        Keys             = "a -r -m1 -ed"
        ArchiveExtension = "rar"
        Enabled          = $true
    }
)

# Загрузка внешней конфигурации, если указана
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        $externalConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $backupConfig = $externalConfig
        Write-Host "Загружена внешняя конфигурация из: $ConfigPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Не удалось загрузить внешнюю конфигурацию. Используется встроенная."
    }
}

# Функция для проверки доступности источников
function Test-BackupSources {
    param($config)
    
    $results = @()
    foreach ($job in $config) {
        if (-not $job.Enabled) {
            $results += @{
                Name    = $job.Name
                Status  = "Skipped"
                Message = "Задание отключено в конфигурации"
            }
            continue
        }
        
        $sourceExists = Test-Path $job.SRC
        $destAccess = $true
        
        # Проверяем доступность папки назначения
        if (-not (Test-Path $job.DST)) {
            try {
                New-Item -ItemType Directory -Path $job.DST -Force -ErrorAction Stop | Out-Null
            }
            catch {
                $destAccess = $false
            }
        }
        
        $results += @{
            Name              = $job.Name
            SourceExists      = $sourceExists
            DestinationAccess = $destAccess
            Status            = if ($sourceExists -and $destAccess) { "Ready" } else { "Error" }
            Message           = if (-not $sourceExists) { "Источник не существует: $($job.SRC)" }
            elseif (-not $destAccess) { "Нет доступа к папке назначения: $($job.DST)" }
            else { "Готов к архивации" }
        }
    }
    
    return $results
}

# Основной процесс архивации
Write-Host "=== МНОГОПОТОЧНАЯ АРХИВАЦИЯ ===" -ForegroundColor Cyan
Write-Host "Начало: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host "Количество заданий: $(($backupConfig | Where-Object { $_.Enabled }).Count)"
Write-Host ""

# Проверка источников
Write-Host "Проверка источников данных..." -ForegroundColor Yellow
$checkResults = Test-BackupSources $backupConfig

foreach ($result in $checkResults) {
    $color = if ($result.Status -eq "Ready") { "Green" }
    elseif ($result.Status -eq "Skipped") { "Gray" }
    else { "Red" }
    
    Write-Host "[$($result.Status)] $($result.Name): $($result.Message)" -ForegroundColor $color
}

# Запрос подтверждения, если есть ошибки
$errorCount = ($checkResults | Where-Object { $_.Status -eq "Error" }).Count
if ($errorCount -gt 0) {
    $confirmation = Read-Host "Обнаружены проблемы с $errorCount источник(ами). Продолжить? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Архивация отменена пользователем" -ForegroundColor Yellow
        exit 0
    }
}

# Выполнение архивации
$results = @()
$successCount = 0
$failCount = 0

foreach ($job in $backupConfig) {
    if (-not $job.Enabled) {
        Write-Host "Пропускаем отключенное задание: $($job.Name)" -ForegroundColor Gray
        continue
    }
    
    Write-Host ""
    Write-Host "Обрабатывается: $($job.Name)" -ForegroundColor Cyan
    Write-Host "Источник: $($job.SRC)"
    Write-Host "Назначение: $($job.DST)"
    
    try {
        # Вызов функции архивации
        $result = Backup-WithRAR @job
        
        $status = if ($result -eq 0) { 
            $successCount++
            "Success" 
        }
        else { 
            $failCount++
            "Failed" 
        }
        
        $results += @{
            Name      = $job.Name
            Status    = $status
            ExitCode  = $result
            Timestamp = Get-Date
        }
        
        Write-Host "Результат: $status (Код: $result)" -ForegroundColor $(if ($result -eq 0) { "Green" } else { "Red" })
    }
    catch {
        $failCount++
        $results += @{
            Name         = $job.Name
            Status       = "Error"
            ExitCode     = -1
            ErrorMessage = $_.Exception.Message
            Timestamp    = Get-Date
        }
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Формирование отчета
Write-Host ""
Write-Host "=== РЕЗУЛЬТАТЫ АРХИВАЦИИ ===" -ForegroundColor Cyan
Write-Host "Завершено: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host "Успешно: $successCount" -ForegroundColor Green
Write-Host "С ошибками: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Задания с ошибками:" -ForegroundColor Red
    $results | Where-Object { $_.Status -ne "Success" } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Status)" -ForegroundColor Red
        if ($_.ErrorMessage) {
            Write-Host "    Ошибка: $($_.ErrorMessage)" -ForegroundColor Red
        }
    }
}

# Сохранение отчета в файл
$reportPath = "D:\Backups\backup_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
try {
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Отчет архивации</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .success { color: green; }
        .failed { color: red; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Отчет архивации</h1>
    <p>Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</p>
    <p>Успешно: $successCount</p>
    <p>С ошибками: $failCount</p>
    <table>
        <tr><th>Задание</th><th>Статус</th><th>Код выхода</th><th>Время</th></tr>
"@

    foreach ($result in $results) {
        $statusClass = if ($result.Status -eq "Success") { "success" } else { "failed" }
        $htmlReport += "<tr><td>$($result.Name)</td><td class='$statusClass'>$($result.Status)</td><td>$($result.ExitCode)</td><td>$($result.Timestamp)</td></tr>"
    }

    $htmlReport += @"
    </table>
</body>
</html>
"@

    $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Отчет сохранен: $reportPath" -ForegroundColor Green
}
catch {
    Write-Warning "Не удалось сохранить отчет: $($_.Exception.Message)"
}

# Завершение работы
if ($failCount -eq 0) {
    Write-Host "Все задания выполнены успешно!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Некоторые задания завершились с ошибками" -ForegroundColor Red
    exit 1
}