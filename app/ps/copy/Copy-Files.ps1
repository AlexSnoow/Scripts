# PowerShell Script for File Copying and Verification based on Copy-Config.xml

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigurationPath
)

# --- Функции ---

function Verify-FileIntegrity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Source,
        [Parameter(Mandatory=$true)]
        [string]$Destination
    )
    Write-Host "   -> Проверка целостности файла..."
    # Используем SHA256 для сравнения хеш-сумм
    try {
        $SourceHash = Get-FileHash -Path $Source -Algorithm SHA256 | Select-Object -ExpandProperty Hash
        $DestHash = Get-FileHash -Path $Destination -Algorithm SHA256 | Select-Object -ExpandProperty Hash
        
        if ($SourceHash -eq $DestHash) {
            Write-Host "   -> [OK] Файл проверен успешно." -ForegroundColor Green
            return $true
        } else {
            Write-Host "   -> [FAIL] Хеш-суммы не совпадают. Файл поврежден." -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "   -> [ERROR] Не удалось проверить целостность файла: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Archive-File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceFile,
        [Parameter(Mandatory=$true)]
        [string]$ArchiveDest
    )
    Write-Host "   -> Архивирование и перемещение файла..."
    try {
        $FileName = Split-Path -Path $SourceFile -Leaf
        $TargetArchivePath = Join-Path -Path $ArchiveDest -ChildPath $FileName
        
        # Используем Move-Item для перемещения (или Copy-Item + Remove-Item, но Move проще)
        Move-Item -Path $SourceFile -Destination $TargetArchivePath -Force
        Write-Host "   -> [OK] Файл успешно перемещен в архив." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "   -> [ERROR] Не удалось переместить файл в архив: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}


# --- Основная логика ---
try {
    Write-Host "======================================================"
    Write-Host "Запуск скрипта копирования с конфигурации: $ConfigurationPath"
    Write-Host "======================================================"

    # 1. Загрузка XML конфигурации
    [xml]$config = Get-Content $ConfigurationPath -Encoding UTF8
    
    # Проверка наличия секции Jobs
    if (-not $config.CopyConfig.Jobs) {
        Write-Error "Конфигурация не содержит секции <Jobs>."
        exit 1
    }

    # 2. Итерация по всем заданиям (Jobs)
    foreach ($job in $config.CopyConfig.Jobs.Job) {
        $jobName = $job.Name
        $sourcePath = $job.Source
        $remoteDest = $job.RemoteDest
        $archivePath = $job.Arhive

        Write-Host "`n[ JOB: $jobName ]" -ForegroundColor Yellow
        Write-Host "  -> Источник: $sourcePath"
        Write-Host "  -> Цель: $remoteDest"
        Write-Host "  -> Архив: $archivePath"

        # Создание директорий, если они не существуют
        if (-not (Test-Path $remoteDest)) {
            Write-Host "  -> Создание целевого каталога: $remoteDest"
            New-Item -Path $remoteDest -ItemType Directory | Out-Null
        }
        if (-not (Test-Path $archivePath)) {
            Write-Host "  -> Создание каталога архива: $archivePath"
            New-Item -Path $archivePath -ItemType Directory | Out-Null
        }

        # Получение всех файлов в исходной директории
        # Используем Get-ChildItem для поиска файлов (исключаем папки)
        $itemsToCopy = Get-ChildItem -Path $sourcePath -File

        if ($itemsToCopy.Count -eq 0) {
            Write-Host "  -> В источнике $sourcePath нет файлов для копирования."
            continue
        }

        # 3. Обработка каждого файла
        foreach ($file in $itemsToCopy) {
            $fileName = $file.Name
            $sourceFilePath = $file.FullName
            $destinationFilePath = Join-Path -Path $remoteDest -ChildPath $fileName
            
            Write-Host "`n  --- Обработка файла: $fileName ---"

            # Копирование
            Write-Host "  -> Попытка копирования..."
            try {
                Copy-Item -Path $sourceFilePath -Destination $destinationFilePath -Force
            }
            catch {
                Write-Host "  -> [FAIL] Ошибка при копировании: $($_.Exception.Message)" -ForegroundColor Red
                continue # Переходим к следующему файлу, если копирование не удалось
            }

            # Проверка целостности
            $integrityCheck = Verify-FileIntegrity -Source $sourceFilePath -Destination $destinationFilePath

            # Постоперации: Перенос в архив при успехе
            if ($integrityCheck) {
                Write-Host "  -> Успешное копирование и проверка. Запуск архивации..."
                Archive-File -SourceFile $sourceFilePath -ArchiveDest $archivePath
            }
        }
    }

    Write-Host "`n======================================================"
    Write-Host "ВСЕ ЗАДАНИЯ ЗАВЕРШЕНЫ." -ForegroundColor Cyan
    Write-Host "======================================================"

} catch {
    Write-Error "`nКРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)"
}