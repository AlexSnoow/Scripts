<# file Send-Mail.ps1
.SYNOPSIS
    Выполняет отправку писем внутри локальной корпоративной сети

.DESCRIPTION
    Функция для автоматической отправки писем
    Поддерживает включение вложенных файлов, адреса источника и адресаты назначения, Тема письма, тело письма и обработку кодов возврата.

.PARAMETER SRC
    Источник: адрес от кого письмо (обязательный параметр)

.PARAMETER DST
    Назначение: Один или несколько адресов кому письмо (обязательный параметр)

.PARAMETER AttachPath
    Путь к файлу который нужно вложить в письмо

.PARAMETER LogName
    Имя лога (может содержать плейсхолдеры {date}, {time}, {datetime})

.PARAMETER LogPath
    Путь для сохранения логов (по умолчанию: "C:\Logs\mail")

.PARAMETER MaxLogAge
    Максимальный возраст логов в днях (автоочистка старых логов)

.EXAMPLE
    #Запуск из командной строки:

.EXAMPLE
    #Использование в планировщике заданий:
    Program: powershell.exe
    Arguments:

.EXAMPLE
    #Использование в другом скрипте:

.EXAMPLE
    #Создание задания в планировщике через PowerShell

.NOTES
    Автор: Иванов
    Версия: 1.0 (2025-08-19)
    Требуется: Windows (встроенный Robocopy)
#>
Send-MailMessage -From "user1@domain.loc" -To "user2@domain.loc" -Subject "Тема письма" -BodyAsHtml -Body "Тело письма" -SmtpServer "smtpserver.domain.loc" -Encoding ([System.Text.Encoding]::UTF8) -Credential (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "NT AUTHORITY\ANONYMOUS LOGON", (New-Object System.Security.SecureString))