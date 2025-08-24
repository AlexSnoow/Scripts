<# file Copy-Robocopy.ps1
.SYNOPSIS
    Выполняет копирование данных с помощью программы Robocopy

.DESCRIPTION
    Функция для автоматического копирования файлов и папок с использованием Robocopy.
    Поддерживает ведение лога, различные ключи копирования и обработку кодов возврата.

.PARAMETER SRC
    Источник: файл или папка для копирования (обязательный параметр)

.PARAMETER DST
    Папка назначения для сохранения копии (обязательный параметр)

.PARAMETER RobocopyPath
    Путь к исполняемому файлу robocopy (по умолчанию: "robocopy.exe" - используется системный)

.PARAMETER LogName
    Имя лога (может содержать плейсхолдеры {date}, {time}, {datetime})

.PARAMETER LogPath
    Путь для сохранения логов (по умолчанию: "C:\Logs\Robocopy")

.PARAMETER Keys
    Ключи и команды для robocopy (по умолчанию: "/E /Z /COPYALL /R:2 /W:5 /NP /V")

.PARAMETER CheckFreeSpace
    Проверять свободное место перед копированием (в процентах)

.EXAMPLE
    Copy-Robocopy -SRC "D:\Data" -DST "E:\Backup" -Keys "/MIR /Z /R:3 /W:10" -LogName "Mirror-{datetime}"
    Зеркальное копирование с увеличенным количеством повторных попыток и интервалом ожидания

.EXAMPLE
    # Использование в планировщике заданий
    Program: powershell.exe
    Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Copy-Robocopy.ps1" -SRC "C:\Source" -DST "\\Server\Backup" -LogName "DailyBackup-{date}"

.EXAMPLE
    # Использование в другом скрипте
    # Импорт функции
    . .\Copy-Robocopy.ps1
    
    # Многоуровневое копирование
    $copyJobs = @(
        @{SRC = "C:\Websites"; DST = "D:\Backups\Web"; LogName = "WebBackup-{datetime}"},
        @{SRC = "C:\Databases"; DST = "D:\Backups\DB"; LogName = "DBBackup-{datetime}"; Keys = "/MIR /Z /R:3 /W:10"},
        @{SRC = "C:\Logs"; DST = "D:\Backups\Logs"; LogName = "LogsBackup-{datetime}"; Keys = "/E /Z /NP"}
    )

    foreach ($job in $copyJobs) {
        $result = Copy-Robocopy @job
        if ($result -ge 8) {
            Write-Error "Ошибка копирования $($job.SRC)"
            # Дополнительные действия при ошибке
        }
    }

.EXAMPLE
    # Использование как модуля
    Import-Module .\Copy-Robocopy.ps1
    Copy-Robocopy -SRC "C:\Websites" -DST "\\Server\Backup\Web" -Keys "/MIR /Z /R:3 /W:10"

.NOTES
    Автор: Иванов
    Версия: 2.0 (2025-08-19)
    Требуется: Windows (встроенный Robocopy)
#>

function Copy-Robocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SRC,

        [Parameter(Mandatory = $true)]
        [string]$DST,

        [Parameter(Mandatory = $false)]
        [string]$RobocopyPath = "robocopy.exe",

        [Parameter(Mandatory = $false)]
        [string]$LogName = "RobocopyLog-{date}",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "C:\Logs\Robocopy",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "/E /Z /COPYALL /R:2 /W:5 /NP /V",

        [Parameter(Mandatory = $false)]
        [int]$CheckFreeSpace = 10
    )

    # Замена плейсхолдеров в имени лога
    $dateString = Get-Date -Format "yyyyMMdd"
    $timeString = Get-Date -Format "HHmmss"
    $dateTimeString = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $finalLogName = $LogName `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # Замена плейсхолдеров в пути логов
    $LogPath = $LogPath `
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
            return -1
        }
    }

    # Формирование полного пути к лог-файлу
    $logFile = Join-Path $LogPath "$finalLogName.log"

    # Проверка свободного места
    if ($CheckFreeSpace -gt 0) {
        try {
            $sourceSize = (Get-ChildItem $SRC -Recurse -File | Measure-Object Length -Sum).Sum
            $destinationDrive = (Get-Item $DST -ErrorAction Stop).PSDrive.Name
            $freeSpace = (Get-PSDrive -Name $destinationDrive -ErrorAction Stop).Free
            
            $requiredSpace = $sourceSize * (1 + ($CheckFreeSpace / 100))
            
            if ($freeSpace -lt $requiredSpace) {
                Write-Warning "Мало свободного места на целевом диске. Требуется: $([math]::Round($requiredSpace/1GB,2)) GB, доступно: $([math]::Round($freeSpace/1GB,2)) GB"
                $confirm = Read-Host "Продолжить несмотря на недостаток места? (y/n)"
                if ($confirm -ne 'y') {
                    Write-Host "Операция отменена пользователем" -ForegroundColor Yellow
                    return -2
                }
            }
        }
        catch {
            Write-Warning "Не удалось проверить свободное место: $($_.Exception.Message)"
        }
    }

    # Формирование командной строки Robocopy
    $robocopyArgs = @(
        "`"$SRC`"",
        "`"$DST`""
    )
    
    # Добавление ключей
    $Keys.Split(" ") | Where-Object { $_ } | ForEach-Object {
        $robocopyArgs += $_
    }
    
    # Добавление параметров логирования
    $robocopyArgs += "/LOG:`"$logFile`""
    $robocopyArgs += "/TEE"
    $robocopyArgs += "/UNILOG+"  # Юникод-логирование

    Write-Host "Запуск Robocopy..." -ForegroundColor Cyan
    Write-Host "Источник: $SRC" -ForegroundColor Cyan
    Write-Host "Назначение: $DST" -ForegroundColor Cyan
    Write-Verbose "Команда: $RobocopyPath $($robocopyArgs -join ' ')"

    # Выполнение копирования
    try {
        $processInfo = @{
            FilePath = $RobocopyPath
            ArgumentList = $robocopyArgs
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardError = "robocopy_errors.txt"
        }
        
        $process = Start-Process @processInfo
        
        # Анализ кода возврата Robocopy
        $exitCode = $process.ExitCode
        Write-Host "Robocopy завершен с кодом: $exitCode" -ForegroundColor Cyan
        
        # Чтение ошибок, если есть
        if (Test-Path "robocopy_errors.txt") {
            $errors = Get-Content "robocopy_errors.txt" -Raw
            if ($errors) {
                Write-Warning "Ошибки Robocopy: $errors"
                Add-Content -Path $logFile -Value "`nОШИБКИ:`n$errors" -Encoding UTF8
            }
            Remove-Item "robocopy_errors.txt" -Force
        }
        
        # Интерпретация кодов возврата Robocopy
        $successCodes = @(0, 1, 2, 3)  # Успешные коды
        $warningCodes = @(4, 5, 6, 7)  # Коды с предупреждениями
        
        if ($exitCode -in $successCodes) {
            Write-Host "Копирование успешно завершено!" -ForegroundColor Green
            if ($exitCode -gt 0) {
                Write-Host "Примечание: некоторые файлы были пропущены (код: $exitCode)" -ForegroundColor Yellow
            }
        }
        elseif ($exitCode -in $warningCodes) {
            Write-Warning "Копирование завершено с предупреждениями (код: $exitCode)"
        }
        else {
            Write-Error "Копирование завершено с ошибками (код: $exitCode)"
        }
        
        Write-Host "Лог-файл: $logFile" -ForegroundColor Cyan
        
        # Краткий анализ лог-файла
        if (Test-Path $logFile) {
            try {
                $logContent = Get-Content $logFile -Tail 20 -Encoding UTF8
                Write-Host "`nКраткая статистика:" -ForegroundColor Cyan
                $logContent | Where-Object { $_ -match "(Dirs|Files|Bytes|Times|Total|Copied|Skipped|Failed|Extras|Ended)" } | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Cyan
                }
            }
            catch {
                Write-Warning "Не удалось прочитать лог-файл: $($_.Exception.Message)"
            }
        }
        
        return $exitCode
    }
    catch {
        Write-Error "Ошибка при выполнении Robocopy: $($_.Exception.Message)"
        return -1
    }
}

# Если скрипт запущен напрямую (не импортирован как модуль)
if ($MyInvocation.InvocationName -eq $MyInvocation.ScriptName) {
    param(
        [string]$SRC,
        [string]$DST
    )
    if (-not $SRC) { $SRC = Read-Host "Укажите путь к источнику (SRC)" }
    if (-not $DST) { $DST = Read-Host "Укажите путь к папке назначения (DST)" }
    
    $params = @{
        SRC = $SRC
        DST = $DST
    }
    Copy-Robocopy @params
}
else {
    # Экспорт функции для использования в других скриптах
    Export-ModuleMember -Function Copy-Robocopy -Alias robocopy-backup
}