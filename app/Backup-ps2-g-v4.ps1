#PowerShell -ExecutionPolicy RemoteSigned -file .\<scriptName>.ps1
#powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\Backup.ps1 -ConfigPath "C:\path\config.xml" -testmode

param(
    [string]$ConfigPath = ".\Backup-Config.xml",
    [switch]$testmode
)
$XmlHash = "223BC719843E53299080DD3024039DE9DDCD2C223E45F1EE5EF36903A15AE6B0"

# ------------------------
# UTILS
# ------------------------

function Write-Log {
    param([string]$Message)
    
    # Защита: не писать, если сообщение пустое или лог ещё не инициализирован
    if (-not $Message -or -not $script:GlobalLog) { return }
    
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}

function Send-Email {
    [CmdletBinding()]
    param(
        # Обязательный конфиг для извлечения настроек
        [Parameter(Mandatory = $true)]$Config,
        
        # Переопределяемые параметры (если не переданы — берём из $Config)
        [Parameter(Mandatory = $false)][string]$SmtpServer,
        [Parameter(Mandatory = $false)][string]$From,
        [Parameter(Mandatory = $false)][string]$To,
        
        # Обязательные для письма
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body,
        
        # Опции SMTP
        [Parameter(Mandatory = $false)][int]$Port = 25,
        [Parameter(Mandatory = $false)][bool]$UseSSL = $false,
        [Parameter(Mandatory = $false)][string]$Username,
        [Parameter(Mandatory = $false)][string]$Password,
        [Parameter(Mandatory = $false)][bool]$IsBodyHtml = $false
    )
    
    # === Извлечение значений из $Config, если не переданы явно ===
    if (-not $SmtpServer) { $SmtpServer = $Config.BackupConfig.General.SmtpServer }
    if (-not $From) { $From = "$env:COMPUTERNAME@$($Config.BackupConfig.General.Domain)" }
    if (-not $To) { $To = $Config.BackupConfig.Recipients.AdminMail }
    
    # === Основная логика отправки (.NET, PS 2.0 safe) ===
    try {
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer, $Port)
        $smtp.EnableSsl = $UseSSL
        $smtp.Timeout = 60000
        
        if ($Username -and $Password) {
            $smtp.Credentials = New-Object Net.NetworkCredential($Username, $Password)
        }
        
        $msg = New-Object Net.Mail.MailMessage
        $msg.From = $From
        $msg.To.Add($To)
        $msg.Subject = $Subject
        $msg.IsBodyHtml = $IsBodyHtml
        $msg.Body = $Body
        
        $smtp.Send($msg)
        Write-Host "[MAIL] Отправлено: $Subject" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[MAIL] Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        # PS 2.0: просто обнуляем ссылки (нет Dispose у SmtpClient в .NET 3.5)
        $msg = $null; $smtp = $null
    }
}

function Test-WritePermission {
    param([string]$Path)
    if (Test-Empty $Path) { return $false }
    try {
        $testFile = Join-Path $Path "._perm_test_$([System.Guid]::NewGuid().ToString().Substring(0,8))"
        # Попытка создать файл через .NET (надёжнее в PS 2.0)
        $fs = [System.IO.File]::OpenWrite($testFile)
        $fs.Close()
        [System.IO.File]::Delete($testFile)
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-TestMode {
    param($Config)
    
    Write-Host "`n[TEST MODE] Запуск проверок..." -ForegroundColor Cyan
    
    $checkErrors = 0
    
    foreach ($job in $Config.BackupConfig.Jobs.Job) {
        Write-Host "`nПроверка задания: $($job.Name)" -ForegroundColor Yellow
        
        if (-not (Test-Path -LiteralPath $job.Source -PathType Container)) {
            Write-Host "  [FAIL] Источник не найден: $($job.Source)" -ForegroundColor Red
            $checkErrors++
        }
        else {
            Write-Host "  [OK] Источник доступен: $($job.Source)" -ForegroundColor Green
        }
        
        $dest = $job.LocalDest
        if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Write-Host "  [OK] Папка назначения создана: $dest" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL] Не удалось создать папку назначения: $dest" -ForegroundColor Red
                $checkErrors++
            }
        }
        if ($allPassed -and (Test-Path -LiteralPath $dest -PathType Container)) {
            if (Test-WritePermission -Path $dest) {
                Write-Host "  [OK] Права записи на назначении: $dest" -ForegroundColor Green
            }
            else {
                Write-Host "  [FAIL] Нет прав записи на назначении: $dest" -ForegroundColor Red
                $checkErrors++
            }
        }
        
        if ($job.RemoteDest -and -not (Test-Empty $job.RemoteDest)) {
            if (-not (Test-Path -LiteralPath $job.RemoteDest -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $job.RemoteDest -Force | Out-Null
                }
                catch { }
            }
            if (Test-Path -LiteralPath $job.RemoteDest -PathType Container) {
                if (Test-WritePermission -Path $job.RemoteDest) {
                    Write-Host "  [OK] Права записи на удалённом назначении: $($job.RemoteDest)" -ForegroundColor Green
                }
                else {
                    Write-Host "  [WARN] Нет прав записи на удалённом назначении: $($job.RemoteDest)" -ForegroundColor Yellow
                    $checkErrors++
                }
            }
        }
    }
	
    Write-Host "`n[TEST MODE] Результат:" -ForegroundColor Cyan

    # --- Определяем статус и текст сообщения ---
    if ($checkErrors -eq 0) {
        $Status = "OK"
        $StatusText = "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ"
        $Color = "Green"
        $ExitCode = 0
    }
    else {
        $Status = "FAIL"
        $StatusText = "ОБНАРУЖЕНЫ ОШИБКИ ($checkErrors)"
        $Color = "Red"
        $ExitCode = 1
    }

    # --- Единый вывод и отправка почты ---
    Write-Host "  $StatusText" -ForegroundColor $Color
    Write-Host $PCNAME
    $SubjectMail = "[$Status] $JobName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $BodyMail = "Job: $JobName`n" + `
        "PC: $env:COMPUTERNAME`n" + `
        "Status: $StatusText`n" + `
        "Errors: $checkErrors`n" + `
        "Time: $(Get-Date)"

    Send-Email -Config $Config -Subject $SubjectMail -Body $BodyMail

    exit $ExitCode
}

#===========================================================
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША
# ===========================================================
function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0, ValueFromPipeline = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'LiteralPath')]
        [string]$LiteralPath,
        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )
    process {
        $filePath = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        try {
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Файл не найден: $filePath"
            }
            $hashAlgo = switch ($Algorithm.ToUpper()) {
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
                'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
                default { [System.Security.Cryptography.SHA256]::Create() }
            }
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                $obj = New-Object PSObject -Property @{
                    Hash      = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path      = (Resolve-Path -LiteralPath $filePath).Path
                }
                return $obj
            }
            finally {
                $fileStream.Dispose()
            }
        }
        catch {
            throw "Ошибка вычисления хеша файла '$filePath': $($_.Exception.Message)"
        }
    }
}

if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    Set-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}

function Test-FileIntegrity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $false)][string]$FileType = "Файл"
    )
    process {
        # Проверка формата хеша ВНУТРИ функции (ValidatePattern бросает исключение до тела)
        if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) {
            Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Неверный формат хеша (ожидается 64 hex символа)" -ForegroundColor Red
            Write-Error "Неверный формат хеша для $FileType"
            return $false
        }
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            $msg = "ОШИБКА: Файл не найден: $FilePath"
            Write-Host $msg -ForegroundColor Red
            Write-Error $msg
            return $false
        }
        try {
            Write-Host "Проверка целостности ($FileType): $FilePath..." -ForegroundColor Cyan
            $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpper()
            $expectedHashUpper = $ExpectedHash.ToUpper()
            Write-Host "  Ожидаемый   : $expectedHashUpper"
            Write-Host "  Фактический : $actualHash"
            if ($actualHash -eq $expectedHashUpper) {
                Write-Host "  [OK] Хеш подтвержден. Файл безопасен." -ForegroundColor Green
                return $true
            }
            else {
                $errorMessage = @"
КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ!
Хеш файла НЕ СОВПАДАЕТ!
Тип: $FileType
Путь: $FilePath
Ожидаемый: $expectedHashUpper
Фактический: $actualHash
"@
                Write-Host $errorMessage -ForegroundColor Red
                Write-Error $errorMessage
                return $false
            }
        }
        catch {
            $errorMsg = "Ошибка вычисления хеша для $FileType`: $($_.Exception.Message)"
            Write-Host $errorMsg -ForegroundColor Red
            Write-Error $errorMsg
            return $false
        }
    }
}
#endregion


function Test-Empty {
    param([string]$s)
    return ($s -eq $null -or $s.Trim().Length -eq 0)
}

function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}

function Resolve-Name {
    param($Pattern, $PC, $Job, $Date, $Name)

    if (Test-Empty $Pattern) { return $null }

    $r = $Pattern
    $r = $r -replace "{PCName}", $PC
    $r = $r -replace "{JobName}", $Job
    $r = $r -replace "{LastWriteTime}", $Date
    $r = $r -replace "{Date}", $Date
    $r = $r -replace "{SourceFileName}", $Name
    $r = $r -replace "{SourceFolderName}", $Name
    $r = $r -replace '[\\/:*?"<>|]', '_'
    $r = $r -replace '_+', '_'
    $r = $r.Trim()

    if ($r -notmatch '\.rar$') { $r += ".rar" }

    return $r
}

function Copy-Remote {
    param(
        $ctx,
        $archivePath
    )

    if (Test-Empty $ctx.RemoteDest) { return }
    if (-not (Test-Path $ctx.RemoteDest)) {
        New-Item -ItemType Directory -Path $ctx.RemoteDest | Out-Null
    }

    if (-not (Test-Path $archivePath)) { return }

    $fileName = [System.IO.Path]::GetFileName($archivePath)
    $destPath = Join-Path $ctx.RemoteDest $fileName

    Copy-Item -Path $archivePath -Destination $destPath -Force

    Write-Log ("COPY REMOTE: " + $destPath)
}

# ==============================================================================
#region РОТАЦИЯ ФАЙЛОВ (PS 2.0 SAFE)
# ==============================================================================

function Remove-OldFiles {
    param(
        [string]$Path,
        [int]$DaysOld,
        [int]$KeepCount,
        [string]$Filter
    )

    $results = @()

    if (-not $Path) { return "Path parameter is empty" }

    $results += "Rotation: $Path DaysOld=$DaysOld Keep=$KeepCount Filter=$Filter"

    if (-not (Test-Path $Path -PathType Container)) {
        $results += "The directory does not exist: $Path"
        return $results -join "`n"
    }

    try {
        $cutoffDate = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { [DateTime]::MaxValue }

        # [array] гарантирует, что .Count отработает даже при 1 файле (баг PS 2.0)
        [array]$allFiles = Get-ChildItem -Path $Path -Filter $Filter | Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTime -Descending

        if ($allFiles.Count -eq 0) {
            $results += "There are no files to process"
            return $results -join "`n"
        }

        $results += "Files found: $($allFiles.Count)"

        [array]$filesToKeep = @()
        if ($KeepCount -gt 0) {
            $filesToKeep = $allFiles | Select-Object -First $KeepCount
        }

        [array]$filesToDelete = @()
        foreach ($f in $allFiles) {
            $keep = $false
            foreach ($k in $filesToKeep) {
                if ($k.FullName -eq $f.FullName) { $keep = $true; break }
            }
            if (-not $keep -and $f.LastWriteTime -lt $cutoffDate) {
                $filesToDelete += $f
            }
        }

        if ($filesToDelete.Count -gt 0) {
            $results += "Files to delete: $($filesToDelete.Count)"
            foreach ($file in $filesToDelete) {
                try {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $results += "Removed: $($file.Name)"
                } catch {
                    $results += "Error deleting: $($file.FullName) $_"
                }
            }
        } else {
            $results += "There are no files to delete."
        }

        $results += "Rotation is complete. Kept: $($allFiles.Count - $filesToDelete.Count) / Total: $($allFiles.Count)"
    } catch {
        $results += "Rotation error: $_"
    }

    return $results -join "`n"
}

#endregion

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

            $diskStrings += ("Disk {0} Total (GB)={1:N1} Free (GB)={2:N1} Free={3:N1}%" -f `
                    $drive.Name.TrimEnd('\'), $sizeGB, $freeGB, $freePct)
        }

        if ($diskStrings -eq $null -or $diskStrings.Count -eq 0) {
            return "No local hard drives > 1 GB"
        }

        return ($diskStrings -join " ; ")
    }
    catch {
        return ("Error getting disk information: " + $_.Exception.Message)
    }
}

# ==============================================================================
# ------------------------
# FAST IO
# ------------------------

function Get-FilesFast {
    param($Path, $Filter)

    $list = New-Object System.Collections.ArrayList
    if (-not (Test-Path $Path)) { return $list }

    $dir = New-Object System.IO.DirectoryInfo($Path)

    foreach ($f in $dir.GetFiles($Filter)) {
        [void]$list.Add($f)
    }

    return $list
}

function Get-FoldersFast {
    param($Path)

    $list = New-Object System.Collections.ArrayList
    if (-not (Test-Path $Path)) { return $list }

    $dir = New-Object System.IO.DirectoryInfo($Path)

    foreach ($d in $dir.GetDirectories()) {
        [void]$list.Add($d)
    }

    return $list
}

# ------------------------
# RAR PARAMS
# ------------------------

function Get-RarParams {
    param($ctx)

    $params = @()

    if ($ctx.Job.ArhParameters) {
        foreach ($p in $ctx.Job.ArhParameters.Param) {
            $params += $p
        }
    }
    else {
        foreach ($p in $ctx.Config.General.DefaultRarParameters.Param) {
            $params += $p
        }
    }

    return ($params -join " ")
}

# ------------------------
# <ArchiveByDate>true</ArchiveByDate> (DATE FILES)
# ------------------------

function Prepare-ArchiveByDate {
    param($ctx)

    $files = Get-FilesFast $ctx.Source "*.*"
    $groups = @{}

    foreach ($f in $files) {

        if ($ctx.ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) {
            continue
        }

        $key = $f.LastWriteTime.ToString("yyyyMMdd")

        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.ArrayList
        }

        [void]$groups[$key].Add($f.FullName)
    }

    return $groups
}

# ------------------------
# <ArchiveIndividualFiles>true</ArchiveIndividualFiles> (1 FILE = 1 ARCHIVE)
# ------------------------

function Prepare-IndividualFiles {
    param($ctx)

    $files = Get-FilesFast $ctx.Source $ctx.SourceFilter
    $groups = @{}

    foreach ($f in $files) {

        if ($ctx.ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) {
            continue
        }

        $key = $f.Name  # ВАЖНО: полный уникальный ключ

        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($f.FullName)
    }

    return $groups
}

# ------------------------
# <ArchiveIndividualFolders>true</ArchiveIndividualFolders> (FOLDERS)
# ------------------------

function Prepare-IndividualFolders {
    param($ctx)

    $dirs = Get-FoldersFast $ctx.Source
    $groups = @{}

    $today = (Get-Date).ToString("yyyyMMdd")

    foreach ($d in $dirs) {

        if ($ctx.ExcludeToday -and $d.Name -eq $today) {
            continue
        }

        $key = $d.Name

        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($d.FullName)
    }

    return $groups
}

# ------------------------
# <ArchiveAll>true</ArchiveAll> (All)
# ------------------------
function Prepare-ArchiveAll {
    param($ctx)

    $groups = @{}

    $key = (Get-Date).ToString("yyyyMMdd_HHmmss")

    $list = New-Object System.Collections.ArrayList

    if (Test-Path $ctx.Source) {

        $dir = New-Object System.IO.DirectoryInfo($ctx.Source)

        foreach ($f in $dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) {

            [void]$list.Add($f.FullName)
        }
    }

    $groups[$key] = $list

    return $groups
}

# ------------------------
# ARCHIVE ENGINE
# ------------------------

function Invoke-Archiving {
    param($ctx, $groups)
    $checkErrors = 0
    foreach ($key in $groups.Keys) {

        $items = $groups[$key]

        $archiveName = Resolve-Name `
            $ctx.Pattern `
            $ctx.PCName `
            $ctx.JobName `
            $key `
            $key

        if (Test-Empty $archiveName) { continue }

        $archivePath = Join-Path $ctx.Dest $archiveName

        # list file
        $listFile = [System.IO.Path]::ChangeExtension($archivePath, ".txt")
        $items | Out-File -Encoding ASCII $listFile

        $args = (Get-RarParams $ctx) + " `"$archivePath`" @$listFile"

        Write-Log ("START " + $archivePath)
        $startTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $jobLog += ("$startTime START " + $archivePath)

        $p = Start-Process -FilePath $ctx.RarPath `
            -ArgumentList $args `
            -Wait `
            -PassThru `
            -NoNewWindow

        $endTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $jobLog += ("$endTime END " + $archivePath + " CODE=" + $p.ExitCode)

        Write-Log ("END " + $archivePath + " CODE=" + $p.ExitCode)

        if ($p.ExitCode -eq 0) {
            $copyStart = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Copy-Remote $ctx $archivePath
            $jobLog += ("$copyStart COPY REMOTE: " + $ctx.RemoteDest + "\" + $archiveName)
            Write-Host "  [OK] Архив создан: $archiveName" -ForegroundColor Green
        }
        else {
            $checkErrors++
            Write-Host "  [FAIL] Ошибка архивации: $archiveName (CODE=$($p.ExitCode))" -ForegroundColor Red
        }
    }
    return $checkErrors
}

# ------------------------
# JOB RUNNER
# ------------------------
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
        LocalDestDaysOld   = [int]$Job.LocalDestDaysOld
        LocalDestKeepCount = [int]$Job.LocalDestKeepCount
        RarPath            = $Config.Paths.RarPath
        RarHASH            = $Config.Paths.RarHASH
        PCName             = $PCName
        Pattern            = ""
        Log                = ""
        ExcludeToday       = To-Bool $Job.ExcludeToday
        SourceFilter       = "*"
        ArchiveAll         = To-Bool $Job.ArchiveAll
        RemoteDest         = $Job.RemoteDest
    }

    if (-not (Test-Path $ctx.Source)) { 
        $msg = "  [WARN] Источник не найден: $($ctx.Source)"
        Write-Host $msg -ForegroundColor Yellow
        $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $msg)
        $checkErrors++
        return @{ Errors = $checkErrors; Log = $jobLog }
    }

    if (-not (Test-Path $ctx.Dest)) {
        New-Item -ItemType Directory -Path $ctx.Dest | Out-Null
    }
    if (-not (Test-Path $ctx.RemoteDest)) {
        New-Item -ItemType Directory -Path $ctx.RemoteDest | Out-Null
    }

    if (-not (Test-Path $Config.Paths.LogPathRoot)) {
        New-Item -ItemType Directory -Path $Config.Paths.LogPathRoot | Out-Null
    }
	
    if ($Job.ArchivePattern) { $ctx.Pattern = $Job.ArchivePattern }
    if ($Job.IndividualArchivePattern) { $ctx.Pattern = $Job.IndividualArchivePattern }
    if ($Job.SourceFilter) { $ctx.SourceFilter = $Job.SourceFilter }

    Write-Log ("===== JOB START " + $ctx.JobName + " =====")
    $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " ===== JOB START " + $ctx.JobName + " =====")
    $groups = @{}

    if ($ctx.ArchiveAll) {
        $groups = Prepare-ArchiveAll $ctx
    }
    elseif (To-Bool $Job.ArchiveByDate) {
        $groups = Prepare-ArchiveByDate $ctx
    }
    elseif (To-Bool $Job.ArchiveIndividualFiles) {
        $groups = Prepare-IndividualFiles $ctx
    }
    elseif (To-Bool $Job.ArchiveIndividualFolders) {
        $groups = Prepare-IndividualFolders $ctx
    }

    $archivingErrors = Invoke-Archiving $ctx $groups
    if ($null -ne $archivingErrors -and $archivingErrors -is [int]) {
        $checkErrors = $checkErrors + $archivingErrors
    }
	
    $null = Remove-OldFiles `
        -Path $ctx.Dest `
        -DaysOld $ctx.LocalDestDaysOld `
        -KeepCount $ctx.LocalDestKeepCount `
        -Filter "*.*"

    Write-Log ("===== /JOB END " + $ctx.JobName + " =====")
    $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " ===== /JOB END " + $ctx.JobName + " =====")

    return @{ Errors = $checkErrors; Log = $jobLog }
}

# ------------------------
# MAIN
# ------------------------

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found"
    exit
}

if (-not (Test-FileIntegrity -FilePath $ConfigPath -ExpectedHash $XmlHash -FileType $ConfigPath)) {
    Write-Host "ПРОВЕРКА XML ПРОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
    exit 1
}

# Загрузка XML
[xml]$script:Config = Get-Content $ConfigPath

# === КЭШИРОВАНИЕ ПЕРЕМЕННЫХ ИЗ XML ===
$script:General = $script:Config.BackupConfig.General
$script:Paths = $script:Config.BackupConfig.Paths
$script:Recipients = $script:Config.BackupConfig.Recipients

# Основные переменные
$script:JobName = $script:General.JobName
$script:Domain = $script:General.Domain
$script:SmtpServer = $script:General.SmtpServer
$script:LogPathRoot = $script:Paths.LogPathRoot
$script:LogDaysOld = [int]$script:Paths.LogDaysOld
$script:LogKeepCount = [int]$script:Paths.LogKeepCount
$script:RarPath = $script:Paths.RarPath
$script:RarHash = $script:Paths.RarHASH

$PCName = $env:COMPUTERNAME
# $PCName = "FXGATE"

# === ИНИЦИАЛИЗАЦИЯ ГЛОБАЛЬНОГО ЛОГА ===
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:JobName + "_" + $DateLog + ".log")

# Создаём папку логов если нет
if (-not (Test-Path $script:LogPathRoot)) {
    New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null
}

Write-Log (" PCNAME: " + $PCName)

if (-not (Test-FileIntegrity -FilePath $script:RarPath -ExpectedHash $script:RarHash  -FileType $script:RarPath)) {
    Write-Host "ПРОВЕРКА RAR ПОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
    Write-Log (" ERROR RarHASH: " + $script:RarPath)
    exit 1
}

if ($testmode) {
    Invoke-TestMode -Config $script:Config
    exit
}

# === ОСНОВНОЙ ЦИКЛ  ===
$totalErrors = 0  # === ОБЩИЙ СЧЕТЧИК ОШИБОК ВСЕХ ЗАДАНИЙ
$jobResults = @{}  # === ХРАНИЛИЩЕ РЕЗУЛЬТАТОВ ПО ЗАДАНИЯМ

foreach ($job in $script:Config.BackupConfig.Jobs.Job) {
    $result = Invoke-Job $script:Config.BackupConfig $job
    $jobErrors = $result.Errors
    $jobLog = $result.Log
    
    $jobResults[$job.Name] = @{
        Errors = $jobErrors
        Log    = $jobLog
    }
    
    $totalErrors = $totalErrors + $jobErrors
    
    # === ВЫВОД РЕЗУЛЬТАТА ПО ЗАДАНИЮ ===
    if ($jobErrors -eq 0) {
        Write-Host ">> [ЗАДАНИЕ ОК] $($job.Name) - ошибок: $jobErrors" -ForegroundColor Green
    }
    else {
        Write-Host ">> [ЗАДАНИЕ С ОШИБКАМИ] $($job.Name) - ошибок: $jobErrors" -ForegroundColor Red
    }
}

foreach ($jobName in $jobResults.Keys) {
    $result = $jobResults[$jobName]
    $errors = $result.Errors
    $jobLog = $result.Log
    
    # === ЗАГОЛОВОК ЗАДАНИЯ ===
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "ЗАДАНИЕ: $jobName | Ошибок: $errors" -ForegroundColor $(if ($errors -eq 0) { "Green" } else { "Red" })
    Write-Host "========================================" -ForegroundColor Cyan
    
    # === ВЫВОД ЛОГОВ ЗАДАНИЯ ===
    foreach ($logLine in $jobLog) {
        Write-Host "  $logLine" -ForegroundColor $(if ($logLine -match "FAIL|ERROR") { "Red" } elseif ($logLine -match "OK|START") { "Green" } else { "Gray" })
    }
    
    Write-Host ""  # пустая строка между заданиями
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[ИТОГ] Всего заданий: $($jobResults.Count)" -ForegroundColor Cyan
Write-Host "[ИТОГ] Всего ошибок: $totalErrors" -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan


# POST operation
$RemoveOldLogs = Remove-OldFiles `
    -Path $script:LogPathRoot `
    -DaysOld $script:LogDaysOld `
    -KeepCount $script:LogKeepCount `
    -Filter "*.*"
Write-Log $RemoveOldLogs

$DiskInfo = Get-DiskSpaceReport
Write-Log "DISK: $DiskInfo"

Write-Log "[TOTAL] JOBS: $($jobResults.Count)"
Write-Log "[TOTAL] ERRORS: $totalErrors"

$BodyMailLog = Get-Content $script:GlobalLog
$BodyMailLog = [string]::Join("`n", $BodyMailLog) 
$recipients = $Config.BackupConfig.Recipients.AdminMail
$ParentJobName = $script:Config.BackupConfig.General.JobName

if ($totalErrors -eq 0) {
  $SubjectMail = "BACKUP SUCCESS $ParentJobName $PCName "
  #$recipients = $Config.BackupConfig.Recipients.AdminIS
  $exitcode = 0
}else{
  $SubjectMail = "BACKUP ERRORS: $totalErrors $ParentJobName $PCName "
  #$recipients = "$Config.BackupConfig.Recipients.AdminIS , $Config.BackupConfig.Recipients.AdminOS "
  $exitcode = 1
}

Send-Email -Config $Config -To $recipients -Subject $SubjectMail -Body $BodyMailLog

exit $exitcode