<# file Backup-Config.psm1
.SYNOPSIS
    Модуль конфигурации для скриптов резервного копирования
.DESCRIPTION
    Управление настройками и конфигурацией заданий
#>

#region Стандартные настройки
$PCName = $env:COMPUTERNAME
$JobName = 'Backup_Folder'
$LogPath = "C:\work\$JobName\logs"
$RarPath = "c:\work\rar.exe"

$Script:DefaultSettings = @{
    PCName = $PCName
    JobName = $JobName
    LogPath = $LogPath
    RarPath = $RarPath
    RarParameters = @("a", "-m5", "-s", "-ep", "-rr1p", "-r", "-t")
}
#endregion

#region Конфигурация заданий
$Script:BackupJobs = @{
    Job1 = @{
        Source = "c:\test\backup1\"
        Archive = "{PCName}_{JobName}_backup1_{Date}.rar"
        LocalDest = "d:\Backup\Local\"
        RemoteDest = "d:\Backup\Remote\"
    }
    Job2 = @{
        Source = "c:\test\backup2\"
        Archive = "{PCName}_{JobName}_backup2_{Date}.rar"
        LocalDest = "d:\Backup\Local\"
        RemoteDest = "d:\Backup\Remote\"
    }
}
#endregion

function Get-BackupConfiguration {
    <#
    .SYNOPSIS
        Возвращает конфигурацию заданий с подставленными значениями
    #>
    param()
    
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $resolvedJobs = @{}
    
    foreach ($jobName in $Script:BackupJobs.Keys) {
        $job = $Script:BackupJobs[$jobName].Clone()
        
        # Замена плейсхолдеров в имени архива
        $job.Archive = $job.Archive -replace '{PCName}', $Script:DefaultSettings.PCName
        $job.Archive = $job.Archive -replace '{JobName}', $Script:DefaultSettings.JobName
        $job.Archive = $job.Archive -replace '{Date}', $currentDate
        
        $resolvedJobs[$jobName] = $job
    }
    
    return @{
        Settings = $Script:DefaultSettings
        Jobs = $resolvedJobs
    }
}

function Set-BackupJob {
    <#
    .SYNOPSIS
        Добавляет или изменяет задание резервного копирования
    .PARAMETER JobName
        Имя задания
    .PARAMETER Source
        Путь к источнику
    .PARAMETER LocalDest
        Локальный путь назначения
    .PARAMETER RemoteDest
        Сетевой путь назначения
    .PARAMETER ArchivePattern
        Шаблон имени архива
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName,
        [Parameter(Mandatory=$true)]
        [string]$Source,
        [Parameter(Mandatory=$true)]
        [string]$LocalDest,
        [string]$RemoteDest = "",
        [string]$ArchivePattern = "{PCName}_{JobName}_$JobName_{Date}.rar"
    )
    
    $Script:BackupJobs[$JobName] = @{
        Source = $Source
        Archive = $ArchivePattern
        LocalDest = $LocalDest
        RemoteDest = $RemoteDest
    }
}

function Remove-BackupJob {
    <#
    .SYNOPSIS
        Удаляет задание резервного копирования
    .PARAMETER JobName
        Имя задания
    #>
    param([Parameter(Mandatory=$true)][string]$JobName)
    
    if ($Script:BackupJobs.ContainsKey($JobName)) {
        $Script:BackupJobs.Remove($JobName)
        return $true
    }
    return $false
}

function Test-Configuration {
    <#
    .SYNOPSIS
        Проверяет корректность конфигурации
    #>
    param()
    
    $config = Get-BackupConfiguration
    $errors = @()
    
    # Проверка RAR
    if (-not (Test-Path $config.Settings.RarPath)) {
        $errors += "RAR архиватор не найден: $($config.Settings.RarPath)"
    }
    
    # Проверка заданий
    foreach ($jobName in $config.Jobs.Keys) {
        $job = $config.Jobs[$jobName]
        
        if (-not (Test-Path $job.Source)) {
            $errors += "Источник не существует ($jobName): $($job.Source)"
        }
        
        if (-not $job.LocalDest) {
            $errors += "Не указан локальный путь назначения ($jobName)"
        }
    }
    
    return @{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
}

function Get-RarParameters {
    <#
    .SYNOPSIS
        Возвращает параметры RAR по умолчанию
    #>
    return $Script:DefaultSettings.RarParameters
}

# Экспорт функций
Export-ModuleMember -Function Get-BackupConfiguration, Set-BackupJob, Remove-BackupJob, Test-Configuration, Get-RarParameters