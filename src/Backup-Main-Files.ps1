<#
.SYNOPSIS
    Основной скрипт для резервного копирования отдельных файлов.
.DESCRIPTION
    Скрипт выполняет резервное копирование файлов по маске согласно конфигурации. 
    Каждый файл архивируется отдельно. Не создает лог со списком файлов.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File ".\Backup-Main-Files.ps1"
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

#region Импорт модулей
try {
    Import-Module -Name ".\Backup-Logger.psm1" -ErrorAction Stop
    Import-Module -Name ".\Backup-RAR.psm1" -ErrorAction Stop
    Import-Module -Name ".\Backup-7z.psm1" -ErrorAction Stop
    Import-Module -Name ".\Backup-Zip.psm1" -ErrorAction Stop
    Import-Module -Name ".\Remove-OldFiles.psm1" -ErrorAction Stop
    Import-Module -Name ".\Backup-Copy.psm1" -ErrorAction Stop
    Import-Module -Name ".\Mail-Email-Send.psm1" -ErrorAction Stop
}
catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $criticalError = "[$timestamp] [CRITICAL] - Не удалось импортировать один или несколько основных модулей. Ошибка: $($_.Exception.Message)"
    Add-Content -Path "C:\logs\critical_error.log" -Value $criticalError
    exit 1
}
#endregion

#region Стандартные настройки
$JobName = "FileBackups"
#$TemplDomainName = "@main.local.loc"

$DefaultSettings = @{
    PCName          = $env:COMPUTERNAME
    JobName         = $JobName
    LogPath         = "C:\work\" + $JobName + "\logs"
    TypeArh         = "rar"
    RarPath         = "c:\Program Files\WinRAR\rar.exe"
    RarParameters   = @("a", "-m5", "-s", "-ep", "-rr1p", "-t") # -ep, чтобы не создавать папки в архиве
    '7zPath'        = "c:\Program Files\7-Zip\7z.exe"
    '7zParameters'  = @("a", "-mx=9", "-ms=on", "-srr", "-t")
    psZipParameters = @{ CompressionLevel = "Optimal" }
    AdminIS         = "user1@local.loc"
    AdminOS         = "user2@local.loc"
    SmtpServer      = "smtp.local.loc"
}
#endregion

#region Конфигурация заданий
$BackupJobs = @{
    Job2 = @{
        Source      = "C:\testBackups\JOB2_File_in_Arh\"
        FilterFiles = "*.msg"
        Archive     = "{PCName}_{FileName}_{Date}.rar"
        LocalDest   = "D:\testBackupsLocal\JOB2\"
        RemoteDest  = "D:\testBackupsRemote\"
        DaysToKeep  = 60
        FilesToKeep = 20
    }
}
#endregion

#region Основной процесс
$mainLogFile = Initialize-Log -LogPath $DefaultSettings.LogPath -JobName $DefaultSettings.JobName
Write-Log -Message "===== Запуск сессии резервного копирования файлов =====" -Level INFO -LogFile $mainLogFile

foreach ($jobName in $BackupJobs.Keys) {
    $job = $BackupJobs[$jobName]
    Write-Log -Message "--- Начало обработки задания: $jobName ---" -Level INFO -LogFile $mainLogFile

    try {
        $sourceFiles = Get-ChildItem -Path $job.Source -Filter $job.FilterFiles -File
        if (-not $sourceFiles) {
            Write-Log -Message "В источнике '$($job.Source)' не найдено файлов по фильтру '$($job.FilterFiles)'." -Level WARN -LogFile $mainLogFile
            continue
        }

        foreach ($file in $sourceFiles) {
            Write-Log -Message "Обработка файла: $($file.FullName)" -Level INFO -LogFile $mainLogFile
            
            # 1. Формирование имени архива
            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $archiveName = $job.Archive -replace "{PCName}", $DefaultSettings.PCName -replace "{FileName}", $fileNameWithoutExt -replace "{Date}", (Get-Date -Format "yyyyMMdd")
            $localArchivePath = Join-Path -Path $job.LocalDest -ChildPath $archiveName
            
            # 2. Создание архива для одного файла
            $archiveSuccess = $false
            switch ($DefaultSettings.TypeArh) {
                "rar" { $archiveSuccess = New-RarArchive -SourcePath $file.FullName -DestinationPath $localArchivePath -RarPath $DefaultSettings.RarPath -Parameters $DefaultSettings.RarParameters }
                "7z" { $archiveSuccess = New-7zArchive -SourcePath $file.FullName -DestinationPath $localArchivePath -SevenZipPath $DefaultSettings.'7zPath' -Parameters $DefaultSettings.'7zParameters' }
                "zip" { $archiveSuccess = New-ZipArchive -SourcePath $file.FullName -DestinationPath $localArchivePath -Parameters $DefaultSettings.psZipParameters }
            }
            if (-not $archiveSuccess) { throw "Ошибка создания архива для файла '$($file.FullName)'." }

            # 3. Копирование в удаленное хранилище
            $copySuccess = Copy-BackupToRemote -SourcePath $localArchivePath -DestinationPath $job.RemoteDest
            if (-not $copySuccess) { throw "Ошибка копирования архива '$localArchivePath'." }
        }

        # 4. Ротация старых бэкапов (для всей папки назначения)
        Remove-OldBackups -Path $job.RemoteDest -DaysToKeep $job.DaysToKeep -FilesToKeep $job.FilesToKeep

        Write-Log -Message "Задание '$jobName' успешно завершено." -Level INFO -LogFile $mainLogFile
    }
    catch {
        Write-Log -Message "ОШИБКА при выполнении задания '$jobName': $($_.Exception.Message)" -Level ERROR -LogFile $mainLogFile
    }
    finally {
        Write-Log -Message "--- Окончание обработки задания: $jobName ---" -Level INFO -LogFile $mainLogFile
    }
}

Write-Log -Message "===== Сессия резервного копирования файлов завершена =====" -Level INFO -LogFile $mainLogFile

# 5. Отправка отчета
$reportBody = Get-Content -Path $mainLogFile -Tail 50 | Out-String
Send-BackupNotification -To $DefaultSettings.AdminIS -Subject "Отчет о резервном копировании файлов" -Body $reportBody -SmtpServer $DefaultSettings.SmtpServer

#endregion