<# file Remove-OldFiles.ps1
.SYNOPSIS
Управляет хранением файлов по сроку давности

.DESCRIPTION
Функция для автоматической очистки старых файлов с гарантией сохранения 
минимального количества последних версий. Поддерживает подтверждение операций.

.PARAMETER Path
Целевая директория (обязательный)

.PARAMETER DaysOld
Максимальный возраст файлов в днях (1-3650)

.PARAMETER KeepCount
Минимальное количество сохраняемых файлов (1-1000)

.EXAMPLE
    Загрузить функцию в сессию
    . C:\Scripts\Remove-OldFiles.ps1
    Вызов функции
    Remove-OldFiles -Path "D:\Backups" -DaysOld 180
    Удалить файлы старше 6 месяцев, сохранив по умолчанию 5 последних

.EXAMPLE
    Remove-OldFiles -Path "C:\Logs" -KeepCount 10 -WhatIf
    Тестовый запуск: показать какие файлы будут удалены без реального удаления

.EXAMPLE
    Вызов из другого скрипта
    # Скрипт MainScript.ps1
    try {
        # Импорт функции
        . "C:\Scripts\Remove-OldFiles.ps1"
    
        # Вызов с параметрами
        Remove-OldFiles -Path "E:\AppLogs" -DaysOld 90 -KeepCount 3
    
        Write-Host "Очистка завершена успешно"
    }
    catch {
        Write-Error "Ошибка: $_"
    }

.NOTES
Автор: Иванов
Версия: 1.0 (2025-08-18)
#>

function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [ValidateRange(1, 3650)]
        [int]$DaysOld = 30,
        
        [ValidateRange(1, 1000)]
        [int]$KeepCount = 5
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "Директория $Path не существует или недоступна"
        return
    }

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $allFiles = @(Get-ChildItem -Path $Path -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
        
        if ($allFiles.Count -eq 0) {
            Write-Host "В директории нет файлов для обработки"
            return
        }

        # 1. Сохраняем TOP-$KeepCount самых новых файлов (ВСЕГДА)
        $filesToKeep = $allFiles | Select-Object -First $KeepCount

        # 2. Формируем список для удаления:
        #   - Файлы старше $cutoffDate
        #   - Исключаем файлы из $filesToKeep
        $filesToDelete = $allFiles | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and
            $filesToKeep.FullName -notcontains $_.FullName
        }

        # Удаление с подтверждением
        if ($filesToDelete.Count -gt 0) {
            Write-Host "Найдено файлов для удаления: $($filesToDelete.Count)"
            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Удаление файла")) {
                    Remove-Item $file.FullName -Force -ErrorAction Continue
                }
            }
            Write-Host "Удалено файлов: $($filesToDelete.Count)"
        }
        else {
            Write-Host "Нет файлов для удаления"
        }
        
        # Общая статистика
        Write-Host "Сохранено файлов: $($allFiles.Count - $filesToDelete.Count)"
    }
    catch {
        Write-Error "Ошибка при обработке файлов: $_"
    }
}