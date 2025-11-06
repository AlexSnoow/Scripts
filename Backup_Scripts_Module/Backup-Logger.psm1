<# file Backup-Logger.psm1
.SYNOPSIS
    Модуль логирования для скриптов резервного копирования
.DESCRIPTION
    Предоставляет функции для детального логирования в файл
#>

#region Инициализация модуля
$Script:LogPath = $null
$Script:MainLogFile = $null
#endregion

function Initialize-Logging {
    <#
    .SYNOPSIS
        Инициализация системы логирования
    .PARAMETER LogPath
        Путь к папке с логами
    .PARAMETER PCName
        Имя компьютера
    .PARAMETER JobName
        Имя задания
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        [Parameter(Mandatory=$true)]
        [string]$PCName,
        [Parameter(Mandatory=$true)]
        [string]$JobName
    )
    
    try {
        # Создание папки для логов
        if (-not (Test-Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        $Script:LogPath = $LogPath
        $Script:MainLogFile = Join-Path $LogPath "$PCName`_$JobName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        # Установка правильной кодировки
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        
        # Создаем файл с UTF8 без BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Script:MainLogFile, "", $utf8NoBom)
        
        Write-Log "========================================"
        Write-Log "СИСТЕМА ЛОГИРОВАНИЯ ИНИЦИАЛИЗИРОВАНА"
        Write-Log "Лог-файл: $($Script:MainLogFile)"
        Write-Log "========================================"
        
        return $true
    }
    catch {
        throw "Ошибка инициализации логирования: $_"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Запись сообщения в лог-файл
    .PARAMETER Message
        Текст сообщения
    .PARAMETER LogFile
        Путь к лог-файлу (по умолчанию основной)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$LogFile = $Script:MainLogFile
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] $Message"
        
        # Запись в файл с UTF8 без BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::AppendAllText($LogFile, "$logEntry`r`n", $utf8NoBom)
    }
    catch {
        # Резервное логирование в случае ошибки
        $errorMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ОШИБКА ЛОГИРОВАНИЯ: $Message (Оригинальная ошибка: $_)"
        $errorMsg | Out-File -FilePath "C:\work\backup_logging_error.log" -Append -Encoding UTF8
    }
}

function Get-LogFilePath {
    <#
    .SYNOPSIS
        Возвращает путь к текущему лог-файлу
    #>
    return $Script:MainLogFile
}

function Write-LogSection {
    <#
    .SYNOPSIS
        Запись разделительной секции в лог
    .PARAMETER Title
        Заголовок секции
    #>
    param([string]$Title = "")
    
    if ($Title) {
        Write-Log "========================================"
        Write-Log $Title.ToUpper()
        Write-Log "========================================"
    } else {
        Write-Log "----------------------------------------"
    }
}

# Экспорт функций
Export-ModuleMember -Function Initialize-Logging, Write-Log, Get-LogFilePath, Write-LogSection