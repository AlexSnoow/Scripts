<#
.SYNOPSIS
    Модуль для отправки email-сообщений.
.DESCRIPTION
    Предоставляет функцию для отправки отчетов о результатах резервного копирования.
.EXAMPLE
    Send-BackupNotification -To "admin@local.loc" -Subject "Backup Report" -Body "Backup completed." -SmtpServer "smtp.local.loc"
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function Send-BackupNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$To,
        
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        
        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [string]$SmtpServer,

        [Parameter(Mandatory = $false)]
        [string]$From = "backup-noreply@local.loc",

        [Parameter(Mandatory = $false)]
        [pscredential]$Credential
    )
    
    $mailParams = @{
        From        = $From
        To          = $To
        Subject     = $Subject
        Body        = $Body
        SmtpServer  = $SmtpServer
        Encoding    = [System.Text.Encoding]::UTF8
        ErrorAction = 'Stop'
    }

    if ($Credential) {
        $mailParams.Credential = $Credential
    }

    try {
        Send-MailMessage @mailParams
        Write-Host "Email-уведомление успешно отправлено на адрес '$To'." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Ошибка при отправке email-уведомления: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Send-BackupNotification