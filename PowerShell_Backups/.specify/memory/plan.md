# Технический план реализации PowerShell модуля резервного копирования

## 1. Структура проекта

Все файлы будут размещены в корневой директории проекта для простоты.

```
/
|-- Backup-Logger.psm1
|-- Backup-RAR.psm1
|-- Backup-7z.psm1
|-- Backup-Zip.psm1
|-- Remove-OldFiles.psm1
|-- Mail-Email-Send.psm1
|-- Backup-Copy.psm1
|-- Backup-Main-Folders.ps1
|-- Backup-Main-Files.ps1
|-- /Tests/
    |-- Create-TestFiles.ps1
    |-- Backup.Tests.ps1
```

## 2. Реализация модулей (`.psm1`)

### 2.1. `Mail-Email-Send.psm1`
Будет реализована функция `Send-Email`, как в вашем примере, для отправки почтовых уведомлений.

```powershell
<#
.SYNOPSIS
    Модуль для отправки email-сообщений.
#>
function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$From,
        [Parameter(Mandatory=$true)][string]$To,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body
    )
    
    $SmtpServer = "cas.head.energotransbank.com"
    $Encoding = [System.Text.Encoding]::UTF8
    
    try {
        Send-MailMessage -From $From -To $To -Subject $Subject -Body $Body `
                        -SmtpServer $SmtpServer -Encoding $Encoding -BodyAsHtml:$false `
                        -Credential (New-Object System.Management.Automation.PSCredential("NT AUTHORITY\ANONYMOUS LOGON", (New-Object System.Security.SecureString))) -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Ошибка отправки email: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Send-Email
```

### 2.2. Прочие модули
Остальные модули (`Backup-Logger`, `Backup-RAR` и т.д.) будут реализованы как набор функций, экспортируемых через `Export-ModuleMember`, в соответствии со спецификацией.

## 3. Реализация основных скриптов (`.ps1`)

Скрипты `Backup-Main-Folders.ps1` и `Backup-Main-Files.ps1` будут содержать в себе логику оркестрации, а также встроенные блоки конфигурации, как вы и указали.

### Пример заголовка и конфигурации для `Backup-Main-Folders.ps1`:
```powershell
<#
.FILE Backup-Main-Folders.ps1
.SYNOPSIS
    Резервное копирование каталогов с архивацией и ротацией.
.DESCRIPTION
    Архивирует каталоги, поддерживает исключения, ротацию и email-отчеты.
#>

#region Настройки
$JobName = "testBackups"
# ... (остальные общие настройки) ...
#endregion

#region Конфигурация заданий
$BackupJobs = @{
    Job1 = @{
        Source        = "C:\testBackups\JOB1_folder\"
        # ... (параметры задания) ...
    }
}
#endregion

# ... (далее основной код скрипта) ...
```

## 4. Тестирование

Будет создана папка `/Tests`.

### 4.1. `Create-TestFiles.ps1`
Скрипт для генерации тестовых данных (файлов и папок) для проверки сценариев бэкапа и ротации.

```powershell
# Скрипт для создания тестовых файлов
$testPath = "C:\testBackups\JOB3_folder_exect\"
if (-not (Test-Path -Path $testPath)) {
    New-Item -ItemType Directory -Path $testPath -Force | Out-Null
}

# Создаем файлы с разными датами
for ($i = 0; $i -lt 12; $i++) {
    $fileName = "$testPath\File_$i.txt"
    $fileDate = (Get-Date).AddDays(-$i)
    "Тестовый файл" | Out-File -FilePath $fileName
    Set-ItemProperty -Path $fileName -Name LastWriteTime -Value $fileDate
}
```

### 4.2. `Backup.Tests.ps1`
Основной файл с тестами Pester. Будет содержать `Describe` и `It` блоки для проверки:
- Корректности создания архивов.
- Правильности работы исключений.
- Работы механизма ротации.
- Функционирования каждого модуля в отдельности (модульные тесты).

## 5. Порядок реализации
1. Создать структуру файлов.
2. Реализовать `Backup-Logger.psm1` как основу для всех модулей.
3. Реализовать модули архивации (`-RAR`, `-7z`, `-Zip`).
4. Реализовать вспомогательные модули (`-Copy`, `-OldFiles`, `-Email`).
5. Написать скрипты-оркестраторы (`-Main-Folders`, `-Main-Files`).
6. Написать тесты Pester и скрипты для их подготовки.