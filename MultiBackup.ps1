<# file MultiBackup.ps1
.SYNOPSIS
    Оркестратор процессов резервного копирования
.DESCRIPTION
    Запускает процессы резервного копирования на основе JSON конфигурации
.PARAMETER ConfigPath
    Путь к файлу конфигурации
.EXAMPLE
    MultiBackup -ConfigPath "BackupConfigs\config.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath
)

function Invoke-BackupProcess {
    param($Config)
    
    if (-not $Config.Enabled) {
        Write-Host "Конфигурация $($Config.Name) отключена" -ForegroundColor Yellow
        return
    }

    Write-Host "Обработка конфигурации: $($Config.Name)" -ForegroundColor Green

    # Create_Backup_Rar
    if ($Config.BackupRar.Enabled) {
        try {
            $backupParams = @{
                SRC = $Config.BackupRar.Source
                DST = $Config.BackupRar.Destination
                ArchiveName = $Config.BackupRar.ArchiveName
                Keys = $Config.BackupRar.Keys
                ArchiveExtension = $Config.BackupRar.Extension
            }
            & ".\Create_Backup_Rar.ps1" @backupParams
        }
        catch {
            Write-Error "Ошибка в Create_Backup_Rar: $($_.Exception.Message)"
        }
    }

    # Copy-Robocopy
    if ($Config.Copy.Enabled) {
        try {
            $copyParams = @{
                SRC = $Config.Copy.Source
                DST = $Config.Copy.Destination
                LogName = $Config.Copy.LogName
                LogPath = $Config.Copy.LogPath
                Keys = $Config.Copy.Keys
                CheckFreeSpace = $Config.Copy.CheckFreeSpace
            }
            & ".\Copy-Robocopy.ps1" @copyParams
        }
        catch {
            Write-Error "Ошибка в Copy-Robocopy: $($_.Exception.Message)"
        }
    }

    # Remove-OldFiles
    if ($Config.RemoveOldFiles.Enabled) {
        try {
            $removeParams = @{
                Path = $Config.RemoveOldFiles.Path
                DaysOld = $Config.RemoveOldFiles.DaysOld
                KeepCount = $Config.RemoveOldFiles.KeepCount
            }
            & ".\Remove-OldFiles.ps1" @removeParams
        }
        catch {
            Write-Error "Ошибка в Remove-OldFiles: $($_.Exception.Message)"
        }
    }

    # Send-Mail
    if ($Config.Notification.Enabled) {
        try {
            $mailParams = @{
                From = $Config.Notification.From
                To = $Config.Notification.To
                Subject = $Config.Notification.Subject
                Body = "Резервное копирование $($Config.Name) завершено"
            }
            & ".\Send-Mail.ps1" @mailParams
        }
        catch {
            Write-Error "Ошибка в Send-Mail: $($_.Exception.Message)"
        }
    }
}

try {
    if (-not (Test-Path $ConfigPath)) {
        throw "Файл конфигурации не найден"
    }

    $configurations = Get-Content $ConfigPath | ConvertFrom-Json

    foreach ($config in $configurations) {
        Invoke-BackupProcess $config
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}