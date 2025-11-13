<#
.SYNOPSIS
    Модуль для копирования артефактов резервного копирования.
.DESCRIPTION
    Предоставляет функцию для копирования файлов (архивов, логов) в сетевое расположение.
    Проверяет доступность удаленного ресурса перед началом копирования.
.EXAMPLE
    Copy-BackupToRemote -SourcePath "D:\local\backup.rar" -DestinationPath "\\server\share"
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function Copy-BackupToRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    try {
        if (-not (Test-Path -Path $SourcePath)) {
            throw "Исходный файл не найден: $SourcePath"
        }

        if (-not (Test-Path -Path $DestinationPath)) {
            Write-Warning "Путь назначения '$DestinationPath' не найден. Попытка создать..."
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }

        $fileName = Split-Path -Path $SourcePath -Leaf
        $destinationFile = Join-Path -Path $DestinationPath -ChildPath $fileName

        Write-Host "Копирование файла '$fileName' в '$DestinationPath'..."
        Copy-Item -Path $SourcePath -Destination $destinationFile -Force -ErrorAction Stop
        
        Write-Host "Копирование успешно завершено." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Ошибка при копировании файла в '$DestinationPath': $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Copy-BackupToRemote