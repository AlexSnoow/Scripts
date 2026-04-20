<#
.SYNOPSIS
    Генератор тестовых файлов на основе XML-конфигурации.

.DESCRIPTION
    Читает пути источников из Backup-Config-All.xml.
    Для каждого задания:
    1. Пытается загрузить список имён из файла jobN.txt
    2. Если файла нет — генерирует файлы автоматически на основе типа задания:
       - Задания с SourceCheckMasks → файлы под каждую маску
       - Задания с ArchiveIndividualFolders → подпапки с файлами
       - Задания с ArchiveIndividualFiles → файлы по маске FileFilter
       - Обычные задания → generic файлы (.dat)

    Поддерживает:
    - Разные даты модификации для тестирования ротации
    - Очистку директории перед созданием (-Clear)
    - Создание тестовых подпапок для индивидуальной архивации
    - Создание тестовых архивов в LocalDest для проверки ротации
    - Создание тестовых логов в LogPathRoot

    Формат текстового файла (job1.txt):
    Каждая строка — имя файла (можно с маской/расширением):
        report.xml
        data_001.dat
        ADV_log_2024.log
    Пустые строки и строки начинающиеся с # игнорируются.

.PARAMETER ConfigPath
    Путь к XML конфигурации. По умолчанию: .\Backup-Config-All.xml

.PARAMETER ListDir
    Директория с текстовыми файлами списков имён.
    По умолчанию: та же директория, что и скрипт.
    Имя файла списка: <имя_задания_из_xml>.txt (регистр не важен).

.PARAMETER DaysBack
    Количество дней назад для создания файлов с разными датами. По умолчанию: 14.

.PARAMETER FilesPerDay
    Сколько файлов создавать для каждой даты. По умолчанию: 2.

.PARAMETER JobName
    Имя задания из конфигурации. Если не указано — обрабатываются все задания.

.PARAMETER Clear
    Очистить директории (Source, LocalDest, LogPathRoot) перед созданием файлов.

.PARAMETER SkipArchives
    Не создавать тестовые архивы в LocalDest.

.PARAMETER SkipLogs
    Не создавать тестовые логи в LogPathRoot.

.EXAMPLE
    .\Create-Test-Files-FromList.ps1
    Создание тестовых данных для всех 21 задания.

.EXAMPLE
    .\Create-Test-Files-FromList.ps1 -JobName JOB1 -DaysBack 7 -Clear
    Очистить и создать 7 дней файлов для JOB1.

.EXAMPLE
    .\Create-Test-Files-FromList.ps1 -SkipArchives -SkipLogs
    Только файлы источников, без архивов и логов.
#>

param(
    [string]$ConfigPath = ".\Backup-Config-All.xml",
    [string]$ListDir = "",
    [int]$DaysBack = 14,
    [int]$FilesPerDay = 2,
    [string[]]$JobName,
    [switch]$Clear,
    [switch]$SkipArchives,
    [switch]$SkipLogs
)

$Script:ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if ([string]::IsNullOrEmpty($ListDir)) { $ListDir = $Script:ScriptDir }

# ===========================================================
# Загрузка XML конфигурации
# ===========================================================
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Файл конфигурации не найден: $ConfigPath"
    exit 1
}

try {
    [xml]$xmlDoc = Get-Content $ConfigPath -Encoding UTF8
    Write-Host "Конфигурация загружена: $ConfigPath" -ForegroundColor Green
}
catch {
    Write-Error "Ошибка парсинга XML: $_"
    exit 1
}

$b = $xmlDoc.BackupConfig
$PCName = $env:COMPUTERNAME

# ===========================================================
# Загрузка списка имён файлов из текстового файла
# ===========================================================
function Get-FileNamesFromList {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return @() }
    $names = @()
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrEmpty($line)) { return }
        if ($line.StartsWith('#')) { return }
        $names += $line
    }
    return $names
}

# ===========================================================
# Генерация тестовых файлов из XML-конфигурации (fallback)
# ===========================================================
function Generate-TestFilesFromXml {
    param([hashtable]$job, [string]$Path, [int]$DaysBack, [int]$FilesPerDay)

    $count = 0

    # 1) Задание с SourceCheckMasks — файлы под каждую маску (JOB1, JOB2)
    if ($job.SourceCheckMasks -and $job.SourceCheckMasks.Count -gt 0) {
        Write-Host "  Генерация по маскам SourceCheckMasks: $($job.SourceCheckMasks.Count) шт." -ForegroundColor DarkGray
        foreach ($mask in $job.SourceCheckMasks) {
            $ext = [System.IO.Path]::GetExtension($mask)
            if ([string]::IsNullOrEmpty($ext)) { $ext = '.dat' }
            $prefix = ($mask -replace '\*', '').TrimStart('*_')
            if ([string]::IsNullOrEmpty($prefix)) { $prefix = 'data' }

            for ($i = 0; $i -lt $DaysBack; $i++) {
                $fileDate = (Get-Date).AddDays(-$i).Date
                $dateNum = $fileDate.ToString('yyyyMMdd')
                for ($f = 0; $f -lt $FilesPerDay; $f++) {
                    $suffix = "{0:D2}" -f ($f + 1)
                    $fileName = "${prefix}_${dateNum}_${suffix}${ext}"
                    try { New-TestFile -Path $Path -FileName $fileName -Date $fileDate | Out-Null; $count++ } catch {}
                }
            }
        }
        return $count
    }

    # 2) Задание с FileFilter — файлы по маске (JOB14,15,20,21)
    if (-not [string]::IsNullOrEmpty($job.FileFilter)) {
        $filter = $job.FileFilter
        $ext = [System.IO.Path]::GetExtension($filter)
        if ([string]::IsNullOrEmpty($ext)) { $ext = '.log' }
        $prefix = [System.IO.Path]::GetFileNameWithoutExtension($filter) -replace '\*', ''
        if ([string]::IsNullOrEmpty($prefix)) { $prefix = 'log' }

        Write-Host "  Генерация по маске FileFilter: $filter" -ForegroundColor DarkGray
        for ($i = 1; $i -le $DaysBack; $i++) {
            $fd = (Get-Date).AddDays(-$i)
            $fileDate = $fd.Date
            $dateNum = "{0:D4}{1:D2}" -f ($fd.Year % 100), $fd.Month
            for ($f = 0; $f -lt $FilesPerDay; $f++) {
                $suffix = "{0:D2}" -f ($f + 1)
                $fileName = "${prefix}${dateNum}_${suffix}${ext}"
                try { New-TestFile -Path $Path -FileName $fileName -Date $fileDate | Out-Null; $count++ } catch {}
            }
        }

        # Создаём исключённый файл (fxserver.log, info.log)
        if (-not [string]::IsNullOrEmpty($job.ExcludeFilePattern)) {
            Write-Host "  Исключённый файл (НЕ будет удалён): $($job.ExcludeFilePattern)" -ForegroundColor Yellow
            New-TestFile -Path $Path -FileName $job.ExcludeFilePattern -Date (Get-Date) | Out-Null
            $count++
        }
        return $count
    }

    # 3) Обычное задание — generic файлы (JOB3,4,5)
    Write-Host "  Генерация generic файлов" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $DaysBack; $i++) {
        $fileDate = (Get-Date).AddDays(-$i).Date
        $dateNum = $fileDate.ToString('yyyyMMdd')
        for ($f = 0; $f -lt $FilesPerDay; $f++) {
            $suffix = "{0:D2}" -f ($f + 1)
            $fileName = "data_${dateNum}_${suffix}.dat"
            try { New-TestFile -Path $Path -FileName $fileName -Date $fileDate | Out-Null; $count++ } catch {}
        }
    }
    return $count
}

# ===========================================================
# Создание тестового файла
# ===========================================================
function New-TestFile {
    param([string]$Path, [string]$FileName, [DateTime]$Date)
    $fullPath = Join-Path $Path $FileName
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $Content = "Test file for backup verification`r`nName: $FileName`r`nDate: $($Date.ToString('yyyy-MM-dd'))"
    Set-Content -Path $fullPath -Value $Content -Encoding UTF8 -Force
    (Get-Item $fullPath).LastWriteTime = $Date
    (Get-Item $fullPath).CreationTime = $Date
    return $fullPath
}

function Clear-TestDirectory {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Host "  Очистка: $Path" -ForegroundColor Yellow
        Get-ChildItem -Path $Path -File -Force | Remove-Item -Force
        Get-ChildItem -Path $Path -Directory -Force | Remove-Item -Recurse -Force
    }
}

# ===========================================================
# Загрузка всех заданий с дополнительными полями
# ===========================================================
$allJobs = @()
foreach ($jobNode in $b.Jobs.Job) {
    $job = @{
        Name                     = $jobNode.Name
        Source                   = $jobNode.Source
        LocalDest                = $jobNode.LocalDest
        RemoteDest               = $jobNode.RemoteDest
        LocalDestDaysOld         = [int]$jobNode.LocalDestDaysOld
        LocalDestKeepCount       = [int]$jobNode.LocalDestKeepCount
        ArhLog                   = ($jobNode.ArhLog -eq 'true')
        ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
        SourceFilter             = $jobNode.SourceFilter
        RemoveSourceFlag         = ($jobNode.RemoveSourceFlag -eq 'true')
    }

    # ArchiveIndividualFiles + FileFilter (JOB14,15,20,21)
    if ($jobNode.ArchiveIndividualFiles) {
        $job['ArchiveIndividualFiles'] = ($jobNode.ArchiveIndividualFiles -eq 'true')
    }
    else {
        $job['ArchiveIndividualFiles'] = $false
    }
    if ($jobNode.FileFilter) { $job['FileFilter'] = $jobNode.FileFilter }
    if ($jobNode.ExcludeFilePattern) { $job['ExcludeFilePattern'] = $jobNode.ExcludeFilePattern }
    if ($jobNode.IndividualArchivePattern) { $job['IndividualArchivePattern'] = $jobNode.IndividualArchivePattern }
    if ($jobNode.ExcludeFolderPattern) { $job['ExcludeFolderPattern'] = $jobNode.ExcludeFolderPattern }

    # SourceCheckMasks
    if ($jobNode.SourceCheckMasks) {
        $masks = @()
        foreach ($m in $jobNode.SourceCheckMasks.Mask) { $masks += $m }
        $job['SourceCheckMasks'] = $masks
    }

    # ArhParameters
    if ($jobNode.ArhParameters) {
        $arhParams = @()
        foreach ($p in $jobNode.ArhParameters.Param) { $arhParams += $p }
        $job['ArhParameters'] = $arhParams
    }

    $allJobs += $job
}

$jobsToProcess = if ($JobName) {
    $allJobs | Where-Object { $JobName -contains $_.Name }
}
else {
    $allJobs
}

if ($jobsToProcess.Count -eq 0) {
    Write-Warning "Задания для обработки не найдены."
    exit 0
}

# ===========================================================
# Основная обработка
# ===========================================================
Write-Host "`nНачало создания тестовых файлов..." -ForegroundColor Cyan
Write-Host "Дней назад: $DaysBack, Файлов в день: $FilesPerDay" -ForegroundColor Cyan
Write-Host "Директория списков: $ListDir`n" -ForegroundColor Cyan

$totalFilesCreated = 0

# Helper: создание файлов с датами
function Create-FilesWithDates {
    param([string]$Path, [string[]]$Names, [int]$DaysBack, [int]$FilesPerDay, [switch]$AddSuffix)
    $count = 0
    foreach ($baseName in $Names) {
        for ($d = 0; $d -lt $DaysBack; $d++) {
            $fileDate = (Get-Date).AddDays(-$d).Date
            if ($FilesPerDay -gt 1) {
                for ($f = 0; $f -lt $FilesPerDay; $f++) {
                    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
                    $ext = [System.IO.Path]::GetExtension($baseName)
                    $suffix = "{0:D2}" -f ($f + 1)
                    $fileName = "${nameWithoutExt}_${suffix}${ext}"
                    try { New-TestFile -Path $Path -FileName $fileName -Date $fileDate | Out-Null; $count++ } catch {}
                }
            }
            else {
                try { New-TestFile -Path $Path -FileName $baseName -Date $fileDate | Out-Null; $count++ } catch {}
            }
        }
    }
    return $count
}

foreach ($job in $jobsToProcess) {
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "[ $($job.Name) ]" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    $sourcePath = $job.Source

    # Создание директории
    if (-not (Test-Path $sourcePath)) {
        Write-Host "  Создание: $sourcePath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    }

    # Очистка
    if ($Clear) { Clear-TestDirectory -Path $sourcePath }

    $createdCount = 0

    # === Определяем тип задания ===
    $isIndividualFolders = $job.ArchiveIndividualFolders
    $isIndividualFiles = $job.ArchiveIndividualFiles

    if ($isIndividualFolders) {
        # --------------------------------------------------
        # ТИП А: Индивидуальная архивация каталогов (JOB6-13,16-19)
        # --------------------------------------------------
        Write-Host "  Тип: Индивидуальная архивация каталогов" -ForegroundColor Gray

        # Подпапки с датами (включая "today" для проверки исключения)
        $todayDate = Get-Date -Format 'yyyyMMdd'
        $subfolders = @()
        # Папки с датами — только дата в имени!
        foreach ($d in 0, 1, 3, 5, 7) {
            $folderDate = (Get-Date).AddDays(-$d).ToString('yyyyMMdd')
            $subfolders += $folderDate
        }
        # Папка "today" для проверки исключения
        $subfolders += $todayDate

        Write-Host "  Подпапки: $($subfolders.Count) шт." -ForegroundColor Gray
        foreach ($subfolder in $subfolders) {
            $subPath = Join-Path $sourcePath $subfolder
            if (-not (Test-Path $subPath)) {
                New-Item -ItemType Directory -Path $subPath -Force | Out-Null
            }

            # Пытаемся загрузить список имён
            $listFileName = ($job.Name).ToLower() + ".txt"
            $listFilePath = Join-Path $ListDir $listFileName
            $fileNames = Get-FileNamesFromList -FilePath $listFilePath

            if ($fileNames.Count -gt 0) {
                Write-Host "  Список: $($fileNames.Count) имён" -ForegroundColor DarkGray
                # Создаём файлы из списка
                foreach ($baseName in $fileNames) {
                    for ($d = 0; $d -lt $DaysBack; $d++) {
                        $fileDate = (Get-Date).AddDays(-$d).Date
                        for ($f = 0; $f -lt $FilesPerDay; $f++) {
                            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
                            $ext = [System.IO.Path]::GetExtension($baseName)
                            if ($FilesPerDay -gt 1) {
                                $suffix = "{0:D2}" -f ($f + 1)
                                $fileName = "${nameWithoutExt}_${suffix}${ext}"
                            }
                            else {
                                $fileName = $baseName
                            }
                            try {
                                New-TestFile -Path $subPath -FileName $fileName -Date $fileDate | Out-Null
                                $createdCount++
                            } catch {}
                        }
                    }
                }
            }
            else {
                # Fallback: генерация из XML
                $genCount = Generate-TestFilesFromXml -job $job -Path $subPath -DaysBack $DaysBack -FilesPerDay $FilesPerDay
                $createdCount += $genCount
            }
        }

        $actualCount = (Get-ChildItem -Path $sourcePath -File -Recurse -ErrorAction SilentlyContinue).Count
        Write-Host "  Создано: $createdCount файлов в $($subfolders.Count) подпапках (всего: $actualCount)" -ForegroundColor Green

    }
    elseif ($isIndividualFiles) {
        # --------------------------------------------------
        # ТИП Б: Индивидуальная архивация файлов по маске (JOB14,15,20,21)
        # --------------------------------------------------
        Write-Host "  Тип: Индивидуальная архивация файлов по маске" -ForegroundColor Gray

        $fileFilter = if (-not [string]::IsNullOrEmpty($job.FileFilter)) { $job.FileFilter } else { '*.log' }
        $excludeFile = $job.ExcludeFilePattern  # файл, который НЕЛЬЗЯ удалять

        # Генерируем имена файлов по маске
        $names = @()
        $ext = [System.IO.Path]::GetExtension($fileFilter)
        if ([string]::IsNullOrEmpty($ext)) { $ext = '.log' }
        $prefix = [System.IO.Path]::GetFileNameWithoutExtension($fileFilter) -replace '\*', ''
        if ([string]::IsNullOrEmpty($prefix)) { $prefix = 'log' }

        for ($i = 1; $i -le $DaysBack; $i++) {
            $dateNum = "{0:D4}{1:D2}" -f ((Get-Date).AddDays(-$i).Year % 100), (Get-Date).AddDays(-$i).Month
            $fname = "${prefix}${dateNum}${ext}"
            # Исключаем файл из ExcludeFilePattern
            if ($excludeFile -and $fname -eq $excludeFile) { continue }
            $names += $fname
        }

        # Также создаём исключённый файл (чтобы проверить, что он НЕ удалится)
        if (-not [string]::IsNullOrEmpty($excludeFile)) {
            Write-Host "  Исключённый файл (НЕ будет удалён): $excludeFile" -ForegroundColor Yellow
            New-TestFile -Path $sourcePath -FileName $excludeFile -Date (Get-Date) | Out-Null
            $createdCount++
        }

        Write-Host "  Маска: $fileFilter, Исключение: $(if($excludeFile){$excludeFile}else{'нет'})" -ForegroundColor Gray
        Write-Host "  Файлов: $($names.Count)" -ForegroundColor Gray

        foreach ($baseName in $names) {
            for ($d = 0; $d -lt [Math]::Min($DaysBack, 7); $d++) {
                $fileDate = (Get-Date).AddDays(-$d).Date
                for ($f = 0; $f -lt $FilesPerDay; $f++) {
                    if ($FilesPerDay -gt 1) {
                        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
                        $suffix = "{0:D2}" -f ($f + 1)
                        $fileName = "${nameWithoutExt}_${suffix}${ext}"
                    }
                    else { $fileName = $baseName }
                    try { New-TestFile -Path $sourcePath -FileName $fileName -Date $fileDate | Out-Null; $createdCount++ } catch {}
                }
            }
        }

        $actualCount = (Get-ChildItem -Path $sourcePath -File -ErrorAction SilentlyContinue).Count
        Write-Host "  Создано: $createdCount файлов (всего: $actualCount)" -ForegroundColor Green

    }
    else {
        # --------------------------------------------------
        # ТИП В: Стандартная архивация (JOB1-5)
        # --------------------------------------------------
        Write-Host "  Тип: Стандартная архивация" -ForegroundColor Gray

        # Пытаемся загрузить список имён
        $listFileName = ($job.Name).ToLower() + ".txt"
        $listFilePath = Join-Path $ListDir $listFileName
        $fileNames = Get-FileNamesFromList -FilePath $listFilePath

        if ($fileNames.Count -gt 0) {
            Write-Host "  Список: $($fileNames.Count) имён" -ForegroundColor Gray
            $createdCount = Create-FilesWithDates -Path $sourcePath -Names $fileNames -DaysBack $DaysBack -FilesPerDay $FilesPerDay
        }
        else {
            # Fallback: генерация из XML (маски, фильтры, generic)
            Write-Host "  Генерация из XML конфигурации..." -ForegroundColor DarkGray
            $createdCount = Generate-TestFilesFromXml -job $job -Path $sourcePath -DaysBack $DaysBack -FilesPerDay $FilesPerDay
        }

        # Если есть маски проверки — показываем
        if ($job.SourceCheckMasks -and $job.SourceCheckMasks.Count -gt 0) {
            Write-Host "  Маски: $($job.SourceCheckMasks -join ', ')" -ForegroundColor Gray
        }

        $actualCount = (Get-ChildItem -Path $sourcePath -File -ErrorAction SilentlyContinue).Count
        Write-Host "  Создано: $createdCount записей (всего: $actualCount)" -ForegroundColor Green
    }

    $totalFilesCreated += $createdCount
}

# ===========================================================
# Тестовые архивы в LocalDest (для проверки ротации)
# ===========================================================
if (-not $SkipArchives) {
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "[ LocalDest — тестовые архивы для ротации ]" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    foreach ($job in $jobsToProcess) {
        $localDest = $job.LocalDest
        if ([string]::IsNullOrEmpty($localDest)) { continue }

        if ($Clear) { Clear-TestDirectory -Path $localDest }
        if (-not (Test-Path $localDest)) {
            New-Item -ItemType Directory -Path $localDest -Force | Out-Null
        }

        $keepCount = $job.LocalDestKeepCount
        $daysOld = $job.LocalDestDaysOld
        $archiveCount = [Math]::Max($keepCount, $daysOld) + 5

        Write-Host "  $($job.Name): $localDest ($archiveCount архивов)" -ForegroundColor Gray

        for ($i = 0; $i -lt $archiveCount; $i++) {
            $fileDate = (Get-Date).AddDays(-$i).Date
            $dateString = $fileDate.ToString("yyyyMMdd_HHmmss")
            $archiveName = "$($PCName)_$($job.Name)_${dateString}.rar"

            try {
                New-TestFile -Path $localDest -FileName $archiveName -Date $fileDate | Out-Null
            }
            catch {
                Write-Warning "    Ошибка: $archiveName — $_"
            }
        }

        $fileCount = (Get-ChildItem -Path $localDest -File -ErrorAction SilentlyContinue).Count
        Write-Host "  Итого архивов: $fileCount" -ForegroundColor Green
    }
}

# ===========================================================
# Тестовые логи в LogPathRoot (для проверки ротации логов)
# ===========================================================
if (-not $SkipLogs) {
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "[ LogPathRoot — тестовые логи для ротации ]" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    $logPathRoot = $b.Paths.LogPathRoot
    $logDaysOld = [int]$b.General.LogDaysOld
    $logKeepCount = [int]$b.General.LogKeepCount
    $jobNameGeneral = $b.General.JobName

    if ($Clear) { Clear-TestDirectory -Path $logPathRoot }
    if (-not (Test-Path $logPathRoot)) {
        New-Item -ItemType Directory -Path $logPathRoot -Force | Out-Null
    }

    $logCount = [Math]::Max($logDaysOld, $logKeepCount) + 10
    Write-Host "  Директория: $logPathRoot" -ForegroundColor Gray
    Write-Host "  LogDaysOld: $logDaysOld, LogKeepCount: $logKeepCount" -ForegroundColor Gray

    for ($i = 0; $i -lt $logCount; $i++) {
        $fileDate = (Get-Date).AddDays(-$i).Date
        $dateString = $fileDate.ToString("yyyyMMdd")

        $logName = "${jobNameGeneral}_${dateString}.log"
        $logContent = "Backup Log: $jobNameGeneral`r`nDate: $($fileDate.ToString('yyyy-MM-dd'))`r`nStatus: SUCCESS`r`nFiles processed: $((Get-Random -Min 10 -Max 100))"

        try {
            New-TestFile -Path $logPathRoot -FileName $logName -Date $fileDate | Out-Null

            # Дополнительные логи архивации для заданий с ArhLog
            foreach ($job in $jobsToProcess) {
                # ArhLog нужно прочитать из XML
                $jobNode = $b.Jobs.Job | Where-Object { $_.Name -eq $job.Name }
                if ($jobNode -and $jobNode.ArhLog -eq 'true') {
                    $archLogName = "${jobNameGeneral}_$($job.Name)_Arch_${dateString}.log"
                    $archLogContent = "Archive Log: $($job.Name)`r`nDate: $($fileDate.ToString('yyyy-MM-dd'))`r`nStatus: SUCCESS"
                    New-TestFile -Path $logPathRoot -FileName $archLogName -Date $fileDate | Out-Null
                }
            }
        }
        catch {
            Write-Warning "    Ошибка: $logName — $_"
        }
    }

    $logFileCount = (Get-ChildItem -Path $logPathRoot -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Итого логов: $logFileCount" -ForegroundColor Green
}

# ===========================================================
# ИТОГИ
# ===========================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ГОТОВО!" -ForegroundColor Green
Write-Host "Создано записей: $totalFilesCreated" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
