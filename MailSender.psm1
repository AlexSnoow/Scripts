<# file 
.SYNOPSIS
    Модуль для отправки сообщений

.DESCRIPTION
    Модуль 

.EXAMPLE
Send-Email -From "sender@local.loc" -To "recipient@local.loc" -Subject "Test" -Body "Текст письма"

#>
function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$From,
        
        [Parameter(Mandatory=$true)]
        [string]$To,
        
        [Parameter(Mandatory=$true)]
        [string]$Subject,
        
        [Parameter(Mandatory=$true)]
        [string]$Body
    )
    
    # Фиксированные параметры
    $SmtpServer = "smtp.local.loc"
    $Encoding = [System.Text.Encoding]::UTF8
    $BodyAsHtml = $false
    
    try {
        Send-MailMessage -From $From -To $To -Subject $Subject -Body $Body `
                        -SmtpServer $SmtpServer -Encoding $Encoding -BodyAsHtml:$BodyAsHtml
        
        Write-Host "✓ Письмо отправлено: $Subject" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "✗ Ошибка: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Send-Email
