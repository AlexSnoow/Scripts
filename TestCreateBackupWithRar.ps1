<# file TestCreateBackupWithRar.ps1
<#
.SYNOPSIS
    Тестовый скрипт для модуля CreateBackupRAR

.DESCRIPTION
    Скрипт тестирует модуль архивации, создавая архивы для каждого файла
    в указанной папке и сохраняя логи в отдельную директорию.
    Готов для использования в рабочих скриптах.
#>

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
$sourceFolder = "C:\test\backup1"
$archiveFolder = "C:\test\rar"
$logFolder = "C:\test\logs"

# Проверка существования исходной папки
if (-not (Test-Path $sourceFolder)) {
    Write-Error "Исходная папка не найдена: $sourceFolder"
    exit 1
}

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

# Получение списка файлов для архивации
try {
    $filesToArchive = Get-ChildItem -Path $sourceFolder -File -ErrorAction Stop
}
catch {
    Write-Error "Не удалось получить список файлов из $sourceFolder : $($_.Exception.Message)"
    exit 1
}

if ($filesToArchive.Count -eq 0) {
    Write-Host "В папке $sourceFolder нет файлов для архивации." -ForegroundColor Yellow
    exit 0
}

Write-Host "Найдено файлов для архивации: $($filesToArchive.Count)" -ForegroundColor Green
Write-Host "Начинаем процесс архивации..."
Write-Host ""

# Счетчики для статистики
$successCount = 0
$errorCount = 0

# Архивация каждого файла
foreach ($file in $filesToArchive) {
    $archiveName = "backup_$($file.BaseName)_{Computer}_{DateTime}"
    $logName = "backup_$($file.BaseName)_{Computer}_{DateTime}_log.txt"
    
    Write-Host "Архивация файла: $($file.Name)"
    
    try {
        $result = BackupWithRAR `
            -RarPath "C:\Program Files\WinRAR\Rar.exe" `
            -SourcePath $file.FullName `
            -DestinationPath $archiveFolder `
            -ArchiveName $archiveName `
            -Keys "a -r -m0 -ep2" `
            -RarLogPath $logFolder `
            -RarLog $logName
        
        if ($result.Success) {
            Write-Host "? УСПЕХ: Файл $($file.Name) успешно заархивирован" -ForegroundColor Green
            Write-Host "   Архив: $($result.ArchivePath)" -ForegroundColor Gray
            
            # Проверяем существование архива перед получением размера
            if (Test-Path $result.ArchivePath) {
                $archiveSize = [math]::Round((Get-Item $result.ArchivePath).Length / 1MB, 2)
                Write-Host "   Размер: $archiveSize MB" -ForegroundColor Gray
            }
            
            $successCount++
        } else {
            Write-Host "? ОШИБКА: Не удалось заархивировать $($file.Name)" -ForegroundColor Red
            Write-Host "   Код ошибки: $($result.ExitCode)" -ForegroundColor Red
            Write-Host "   Описание: $($result.ErrorDescription)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host "   Лог: $($result.LogPath)" -ForegroundColor Gray
    }
    catch {
        Write-Host "? ИСКЛЮЧЕНИЕ: При архивации $($file.Name) возникла ошибка" -ForegroundColor Red
        Write-Host "   Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# Итоговая статистика
Write-Host "=" * 50
Write-Host "ИТОГИ АРХИВАЦИИ:" -ForegroundColor Cyan
Write-Host "Успешных операций: $successCount" -ForegroundColor Green
Write-Host "Ошибок: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Всего обработано файлов: $($filesToArchive.Count)" -ForegroundColor Cyan
Write-Host "Архивы сохранены в: $archiveFolder" -ForegroundColor Yellow
Write-Host "Логи сохранены в: $logFolder" -ForegroundColor Yellow
Write-Host "=" * 50

# Возвращаем код выхода в зависимости от наличия ошибок
if ($errorCount -gt 0) {
    exit 1
} else {
    exit 0
}