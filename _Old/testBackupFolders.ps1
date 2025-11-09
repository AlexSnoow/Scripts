<# file testBackupFolders.ps1
.SYNOPSIS
    Тестовый скрипт для архивирования нескольких папок с помощью модуля CreateBackupRAR

.DESCRIPTION
    Скрипт тестирует модуль архивации, создавая архивы для 4 указанных папок
    и сохраняя логи в отдельную директорию.
#>

# Устанавливаем кодировку вывода консоли в UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Определяем путь к модулю (предполагаем, что он в той же папке, что и скрипт)
$modulePath = Join-Path $PSScriptRoot "CreateBackupRAR.psm1"

# Проверяем существование модуля
if (-not (Test-Path $modulePath)) {
    Write-Error "Модуль не найден по пути: $modulePath"
    Write-Host "Убедитесь, что файл CreateBackupRAR.psm1 находится в той же папке, что и этот скрипт" -ForegroundColor Yellow
    exit 1
}

# Импорт модуля
try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "Модуль CreateBackupRAR успешно загружен" -ForegroundColor Green
}
catch {
    Write-Error "Не удалось загрузить модуль CreateBackupRAR: $($_.Exception.Message)"
    exit 1
}

# Определение путей
$archiveFolder = "C:\test\rar"
$logFolder = "C:\test\logs"

# Список папок для архивации
$foldersToArchive = @(
    "C:\test\backup1",
    "C:\test\backup2", 
    "C:\test\backup3",
    "C:\test\backup4"
)

# Проверка/создание папок для архивов и логов
foreach ($folder in $archiveFolder, $logFolder) {
    if (-not (Test-Path $folder)) {
        try {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Host "Создана папка: $folder" -ForegroundColor Yellow
        }
        catch {
            Write-Error "Не удалось создать папку $folder : $($_.Exception.Message)"
            exit 1
        }
    }
}

# Проверка существования исходных папок
$existingFolders = @()
foreach ($folder in $foldersToArchive) {
    if (Test-Path $folder -PathType Container) {
        $existingFolders += $folder
        Write-Host "Найдена папка для архивации: $folder" -ForegroundColor Green
    } else {
        Write-Host "Папка не найдена (будет пропущена): $folder" -ForegroundColor Yellow
    }
}

if ($existingFolders.Count -eq 0) {
    Write-Host "Не найдено ни одной папки для архивации." -ForegroundColor Yellow
    exit 0
}

Write-Host "Найдено папок для архивации: $($existingFolders.Count)" -ForegroundColor Green
Write-Host "Начинаем процесс архивации..."
Write-Host ""

# Счетчики для статистики
$successCount = 0
$errorCount = 0

# Архивация каждой папки
foreach ($folder in $existingFolders) {
    $folderName = Split-Path $folder -Leaf
    $archiveName = "backup_$($folderName)_{Computer}_{DateTime}"
    $logName = "backup_$($folderName)_{Computer}_{DateTime}_log.txt"
    
    Write-Host "Архивация папки: $folderName"
    
    try {
        $result = BackupWithRAR `
            -RarPath "C:\Program Files\WinRAR\Rar.exe" `
            -SourcePath $folder `
            -DestinationPath $archiveFolder `
            -ArchiveName $archiveName `
            -Keys "a -r -m5 -ep2" `
            -RarLogPath $logFolder `
            -RarLog $logName
        
        if ($result.Success) {
            Write-Host "? УСПЕХ: Папка $folderName успешно заархивирована" -ForegroundColor Green
            Write-Host "   Архив: $($result.ArchivePath)" -ForegroundColor Gray
            
            # Проверяем существование архива перед получением размера
            if (Test-Path $result.ArchivePath) {
                $archiveSize = [math]::Round((Get-Item $result.ArchivePath).Length / 1MB, 2)
                Write-Host "   Размер: $archiveSize MB" -ForegroundColor Gray
            }
            
            $successCount++
        } else {
            Write-Host "? ОШИБКА: Не удалось заархивировать папку $folderName" -ForegroundColor Red
            Write-Host "   Код ошибки: $($result.ExitCode)" -ForegroundColor Red
            Write-Host "   Описание: $($result.ErrorDescription)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host "   Лог: $($result.LogPath)" -ForegroundColor Gray
    }
    catch {
        Write-Host "? ИСКЛЮЧЕНИЕ: При архивации папки $folderName возникла ошибка" -ForegroundColor Red
        Write-Host "   Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# Итоговая статистика
Write-Host "=" * 50
Write-Host "ИТОГИ АРХИВАЦИИ ПАПОК:" -ForegroundColor Cyan
Write-Host "Успешных операций: $successCount" -ForegroundColor Green
Write-Host "Ошибок: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Всего обработано папок: $($existingFolders.Count)" -ForegroundColor Cyan
Write-Host "Архивы сохранены в: $archiveFolder" -ForegroundColor Yellow
Write-Host "Логи сохранены в: $logFolder" -ForegroundColor Yellow
Write-Host "=" * 50

# Возвращаем код выхода в зависимости от наличия ошибок
if ($errorCount -gt 0) {
    exit 1
} else {
    exit 0
}