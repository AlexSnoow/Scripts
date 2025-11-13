<# file Backup-RAR.psm1
.SYNOPSIS
    Модуль операций с RAR архиватором
.DESCRIPTION
    Предоставляет функции для работы с RAR архивацией
#>

function Get-RarExitCodeMeaning {
    <#
    .SYNOPSIS
        Расшифровка кодов возврата RAR
    .PARAMETER ExitCode
        Код возврата от RAR
    #>
    param([int]$ExitCode)
    
    $errorDescriptions = @{
        0 = "Успешное выполнение"
        1 = "Произошла незначительная ошибка при создании архива"
        2 = "Произошла критическая ошибка при создании архива" 
        3 = "Ошибка при проверке целостности архива"
        4 = "Ошибка при открытии файла"
        5 = "Ошибка записи файла"
        6 = "Ошибка при открытии архива"
        7 = "Недопустимая команда или параметр"
        8 = "Не хватает памяти для выполнения операции"
        9 = "Невозможно создать временный файл"
        10 = "Невозможно создать архив"
        11 = "Невозможно открыть файл для чтения"
        255 = "Пользователь прервал операцию"
    }
    
    if ($errorDescriptions.ContainsKey($ExitCode)) {
        return $errorDescriptions[$ExitCode]
    } else {
        return "Неизвестный код возврата: $ExitCode"
    }
}

function Start-RarArchive {
    <#
    .SYNOPSIS
        Выполняет архивацию с помощью RAR
    .PARAMETER RarPath
        Путь к RAR.exe
    .PARAMETER ArchivePath
        Полный путь к создаваемому архиву
    .PARAMETER SourcePath
        Путь к исходным файлам
    .PARAMETER Parameters
        Параметры RAR
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RarPath,
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        [array]$Parameters = @("a", "-m5", "-s", "-ep", "-rr1p", "-r", "-tl", "-t")
    )
    
    $argsList = $Parameters + @("`"$ArchivePath`"", "`"$SourcePath`"")
    
    Write-Log "Запуск RAR: $RarPath $($argsList -join ' ')"
    
    $processStart = Get-Date
    $process = Start-Process -FilePath $RarPath -ArgumentList $argsList -Wait -PassThru -WindowStyle Hidden
    $processEnd = Get-Date
    $duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
    
    return @{
        ExitCode = $process.ExitCode
        Duration = $duration
        StartTime = $processStart
        EndTime = $processEnd
    }
}

function Test-RarArchive {
    <#
    .SYNOPSIS
        Проверяет целостность RAR архива
    .PARAMETER RarPath
        Путь к RAR.exe
    .PARAMETER ArchivePath
        Путь к архиву для проверки
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RarPath,
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath
    )
    
    $testArgs = @("t", "`"$ArchivePath`"")
    
    Write-Log "Проверка целостности архива: $ArchivePath"
    
    $process = Start-Process -FilePath $RarPath -ArgumentList $testArgs -Wait -PassThru -WindowStyle Hidden
    
    return @{
        ExitCode = $process.ExitCode
        IsValid = ($process.ExitCode -eq 0)
    }
}

function Get-FileInfoDetails {
    <#
    .SYNOPSIS
        Возвращает детальную информацию о файлах в папке
    .PARAMETER Path
        Путь к анализируемой папке
    #>
    param([Parameter(Mandatory=$true)][string]$Path)
    
    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $fileCount = $items.Count
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
        
        $fileSamples = $items | Select-Object -First 5 | ForEach-Object {
            @{
                Name = $_.Name
                SizeKB = [math]::Round($_.Length / 1KB, 2)
                FullPath = $_.FullName
            }
        }
        
        return @{
            FileCount = $fileCount
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
            TotalSizeBytes = $totalSize
            FileSamples = $fileSamples
            HasMoreFiles = ($fileCount -gt 5)
            MoreFilesCount = ($fileCount - 5)
        }
    }
    catch {
        return @{
            FileCount = 0
            TotalSizeMB = 0
            TotalSizeBytes = 0
            FileSamples = @()
            HasMoreFiles = $false
            MoreFilesCount = 0
            Error = $_.Exception.Message
        }
    }
}

function Copy-BackupFile {
    <#
    .SYNOPSIS
        Копирует файл архива с проверкой
    .PARAMETER SourcePath
        Путь к исходному файлу
    .PARAMETER DestinationPath
        Путь к назначению
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )
    
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $copyEnd = Get-Date
    $duration = [math]::Round(($copyEnd - $copyStart).TotalSeconds, 2)
    
    # Проверка размеров
    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length
    
    return @{
        Success = ($sourceSize -eq $destSize)
        Duration = $duration
        SourceSize = $sourceSize
        DestinationSize = $destSize
        StartTime = $copyStart
        EndTime = $copyEnd
    }
}

# Экспорт функций
Export-ModuleMember -Function Get-RarExitCodeMeaning, Start-RarArchive, Test-RarArchive, Get-FileInfoDetails, Copy-BackupFile