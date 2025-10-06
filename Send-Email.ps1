# Функция для отправки email
function Send-Email {
    param(
        [Parameter(Mandatory=$true)][string]$SmtpServer,
        [Parameter(Mandatory=$true)][string]$From,
        [Parameter(Mandatory=$false)][string]$FromDisplayName,
        [Parameter(Mandatory=$false)][string[]]$To,
        [Parameter(Mandatory=$false)][string[]]$Cc,
        [Parameter(Mandatory=$false)][string[]]$Bcc,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body,
        [Parameter(Mandatory=$false)][string[]]$Attachments,
        [Parameter(Mandatory=$false)][int]$Port = 25,
        [Parameter(Mandatory=$false)][bool]$UseSsl = $false,
        [Parameter(Mandatory=$false)][System.Management.Automation.PSCredential]$Credential
    )

    # Проверка: хотя бы один получатель должен быть указан
    if (($To -eq $null -or $To.Count -eq 0) -and ($Cc -eq $null -or $Cc.Count -eq 0) -and ($Bcc -eq $null -or $Bcc.Count -eq 0)) {
        Write-Error "Ошибка: Не указаны получатели. Заполните хотя бы один из параметров: To, Cc или Bcc."
        return
    }

    try {
        # Создание объекта письма
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $MailMessage.IsBodyHtml = $false  # Установите в $true, если тело письма в HTML
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body

        # Установка адреса отправителя
        if ($FromDisplayName) {
            $MailMessage.From = New-Object System.Net.Mail.MailAddress($From, $FromDisplayName)
        } else {
            $MailMessage.From = New-Object System.Net.Mail.MailAddress($From)
        }

        # Добавление получателей
        if ($To) { foreach ($recipient in $To) { $MailMessage.To.Add($recipient) } }
        if ($Cc) { foreach ($recipient in $Cc) { $MailMessage.CC.Add($recipient) } }
        if ($Bcc) { foreach ($recipient in $Bcc) { $MailMessage.Bcc.Add($recipient) } }

        # Добавление вложений
        if ($Attachments) {
            foreach ($Attachment in $Attachments) {
                if (Test-Path $Attachment) {
                    $MailMessage.Attachments.Add((New-Object System.Net.Mail.Attachment($Attachment)))
                } else {
                    Write-Warning "Файл не найден и не будет прикреплен: $Attachment"
                }
            }
        }

        # Создание и настройка SMTP-клиента
        $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpServer, $Port)
        $SmtpClient.EnableSsl = $UseSsl
        
        # Если требуются учетные данные
        if ($Credential) {
            $SmtpClient.Credentials = $Credential.GetNetworkCredential()
        }

        # Таймаут для отправки (30 секунд)
        $SmtpClient.Timeout = 30000

        # Попытка отправки письма
        Write-Host "Попытка отправки письма через сервер: $SmtpServer:$Port (SSL: $UseSsl)..."
        $SmtpClient.Send($MailMessage)
        Write-Host "✅ Письмо успешно отправлено!" -ForegroundColor Green

    } catch {
        # Детальный вывод ошибки
        Write-Error "❌ Ошибка при отправке письма: $($_.Exception.Message)"
        
        # Логирование полной информации об ошибке
        $ErrorDetails = @"
Время ошибки: $(Get-Date)
Тип ошибки: $($_.Exception.GetType().FullName)
Сообщение: $($_.Exception.Message)
Стек вызовов: $($_.ScriptStackTrace)
Внутреннее исключение: $($_.Exception.InnerException)
"@
        Write-Warning "Детали ошибки:`n$ErrorDetails"
        
    } finally {
        # Освобождение ресурсов
        if ($MailMessage) { $MailMessage.Dispose() }
        if ($SmtpClient) { $SmtpClient.Dispose() }
    }
}

# ПРИМЕР ИСПОЛЬЗОВАНИЯ функции Send-Email:
# Настройте параметры для своего SMTP-сервера
$emailParams = @{
    SmtpServer = 'smtp.yourcompany.com'  # Замените на ваш SMTP-сервер
    From = 'sender@yourcompany.com'
    To = 'recipient@example.com'
    Subject = 'Тестовое письмо из PowerShell'
    Body = 'Это тестовое письмо, отправленное с помощью .NET классов в PowerShell.'
    Port = 25        # Стандартный порт SMTP. Для SSL обычно 465 или 587
    UseSsl = $false  # Установите $true, если ваш сервер требует SSL
    # Credential = $cred  # Раскомментируйте, если нужна аутентификация
}

# Вызов функции отправки
Send-Email @emailParams
