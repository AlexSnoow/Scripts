<#
.SYNOPSIS
    Модуль логирования для скриптов резервного копирования.
.DESCRIPTION
    Предоставляет функции для инициализации лог-файла и записи сообщений с разными уровнями (INFO, WARN, ERROR).
    Обеспечивает ротацию логов по дате и запись сообщений с временными метками.
.EXAMPLE
    # Инициализация лога в основном скрипте
    $logFile = Initialize-Log -LogPath "C:\logs" -JobName "MyBackup"
    
    # Запись информационного сообщения
    Write-Log -Message "Процесс запущен" -Level INFO -LogFile $logFile
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function Initialize-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$JobName
    )

    try {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $logDate = Get-Date -Format "yyyy-MM-dd"
        $logFile = Join-Path -Path $LogPath -ChildPath "${JobName}_${logDate}.log"
        return $logFile
    }
    catch {
        Write-Error "Не удалось создать директорию для логов: $($_.Exception.Message)"
        return $null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] - $Message"

    try {
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
    }
    catch {
        Write-Error "Критическая ошибка: не удалось записать сообщение в лог-файл '$LogFile'. Сообщение: '$Message'. Ошибка: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Initialize-Log, Write-Log