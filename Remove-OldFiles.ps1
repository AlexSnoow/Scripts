function Remove-OldFiles {
    <#
    .SYNOPSIS
    Удаляет файлы старше указанного возраста, сохраняя минимальное количество последних файлов.
    
    .DESCRIPTION
    Скрипт удаляет файлы в указанной директории, которые старше заданного количества дней,
    но всегда сохраняет минимальное количество самых новых файлов (даже если они просрочены).
    
    .PARAMETER Path
    Путь к целевой директории
    
    .PARAMETER DaysOld
    Максимальный возраст файлов в днях (по умолчанию 30)
    
    .PARAMETER KeepCount
    Минимальное количество файлов для сохранения (по умолчанию 5)
    
    .EXAMPLE
    Remove-OldFiles -Path "C:\Logs" -DaysOld 30 -KeepCount 10
    
    .NOTES
    Версия: 1.1 (15.08.2025)
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [ValidateRange(1, 3650)]
        [int]$DaysOld = 30,
        
        [ValidateRange(1, 1000)]
        [int]$KeepCount = 5
    )

    # Проверка существования директории
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "Директория $Path не существует или недоступна"
        return
    }

    try {
        # Рассчет пороговой даты
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        
        # Получение всех файлов в директории
        $allFiles = @(Get-ChildItem -Path $Path -File -ErrorAction Stop)
        
        # Проверка наличия файлов
        if ($allFiles.Count -eq 0) {
            Write-Host "В директории нет файлов для обработки"
            return
        }

        # Разделение файлов на группы
        $expiredFiles = $allFiles | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        $validFiles = $allFiles | Where-Object { $_.LastWriteTime -ge $cutoffDate }

        # Определение файлов для удаления с учетом минимального количества
        $filesToDelete = if ($expiredFiles.Count -gt $KeepCount) {
            $expiredFiles | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -Skip $KeepCount
        } else {
            @()
        }

        # Удаление файлов с подтверждением
        if ($filesToDelete.Count -gt 0) {
            Write-Host "Найдено файлов для удаления: $($filesToDelete.Count)"
            
            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Удаление файла")) {
                    Remove-Item $file.FullName -Force -ErrorAction Continue
                }
            }
            
            Write-Host "Удалено файлов: $($filesToDelete.Count)"
            Write-Host "Сохранено файлов: $($allFiles.Count - $filesToDelete.Count)"
        } else {
            Write-Host "Нет файлов для удаления. Сохранено файлов: $($allFiles.Count)"
        }
    }
    catch {
        Write-Error "Ошибка при обработке файлов: $_"
    }
}
