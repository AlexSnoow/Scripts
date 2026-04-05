<#
.SYNOPSIS
    Модуль для ротации старых файлов резервных копий.
.DESCRIPTION
    Предоставляет функцию для удаления старых файлов в указанной директории на основе их возраста и/или количества.
.EXAMPLE
    # Удалить все файлы старше 30 дней, но оставить 5 самых новых
    Remove-OldBackups -Path "D:\backups" -DaysToKeep 30 -FilesToKeep 5
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function Remove-OldBackups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$DaysToKeep,

        [Parameter(Mandatory = $true)]
        [int]$FilesToKeep
    )

    try {
        $allFiles = Get-ChildItem -Path $Path -File | Sort-Object -Property LastWriteTime -Descending
        $filesToDelete = @()

        if ($allFiles.Count -le $FilesToKeep) {
            Write-Host "Количество файлов ($($allFiles.Count)) меньше или равно количеству для сохранения ($FilesToKeep). Удаление не требуется."
            return
        }

        # Отбираем файлы, которые точно нужно оставить

        # Из остальных выбираем те, что старше нужного количества дней
        $filesForDateCheck = $allFiles | Select-Object -Skip $FilesToKeep
        $cutOffDate = (Get-Date).AddDays(-$DaysToKeep)

        foreach ($file in $filesForDateCheck) {
            if ($file.LastWriteTime -lt $cutOffDate) {
                $filesToDelete += $file
            }
        }

        if ($filesToDelete.Count -eq 0) {
            Write-Host "Нет файлов для удаления по указанным критериям."
            return
        }

        Write-Host "Следующие файлы будут удалены:"
        $filesToDelete | ForEach-Object { Write-Host "- $($_.FullName)" }

        $filesToDelete | Remove-Item -Force -ErrorAction Stop

        Write-Host "Ротация старых бэкапов успешно завершена. Удалено $($filesToDelete.Count) файлов." -ForegroundColor Green
    }
    catch {
        Write-Error "Ошибка при ротации старых бэкапов: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Remove-OldBackups