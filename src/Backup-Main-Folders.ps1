<#
.SYNOPSIS
    Основной скрипт для резервного копирования каталогов.
.DESCRIPTION
    Скрипт выполняет резервное копирование папок согласно конфигурации заданий.
    Поддерживает архивацию (RAR, 7z, ZIP), ротацию, копирование в сетевое хранилище и отправку отчетов.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File ".\Backup-Main-Folders.ps1"
.NOTES
    Автор: Kilo Code
    Версия: 1.1
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
$JobName = "FolderBackups"
#$TemplDomainName = "@main.local.loc"

$DefaultSettings = @{
    PCName          = $env:COMPUTERNAME
    JobName         = $JobName
    LogPath         = "C:\work\" + $JobName + "\logs"
    TypeArh         = "rar"
    RarPath         = "c:\Program Files\WinRAR\rar.exe"
    RarParameters   = @("a", "-m5", "-s", "-ep1", "-rr1p", "-r", "-t")
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
    Job1 = @{
        Source         = "C:\testBackups\JOB1_folder\"
        ListExceptions = @()
        Archive        = "{PCName}_Job1_{Date}.rar"
        LocalDest      = "D:\testBackupsLocal\JOB1\"
        RemoteDest     = "D:\testBackupsRemote\"
        DaysToKeep     = 30
        FilesToKeep    = 5
    }
    Job3 = @{
        Source         = "C:\testBackups\JOB3_folder_exect\"
        ListExceptions = @("C:\testBackups\JOB3_folder_exect\test1", "C:\testBackups\JOB3_folder_exect\test2")
        Archive        = "{PCName}_JOB3_{Date}.rar"
        LocalDest      = "D:\testBackupsLocal\JOB3\"
        RemoteDest     = "D:\testBackupsRemote\"
        DaysToKeep     = 15
        FilesToKeep    = 3
    }
}
#endregion

#region Основной процесс
$mainLogFile = Initialize-Log -LogPath $DefaultSettings.LogPath -JobName $DefaultSettings.JobName
Write-Log -Message "===== Запуск сессии резервного копирования папок =====" -Level INFO -LogFile $mainLogFile

foreach ($jobName in $BackupJobs.Keys) {
    $job = $BackupJobs[$jobName]
    Write-Log -Message "--- Начало обработки задания: $jobName ---" -Level INFO -LogFile $mainLogFile

    try {
        # 1. Формирование имени архива
        $archiveName = $job.Archive -replace "{PCName}", $DefaultSettings.PCName -replace "{Date}", (Get-Date -Format "yyyyMMdd")
        $localArchivePath = Join-Path -Path $job.LocalDest -ChildPath $archiveName

        # 2. Создание архива
        $archiveSuccess = $false
        switch ($DefaultSettings.TypeArh) {
            "rar" { $archiveSuccess = New-RarArchive -SourcePath $job.Source -DestinationPath $localArchivePath -RarPath $DefaultSettings.RarPath -Parameters $DefaultSettings.RarParameters -ExcludePaths $job.ListExceptions }
            "7z" { $archiveSuccess = New-7zArchive -SourcePath $job.Source -DestinationPath $localArchivePath -SevenZipPath $DefaultSettings.'7zPath' -Parameters $DefaultSettings.'7zParameters' -ExcludePaths $job.ListExceptions }
            "zip" { $archiveSuccess = New-ZipArchive -SourcePath $job.Source -DestinationPath $localArchivePath -Parameters $DefaultSettings.psZipParameters }
        }

        if (-not $archiveSuccess) { throw "Ошибка на этапе создания архива." }

        # 3. Копирование в удаленное хранилище
        $copySuccess = Copy-BackupToRemote -SourcePath $localArchivePath -DestinationPath $job.RemoteDest
        if (-not $copySuccess) { throw "Ошибка на этапе копирования в удаленное хранилище." }

        # 4. Ротация старых бэкапов
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

Write-Log -Message "===== Сессия резервного копирования папок завершена =====" -Level INFO -LogFile $mainLogFile

# 5. Отправка отчета (здесь можно добавить логику для формирования тела письма)
$reportBody = Get-Content -Path $mainLogFile -Tail 50 | Out-String
Send-BackupNotification -To $DefaultSettings.AdminIS -Subject "Отчет о резервном копировании папок" -Body $reportBody -SmtpServer $DefaultSettings.SmtpServer

#endregion
