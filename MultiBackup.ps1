<# file MultiBackup.ps1
.SYNOPSIS
    Выполняет пакетную архивацию нескольких источников данных с индивидуальными настройками

.DESCRIPTION
    Скрипт-оркестратор для выполнения цепочки задач резервного копирования:
    1. Создание RAR-архивов через Create_Backup_Rar.ps1
    2. Копирование через Copy-Robocopy.ps1
    3. Очистка старых файлов через Remove-OldFiles.ps1
    4. Отправка уведомлений через Send-Mail.ps1

.PARAMETER ConfigPath
    Путь к JSON-файлу с конфигурацией задач (обязательный параметр).

.EXAMPLE
    # Использование конфигурационного файла
    .\MultiBackup.ps1 -ConfigPath "C:\BackupConfigs\daily.json"

.NOTES
    Автор: Системный администратор
    Версия: 2.1
    Дата: $(Get-Date -Format "yyyy-MM-dd")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "Конфигурационный файл не существует: $_"
        }
        if ((Get-Item $_).Extension -ne ".json") {
            throw "Файл конфигурации должен иметь расширение .json: $_"
        }
        $true
    })]
    [string]$ConfigPath
)

#region Инициализация
# Текущая директория скрипта
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Импорт необходимых скриптов
$ScriptsToImport = @(
    "Create_Backup_Rar.ps1",
    "Copy-Robocopy.ps1", 
    "Remove-OldFiles.ps1",
    "Send-Mail.ps1"
)

foreach ($script in $ScriptsToImport) {
    $scriptPath = Join-Path $ScriptDir $script
    if (Test-Path $scriptPath) {
        try {
            . $scriptPath
            Write-Verbose "Успешно импортирован скрипт: $script"
        }
        catch {
            Write-Error "Ошибка импорта скрипта $script : $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        Write-Warning "Скрипт $script не найден. Некоторые функции будут недоступны."
    }
}
#endregion

#region Загрузка конфигурации
try {
    Write-Verbose "Загрузка конфигурации из файла: $ConfigPath"
    $configData = Get-Content $ConfigPath -Raw -ErrorAction Stop
    $BackupConfig = $configData | ConvertFrom-Json -ErrorAction Stop
    
    # Проверка наличия хотя бы одной задачи
    if ($BackupConfig.Count -eq 0) {
        throw "Конфигурационный файл не содержит задач"
    }
    
    # Проверка структуры конфигурации
    $requiredProps = @("Enabled", "Name")
    foreach ($task in $BackupConfig) {
        foreach ($prop in $requiredProps) {
            if (-not $task.PSObject.Properties.Name.Contains($prop)) {
                throw "Задача '$($task.Name)' не содержит обязательное свойство: $prop"
            }
        }
    }
}
catch {
    Write-Error "Ошибка загрузки конфигурации: $($_.Exception.Message)"
    exit 1
}
#endregion

#region Вспомогательные функции
function Get-ParametersFromConfig {
    param(
        [PSCustomObject]$Config,
        [string]$Prefix
    )
    
    $params = @{}
    $Config.PSObject.Properties | Where-Object {
        $_.Name -like "$Prefix*" -and $_.Name -ne "${Prefix}Enabled"
    } | ForEach-Object {
        $paramName = $_.Name.Replace("${Prefix}_", "").Replace($Prefix, "")
        $params[$paramName] = $_.Value
    }
    
    return $params
}

function Invoke-BackupTask {
    param(
        [PSCustomObject]$TaskConfig
    )
    
    $taskResult = @{
        Name = $TaskConfig.Name
        Steps = @()
        StartTime = Get-Date
        EndTime = $null
        Success = $false
        ErrorMessage = $null
    }
    
    Write-Host "Параметры для Backup-WithRAR: $rarParams" -ForegroundColor Yellow

    Write-Host "Выполнение задачи: $($TaskConfig.Name)" -ForegroundColor Cyan
    
    try {
        # Шаг 1: Создание RAR-архива
        if ($TaskConfig["Create_Backup_Rar"] -eq $true) {
            Write-Host "  → Создание RAR-архива" -ForegroundColor Yellow
            $rarParams = Get-ParametersFromConfig -Config $TaskConfig -Prefix "Create_Backup_Rar"
            
            $stepResult = @{
                Name = "Create_Backup_Rar"
                StartTime = Get-Date
            }
            
            try {
                # Вызов функции из импортированного скрипта
                $result = Backup-WithRAR @rarParams
                $stepResult.Success = ($result -eq 0)
                $stepResult.Message = if ($result -eq 0) { "Успешно" } else { "Код ошибки: $result" }
                $stepResult.ExitCode = $result
            }
            catch {
                $stepResult.Success = $false
                $stepResult.Message = $_.Exception.Message
            }
            
            $stepResult.EndTime = Get-Date
            $taskResult.Steps += $stepResult
            
            if (-not $stepResult.Success) {
                throw "Ошибка создания архива: $($stepResult.Message)"
            }
        }
        
        # Шаг 2: Копирование Robocopy
        if ($TaskConfig["Copy-Robocopy"] -eq $true) {
            Write-Host "  → Копирование с помощью Robocopy" -ForegroundColor Yellow
            $robocopyParams = Get-ParametersFromConfig -Config $TaskConfig -Prefix "Copy-Robocopy"
            
            $stepResult = @{
                Name = "Copy-Robocopy"
                StartTime = Get-Date
            }
            
            try {
                # Вызов функции из импортированного скрипта
                Copy-Robocopy @robocopyParams
                $stepResult.Success = $true
                $stepResult.Message = "Успешно"
            }
            catch {
                $stepResult.Success = $false
                $stepResult.Message = $_.Exception.Message
            }
            
            $stepResult.EndTime = Get-Date
            $taskResult.Steps += $stepResult
            
            if (-not $stepResult.Success) {
                throw "Ошибка копирования: $($stepResult.Message)"
            }
        }
        
        # Шаг 3: Очистка старых файлов
        if ($TaskConfig["Remove-OldFiles"] -eq $true) {
            Write-Host "  → Очистка старых файлов" -ForegroundColor Yellow
            $cleanupParams = Get-ParametersFromConfig -Config $TaskConfig -Prefix "Remove-OldFiles"
            
            $stepResult = @{
                Name = "Remove-OldFiles"
                StartTime = Get-Date
            }
            
            try {
                # Вызов функции из импортированного скрипта
                Remove-OldFiles @cleanupParams
                $stepResult.Success = $true
                $stepResult.Message = "Успешно"
            }
            catch {
                $stepResult.Success = $false
                $stepResult.Message = $_.Exception.Message
            }
            
            $stepResult.EndTime = Get-Date
            $taskResult.Steps += $stepResult
            
            if (-not $stepResult.Success) {
                throw "Ошибка очистки файлов: $($stepResult.Message)"
            }
        }
        
        # Шаг 4: Отправка email
        if ($TaskConfig["Send-Mail"] -eq $true) {
            Write-Host "  → Отправка уведомления" -ForegroundColor Yellow
            $mailParams = Get-ParametersFromConfig -Config $TaskConfig -Prefix "Send-Mail"
            
            $stepResult = @{
                Name = "Send-Mail"
                StartTime = Get-Date
            }
            
            try {
                # Вызов функции из импортированного скрипта
                Send-Mail @mailParams
                $stepResult.Success = $true
                $stepResult.Message = "Успешно"
            }
            catch {
                $stepResult.Success = $false
                $stepResult.Message = $_.Exception.Message
            }
            
            $stepResult.EndTime = Get-Date
            $taskResult.Steps += $stepResult
        }
        
        $taskResult.Success = $true
        Write-Host "Задача завершена успешно: $($TaskConfig.Name)" -ForegroundColor Green
    }
    catch {
        $taskResult.Success = $false
        $taskResult.ErrorMessage = $_.Exception.Message
        Write-Host "Ошибка выполнения задачи: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        $taskResult.EndTime = Get-Date
    }
    
    return $taskResult
}
#endregion

#region Основной процесс
$startTime = Get-Date
Write-Host "=== ЗАПУСК MULTIBACKUP ===" -ForegroundColor Green
Write-Host "Время начала: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor White
Write-Host "Конфигурационный файл: $ConfigPath" -ForegroundColor White
Write-Host "Количество задач в конфигурации: $($BackupConfig.Count)" -ForegroundColor White
Write-Host ""

# Фильтруем только включенные задачи
$enabledTasks = $BackupConfig | Where-Object { $_.Enabled -eq $true }
Write-Host "Активных задач: $($enabledTasks.Count)" -ForegroundColor White

if ($enabledTasks.Count -eq 0) {
    Write-Host "Нет активных задач для выполнения. Завершение работы." -ForegroundColor Yellow
    exit 0
}

$results = @()
$successCount = 0
$failCount = 0

foreach ($task in $enabledTasks) {
    $result = Invoke-BackupTask -TaskConfig $task
    $results += $result
    
    if ($result.Success) {
        $successCount++
    }
    else {
        $failCount++
    }
    
    Write-Host ""
}
#endregion

#region Формирование отчета
Write-Host "=== РЕЗУЛЬТАТЫ ВЫПОЛНЕНИЯ ===" -ForegroundColor Cyan
Write-Host "Успешных задач: $successCount" -ForegroundColor Green
Write-Host "Неудачных задач: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "Общее время выполнения: $((Get-Date).Subtract($startTime).ToString('hh\:mm\:ss'))"

# Детальный отчет по задачам
foreach ($result in $results) {
    $color = if ($result.Success) { "Green" } else { "Red" }
    Write-Host "Задача: $($result.Name) - Status: $(if ($result.Success) {'Success'} else {'Failed'})" -ForegroundColor $color
    
    if (-not $result.Success) {
        Write-Host "  Ошибка: $($result.ErrorMessage)" -ForegroundColor Red
    }
    
    foreach ($step in $result.Steps) {
        $stepColor = if ($step.Success) { "Green" } else { "Red" }
        Write-Host "  → $($step.Name): $(if ($step.Success) {'Успешно'} else {'Ошибка'}) - $($step.Message)" -ForegroundColor $stepColor
    }
    Write-Host ""
}

# Сохранение отчета в файл
$reportDir = Join-Path $ScriptDir "Reports"
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$reportPath = Join-Path $reportDir "backup_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
try {
    $reportContent = @"
Отчет выполнения MultiBackup
Время формирования: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
Конфигурационный файл: $ConfigPath
Общее время выполнения: $((Get-Date).Subtract($startTime).ToString('hh\:mm\:ss'))
Успешных задач: $successCount
Неудачных задач: $failCount

Детализация:
"@

    foreach ($result in $results) {
        $status = if ($result.Success) { "УСПЕХ" } else { "ОШИБКА" }
        $reportContent += @"

ЗАДАЧА: $($result.Name)
СТАТУС: $status
ВРЕМЯ НАЧАЛА: $($result.StartTime)
ВРЕМЯ ЗАВЕРШЕНИЯ: $($result.EndTime)
"@
        
        if (-not $result.Success -and $result.ErrorMessage) {
            $reportContent += @"
ОШИБКА: $($result.ErrorMessage)
"@
        }
        
        foreach ($step in $result.Steps) {
            $stepStatus = if ($step.Success) { "Успешно" } else { "Ошибка" }
            $reportContent += @"
  - $($step.Name): $stepStatus ($($step.Message))
"@
        }
    }
    
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Подробный отчет сохранен: $reportPath" -ForegroundColor Green
}
catch {
    Write-Warning "Не удалось сохранить отчет: $($_.Exception.Message)"
}
#endregion

# Завершение
if ($failCount -eq 0) {
    Write-Host "Все задачи выполнены успешно!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Некоторые задачи завершились с ошибками" -ForegroundColor Red
    exit 1
}