<#
.SYNOPSIS
    Модуль управления ротацией файлов
.DESCRIPTION
    Предоставляет функцию для ротации файлов по возрасту и количеству
#>

function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3650)]
        [int]$DaysOld,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 1000)]
        [int]$KeepCount,
        
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    Write-Log "Ротация файлов: $Path (DaysOld: $DaysOld, KeepCount: $KeepCount, Filter: $Filter)"

    if (-not (Test-Path -Path $Path -PathType Container)) {
        $errorMsg = "Директория $Path не существует"
        Write-Log $errorMsg
        throw $errorMsg
    }

    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
        $allFiles = @(Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
        
        if ($allFiles.Count -eq 0) {
            Write-Log "Нет файлов для обработки"
            return @{ TotalFiles = 0; FilesDeleted = 0; FilesKept = 0 }
        }

        Write-Log "Найдено файлов: $($allFiles.Count)"

        # Сохраняем самые новые файлы
        $filesToKeep = if ($KeepCount -gt 0) { $allFiles | Select-Object -First $KeepCount } else { @() }

        # Формируем список для удаления
        $filesToDelete = $allFiles | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and
            $filesToKeep.FullName -notcontains $_.FullName
        }

        $deletedCount = 0
        
        # Удаление
        if ($filesToDelete.Count -gt 0) {
            Write-Log "Файлов для удаления: $($filesToDelete.Count)"
            
            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Удаление файла")) {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    Write-Log "Удален: $($file.Name)"
                }
            }
        } 
        else {
            Write-Log "Нет файлов для удаления"
        }
        
        $keptCount = $allFiles.Count - $deletedCount
        Write-Log "Сохранено файлов: $keptCount"
        
        return @{
            TotalFiles = $allFiles.Count
            FilesDeleted = $deletedCount
            FilesKept = $keptCount
        }
    }
    catch {
        $errorMsg = "Ошибка ротации файлов: $_"
        Write-Log $errorMsg
        throw $errorMsg
    }
}

Export-ModuleMember -Function Remove-OldFiles