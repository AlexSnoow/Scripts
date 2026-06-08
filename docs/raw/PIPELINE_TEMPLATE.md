# Шаблон 5-Stage Pipeline

> Мета-шаблон для создания скриптов с единым 5-этапным конвейером
> на PowerShell (Windows) и Bash (Linux/Solaris).
>
> **Охват:** Backup, Copy, Sync, Cleanup, Monitor
> **Цель:** Унификация структуры всех скриптов проекта

---

## 1. Концепция "5-Stage Pipeline"

### 1.1. Общее описание

Все скрипты проекта независимо от назначения (Backup, Copy, Sync, Cleanup, Monitor)
исполняются по единому 5-этапному конвейеру. Каждый этап имеет строго определённую
ответственность и интерфейс. Нарушение порядка этапов запрещено.

Конвейер гарантирует:
- Предсказуемый поток выполнения
- Единообразную обработку ошибок на каждом этапе
- Возможность повторного использования кода между скриптами
- Прозрачное логирование и отчётность

### 1.2. Этап 1: Подготовка (Preparation)

**Назначение:** Загрузка конфигурации, валидация входных данных, инициализация
окружения, создание необходимых директорий.

**Типовые операции:**
- Загрузка XML/conf конфигурации
- Проверка наличия конфигурации (хеш-сумма для критичных файлов)
- Валидация параметров (существуют ли Source, доступны ли пути)
- Разбор секции <Jobs>, подготовка контекста для каждого задания
- Инициализация системы логирования
- Проверка целостности внешних утилит (хеш бинарников)

**Выход:** Контекст выполнения $ctx / $JOB_* переменные

### 1.3. Этап 2: Основная операция (Main Operation)

**Назначение:** Выполнение профильной операции скрипта (архивация, копирование,
синхронизация, очистка, проверка).

**Типовые операции:**
- Backup: архивация RAR / 7zip / powershell zip / tar.gz
- Copy: копирование файлов с контролем
- Sync: синхронизация source <> dest через Compare-Object / rsync
- Cleanup: удаление файлов по маскам и политикам
- Monitor: сбор метрик (диски, пути, размеры)

**Выход:** Код возврата / количество ошибок этапа

### 1.4. Этап 3: Верификация (Verification)

**Назначение:** Проверка целостности результата основной операции.

**Типовые операции:**
- Backup: проверка кода возврата главной операции (для архивов: проверка наличия архива, тест архива, если tar.gz отдельная проверка tar и gz)
- Copy: сравнение размеров исходного и скопированного файла
- Sync: проверка, что все файлы синхронизированы
- Cleanup: проверка, что файлы удалены (или подсчёт удалённых)
- Monitor: проверка метрик на соответствие порогам

**Выход:** true/false — прошла ли верификация

### 1.5. Этап 4: Пост-операции (Post-Operations)

**Назначение:** Ротация старых данных, копирование в удалённое хранилище, очистка временных файлов.

**Типовые операции:**
- Backup: ротация старых архивов по DaysOld/KeepCount, копирование в RemoteDest
- Copy: перемещение верифицированных файлов в Arhive
- Sync: удаление файлов в dest, которых нет в source (при full sync)
- Cleanup: дополнительные действия после очистки
- Monitor: (обычно нет пост-операций, но можно записать событие)

**Выход:** Строка результата / количество удалённых объектов

### 1.6. Этап 5: Отчётность (Reporting)

**Назначение:** Формирование отчётов (XML/CSV), отправка email-уведомлений, запись в лог итогов выполнения.

**Типовые операции:**
- Агрегация результатов всех Job в один лог файл
- формирование результатов по каждому Job
- Формирование Subject и Body для email
- Отправка email через Send-Email
- Сохранение XML/CSV отчётов в LogPathRoot
- Запись сводки в лог

**Выход:** exit code 0 (успех) / 1 (ошибки)

### 1.7. Mermaid-диаграмма конвейера

`mermaid
graph LR
    A[Preparation] --> B[Main Operation]
    B --> C[Verification]
    C --> D[Post-Operations]
    D --> E[Reporting]
    E --> F{Errors?}
    F -->|0| G[Exit 0]
    F -->|>0| H[Exit 1]
`

**Упрощённая схема:**
`
[Preparation] -> [Main Operation] -> [Verification] -> [Post-Operations] -> [Reporting]
`

**Детальная схема с ветвлением:**

`mermaid
graph TD
    Start --> LoadConfig[Load Configuration]
    LoadConfig --> Validate[Validate Config and Env]
    Validate --> ForEachJob{For each Job}
    ForEachJob -->|next Job| PrepareCtx[Prepare Context]
    PrepareCtx --> MainOp[Execute Main Operation]
    MainOp --> Verify{Verification}
    Verify -->|PASS| PostOp[Post-Operations]
    Verify -->|FAIL| LogError[Log Error]
    LogError --> ForEachJob
    PostOp --> ForEachJob
    ForEachJob -->|all done| Aggregate[Aggregate Results]
    Aggregate --> SendReport[Send Email Report]
    SendReport --> Exit
`

### 1.8. Принципы из constitution.md

При разработке любого скрипта по данному шаблону необходимо соблюдать
следующие принципы из docs/constitution.md:

| Принцип | Суть | Применение в шаблоне |
|---------|------|----------------------|
| **PS 2.0 совместимость** | Весь код PowerShell должен работать на PS 2.0 / Windows 7 | Использовать Get-FileHashCompat, Test-Empty, New-Object PSObject |
| **KISS** | Простота и очевидность решений | Каждый этап — одна функция с single responsibility |
| **Единый конвейер (Unified Pipeline)** | Обязательный порядок: Preparation -> Main -> Verify -> Post -> Report | Нарушение порядка запрещено |
| **DRY** | Повторяющаяся логика -> отдельные функции | Write-Log, Send-Email, Remove-OldFiles — общие для всех скриптов |
| **SOLID (единственная ответственность)** | Каждая функция — одна доменная операция | Start-RarArchive -> только архивация, Invoke-Verification -> только проверка |
| **YAGNI** | Только то, что есть в конфиге, без кода "на будущее" | TODO-маркеры только для следующих спринтов |
| **Чистый код** | Без скрытых побочных эффектов | Модификация файлов только в Post-Operations |
| **Обработка ошибок** | try/catch с логированием, запрещён SilentContinue | Каждый этап обёрнут в try/catch |
| **Кодировки** | OEM(CP866) для логов, UTF8 без BOM для отчётов | $Script:EncodingOEM, $Script:EncodingUTF8NoBOM |

---
## 2. Реализация в Backup-ps2-g-v4.ps1 (эталон)

Файл: `app/ps/backup/Backup-ps2-g-v4.ps1` (901 строка)

### 2.1. Точка входа (строки 766–901)

Главный блок скрипта начинается после объявления всех функций.
Последовательность:

1. Проверка конфигурации — `if (-not (Test-Path $ConfigPath))`
2. Верификация целостности — `Test-FileIntegrity` для XML-конфига
3. Загрузка XML — `[xml] $script:Config = Get-Content $ConfigPath`
4. Инициализация переменных — разбор General, Paths, Recipients
5. Создание LogPathRoot — если не существует
6. Верификация RAR — `Test-FileIntegrity` для RAR.exe
7. testmode — если ключ `-testmode`, вызов `Invoke-TestMode` и exit
8. Цикл по Jobs — `foreach ($job in $Config.BackupConfig.Jobs.Job)`
9. Вызов Invoke-Job — выполнение задания
10. Сбор результатов — агрегация в `$totalErrors`
11. Пост-операции — ротация логов, информация о дисках
12. Отчётность — отправка email, exit code

### 2.2. Инициализация пайплайна (строки 768–794)

```
# Проверка наличия конфига
if (-not (Test-Path $ConfigPath)) { exit }

# Проверка целостности XML
if (-not (Test-FileIntegrity -FilePath $ConfigPath -ExpectedHash $XmlHash -FileType $ConfigPath)) { exit 1 }

# Загрузка XML
[xml] $script:Config = Get-Content $ConfigPath

# Разбор секций
$script:General    = $script:Config.BackupConfig.General
$script:Paths      = $script:Config.BackupConfig.Paths
$script:Recipients = $script:Config.BackupConfig.Recipients
$script:JobName    = $script:General.JobName
$script:Domain     = $script:General.Domain
$script:SmtpServer = $script:General.SmtpServer
$script:LogPathRoot = $script:Paths.LogPathRoot

# Инициализация лога
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $LogPathRoot ("$PCName" + "_" + $JobName + "_" + $DateLog + ".log")
```

### 2.3. Preparation -> Invoke-Job (строки 684–762)

Функция `Invoke-Job` — центральный элемент подготовки.
Она создаёт контекст `$ctx` — хеш-таблицу со всеми параметрами задания.

Preparation в Backup включает:
1. Создание контекста `$ctx` с Source, Dest, Pattern, фильтрами
2. Проверка существования Source
3. Создание Dest и RemoteDest при необходимости
4. Определение режима архивации
5. Вызов соответствующей Prepare-* функции

```
function Invoke-Job {
    param($Config, $Job)
    $checkErrors = 0
    $jobLog = @()
    $ctx = @{
        Config             = $Config
        Job                = $Job
        JobName            = $Job.Name
        Source             = $Job.Source
        Dest               = $Job.LocalDest
        LocalDestDaysOld   = [int] $Job.LocalDestDaysOld
        LocalDestKeepCount = [int] $Job.LocalDestKeepCount
        RarPath            = $Config.Paths.RarPath
        RarHASH            = $Config.Paths.RarHASH
        PCName             = $PCName
        Pattern            = ""
        ExcludeToday       = To-Bool $Job.ExcludeToday
        SourceFilter       = "*"
        ArchiveAll         = To-Bool $Job.ArchiveAll
        RemoteDest         = $Job.RemoteDest
    }
    if (-not (Test-Path $ctx.Source)) { $checkErrors++; return }
    if (-not (Test-Path $ctx.Dest)) { New-Item -ItemType Directory -Path $ctx.Dest | Out-Null }
    if ($ctx.ArchiveAll) { $groups = Prepare-ArchiveAll $ctx }
    elseif (To-Bool $Job.ArchiveByDate) { $groups = Prepare-ArchiveByDate $ctx }
    elseif (To-Bool $Job.ArchiveIndividualFiles) { $groups = Prepare-IndividualFiles $ctx }
    elseif (To-Bool $Job.ArchiveIndividualFolders) { $groups = Prepare-IndividualFolders $ctx }
}
```

### 2.4. Main Operation -> Invoke-Archiving (строки 628–679)

Функция `Invoke-Archiving` — сердце скрипта. Выполняет архивацию через RAR.exe.

```
function Invoke-Archiving {
    param($ctx, $groups)
    foreach ($key in $groups.Keys) {
        $items = $groups[$key]
        $archiveName = Resolve-Name $ctx.Pattern $ctx.PCName $ctx.JobName $key $key
        $archivePath = Join-Path $ctx.Dest $archiveName
        $listFile = [System.IO.Path]::ChangeExtension($archivePath, ".txt")
        $items | Out-File -Encoding ASCII $listFile
        $args = (Get-RarParams $ctx) + " '" + $archivePath + "' @" + $listFile
        $p = Start-Process -FilePath $ctx.RarPath -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) { Copy-Remote $ctx $archivePath }
        else { $checkErrors++ }
    }
    return $checkErrors
}
```

### 2.5. Verification -> ExitCode + Test-FileIntegrity (строки 667–676, 241–293)

Верификация в Backup двухуровневая:

1. ExitCode RAR (строка 667): `if ($p.ExitCode -eq 0)` — минимальная проверка
2. Test-FileIntegrity (строки 241–293) — SHA256 хеш для конфига и RAR.exe

```
function Test-FileIntegrity {
    param([string]$FilePath, [string]$ExpectedHash, [string]$FileType = "файл")
    if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) { return $false }
    if (-not (Test-Path $FilePath -PathType Leaf)) { return $false }
    $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToUpper()
    return ($actualHash -eq $ExpectedHash.ToUpper())
}
```

### 2.6. Post-Operations -> Remove-OldFiles + Copy-Remote (строки 354–422, 329–348)

Copy-Remote (строки 329–348) — копирование архива в удалённое хранилище:

```
function Copy-Remote {
    param($ctx, $archivePath)
    if (Test-Empty $ctx.RemoteDest) { return }
    if (-not (Test-Path $ctx.RemoteDest)) { New-Item -ItemType Directory -Path $ctx.RemoteDest | Out-Null }
    $destPath = Join-Path $ctx.RemoteDest ([System.IO.Path]::GetFileName($archivePath))
    Copy-Item -Path $archivePath -Destination $destPath -Force
    Write-Log ("COPY REMOTE: " + $destPath)
}
```

Remove-OldFiles (строки 354–422) — ротация по DaysOld и KeepCount:

```
function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)
    $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
    [array] $allFiles = Get-ChildItem -Path $Path -Filter $Filter |
        Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTime -Descending
    [array] $filesToKeep = @()
    if ($KeepCount -gt 0) { $filesToKeep = $allFiles | Select-Object -First $KeepCount }
    [array] $filesToDelete = @()
    foreach ($f in $allFiles) {
        $keep = $false
        foreach ($k in $filesToKeep) { if ($k.FullName -eq $f.FullName) { $keep = $true; break } }
        if (-not $keep -and $f.LastWriteTime -lt $cutoffDate) { $filesToDelete += $f }
    }
    foreach ($file in $filesToDelete) {
        try { Remove-Item $file.FullName -Force -ErrorAction Stop }
        catch { Write-Log ("Ошибка удаления: " + $file.FullName) }
    }
}
```

### 2.7. Reporting -> Send-Email + отчёты (строки 24–81, 846–900)

Send-Email (строки 24–81):

```
function Send-Email {
    param($Config, [string]$SmtpServer, [string]$From, [string]$To,
          [string]$Subject, [string]$Body, [int]$Port = 25)
    try {
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer, $Port)
        $msg = New-Object Net.Mail.MailMessage
        $msg.From = $From; $msg.To.Add($To)
        $msg.Subject = $Subject; $msg.Body = $Body
        $smtp.Send($msg)
    } catch { Write-Host "[MAIL] Error: $($_.Exception.Message)" }
}
```

Блок отчётности (строки 846–900) — после цикла по всем Job:

```
foreach ($jobName in $jobResults.Keys) {
    Write-Host "Job: $jobName | Errors: $($jobResults[$jobName].Errors)"
}
Remove-OldFiles -Path $LogPathRoot -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.*"
$DiskInfo = Get-DiskSpaceReport
if ($totalErrors -eq 0) { $SubjectMail = "BACKUP SUCCESS ..."; $exitcode = 0 }
else { $SubjectMail = "BACKUP ERRORS: ..."; $exitcode = 1 }
Send-Email -Config $Config -To $recipients -Subject $SubjectMail -Body $BodyMailLog
exit $exitcode
```

### 2.8. Схема общего потока

```
Main (line 766)
  |-> foreach Job
  |     |-> Invoke-Job (line 684)
  |     |     |-> Prepare-* (line 521-622) -> groups
  |     |     |-> Invoke-Archiving (line 628)
  |     |     |     |-> RAR.exe -> ExitCode
  |     |     |     |-> Copy-Remote
  |     |     |-> Remove-OldFiles (local archives)
  |     |     |-> return @{Errors; Log}
  |-> Remove-OldFiles (logs)
  |-> Get-DiskSpaceReport
  |-> Send-Email
  |-> exit
```

---
## 3. PowerShell Skeleton (готовый код)

### 3.1. sync-ps-v4.ps1 (полностью рабочий скрипт)

```powershell
# PowerShell -ExecutionPolicy RemoteSigned -file .\sync-ps-v4.ps1 -ConfigurationPath .\Sync-Config.xml
# powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\sync-ps-v4.ps1 -ConfigurationPath .\Sync-Config.xml -testmode

param(
    [string]$ConfigurationPath = ".\Sync-Config.xml",
    [switch]$testmode
)

# ============================================================================
# ОБЩИЕ ФУНКЦИИ
# ============================================================================

function Write-Log {
    param([string]$Message)
    if (-not $Message -or -not $script:GlobalLog) { return }
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}

function Send-Email {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $false)][string]$SmtpServer,
        [Parameter(Mandatory = $false)][string]$From,
        [Parameter(Mandatory = $false)][string]$To,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $false)][int]$Port = 25,
        [Parameter(Mandatory = $false)][bool]$UseSSL = $false
    )
    if (-not $SmtpServer) { $SmtpServer = $Config.SyncConfig.General.SmtpServer }
    if (-not $From) { $From = "$env:COMPUTERNAME@$($Config.SyncConfig.General.Domain)" }
    if (-not $To) { $To = $Config.SyncConfig.Recipients.AdminMail }
    try {
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer, $Port)
        $msg = New-Object Net.Mail.MailMessage
        $msg.From = $From; $msg.To.Add($To)
        $msg.Subject = $Subject; $msg.Body = $Body
        $smtp.Send($msg)
        Write-Host "[MAIL] Sent: $Subject" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[MAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally { $msg = $null; $smtp = $null }
}

function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'LiteralPath')]
        [string]$LiteralPath,
        [string]$Algorithm = 'SHA256'
    )
    process {
        $filePath = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        try {
            $hashAlgo = switch ($Algorithm.ToUpper()) {
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'MD5'    { [System.Security.Cryptography.MD5]::Create() }
                default  { [System.Security.Cryptography.SHA256]::Create() }
            }
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                return (New-Object PSObject -Property @{
                    Hash = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path = (Resolve-Path -LiteralPath $filePath).Path
                })
            } finally { $fileStream.Dispose() }
        } catch {
            throw "Error computing hash: $($_.Exception.Message)"
        }
    }
}

function Test-Empty { param([string]$s); return ($s -eq $null -or $s.Trim().Length -eq 0) }

function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}

function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)
    $results = @()
    if (-not $Path) { return "Path is empty" }
    if (-not (Test-Path $Path -PathType Container)) { return "Directory not found: $Path" }
    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
        [array] $allFiles = Get-ChildItem -Path $Path -Filter $Filter |
            Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTime -Descending
        if ($allFiles.Count -eq 0) { return "No files to process" }
        [array] $filesToKeep = @()
        if ($KeepCount -gt 0) { $filesToKeep = $allFiles | Select-Object -First $KeepCount }
        [array] $filesToDelete = @()
        foreach ($f in $allFiles) {
            $keep = $false
            foreach ($k in $filesToKeep) { if ($k.FullName -eq $f.FullName) { $keep = $true; break } }
            if (-not $keep -and $f.LastWriteTime -lt $cutoffDate) { $filesToDelete += $f }
        }
        foreach ($file in $filesToDelete) {
            try { Remove-Item $file.FullName -Force -ErrorAction Stop; $results += "Deleted: $($file.Name)" }
            catch { $results += "Error deleting: $($file.FullName) $_" }
        }
        $results += "Rotation complete. Kept: $($allFiles.Count - $filesToDelete.Count) / Total: $($allFiles.Count)"
    } catch { $results += "Rotation error: $_" }
    return ($results -join "`n")
}

function Get-DiskSpaceReport {
    param([string]$ComputerName = $env:COMPUTERNAME)
    try {
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object {
            $_ -ne $null -and $_.IsReady -and $_.DriveType -eq 'Fixed' -and $_.TotalSize -gt 1073741824
        }
        $diskStrings = @()
        foreach ($drive in $drives) {
            if ($drive.TotalSize -eq 0) { continue }
            $sizeGB = [math]::Round($drive.TotalSize / 1073741824, 1)
            $freeGB = [math]::Round($drive.AvailableFreeSpace / 1073741824, 1)
            $freePct = [math]::Round(($drive.AvailableFreeSpace / $drive.TotalSize) * 100, 1)
            $diskStrings += "Drive $($drive.Name.TrimEnd('\')) Total(GB)=$sizeGB Free(GB)=$freeGB Free=$freePct%"
        }
        if ($diskStrings.Count -eq 0) { return "No local drives > 1 GB" }
        return ($diskStrings -join " ; ")
    } catch { return ("Error: " + $_.Exception.Message) }
}
# ============================================================================
# ФУНКЦИИ СИНХРОНИЗАЦИИ
# ============================================================================

function Sync-Job {
    param($Config, $Job)

    $checkErrors = 0
    $jobLog = @()

    $ctx = @{
        Config       = $Config
        Job          = $Job
        JobName      = $Job.Name
        Source       = $Job.Source
        Dest         = $Job.Dest
        Mode         = if ($Job.Mode) { $Job.Mode } else { "incremental" }
        ExcludeToday = To-Bool $Job.ExcludeToday
        SourceFilter = if ($Job.SourceFilter) { $Job.SourceFilter } else { "*" }
        PCName       = $env:COMPUTERNAME
    }

    # --- STAGE 1: Preparation ---
    Write-Log ("===== SYNC JOB START " + $ctx.JobName + " =====")
    $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " ===== SYNC JOB START " + $ctx.JobName + " =====")

    if (-not (Test-Path $ctx.Source)) {
        Write-Host "  [WARN] Source not found: $($ctx.Source)" -ForegroundColor Yellow
        $checkErrors++
        return @{ Errors = $checkErrors; Log = $jobLog }
    }
    if (-not (Test-Path $ctx.Dest)) { New-Item -ItemType Directory -Path $ctx.Dest | Out-Null }

    [array] $sourceFiles = Get-ChildItem -Path $ctx.Source -Filter $ctx.SourceFilter |
        Where-Object { -not $_.PSIsContainer } | Select-Object -ExpandProperty Name
    [array] $destFiles = Get-ChildItem -Path $ctx.Dest |
        Where-Object { -not $_.PSIsContainer } | Select-Object -ExpandProperty Name

    # --- STAGE 2: Main Operation ---
    $filesToCopy = @(); $filesToDelete = @(); $syncCount = 0

    if ($ctx.Mode -eq "full") {
        $filesToCopy = $sourceFiles
        $filesToDelete = $destFiles | Where-Object { $_ -notin $sourceFiles }
        foreach ($fileName in $filesToCopy) {
            $srcPath = Join-Path $ctx.Source $fileName
            $dstPath = Join-Path $ctx.Dest $fileName
            try { Copy-Item -Path $srcPath -Destination $dstPath -Force; $syncCount++
                Write-Log ("SYNC COPY: " + $fileName) }
            catch { Write-Host "  [FAIL] Copy error: $fileName" -ForegroundColor Red; $checkErrors++ }
        }
        foreach ($fileName in $filesToDelete) {
            try { Remove-Item -Path (Join-Path $ctx.Dest $fileName) -Force
                Write-Log ("SYNC DELETE: " + $fileName) }
            catch { $checkErrors++ }
        }
    } else {
        # Incremental: compare and copy new/modified files
        $filesToCopy = Compare-Object $sourceFiles $destFiles |
            Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -ExpandProperty InputObject
        foreach ($fileName in $filesToCopy) {
            $srcPath = Join-Path $ctx.Source $fileName
            $dstPath = Join-Path $ctx.Dest $fileName
            try { Copy-Item -Path $srcPath -Destination $dstPath -Force; $syncCount++
                Write-Log ("SYNC COPY: " + $fileName) }
            catch { Write-Host "  [FAIL] Copy error: $fileName" -ForegroundColor Red; $checkErrors++ }
        }
    }

    # --- STAGE 3: Verification ---
    $verifiedCount = 0
    foreach ($fileName in $filesToCopy) {
        $srcPath = Join-Path $ctx.Source $fileName
        $dstPath = Join-Path $ctx.Dest $fileName
        if ((Test-Path $dstPath) -and (Get-Item $dstPath).Length -eq (Get-Item $srcPath).Length) {
            $verifiedCount++
        } else { Write-Host "  [FAIL] Verification failed: $fileName" -ForegroundColor Red; $checkErrors++ }
    }

    Write-Log ("===== SYNC JOB END " + $ctx.JobName + " =====")
    return @{ Errors = $checkErrors; Log = $jobLog; SyncCount = $syncCount; VerifiedCount = $verifiedCount }
}

# ============================================================================
# MAIN
# ============================================================================

if (-not (Test-Path $ConfigurationPath)) { Write-Host "Config not found: $ConfigurationPath"; exit }

[xml] $script:Config = Get-Content $ConfigurationPath
$script:General     = $script:Config.SyncConfig.General
$script:Paths       = $script:Config.SyncConfig.Paths
$script:Recipients  = $script:Config.SyncConfig.Recipients
$script:ParentJobName = $script:General.ParentJobName
$script:SmtpServer  = $script:General.SmtpServer
$script:LogPathRoot = $script:Paths.LogPathRoot
$script:LogDaysOld  = [int] $script:Paths.LogDaysOld
$script:LogKeepCount = [int] $script:Paths.LogKeepCount

$PCName = $env:COMPUTERNAME
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:ParentJobName + "_" + $DateLog + ".log")
if (-not (Test-Path $script:LogPathRoot)) { New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null }
Write-Log ("SYNC START PCNAME: " + $PCName)

if ($testmode) {
    Write-Host "[TEST MODE] Checking configuration..." -ForegroundColor Cyan
    foreach ($job in $script:Config.SyncConfig.Jobs.Job) {
        Write-Host "  Job: $($job.Name)" -ForegroundColor Yellow
        if (Test-Path $job.Source) { Write-Host "    [OK] Source: $($job.Source)" -ForegroundColor Green }
        else { Write-Host "    [FAIL] Source: $($job.Source)" -ForegroundColor Red }
    }
    exit
}

# Pipeline
$totalErrors = 0; $totalSyncCount = 0; $totalVerifiedCount = 0; $jobResults = @{}
foreach ($job in $script:Config.SyncConfig.Jobs.Job) {
    $result = Sync-Job $script:Config $job
    $jobResults[$job.Name] = $result
    $totalErrors += $result.Errors; $totalSyncCount += $result.SyncCount; $totalVerifiedCount += $result.VerifiedCount
}

# --- STAGE 5: Reporting ---
foreach ($jobName in $jobResults.Keys) {
    $result = $jobResults[$jobName]
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host "Job: $jobName | Errors: $($result.Errors)" -ForegroundColor $(if ($result.Errors -eq 0) { "Green" } else { "Red" })
    Write-Host "  Synced: $($result.SyncCount) | Verified: $($result.VerifiedCount)" -ForegroundColor Cyan
}

Remove-OldFiles -Path $script:LogPathRoot -DaysOld $script:LogDaysOld -KeepCount $script:LogKeepCount -Filter "*.*"
$DiskInfo = Get-DiskSpaceReport; Write-Log "DISK: $DiskInfo"
Write-Log "[TOTAL] JOBS: $($jobResults.Count)"; Write-Log "[TOTAL] ERRORS: $totalErrors"

$BodyMailLog = [string]::Join("`n", (Get-Content $script:GlobalLog))
$recipients = $script:Config.SyncConfig.Recipients.AdminMail
$ParentJobName = $script:Config.SyncConfig.General.ParentJobName

if ($totalErrors -eq 0) { $SubjectMail = "SYNC SUCCESS $ParentJobName $PCName"; $exitcode = 0 }
else { $SubjectMail = "SYNC ERRORS: $totalErrors $ParentJobName $PCName"; $exitcode = 1 }

Send-Email -Config $Config -To $recipients -Subject $SubjectMail -Body $BodyMailLog
exit $exitcode
```
### 3.2. cleanup-ps-v4.ps1 (с TODO-маркерами)

```powershell
# PowerShell -ExecutionPolicy RemoteSigned -file .\cleanup-ps-v4.ps1 -ConfigurationPath .\Cleanup-Config.xml
# powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\cleanup-ps-v4.ps1 -ConfigurationPath .\Cleanup-Config.xml -testmode

param(
    [string]$ConfigurationPath = ".\Cleanup-Config.xml",
    [switch]$testmode
)

# ============================================================================
# ОБЩИЕ ФУНКЦИИ (TODO: вынести в общий модуль)
# ============================================================================

function Write-Log { param([string]$Message)
    if (-not $Message -or -not $script:GlobalLog) { return }
    Add-Content -Path $script:GlobalLog -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message) -ErrorAction SilentlyContinue
}

function Send-Email { param($Config, [string]$Subject, [string]$Body)
    try {
        $smtp = New-Object Net.Mail.SmtpClient($Config.CleanupConfig.General.SmtpServer, 25)
        $msg = New-Object Net.Mail.MailMessage
        $msg.From = "$env:COMPUTERNAME@$($Config.CleanupConfig.General.Domain)"
        $msg.To.Add($Config.CleanupConfig.Recipients.AdminMail)
        $msg.Subject = $Subject; $msg.Body = $Body
        $smtp.Send($msg)
        Write-Host "[MAIL] Sent: $Subject" -ForegroundColor Green
    } catch { Write-Host "[MAIL] Error: $($_.Exception.Message)" -ForegroundColor Red }
}

function Test-Empty { param([string]$s); return ($s -eq $null -or $s.Trim().Length -eq 0) }

# ============================================================================
# ФУНКЦИИ ОЧИСТКИ
# ============================================================================

function Invoke-CleanupJob {
    param($Config, $Job)

    $checkErrors = 0; $jobLog = @(); $deletedCount = 0; $freedBytes = 0

    # --- STAGE 1: Preparation ---
    Write-Log ("===== CLEANUP JOB START " + $Job.Name + " =====")

    $TargetPath  = $Job.TargetPath
    $FileMasks   = if ($Job.FileMasks) { $Job.FileMasks.Split(',') } else @("*.*")
    $DaysOld     = [int] $Job.DaysOld
    $KeepCount   = [int] $Job.KeepCount
    $Recurse     = ($Job.Recurse -eq "true")

    # TODO: Добавить проверку на опасные пути (System32, Program Files)
    # TODO: Добавить белый список исключений (ExcludePatterns)

    if (Test-Empty $TargetPath) {
        return @{ Errors = 1; Log = @("TargetPath is empty"); Deleted = 0; FreedBytes = 0 }
    }
    if (-not (Test-Path $TargetPath -PathType Container)) {
        return @{ Errors = 0; Log = @("Path not found: $TargetPath"); Deleted = 0; FreedBytes = 0 }
    }

    # --- STAGE 2: Main Operation ---
    $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }
    $searchOption = if ($Recurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }

    foreach ($mask in $FileMasks) {
        $mask = $mask.Trim()
        if (Test-Empty $mask) { continue }
        Write-Log ("  Searching mask: " + $mask)

        # TODO: Для PS 2.0 использовать [System.IO.DirectoryInfo]::GetFiles($mask)
        # TODO: Реализовать прогресс-бар для больших директорий
        [array] $files = Get-ChildItem -Path $TargetPath -Filter $mask -Recurse:$Recurse |
            Where-Object { -not $_.PSIsContainer }

        [array] $sortedFiles = $files | Sort-Object LastWriteTime
        [array] $candidatesForDeletion = @()

        if ($KeepCount -gt 0 -and $sortedFiles.Count -gt $KeepCount) {
            $candidatesForDeletion = $sortedFiles | Select-Object -First ($sortedFiles.Count - $KeepCount)
            Write-Log ("  KeepCount=$KeepCount, files=$($sortedFiles.Count), to delete=$($candidatesForDeletion.Count)")
        } else {
            $candidatesForDeletion = $sortedFiles | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        }

        foreach ($file in $candidatesForDeletion) {
            try {
                $size = $file.Length
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $deletedCount++; $freedBytes += $size
                Write-Log ("  Deleted: " + $file.FullName)
            } catch {
                Write-Host "  [FAIL] Delete error: $($file.FullName)" -ForegroundColor Red
                $checkErrors++
            }
        }
    }

    # --- STAGE 3: Verification ---
    # TODO: Проверить, что файлы действительно удалены
    # TODO: Проверить, не осталось ли пустых каталогов

    # --- STAGE 4: Post-Operations ---
    # TODO: Очистка пустых директорий
    # TODO: Логирование освобождённого места

    Write-Log ("===== CLEANUP JOB END " + $Job.Name + " =====")
    $freedMB = [math]::Round($freedBytes / 1MB, 2)
    Write-Host "  [INFO] Deleted: $deletedCount files, freed: $freedMB MB" -ForegroundColor Cyan

    return @{ Errors = $checkErrors; Log = $jobLog; Deleted = $deletedCount; FreedBytes = $freedBytes }
}

# ============================================================================
# MAIN
# ============================================================================

if (-not (Test-Path $ConfigurationPath)) { Write-Host "Config not found"; exit }

[xml] $script:Config = Get-Content $ConfigurationPath
$script:General     = $script:Config.CleanupConfig.General
$script:Paths       = $script:Config.CleanupConfig.Paths
$script:Recipients  = $script:Config.CleanupConfig.Recipients
$script:ParentJobName = $script:General.ParentJobName
$script:LogPathRoot = $script:Paths.LogPathRoot

# TODO: Добавить ротацию логов как в Backup-ps2-g-v4.ps1
$PCName = $env:COMPUTERNAME
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:ParentJobName + "_" + $DateLog + ".log")
if (-not (Test-Path $script:LogPathRoot)) { New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null }
Write-Log ("CLEANUP START PCNAME: " + $PCName)

if ($testmode) {
    Write-Host "[TEST MODE]" -ForegroundColor Cyan
    foreach ($job in $script:Config.CleanupConfig.Jobs.Job) {
        Write-Host "  Job: $($job.Name), Target: $($job.TargetPath)" -ForegroundColor Yellow
    }
    exit
}

$totalErrors = 0; $totalDeleted = 0
foreach ($job in $script:Config.CleanupConfig.Jobs.Job) {
    $result = Invoke-CleanupJob $script:Config $job
    $totalErrors += $result.Errors; $totalDeleted += $result.Deleted
}

# --- STAGE 5: Reporting ---
# TODO: Добавить полную отчётность (XML-отчёты, CSV)
# TODO: Формировать детальный отчёт по каждому Job

$BodyMailLog = [string]::Join("`n", (Get-Content $script:GlobalLog))
$SubjectMail = if ($totalErrors -eq 0) {
    "CLEANUP SUCCESS $script:ParentJobName $PCName (deleted: $totalDeleted)"
} else {
    "CLEANUP ERRORS: $totalErrors $script:ParentJobName $PCName"
}
Send-Email -Config $Config -Subject $SubjectMail -Body $BodyMailLog
exit $(if ($totalErrors -eq 0) { 0 } else { 1 })
```
### 3.3. monitor-ps-v4.ps1 (с TODO-маркерами)

```powershell
# PowerShell -ExecutionPolicy RemoteSigned -file .\monitor-ps-v4.ps1 -ConfigurationPath .\Monitor-Config.xml
# powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\monitor-ps-v4.ps1 -ConfigurationPath .\Monitor-Config.xml

param(
    [string]$ConfigurationPath = ".\Monitor-Config.xml"
)

# ============================================================================
# ОБЩИЕ ФУНКЦИИ
# ============================================================================

function Write-Log { param([string]$Message)
    if (-not $Message -or -not $script:GlobalLog) { return }
    Add-Content -Path $script:GlobalLog -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message) -ErrorAction SilentlyContinue
}

function Send-Email { param([string]$Subject, [string]$Body)
    # TODO: Реализовать полную Send-Email как в Backup
    Write-Host "[MAIL] $Subject" -ForegroundColor Cyan
}

# ============================================================================
# ФУНКЦИИ МОНИТОРИНГА
# ============================================================================

function Invoke-Check {
    param($Config, $Check)

    $checkName = $Check.Name
    $checkType = $Check.Type
    $checkPath = $Check.Path
    $result = "UNKNOWN"
    $message = ""

    Write-Log ("  CHECK: " + $checkName + " (" + $checkType + ")")

    # TODO: Добавить больше типов проверок
    switch ($checkType) {
        "FreeSpace" {
            $minFreeGB = [double] ($Check.MinFreeGB)
            try {
                $drive = [System.IO.DriveInfo]::GetDrives() | Where-Object {
                    $_.Name.TrimEnd('\') -eq $checkPath.TrimEnd('\') -and $_.IsReady
                }
                if ($drive) {
                    $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
                    $totalGB = [math]::Round($drive.TotalSize / 1GB, 2)
                    if ($freeGB -ge $minFreeGB) {
                        $result = "OK"
                        $message = "Drive $checkPath: $freeGB GB free of $totalGB GB (threshold: $minFreeGB GB)"
                    } else {
                        $result = "WARNING"
                        $message = "Drive $checkPath: $freeGB GB free (threshold: $minFreeGB GB)"
                    }
                } else {
                    $result = "ERROR"
                    $message = "Drive $checkPath not found"
                }
            } catch {
                $result = "ERROR"
                $message = "Error: $($_.Exception.Message)"
            }
        }
        "PathExists" {
            if (Test-Path -LiteralPath $checkPath) {
                $result = "OK"
                $message = "Path exists: $checkPath"
            } else {
                $result = "ERROR"
                $message = "Path not found: $checkPath"
            }
        }
        "MaxSize" {
            $maxSizeMB = [double] ($Check.MaxSizeMB)
            try {
                $totalSize = 0
                $dir = New-Object System.IO.DirectoryInfo($checkPath)
                if ($dir.Exists) {
                    foreach ($f in $dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) {
                        $totalSize += $f.Length
                    }
                    $sizeMB = [math]::Round($totalSize / 1MB, 2)
                    if ($sizeMB -le $maxSizeMB) {
                        $result = "OK"
                        $message = "Size $checkPath: $sizeMB MB (threshold: $maxSizeMB MB)"
                    } else {
                        $result = "WARNING"
                        $message = "Size $checkPath: $sizeMB MB exceeds $maxSizeMB MB"
                    }
                } else {
                    $result = "ERROR"
                    $message = "Path not found: $checkPath"
                }
            } catch {
                $result = "ERROR"
                $message = "Error: $($_.Exception.Message)"
            }
        }
        default {
            $result = "UNKNOWN"
            $message = "Unknown check type: $checkType"
        }
    }

    # TODO: Добавить пороговые значения с разными уровнями (WARNING/CRITICAL)
    # TODO: Добавить проверку процессов (Get-Process)
    # TODO: Добавить проверку Event Log
    # TODO: Добавить проверку служб Windows

    Write-Log ("    RESULT: " + $result + " - " + $message)
    return @{ Name = $checkName; Type = $checkType; Result = $result; Message = $message }
}

# ============================================================================
# MAIN
# ============================================================================

if (-not (Test-Path $ConfigurationPath)) { Write-Host "Config not found"; exit }

[xml] $script:Config = Get-Content $ConfigurationPath
$script:General    = $script:Config.MonitorConfig.General
$script:Paths      = $script:Config.MonitorConfig.Paths
$script:Recipients = $script:Config.MonitorConfig.Recipients
$script:ParentJobName = $script:General.ParentJobName
$script:LogPathRoot = $script:Paths.LogPathRoot

$PCName = $env:COMPUTERNAME
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:ParentJobName + "_" + $DateLog + ".log")
if (-not (Test-Path $script:LogPathRoot)) { New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null }
Write-Log ("MONITOR START PCNAME: " + $PCName)

# --- STAGE 1-2: Preparation + Main Operation ---
$checkResults = @(); $totalErrors = 0; $totalWarnings = 0

# TODO: Добавить проверку подключения к сетевым ресурсам
# TODO: Добавить проверку доступности SMTP-сервера

foreach ($check in $script:Config.MonitorConfig.Checks.Check) {
    $result = Invoke-Check $script:Config $check
    $checkResults += $result
    if ($result.Result -eq "ERROR") { $totalErrors++ }
    if ($result.Result -eq "WARNING") { $totalWarnings++ }
}

# --- STAGE 3-4: Verification + Post-Ops ---
# TODO: Добавить агрегацию — если > N ошибок, то CRITICAL статус
# (Post-Operations не применяется для Monitor)

# --- STAGE 5: Reporting ---
$bodyLines = @("Monitor Report $PCName", "=" * 50)
foreach ($cr in $checkResults) {
    $color = switch ($cr.Result) {
        "OK"      { "Green" }; "WARNING" { "Yellow" }; "ERROR" { "Red" }; default { "Gray" }
    }
    Write-Host ("  [" + $cr.Result + "] " + $cr.Name + ": " + $cr.Message) -ForegroundColor $color
    $bodyLines += ("[" + $cr.Result + "] " + $cr.Name + ": " + $cr.Message)
}

$bodyLines += ("=" * 50)
$bodyLines += "Total checks: $($checkResults.Count)"
$bodyLines += "Errors: $totalErrors"
$bodyLines += "Warnings: $totalWarnings"

Write-Log ("MONITOR COMPLETE: $($checkResults.Count) checks, $totalErrors errors, $totalWarnings warnings")

# TODO: Формировать XML-отчёт
# TODO: Отправлять email только при наличии ошибок/предупреждений
$SubjectMail = "[MONITOR] $PCName - $totalErrors errors, $totalWarnings warnings"
Send-Email -Subject $SubjectMail -Body ($bodyLines -join "`n")

exit $(if ($totalErrors -eq 0) { 0 } else { 1 })
```
---

## 4. Bash Skeleton (готовый код)

### 4.1. sync-bash-v4.sh (полностью рабочий скрипт)

```bash
#!/usr/bin/env bash
###############################################################################
# SYNC MODULE (Bash)
# PIPELINE: Preparation -> Sync -> Verification -> Post-Ops -> Reporting
# Совместимость: bash 3.0+ (Solaris 10), Linux
###############################################################################

CONFIG_FILE="./Sync-Config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found: $CONFIG_FILE"
    exit 1
fi

. "$CONFIG_FILE"

###############################################################################
# GLOBALS
###############################################################################

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')
LOG_DIR="$LOG_PATH_ROOT"
GLOBAL_LOG="${LOG_DIR}/${HOSTNAME_SHORT}_${PARENT_JOB_NAME}_${DATE_NOW}.log"
TOTAL_ERRORS=0
TOTAL_SYNCED=0

mkdir -p "$LOG_DIR"

###############################################################################
# LOG
###############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$GLOBAL_LOG"
}

###############################################################################
# SEND EMAIL
###############################################################################

send_email() {
    local subject="$1"
    local body="$2"
    # TODO: Реализовать SMTP через curl или netcat
    echo "[MAIL] $subject"
    log "MAIL: $subject"
}

###############################################################################
# COMPARE DIRECTORIES
###############################################################################

compare_dirs() {
    local src="$1"
    local dst="$2"
    local mode="$3"

    FILES_TO_COPY=""
    FILES_TO_DELETE=""

    local src_files=$(find "$src" -maxdepth 1 -type f -printf "%f\n" 2>/dev/null | sort)
    local dst_files=$(find "$dst" -maxdepth 1 -type f -printf "%f\n" 2>/dev/null | sort)

    if [ "$mode" = "full" ]; then
        FILES_TO_COPY="$src_files"
        FILES_TO_DELETE=$(comm -13 <(echo "$src_files") <(echo "$dst_files"))
    else
        FILES_TO_COPY=$(comm -23 <(echo "$src_files") <(echo "$dst_files"))
        FILES_TO_DELETE=""
    fi
}

###############################################################################
# MAIN
###############################################################################

log "SYNC START"

# --- STAGE 1-2: Preparation + Sync ---
for JOB in $JOBS; do
    SRC=$(eval echo "\${${JOB}_SOURCE}")
    DST=$(eval echo "\${${JOB}_DEST}")
    MODE=$(eval echo "\${${JOB}_MODE:-incremental}")

    echo "========== JOB: $JOB =========="
    log "JOB START $JOB (mode=$MODE)"

    if [ ! -d "$SRC" ]; then
        echo "  [WARN] Source not found: $SRC"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi
    mkdir -p "$DST"

    compare_dirs "$SRC" "$DST" "$MODE"

    SYNCED_COUNT=0
    for FILE in $FILES_TO_COPY; do
        cp "$SRC/$FILE" "$DST/$FILE"
        if [ $? -eq 0 ]; then
            SYNCED_COUNT=$((SYNCED_COUNT + 1))
            TOTAL_SYNCED=$((TOTAL_SYNCED + 1))
            log "SYNC COPY: $FILE"
        else
            echo "  [FAIL] Copy error: $FILE"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        fi
    done

    for FILE in $FILES_TO_DELETE; do
        rm -f "$DST/$FILE"
        log "SYNC DELETE: $FILE"
    done

    # --- STAGE 3: Verification ---
    VERIFIED=0
    for FILE in $FILES_TO_COPY; do
        if [ -f "$DST/$FILE" ]; then
            src_size=$(wc -c < "$SRC/$FILE")
            dst_size=$(wc -c < "$DST/$FILE")
            if [ "$src_size" -eq "$dst_size" ]; then
                VERIFIED=$((VERIFIED + 1))
            else
                echo "  [FAIL] Size mismatch: $FILE"
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
        fi
    done

    echo "  Synced: $SYNCED_COUNT, Verified: $VERIFIED"

    # --- STAGE 4: Post-Operations ---
    # TODO: Добавить ротацию старых файлов в dst
    # TODO: Добавить копирование в удалённое хранилище

    log "JOB END $JOB (synced=$SYNCED_COUNT, verified=$VERIFIED)"
done

# --- STAGE 5: Reporting ---
echo "=============================="
echo "TOTAL SYNCED: $TOTAL_SYNCED"
echo "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL SYNCED: $TOTAL_SYNCED"
log "TOTAL ERRORS: $TOTAL_ERRORS"

send_email "SYNC $PARENT_JOB_NAME $HOSTNAME_SHORT (errors=$TOTAL_ERRORS)" \
    "SYNC report\nHost: $HOSTNAME_SHORT\nErrors: $TOTAL_ERRORS\nSynced: $TOTAL_SYNCED"

exit "$TOTAL_ERRORS"
```
### 4.2. cleanup-bash-v4.sh (с TODO-маркерами)

```bash
#!/usr/bin/env bash
###############################################################################
# CLEANUP MODULE (Bash)
# PIPELINE: Preparation -> Cleanup -> Verification -> Post-Ops -> Reporting
# Совместимость: bash 3.0+ (Solaris 10), Linux
###############################################################################

CONFIG_FILE="./Cleanup-Config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found: $CONFIG_FILE"
    exit 1
fi

. "$CONFIG_FILE"

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')
LOG_DIR="$LOG_PATH_ROOT"
GLOBAL_LOG="${LOG_DIR}/${HOSTNAME_SHORT}_${PARENT_JOB_NAME}_${DATE_NOW}.log"
TOTAL_ERRORS=0
TOTAL_DELETED=0

mkdir -p "$LOG_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$GLOBAL_LOG"
}

log "CLEANUP START"

for JOB in $JOBS; do
    TARGET=$(eval echo "\${${JOB}_TARGET_PATH}")
    MASKS=$(eval echo "\${${JOB}_FILE_MASKS}")
    DAYS_OLD=$(eval echo "\${${JOB}_DAYS_OLD:-0}")
    KEEP_COUNT=$(eval echo "\${${JOB}_KEEP_COUNT:-0}")
    RECURSE=$(eval echo "\${${JOB}_RECURSE:-true}")

    echo "========== JOB: $JOB =========="
    log "JOB START $JOB (target=$TARGET, days=$DAYS_OLD, keep=$KEEP_COUNT)"

    # --- STAGE 1: Preparation ---
    if [ ! -d "$TARGET" ]; then
        echo "  [WARN] Target not found: $TARGET"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # TODO: Добавить проверку на опасные пути (/, /etc, /bin, /usr)

    IFS=',' read -ra MASK_ARRAY <<< "$MASKS"
    JOB_DELETED=0

    # --- STAGE 2: Main Operation ---
    for MASK in "${MASK_ARRAY[@]}"; do
        MASK=$(echo "$MASK" | xargs)
        [ -z "$MASK" ] && continue

        # TODO: Реализовать KeepCount (сортировка по mtime, удаление старых сверх лимита)
        # TODO: Реализовать DaysOld (find -mtime)

        FIND_OPTS=""
        [ "$RECURSE" = "true" ] || FIND_OPTS="-maxdepth 1"

        FILES=$(find "$TARGET" $FIND_OPTS -type f -name "$MASK" 2>/dev/null)
        for FILE in $FILES; do
            # TODO: Применить политику DaysOld/KeepCount
            echo "  DELETE: $FILE"
            rm -f "$FILE"
            if [ $? -eq 0 ]; then
                JOB_DELETED=$((JOB_DELETED + 1))
                log "  DELETED: $FILE"
            else
                echo "  [FAIL] Delete error: $FILE"
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
        done
    done

    # --- STAGE 3: Verification ---
    # TODO: Проверить, что файлы действительно удалены

    # --- STAGE 4: Post-Operations ---
    # TODO: Удаление пустых директорий

    TOTAL_DELETED=$((TOTAL_DELETED + JOB_DELETED))
    echo "  Deleted: $JOB_DELETED files"
    log "JOB END $JOB (deleted=$JOB_DELETED)"
done

# --- STAGE 5: Reporting ---
echo "=============================="
echo "TOTAL DELETED: $TOTAL_DELETED"
echo "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL DELETED: $TOTAL_DELETED"
log "TOTAL ERRORS: $TOTAL_ERRORS"

# TODO: Реализовать отправку email
exit "$TOTAL_ERRORS"
```

### 4.3. monitor-bash-v4.sh (с TODO-маркерами)

```bash
#!/usr/bin/env bash
###############################################################################
# MONITOR MODULE (Bash)
# PIPELINE: Preparation -> Checks -> Analysis -> Reporting
# Совместимость: bash 3.0+ (Solaris 10), Linux
###############################################################################

CONFIG_FILE="./Monitor-Config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found: $CONFIG_FILE"
    exit 1
fi

. "$CONFIG_FILE"

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')
LOG_DIR="$LOG_PATH_ROOT"
GLOBAL_LOG="${LOG_DIR}/${HOSTNAME_SHORT}_${PARENT_JOB_NAME}_${DATE_NOW}.log"
TOTAL_ERRORS=0
TOTAL_WARNINGS=0

mkdir -p "$LOG_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$GLOBAL_LOG"
}

log "MONITOR START"

# --- STAGE 1-2: Preparation + Checks ---
# TODO: Добавить типы проверок:
#       - DISK: df -h / df -g (Solaris)
#       - PATH: test -d
#       - SIZE: du -sb
#       - PROCESS: pgrep/ps
#       - PORT: nc -z

for CHECK in $CHECKS; do
    TYPE=$(eval echo "\${${CHECK}_TYPE}")
    TARGET=$(eval echo "\${${CHECK}_TARGET}")
    THRESHOLD=$(eval echo "\${${CHECK}_THRESHOLD}")

    echo "  CHECK: $CHECK ($TYPE)"
    log "  CHECK: $CHECK ($TYPE)"

    case "$TYPE" in
        "FreeSpace")
            # TODO: Реализовать проверку свободного места
            # df -h "$TARGET" | awk ...
            echo "    [TODO] FreeSpace check for $TARGET"
            ;;
        "PathExists")
            if [ -d "$TARGET" ] || [ -f "$TARGET" ]; then
                echo "    [OK] Path exists: $TARGET"
            else
                echo "    [ERROR] Path not found: $TARGET"
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
            ;;
        "MaxSize")
            # TODO: Реализовать проверку максимального размера
            echo "    [TODO] MaxSize check for $TARGET"
            ;;
        *)
            echo "    [UNKNOWN] Type: $TYPE"
            ;;
    esac
done

# --- STAGE 3: Verification ---
# TODO: Агрегация результатов

# --- STAGE 4: Post-Operations ---
# (не применяется для Monitor)

# --- STAGE 5: Reporting ---
echo "=============================="
echo "TOTAL ERRORS: $TOTAL_ERRORS"
echo "TOTAL WARNINGS: $TOTAL_WARNINGS"
log "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL WARNINGS: $TOTAL_WARNINGS"

# TODO: Отправка email
exit "$TOTAL_ERRORS"
```
---

## 5. Примеры конфигураций

### 5.1. XML-пример (Sync)

```xml
<?xml version="1.0" encoding="utf-8"?>
<SyncConfig>
  <General>
    <ParentJobName>SyncAll</ParentJobName>
    <Domain>localdomain.loc</Domain>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\SyncAll\logs</LogPathRoot>
    <LogDaysOld>7</LogDaysOld>
    <LogKeepCount>14</LogKeepCount>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Jobs>
    <Job Name="JOB1">
      <Source>C:\Source\JOB1\</Source>
      <Dest>C:\Dest\JOB1\</Dest>
      <Mode>incremental</Mode>
      <ExcludeToday>true</ExcludeToday>
      <SourceFilter>*</SourceFilter>
    </Job>
    <Job Name="JOB2">
      <Source>C:\Source\JOB2\</Source>
      <Dest>C:\Dest\JOB2\</Dest>
      <Mode>full</Mode>
      <ExcludeToday>false</ExcludeToday>
      <SourceFilter>*.txt</SourceFilter>
    </Job>
  </Jobs>
</SyncConfig>
```

### 5.2. XML-пример (Cleanup)

```xml
<?xml version="1.0" encoding="utf-8"?>
<CleanupConfig>
  <General>
    <ParentJobName>CleanupAll</ParentJobName>
    <Domain>localdomain.loc</Domain>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\CleanupAll\logs</LogPathRoot>
    <LogDaysOld>7</LogDaysOld>
    <LogKeepCount>14</LogKeepCount>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Jobs>
    <Job Name="JOB1">
      <TargetPath>C:\Temp\</TargetPath>
      <FileMasks>*.tmp,*.log,*.bak</FileMasks>
      <DaysOld>30</DaysOld>
      <KeepCount>10</KeepCount>
      <Recurse>true</Recurse>
    </Job>
    <Job Name="JOB2">
      <TargetPath>D:\OldProjects\</TargetPath>
      <FileMasks>*.zip,*.rar</FileMasks>
      <DaysOld>90</DaysOld>
      <KeepCount>5</KeepCount>
      <Recurse>true</Recurse>
    </Job>
  </Jobs>
</CleanupConfig>
```

### 5.3. XML-пример (Monitor)

```xml
<?xml version="1.0" encoding="utf-8"?>
<MonitorConfig>
  <General>
    <ParentJobName>MonitorAll</ParentJobName>
    <Domain>localdomain.loc</Domain>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\MonitorAll\logs</LogPathRoot>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Checks>
    <Check Name="DISK_C">
      <Type>FreeSpace</Type>
      <Path>C:\</Path>
      <MinFreeGB>10</MinFreeGB>
    </Check>
    <Check Name="BACKUP_DIR">
      <Type>PathExists</Type>
      <Path>C:\Backup\</Path>
    </Check>
    <Check Name="LOG_SIZE">
      <Type>MaxSize</Type>
      <Path>C:\Work\logs\</Path>
      <MaxSizeMB>500</MaxSizeMB>
    </Check>
    <Check Name="SMTP_CHECK">
      <Type>PortOpen</Type>
      <Host>smtp.localdomain.loc</Host>
      <Port>25</Port>
    </Check>
  </Checks>
</MonitorConfig>
```

### 5.4. Shell conf-пример (Sync)

```bash
# Sync config for Bash
PARENT_JOB_NAME="SyncAll"
DOMAIN="localdomain.loc"
SMTP_SERVER="smtp.localdomain.loc"
LOG_PATH_ROOT="/var/log/sync"
JOBS="JOB1 JOB2"

JOB1_SOURCE="/data/source/JOB1"
JOB1_DEST="/data/dest/JOB1"
JOB1_MODE="incremental"

JOB2_SOURCE="/data/source/JOB2"
JOB2_DEST="/data/dest/JOB2"
JOB2_MODE="full"
```

### 5.5. Shell conf-пример (Cleanup)

```bash
# Cleanup config for Bash
PARENT_JOB_NAME="CleanupAll"
DOMAIN="localdomain.loc"
LOG_PATH_ROOT="/var/log/cleanup"
JOBS="JOB1 JOB2"

JOB1_TARGET_PATH="/tmp"
JOB1_FILE_MASKS="*.tmp,*.log,*.bak"
JOB1_DAYS_OLD=30
JOB1_KEEP_COUNT=10
JOB1_RECURSE=true

JOB2_TARGET_PATH="/var/old"
JOB2_FILE_MASKS="*.tar.gz,*.zip"
JOB2_DAYS_OLD=90
JOB2_KEEP_COUNT=5
JOB2_RECURSE=true
```

### 5.6. Shell conf-пример (Monitor)

```bash
# Monitor config for Bash
PARENT_JOB_NAME="MonitorAll"
DOMAIN="localdomain.loc"
SMTP_SERVER="smtp.localdomain.loc"
LOG_PATH_ROOT="/var/log/monitor"
CHECKS="DISK_ROOT DISK_VAR BACKUP_DIR"

DISK_ROOT_TYPE="FreeSpace"
DISK_ROOT_TARGET="/"
DISK_ROOT_THRESHOLD="10G"

DISK_VAR_TYPE="MaxSize"
DISK_VAR_TARGET="/var/log"
DISK_VAR_THRESHOLD="500M"

BACKUP_DIR_TYPE="PathExists"
BACKUP_DIR_TARGET="/backup"
```
---

## 6. Сравнения: что меняется для каждого скрипта

### 6.1. Backup

| Аспект | Описание |
|--------|----------|
| **Назначение** | Создание RAR/tar.gz архивов исходных файлов |
| **Pipeline (5/5)** | Preparation -> Archiving -> Verification -> Post-Ops -> Reporting |
| **Main Operation** | RAR.exe (PS) / tar + gzip (Bash) |
| **Verification** | ExitCode + SHA256 хеш (конфиг, RAR.exe) |
| **Post-Operations** | Copy-Remote + Remove-OldFiles (ротация) |
| **Reporting** | XML + CSV + email |
| **PS vs Bash** | PS: RAR.exe через Start-Process; Bash: tar + gzip pipeline |

### 6.2. Copy

| Аспект | Описание |
|--------|----------|
| **Назначение** | Копирование файлов из Source в RemoteDest с верификацией |
| **Pipeline (5/5)** | Preparation -> Copying -> Verification -> Archiving -> Reporting |
| **Main Operation** | Copy-Item (PS) / cp (Bash) |
| **Verification** | Сравнение размеров (Source vs Dest) |
| **Post-Operations** | Move-Item в Arhive (после успешной верификации) |
| **Reporting** | XML-отчёт + email (TODO) |
| **PS vs Bash** | PS: Copy-Item + Move-Item; Bash: cp + mv |

### 6.3. Sync

| Аспект | Описание |
|--------|----------|
| **Назначение** | Синхронизация source с dest (полная или инкрементальная) |
| **Pipeline (5/5)** | Preparation -> Sync -> Verification -> Cleanup -> Reporting |
| **Main Operation** | Compare-Object (PS) / comm (Bash) для diff, затем копирование |
| **Verification** | Сравнение размеров синхронизированных файлов |
| **Post-Operations** | Удаление файлов из dest (только full sync) |
| **Reporting** | XML + email |
| **Режимы** | `incremental` (только новые/изменённые) / `full` (полная копия) |
| **PS vs Bash** | PS: Compare-Object; Bash: comm + find |

### 6.4. Cleanup

| Аспект | Описание |
|--------|----------|
| **Назначение** | Удаление файлов по маскам, политикам DaysOld/KeepCount |
| **Pipeline (3-5/5)** | Preparation -> Cleanup -> Verification -> (Post-Ops) -> Reporting |
| **Main Operation** | Remove-Item (PS) / rm (Bash) |
| **Verification** | Проверка, что файлы удалены |
| **Post-Operations** | Очистка пустых директорий (опционально) |
| **Reporting** | Email (TODO: детальный отчёт) |
| **Примеры масок** | `*.tmp,*.log,*.bak`, `*.old`, `*~` |

### 6.5. Monitor

| Аспект | Описание |
|--------|----------|
| **Назначение** | Проверка состояния системы (диски, пути, размеры, процессы) |
| **Pipeline (3-5/5)** | Preparation -> Checks -> Analysis -> (no Post-Ops) -> Reporting |
| **Main Operation** | .NET DriveInfo/IO classes (PS) / df, du, test (Bash) |
| **Verification** | Сравнение метрик с порогами (MinFreeGB, MaxSizeMB) |
| **Post-Operations** | Не применяется (read-only) |
| **Reporting** | XML + email (только при ошибках/предупреждениях) |
| **Типы проверок** | FreeSpace, PathExists, MaxSize, PortOpen, ProcessRunning |

---

## 7. Чек-лист создания нового скрипта

### 7.1. Выбор имени и направление

- [ ] Определиться с типом: Backup / Copy / Sync / Cleanup / Monitor
- [ ] Выбрать платформу: PS (Windows) / Bash (Linux/Solaris) / обе
- [ ] Создать директорию `app/ps/{type}/` или `app/bash/{type}/`
- [ ] Определить имя файла: `{type}-ps-v4.ps1` / `{type}-bash-v4.sh`

### 7.2. Подготовка библиотек

- [ ] Скопировать общие функции: `Write-Log`, `Send-Email`, `Test-Empty`, `To-Bool`
- [ ] Для PS: добавить `Get-FileHashCompat`, `Remove-OldFiles`, `Get-DiskSpaceReport`
- [ ] Для Bash: добавить `log()`, `resolve_name()`, `copy_remote()`, `send_email()`
- [ ] Убедиться в PS 2.0 совместимости (никаких `Get-FileHash`, `PSCustomObject`)

### 7.3. Реализация пайплайна

- [ ] **Stage 1: Preparation** — загрузка конфига, валидация, создание `$ctx`
- [ ] **Stage 2: Main Operation** — профильная операция
- [ ] **Stage 3: Verification** — проверка результата
- [ ] **Stage 4: Post-Operations** — ротация, удалённое копирование, очистка
- [ ] **Stage 5: Reporting** — агрегация, email, отчёты
- [ ] Проверить порядок этапов (нарушение запрещено)

### 7.4. Создание конфигурации

- [ ] Создать XML-конфиг для PS: `{type}-Config.xml`
- [ ] Создать shell conf для Bash: `{type}-Config.conf`
- [ ] Добавить секции: `<General>`, `<Paths>`, `<Recipients>`, `<Jobs>`
- [ ] Добавить типовые параметры (Source, Dest, Filter, Mode и т.д.)

### 7.5. Добавление тестов

- [ ] Создать Pester-тесты для PS (`app/tests/{type}.Tests.ps1`)
- [ ] Создать unit-тесты для Bash
- [ ] Проверить testmode (ключ `-testmode`)
- [ ] Проверить обработку ошибок (недоступный Source, плохой конфиг)

### 7.6. Документация

- [ ] Создать `docs/{type}/README.md`
- [ ] Описать назначение, pipeline, параметры, примеры
- [ ] Обновить `docs/DEVELOPMENT_PLAN.md` (статус задач)
- [ ] Обновить корневой `README.md` (список скриптов)

### 7.7. Верификация

- [ ] Проверить на PowerShell 2.0 / Windows 7
- [ ] Проверить на Bash 3.0+ / Solaris 10
- [ ] Прогнать линтер: `.app\PS_linter.ps1`
- [ ] Проверить все TODO-маркеры (ничего не пропущено)
- [ ] Проверить обработку кодировок (OEM для логов, UTF8 для отчётов)

---
