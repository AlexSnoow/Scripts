<# file Send-Mail.ps1
.SYNOPSIS
    Выполняет отправку писем внутри локальной корпоративной сети

.DESCRIPTION
    Функция для автоматической отправки писем с поддержкой вложений, HTML-форматирования,
    и подробного логирования. Поддерживает множественных получателей и вложения.

.PARAMETER From
    Адрес отправителя (обязательный параметр)

.PARAMETER To
    Адрес или адреса получателей через запятую (обязательный параметр)

.PARAMETER Subject
    Тема письма (обязательный параметр)

.PARAMETER Body
    Текст письма (обязательный параметр)

.PARAMETER SmtpServer
    SMTP-сервер для отправки (обязательный параметр)

.PARAMETER AttachPath
    Путь к файлу или папке с файлами для вложения в письмо

.PARAMETER LogPath
    Путь для сохранения логов (по умолчанию: "C:\Logs\mail")

.PARAMETER LogName
    Имя лога (может содержать плейсхолдеры {date}, {time}, {datetime})

.PARAMETER MaxLogAge
    Максимальный возраст логов в днях (автоочистка старых логов)

.PARAMETER Credential
    Учетные данные для аутентификации на SMTP-сервере

.PARAMETER UseSSL
    Использовать SSL-шифрование при подключении

.PARAMETER Port
    Порт SMTP-сервера (по умолчанию: 25 для без SSL, 587 для SSL)

.PARAMETER BodyAsHtml
    Использовать HTML-форматирование тела письма

.PARAMETER Priority
    Приоритет письма (High, Normal, Low)

.PARAMETER Encoding
    Кодировка письма (по умолчанию: UTF8)

.EXAMPLE
    # Отправка простого письма
    Send-Mail -From "user1@domain.loc" -To "user2@domain.loc" -Subject "Тест" -Body "Текст письма" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Отправка с вложением и HTML-форматированием
    Send-Mail -From "report@domain.loc" -To "admin@domain.loc" -Subject "Отчет" -Body "<h1>Ежедневный отчет</h1>" -BodyAsHtml -AttachPath "C:\Reports\report.pdf" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Отправка нескольким получателям
    Send-Mail -From "service@domain.loc" -To "user1@domain.loc", "user2@domain.loc" -Subject "Уведомление" -Body "Важное сообщение" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Запуск из командной строки
    .\Send-Mail.ps1 -From "alert@domain.loc" -To "admin@domain.loc" -Subject "Ошибка" -Body "Обнаружена ошибка в системе" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Использование в планировщике заданий
    Program: powershell.exe
    Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Send-Mail.ps1" -From "daily@domain.loc" -To "report@domain.loc" -Subject "Ежедневный отчет" -Body "Отчет прикреплен" -AttachPath "C:\Reports\daily.txt" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Использование в другом скрипте
    . .\Send-Mail.ps1
    Send-Mail -From "noreply@domain.loc" -To "user@domain.loc" -Subject "Добро пожаловать" -Body "Регистрация завершена" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # Создание задания в планировщике через PowerShell
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\Scripts\Send-Mail.ps1`" -From `"alert@domain.loc`" -To `"admin@domain.loc`" -Subject `"Ежедневное уведомление`" -Body `"Система работает нормально`" -SmtpServer `"smtp.domain.loc`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DailyMailAlert" -Description "Ежедневное уведомление по email" -Principal $principal -Settings $settings

.NOTES
    Автор: Иванов
    Версия: 2.1 (2025-08-19)
    Требуется: PowerShell 3.0 или выше
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}")]
    [string]$From,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}")]
    [string[]]$To,

    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [Parameter(Mandatory = $true)]
    [string]$Body,

    [Parameter(Mandatory = $false)]
    [string]$SmtpServer = "SmtpServer.domail.loc",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ($_ -and -not (Test-Path $_)) { throw "Путь не существует: $_" }
            $true
        })]
    [string[]]$AttachPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\mail",

    [Parameter(Mandatory = $false)]
    [string]$LogName = "MailLog-{datetime}",

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$UseSSL,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port,

    [Parameter(Mandatory = $false)]
    [switch]$BodyAsHtml,

    [Parameter(Mandatory = $false)]
    [ValidateSet("High", "Normal", "Low")]
    [string]$Priority = "Normal",

    [Parameter(Mandatory = $false)]
    [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
)

function Send-Mail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$From,

        [Parameter(Mandatory = $true)]
        [string[]]$To,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [string]$SmtpServer,

        [Parameter(Mandatory = $false)]
        [string[]]$AttachPath,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "C:\Logs\mail",

        [Parameter(Mandatory = $false)]
        [string]$LogName = "MailLog-{datetime}",

        [Parameter(Mandatory = $false)]
        [int]$MaxLogAge = 30,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$UseSSL,

        [Parameter(Mandatory = $false)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [switch]$BodyAsHtml,

        [Parameter(Mandatory = $false)]
        [string]$Priority = "Normal",

        [Parameter(Mandatory = $false)]
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    # Замена плейсхолдеров в имени лога
    $dateString = Get-Date -Format "yyyyMMdd"
    $timeString = Get-Date -Format "HHmmss"
    $dateTimeString = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $finalLogName = $LogName `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # Создание папки для логов, если не существует
    if (-not (Test-Path $LogPath)) {
        Write-Verbose "Создание папки для логов: $LogPath"
        try {
            New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "Не удалось создать папку для логов: $($_.Exception.Message)"
            return $false
        }
    }

    # Очистка старых логов
    if ($MaxLogAge -gt 0) {
        try {
            $oldLogs = Get-ChildItem -Path $LogPath -Filter "*.log" | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$MaxLogAge)
            }
            
            if ($oldLogs.Count -gt 0) {
                Write-Verbose "Удаление старых логов ($($oldLogs.Count) файлов)"
                $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Не удалось очистить старые логи: $($_.Exception.Message)"
        }
    }

    # Формирование полного пути к лог-файлу
    $logFile = Join-Path $LogPath "$finalLogName.log"

    # Подготовка параметров для отправки
    $mailParams = @{
        From        = $From
        To          = $To
        Subject     = $Subject
        Body        = $Body
        SmtpServer  = $SmtpServer
        ErrorAction = "Stop"
        Encoding    = $Encoding
    }

    # Добавление необязательных параметров
    if ($AttachPath) { 
        $mailParams.Attachments = $AttachPath
    }
    if ($Credential) { 
        $mailParams.Credential = $Credential
    }
    else {
        # Использование анонимной аутентификации по умолчанию
        $mailParams.Credential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "NT AUTHORITY\ANONYMOUS LOGON", (New-Object System.Security.SecureString))
    }
    if ($UseSSL) { 
        $mailParams.UseSsl = $true
    }
    if ($Port -gt 0) { 
        $mailParams.Port = $Port
    }
    if ($BodyAsHtml) { 
        $mailParams.BodyAsHtml = $true
    }
    if ($Priority -ne "Normal") { 
        $mailParams.Priority = $Priority
    }

    # Логирование информации о отправке
    $logMessage = @"
========================================
Отправка письма: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
От: $From
Кому: $($To -join ", ")
Тема: $Subject
Сервер: $SmtpServer
Вложения: $(if ($AttachPath) { $AttachPath -join ", " } else { "нет" })
========================================
"@

    try {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        Write-Verbose "Подготовка к отправке письма..."

        # Отправка письма
        Send-MailMessage @mailParams

        # Логирование успеха
        $successMessage = "Письмо успешно отправлено!`n"
        Add-Content -Path $logFile -Value $successMessage -Encoding UTF8
        Write-Host "Письмо успешно отправлено!" -ForegroundColor Green

        return $true
    }
    catch {
        # Логирование ошибки
        $errorMessage = "Ошибка при отправке письма: $($_.Exception.Message)`n"
        Add-Content -Path $logFile -Value $errorMessage -Encoding UTF8
        Write-Error "Ошибка при отправке письма: $($_.Exception.Message)"
        
        return $false
    }
    finally {
        Add-Content -Path $logFile -Value "========================================`n" -Encoding UTF8
    }
}

# Если скрипт запущен напрямую (не импортирован как модуль)
if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Запуск отправки
        $result = Send-Mail @PSBoundParameters
        
        # Завершение с соответствующим кодом выхода
        exit $(if ($result) { 0 } else { 1 })
    }
    catch {
        Write-Error "Ошибка выполнения: $($_.Exception.Message)"
        exit 1
    }
}
else {
    # Экспорт функции для использования в других скриптах
    Export-ModuleMember -Function Send-Mail -Alias sendmail
}