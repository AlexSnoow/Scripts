<#
.SYNOPSIS
    Основной скрипт резервного копирования
.DESCRIPTION
    Использует модули для выполнения резервного копирования и обслуживания
#>

#region Импорт модулей
try {
    Import-Module "$PSScriptRoot\Backup-Logger.psm1" -Force
    Import-Module "$PSScriptRoot\Backup-Config.psm1" -Force
    Import-Module "$PSScriptRoot\Backup-RAR.psm1" -Force
    Import-Module "$PSScriptRoot\Backup-Maintenance.psm1" -Force
}
catch {
    Write-Error "Ошибка загрузки модулей: $_"
    exit 1
}
#endregion

#region Инициализация
$scriptStartTime = Get-Date
$config = Get-BackupConfiguration

# Проверка конфигурации
$configTest = Test-Configuration
if (-not $configTest.IsValid) {
    Write-Error "Ошибки в конфигурации:`n$($configTest.Errors -join "`n")"
    exit 1
}

# Инициализация логирования
try {
    Initialize-Logging -LogPath $config.Settings.LogPath -PCName $config.Settings.PCName -JobName $config.Settings.JobName
}
catch {
    Write-Error $_
    exit 1
}

Write-LogSection "ЗАПУСК СКРИПТА РЕЗЕРВНОГО КОПИРОВАНИЯ"
Write-Log "Компьютер: $($config.Settings.PCName)"
Write-Log "Время запуска: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Количество заданий: $($config.Jobs.Count)"
#endregion

#region Основной цикл выполнения
$results = @{}
$successCount = 0
$errorCount = 0

foreach ($jobName in $config.Jobs.Keys) {
    $job = $config.Jobs[$jobName]
    $jobStart = Get-Date
    
    Write-LogSection "ОБРАБОТКА ЗАДАНИЯ: $jobName"
    Write-Log "Источник: $($job.Source)"
    Write-Log "Локальное назначение: $($job.LocalDest)"
    Write-Log "Сетевое назначение: $($job.RemoteDest)"
    Write-Log "Имя архива: $($job.Archive)"
    
    try {
        # Проверка и подготовка путей
        if (-not (Test-Path $job.Source)) {
            throw "Источник не существует: $($job.Source)"
        }
        
        if (-not (Test-Path $job.LocalDest)) {
            New-Item -Path $job.LocalDest -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Создана локальная папка: $($job.LocalDest)"
        }
        
        # Анализ исходных файлов
        $fileInfo = Get-FileInfoDetails -Path $job.Source
        Write-Log "Найдено файлов: $($fileInfo.FileCount)"
        Write-Log "Общий размер: $($fileInfo.TotalSizeMB) MB"
        
        if ($fileInfo.FileCount -eq 0) {
            Write-Log "Предупреждение: В источнике нет файлов для архивации"
        }
        
        # Архивация
        $archivePath = Join-Path $job.LocalDest $job.Archive
        $rarResult = Start-RarArchive -RarPath $config.Settings.RarPath -ArchivePath $archivePath -SourcePath "$($job.Source)*"
        
        Write-Log "Архивация завершена за $($rarResult.Duration) минут"
        Write-Log "Код возврата RAR: $($rarResult.ExitCode)"
        
        if ($rarResult.ExitCode -ne 0) {
            $errorDescription = Get-RarExitCodeMeaning -ExitCode $rarResult.ExitCode
            throw "Ошибка RAR: $errorDescription"
        }
        
        if (-not (Test-Path $archivePath)) {
            throw "Архив не создан: $archivePath"
        }
        
        $archiveSize = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-Log "Архив создан успешно. Размер: $archiveSize MB"
        
        # Проверка целостности
        $testResult = Test-RarArchive -RarPath $config.Settings.RarPath -ArchivePath $archivePath
        if (-not $testResult.IsValid) {
            $testError = Get-RarExitCodeMeaning -ExitCode $testResult.ExitCode
            throw "Ошибка проверки целостности: $testError"
        }
        Write-Log "Проверка целостности пройдена успешно"
        
        # Копирование в сетевую папку
        $remoteAccessible = $false
        if ($job.RemoteDest -and (Test-Path $job.RemoteDest)) {
            $remoteAccessible = $true
            Write-Log "Копирование в сетевую папку: $($job.RemoteDest)"
            
            $remotePath = Join-Path $job.RemoteDest $job.Archive
            $copyResult = Copy-BackupFile -SourcePath $archivePath -DestinationPath $remotePath
            
            if ($copyResult.Success) {
                Write-Log "Копирование завершено успешно за $($copyResult.Duration) секунд"
                
                # Удаление локальной копии с использованием модуля обслуживания
                Write-Log "Удаление локальной копии архива..."
                try {
                    
                    Remove-OldFiles -Path $job.LocalDest -DaysOld 0 -KeepCount 2 -Filter "*.*"
                    Write-Log "Локальная копия успешно удалена"
                }
                catch {
                    Write-Log "Ошибка при удалении локальной копии: $_"
                    # Не считаем это критической ошибкой
                }
                
                $results[$jobName] = "Успешно (скопировано в сеть)"
                $successCount++
            }
            else {
                throw "Размеры файлов не совпадают после копирования"
            }
        }
        else {
            Write-Log "Сетевая папка недоступна, архив сохранен локально"
            $results[$jobName] = "Успешно (только локально)"
            $successCount++
        }
    }
    catch {
        Write-Log "ОШИБКА: $_"
        Write-Log "Стек вызовов: $($_.ScriptStackTrace)"
        $results[$jobName] = "Ошибка: $_"
        $errorCount++
    }
    
    $jobEnd = Get-Date
    $jobDuration = [math]::Round(($jobEnd - $jobStart).TotalMinutes, 2)
    Write-Log "Задание завершено за $jobDuration минут"
    Write-Log "Результат: $($results[$jobName])"
}
#endregion

#region Очистка старых Логов
Write-LogSection "ЗАПУСК ОЧИСТКИ СТАРЫХ Логов"

try {
    Remove-OldFiles -Path $config.Settings.LogPath -DaysOld 0 -KeepCount 2 -Filter "*.*"

    Write-Log "Очистка завершена успешно"
}
catch {
    Write-Log "Ошибка при выполнении очистки: $_"
    # Не считаем это критической ошибкой основного процесса
}
#endregion

#region Финальные результаты
$scriptEndTime = Get-Date
$totalDuration = [math]::Round(($scriptEndTime - $scriptStartTime).TotalMinutes, 2)

Write-LogSection "ФИНАЛЬНЫЕ РЕЗУЛЬТАТЫ"
Write-Log "Общее время выполнения: $totalDuration минут"
Write-Log "Успешных заданий: $successCount"
Write-Log "Заданий с ошибками: $errorCount"

foreach ($jobName in $results.Keys) {
    Write-Log "  $jobName : $($results[$jobName])"
}

if ($errorCount -gt 0) {
    Write-Log "СКРИПТ ЗАВЕРШЕН С ОШИБКАМИ"
    exit 1
} else {
    Write-Log "СКРИПТ ЗАВЕРШЕН УСПЕШНО"
    exit 0
}
#endregion