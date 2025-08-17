# Путь для логов
$LogPath = "C:\Logs\Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$SourcePath = "C:\Source"
$DestinationPath = "\\Server\Backup\Destination"

# Запускаем транскрипт, чтобы залогировать весь вывод
Start-Transcript -Path $LogPath -Append

Write-Host "--- Starting backup process at $(Get-Date) ---"

try {
    # Запускаем Robocopy с необходимыми параметрами
    # /E - копировать все поддиректории, включая пустые
    # /Z - возобновляемый режим
    # /COPYALL - копировать все атрибуты, включая разрешения
    # /R:2 - 2 попытки при сбое копирования
    # /W:5 - 5 секунд ожидания между попытками
    # /LOG: - логирование в файл, который потом обработает PowerShell
    # /TEE - вывод в консоль
    # /NP - не показывать прогресс в процентах
    # /V - подробный вывод
    robocopy $SourcePath $DestinationPath /E /Z /COPYALL /R:2 /W:5 /LOG:$LogPath /TEE /NP /V

    # Проверяем код возврата Robocopy для определения успеха
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Backup completed successfully!" -ForegroundColor Green
    } elseif ($LASTEXITCODE -lt 8) {
        Write-Host "Backup completed with some non-critical issues (e.g., some files were skipped)." -ForegroundColor Yellow
    } else {
        throw "Robocopy failed with exit code $LASTEXITCODE."
    }

} catch {
    Write-Error "An error occurred: $_"
    # Здесь можно добавить логику для отправки уведомления об ошибке
} finally {
    Write-Host "--- Backup process finished at $(Get-Date) ---"
    # Останавливаем транскрипт
    Stop-Transcript
}
