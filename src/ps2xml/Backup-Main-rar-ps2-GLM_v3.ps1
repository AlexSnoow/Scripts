<#
.SYNOPSIS
    File Backup-rar-ps2-GLM_v3.ps1
    Автономный скрипт резервного копирования (Версия 2.6 RAR-only, PS 2.0 Strict)
.DESCRIPTION
    Исправлена ошибка $PSScriptRoot для Windows 7 (PS 2.0).
    Удалены все конструкции PS 3.0+ (HasFlag, -File, -Directory).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$TestMode
)

# ===========================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ===========================================================

# --- ВАЖНО: Инициализация $PSScriptRoot для PowerShell 2.0 ---
if (-not (Test-Path variable:PSScriptRoot)) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# -------------------------------------------------------------

$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
$Script:CultureInvariant = [System.Globalization.CultureInfo]::InvariantCulture

Clear-Host

# ===========================================================
#region CONFIG_BLOCK
# Загрузка конфигурации из XML
$xmlPath = Join-Path $PSScriptRoot "Backup-Config-All.xml"
if (-not (Test-Path $xmlPath)) {
    $xmlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "common\Backup-Config-All.xml"
}
if (-not (Test-Path $xmlPath)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: XML конфигурация не найдена." -ForegroundColor Red
    exit 1
}

[xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
$b = $xmlDoc.BackupConfig

# Проверка типа архиватора
$archiverType = $b.General.ArchiverType
if ($archiverType -ne "RAR") {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Скрипт настроен только на RAR, в конфигурации указан '$archiverType'" -ForegroundColor Red
    exit 1
}

# Создание хеш-таблицы конфигурации
$Script:EmbeddedConfig = @{
    General = @{
        JobName      = $b.General.JobName
        Domain       = $b.General.Domain
        SmtpServer   = $b.General.SmtpServer
        LogDaysOld   = [int]$b.General.LogDaysOld
        LogKeepCount = [int]$b.General.LogKeepCount
        ArchiverType = $b.General.ArchiverType
    }
    Paths = @{
        LogPathRoot = $b.Paths.LogPathRoot
        NetLogPath  = $b.Paths.NetLogPath
        RarPath     = $b.Paths.RarPath
    }
    Recipients = @{
        AdminIS   = $b.Recipients.AdminIS
        AdminOS   = $b.Recipients.AdminOS
        AdminMail = $b.Recipients.AdminMail
    }
    Integrity = @{
        RarExeHash = $b.Integrity.RarExeHash
    }
    Jobs = @{}
}

foreach ($jobNode in $b.Jobs.Job) {
    $jn = $jobNode.Name
    $Script:EmbeddedConfig['Jobs'][$jn] = @{
        Name = $jn
        Source = $jobNode.Source
        LocalDest = $jobNode.LocalDest
        RemoteDest = $jobNode.RemoteDest
        ArchivePattern = $jobNode.ArchivePattern
        RemoveSourceFlag = ($jobNode.RemoveSourceFlag -eq 'true')
        SourceDaysOld = [int]$jobNode.SourceDaysOld
        SourceKeepCount = [int]$jobNode.SourceKeepCount
        LocalDestDaysOld = [int]$jobNode.LocalDestDaysOld
        LocalDestKeepCount = [int]$jobNode.LocalDestKeepCount
        RemoveRemoteDestFlag = ($jobNode.RemoveRemoteDestFlag -eq 'true')
        RemoteDestDaysOld = [int]$jobNode.RemoteDestDaysOld
        RemoteDestKeepCount = [int]$jobNode.RemoteDestKeepCount
        ArhLog = ($jobNode.ArhLog -eq 'true')
        ArchiveIndividualFolders = ($jobNode.ArchiveIndividualFolders -eq 'true')
        ArchiveIndividualFiles = ($jobNode.ArchiveIndividualFiles -eq 'true')
    }
    if ($jobNode.ArhParameters) {
        $ap = @()
        foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
        $Script:EmbeddedConfig['Jobs'][$jn]['ArhParameters'] = $ap
    }
    if ($jobNode.SourceCheckMasks) {
        $sm = @()
        foreach ($m in $jobNode.SourceCheckMasks.Mask) { $sm += $m }
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceCheckMasks'] = $sm
    }
    if ($jobNode.SourceFilter) {
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceFilter'] = $jobNode.SourceFilter
    }
    if ($jobNode.FileFilter) {
        $Script:EmbeddedConfig['Jobs'][$jn]['SourceFilter'] = $jobNode.FileFilter
    }
    if ($jobNode.IndividualArchivePattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['IndividualArchivePattern'] = $jobNode.IndividualArchivePattern
    }
    if ($jobNode.ExcludeFolderPattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ExcludeFolderPattern'] = $jobNode.ExcludeFolderPattern
    }
    if ($jobNode.ExcludeFilePattern) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ExcludeFilePattern'] = $jobNode.ExcludeFilePattern
    }
    if ($jobNode.ListSourceFlag) {
        $Script:EmbeddedConfig['Jobs'][$jn]['ListSourceFlag'] = $jobNode.ListSourceFlag
    }
}

$BackupConfig = $Script:EmbeddedConfig

$config = @{
    Settings = @{
        PCName         = $env:COMPUTERNAME
        JobName        = $BackupConfig['General']['JobName']
        Domain         = $BackupConfig['General']['Domain']
        LogPath        = $BackupConfig['Paths']['LogPathRoot']
        ArchiverType   = $BackupConfig['General']['ArchiverType']
        ArchiverPath   = $BackupConfig['Paths']['RarPath']
        ArchiverHash   = $BackupConfig['Integrity']['RarExeHash']
        ArchiverParams = $BackupConfig['General']['DefaultRarParameters']
        SmtpServer     = $BackupConfig['General']['SmtpServer']
    }
    Jobs = $BackupConfig['Jobs']
}
#endregion CONFIG_BLOCK

# ===========================================================
#region ФУНКЦИЯ ВЫЧИСЛЕНИЯ SHA256 ХЕША
# ===========================================================
function Get-FileHashCompat {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Path', Position=0, ValueFromPipeline=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true, ParameterSetName='LiteralPath')]
        [string]$LiteralPath,
        [Parameter(Mandatory=$false)]
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )
    process {
        $filePath = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        try {
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Файл не найден: $filePath"
            }
            $hashAlgo = [System.Security.Cryptography.SHA256]::Create()
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $hashBytes = $hashAlgo.ComputeHash($fileStream)
                $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
                $obj = New-Object PSObject -Property @{
                    Hash = $hashString.ToUpper()
                    Algorithm = $Algorithm.ToUpper()
                    Path = (Resolve-Path -LiteralPath $filePath).Path
                }
                return $obj
            }
            finally {
                $fileStream.Dispose()
                $hashAlgo.Dispose()
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
#endregion

# ===========================================================
#region ФУНКЦИЯ ПРОВЕРКИ ЦЕЛОСТНОСТИ
# ===========================================================
function Test-FileIntegrity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$ExpectedHash,
        [Parameter(Mandatory=$false)][string]$FileType = "Файл"
    )
    process {
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
            if ($actualHash -eq $expectedHashUpper) {
                Write-Host "  [OK] Хеш подтвержден." -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "  [FAIL] Хеш НЕ СОВПАДАЕТ!" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "  Ошибка: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
}
#endregion

# ===========================================================
# Извлечение базовых переменных
# ===========================================================
$PCName = $env:COMPUTERNAME
$NameDomain = $BackupConfig['General']['Domain']
$PCNameMail = "$PCName@head.$NameDomain"
$SmtpServer = $BackupConfig['General']['SmtpServer']
$ParentJobName = $BackupConfig['General']['JobName']
$LogDaysOld = $BackupConfig['General']['LogDaysOld']
$LogKeepCount = $BackupConfig['General']['LogKeepCount']
$AdminIS = $BackupConfig['Recipients']['AdminIS']
$AdminOS = $BackupConfig['Recipients']['AdminOS']
$AdminMail = $BackupConfig['Recipients']['AdminMail']

# ==============================================================================
#region ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR
# ==============================================================================
Write-Host "`n=== ЭТАП 1: ПРОВЕРКА АРХИВАТОРА RAR ===" -ForegroundColor Yellow

$archiverPathValue = $BackupConfig['Paths']['RarPath']
$archiverHash = $BackupConfig['Integrity']['RarExeHash']

if ([string]::IsNullOrWhiteSpace($archiverPathValue)) {
    Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Не найден путь к RAR.exe" -ForegroundColor Red
    exit 1
}

if (-not (Test-FileIntegrity -FilePath $archiverPathValue -ExpectedHash $archiverHash -FileType "RAR.exe")) {
    Write-Host "ПРОВЕРКА АРХИВАТОРА ПРОВАЛЕНА. Запуск скрипта запрещен." -ForegroundColor Red
    exit 1
}

Write-Host "Архиватор RAR проверен: $archiverPathValue`n" -ForegroundColor Green
#endregion

# ==============================================================================
#region МОДУЛЬ ЛОГИРОВАНИЯ
# ==============================================================================
$Script:LogPath = $null
$Script:MainLogFile = $null
$Script:ReportEntries = @()

function Initialize-Logging {
    param([string]$LogPath, [string]$PCName, [string]$JobName)
    try {
        $safePCName = $PCName -replace '[\\/:*?"<>|]', '-'
        $safeJobName = $JobName -replace '[\\/:*?"<>|]', '-'
        if (-not (Test-Path -LiteralPath $LogPath -PathType Container)) {
            New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $logFileName = "${safePCName}_${safeJobName}_${timestamp}.log"
        $fullLogPath = Join-Path -Path $LogPath -ChildPath $logFileName
        $Script:LogPath = $LogPath
        $Script:MainLogFile = $fullLogPath
        $Script:ReportEntries = @()
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($fullLogPath, "", $utf8NoBom)
        return $true
    }
    catch { throw "Ошибка инициализации логирования: $_" }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO', [switch]$ResultKey)
    if (-not $Script:MainLogFile) { return }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) { "ERROR" { "[ERR]" } "WARNING" { "[WRN]" } "SUCCESS" { "[OK ]" } default { "[INF]" } }
    $line = "[$timestamp] $prefix $Message"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::AppendAllText($Script:MainLogFile, "$line`r`n", $utf8NoBom)
    if ($ResultKey) { $Script:ReportEntries += $line }
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
    }
}
function Write-LogSection { param([string]$Title); Write-Log "=== $Title ===" }

function Write-WinEventAppLog {
    param([string]$StatusKey, [string]$MessageText, [string]$Source = $ParentJobName)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) { return }
        $eventIdMap = @{ Start = 3000; Success = 3001; Error = 3003; End = 3004 }
        $entryTypeMap = @{
            Start   = [System.Diagnostics.EventLogEntryType]::Information
            Success = [System.Diagnostics.EventLogEntryType]::Information
            Error   = [System.Diagnostics.EventLogEntryType]::Error
            End     = [System.Diagnostics.EventLogEntryType]::Information
        }
        $eventLog = New-Object System.Diagnostics.EventLog("Application")
        $eventLog.Source = $Source
        $eventLog.WriteEntry($MessageText, $entryTypeMap[$StatusKey], $eventIdMap[$StatusKey])
    }
    catch { Write-Log "EventLog Error: $_" -Level WARNING }
}
#endregion

# ==============================================================================
#region МОДУЛЬ RAR ОПЕРАЦИЙ
# ==============================================================================
function Get-RarExitCodeMeaning {
    param([int]$ExitCode)
    switch ($ExitCode) {
        0 { "OK" } 1 { "Warning" } 2 { "Fatal Error" } 3 { "CRC Error" } default { "Unknown $ExitCode" }
    }
}

function Start-RarArchive {
    param([string]$RarPath, [string]$ArchivePath, [string]$SourcePath, [string[]]$Params, [string]$LogPath, [string]$Filter)
    
    $argsList = @($Params)
    if (-not [string]::IsNullOrEmpty($LogPath)) { $argsList += '-ilog"' + $LogPath + '"' }
    
    $safeArchive = '"' + $ArchivePath + '"'
    $targetPath = if (-not [string]::IsNullOrEmpty($Filter)) { Join-Path $SourcePath $Filter } else { $SourcePath }
    $safeSource = '"' + $targetPath + '"'
    
    $argsList += @($safeArchive, $safeSource)
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RarPath
    $psi.Arguments = $argsList -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Script:EncodingOEM
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.Start() | Out-Null
    $p.WaitForExit()
    
    $size = 0
    if (Test-Path $ArchivePath) { $size = [math]::Round((Get-Item $ArchivePath).Length / 1MB, 2) }
    return @{ ExitCode = $p.ExitCode; Size = $size }
}

function Test-RarArchive {
    param([string]$RarPath, [string]$ArchivePath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RarPath
    $psi.Arguments = "t `"$ArchivePath`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.Start() | Out-Null
    $p.WaitForExit()
    return ($p.ExitCode -eq 0)
}
#endregion

# ==============================================================================
#region ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (PS 2.0 Compatible)
# ==============================================================================
function Get-FileInfoDetails {
    param([string]$Path)
    try {
        # PS 2.0: Нет -File
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $cnt = ($items | Measure-Object).Count
        $sz = [math]::Round(($items | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        return @{ FileCount = $cnt; TotalSizeMB = $sz }
    }
    catch { return @{ FileCount = 0; TotalSizeMB = 0 } }
}

function Copy-BackupFile {
    param([string]$SourcePath, [string]$DestinationPath)
    $copyStart = Get-Date
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    $duration = [math]::Round(((Get-Date) - $copyStart).TotalSeconds, 2)
    $sourceSize = (Get-Item $SourcePath).Length
    $destSize = (Get-Item $DestinationPath).Length
    return @{ Success = ($sourceSize -eq $destSize); Duration = $duration }
}

# PS 2.0: Вспомогательная функция для списков файлов
function Get-FileList {
    param([string]$Path)
    $rootPath = (Resolve-Path -LiteralPath $Path).Path
    if ($rootPath.EndsWith('\')) { $rootPath = $rootPath.Substring(0, $rootPath.Length - 1) }
    
    $items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue | 
             Where-Object { -not $_.PSIsContainer }
    
    $result = @()
    foreach ($item in $items) {
        # PS 2.0: HasFlag нет, используем -band
        $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
        if ($isReparse) { continue }
        
        $relative = $item.FullName.Substring($rootPath.Length).TrimStart('\')
        $result += New-Object PSObject -Property @{
            RelativePath = $relative
            Length = $item.Length
            LastWriteTime = $item.LastWriteTime
            FullName = $item.FullName
        }
    }
    return $result
}

function Get-FilterFileList {
    param([string]$Path, [string]$Filter)
    $allFiles = Get-FileList -Path $Path
    if ($allFiles.Count -eq 0) { return @() }
    
    $filtered = $allFiles | Where-Object {
        $name = Split-Path -Path $_.RelativePath -Leaf
        $name -like $Filter
    }
    return $filtered
}

function Remove-OldFiles {
    param([string]$Path, [int]$DaysOld, [int]$KeepCount, [string]$Filter)
    if (-not (Test-Path $Path)) { return }
    
    $dateLimit = (Get-Date).AddDays(-$DaysOld)
    # PS 2.0: Нет -File
    $allFiles = Get-ChildItem -Path $Path -Filter $Filter -ErrorAction SilentlyContinue | 
                Where-Object { -not $_.PSIsContainer } | 
                Sort-Object LastWriteTime -Descending
    
    $keep = $allFiles | Select-Object -First $KeepCount
    
    foreach ($f in $allFiles) {
        if ($keep -notcontains $f -and $f.LastWriteTime -lt $dateLimit) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Deleted: $($f.Name)"
        }
    }
}

function Get-DiskSpaceReport {
    # PS 2.0: Используем .NET вместо Get-CimInstance
    try {
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
        $res = ""
        foreach ($d in $drives) {
            $free = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
            $total = [math]::Round($d.TotalSize / 1GB, 1)
            $res += "$($d.Name.Substring(0,1))($free/$total GB) "
        }
        return $res
    }
    catch { return "Error" }
}

function Send-Email {
    param([string]$SmtpServer, [string]$From, [string]$To, [string]$Subject, [string]$Body)
    try {
        $msg = New-Object Net.Mail.MailMessage($From, $To, $Subject, $Body)
        $msg.BodyEncoding = [System.Text.Encoding]::UTF8
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer)
        $smtp.Send($msg)
        return $true
    }
    catch { return $false }
}
#endregion

# ==============================================================================
#region МОДУЛЬ ИНДИВИДУАЛЬНОЙ АРХИВАЦИИ (PS 2.0 Compatible)
# ==============================================================================
function Start-IndividualFileArchive {
    param(
        [string]$ArchiverPath, [string]$SourcePath, [string]$DestinationPath, 
        [string]$FileFilter, [string]$ExcludeFilePattern, [string]$ArchivePattern, 
        [string[]]$Parameters, [string]$PCName, [string]$JobName
    )
    $results = @()
    Write-Log "Поиск файлов: $FileFilter" -Level INFO -ResultKey
    $files = Get-FilterFileList -Path $SourcePath -Filter $FileFilter
    
    if ($ExcludeFilePattern) {
        $files = $files | Where-Object {
            $name = Split-Path $_.RelativePath -Leaf
            ($_.RelativePath -notlike $ExcludeFilePattern) -and ($name -notlike $ExcludeFilePattern)
        }
    }
    
    if ($files.Count -eq 0) { Write-Log "Файлы не найдены" -Level WARNING -ResultKey; return $results }
    
    Write-Log "Найдено: $($files.Count)" -Level INFO -ResultKey
    if (-not (Test-Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }
    
    foreach ($file in $files) {
        $sourceFileName = Split-Path -Path $file.RelativePath -Leaf
        $archiveName = $ArchivePattern -replace '{SourceFileName}', $sourceFileName -replace '{PCName}', $PCName -replace '{JobName}', $JobName
        $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
        if (-not $archiveName.EndsWith('.rar')) { $archiveName += '.rar' }
        
        $archivePath = Join-Path $DestinationPath $archiveName
        Write-Log "File: $sourceFileName -> $archiveName" -Level INFO
        
        $res = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $file.FullName -Params $Parameters
        
        if ($res.ExitCode -eq 0) {
            $obj = New-Object PSObject -Property @{ SourceFile = $sourceFileName; SourceFileFullName = $file.FullName; ArchivePath = $archivePath; Status = 'Success'; ArchiveSize = $res.Size }
            $results += $obj
            Write-Log "Success: $archiveName ($($res.Size) MB)" -Level SUCCESS -ResultKey
        }
        else {
            $obj = New-Object PSObject -Property @{ SourceFile = $sourceFileName; SourceFileFullName = $file.FullName; Status = 'Error' }
            $results += $obj
            Write-Log "Error: $sourceFileName" -Level ERROR -ResultKey
        }
    }
    return $results
}

function Start-IndividualFolderArchive {
    param(
        [string]$ArchiverPath, [string]$SourcePath, [string]$DestinationPath, 
        [string]$ArchivePattern, [string]$FolderFilter, [string]$ExcludeFolderPattern,
        [string[]]$Parameters, [string]$PCName, [string]$JobName
    )
    $results = @()
    Write-Log "Поиск папок: $SourcePath" -Level INFO -ResultKey
    
    # PS 2.0: Нет -Directory
    $folders = Get-ChildItem -Path $SourcePath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
    
    if ($FolderFilter) { $folders = $folders | Where-Object { $_.Name -like $FolderFilter } }
    if ($ExcludeFolderPattern) {
        if ($ExcludeFolderPattern -eq 'today') {
             $today = Get-Date -Format 'yyyyMMdd'
             $folders = $folders | Where-Object { $_.Name -ne $today }
        } else {
             $folders = $folders | Where-Object { $_.Name -notlike $ExcludeFolderPattern }
        }
    }
    
    if ($folders.Count -eq 0) { Write-Log "Папки не найдены" -Level WARNING -ResultKey; return $results }
    
    Write-Log "Найдено: $($folders.Count)" -Level INFO -ResultKey
    if (-not (Test-Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }
    
    foreach ($folder in $folders) {
        $archiveName = $ArchivePattern -replace '{SourceFolderName}', $folder.Name -replace '{PCName}', $PCName -replace '{JobName}', $JobName
        $archiveName = $archiveName -replace '[\\/:*?"<>|]', '_'
        if (-not $archiveName.EndsWith('.rar')) { $archiveName += '.rar' }
        
        $archivePath = Join-Path $DestinationPath $archiveName
        Write-Log "Folder: $($folder.Name) -> $archiveName" -Level INFO
        
        $res = Start-RarArchive -RarPath $ArchiverPath -ArchivePath $archivePath -SourcePath $folder.FullName -Params $Parameters
        
        if ($res.ExitCode -eq 0) {
            $obj = New-Object PSObject -Property @{ SourceFolder = $folder.Name; SourceFolderFullPath = $folder.FullName; ArchivePath = $archivePath; Status = 'Success'; ArchiveSize = $res.Size }
            $results += $obj
            Write-Log "Success: $archiveName" -Level SUCCESS -ResultKey
        }
        else {
            $obj = New-Object PSObject -Property @{ SourceFolder = $folder.Name; SourceFolderFullPath = $folder.FullName; Status = 'Error' }
            $results += $obj
            Write-Log "Error: $($folder.Name)" -Level ERROR -ResultKey
        }
    }
    return $results
}
#endregion

# ==============================================================================
#region ГЛАВНЫЙ БЛОК
# ==============================================================================
$scriptStartTime = Get-Date

# ТЕСТОВЫЙ РЕЖИМ
if ($TestMode) {
    Write-Host "`n=== TEST MODE ===" -ForegroundColor Cyan
    $err = 0
    if (-not (Test-Path $BackupConfig['Paths']['RarPath'])) { Write-Host "RAR not found" -Red; $err++ }
    foreach ($j in $BackupConfig['Jobs'].Keys) {
        if (-not (Test-Path $BackupConfig['Jobs'][$j]['Source'])) { Write-Host "Source missing: $j" -Red; $err++ }
    }
    if ($err -eq 0) { Write-Host "All OK" -Green; exit 0 } else { exit 1 }
}

# Инициализация лога
try { Initialize-Logging -LogPath $config['Settings']['LogPath'] -PCName $PCName -JobName $ParentJobName }
catch { Write-Host "Log Init Failed: $_" -Red; exit 1 }

Write-LogSection "START BACKUP"
Write-Log "Config: $xmlPath" -ResultKey

$results = @{}
$errCount = 0
$okCount = 0

Write-WinEventAppLog -StatusKey "Start" -MessageText "Start: $ParentJobName"

# ЦИКЛ ЗАДАНИЙ
foreach ($jobName in $BackupConfig['Jobs'].Keys) {
    $job = $BackupConfig['Jobs'][$jobName]
    $jobStart = Get-Date
    Write-LogSection "JOB: $jobName" -ResultKey
    
    try {
        if (-not (Test-Path $job['Source'])) { throw "Source missing" }
        
        # Создание каталогов
        if (-not (Test-Path $job['LocalDest'])) { New-Item -Path $job['LocalDest'] -ItemType Directory -Force | Out-Null }
        if ($job['RemoteDest'] -and (-not (Test-Path $job['RemoteDest']))) { New-Item -Path $job['RemoteDest'] -ItemType Directory -Force | Out-Null }

        $fileInfo = Get-FileInfoDetails -Path $job['Source']
        Write-Log "Files: $($fileInfo.FileCount), Size: $($fileInfo.TotalSizeMB) MB" -ResultKey

        # 1. Индивидуальные файлы
        if ($job['ArchiveIndividualFiles']) {
            Write-Log "Mode: Individual Files" -ResultKey
            if (-not $job['SourceFilter']) { throw "SourceFilter required" }
            
            $indRes = Start-IndividualFileArchive -ArchiverPath $config['Settings']['ArchiverPath'] -SourcePath $job['Source'] -DestinationPath $job['LocalDest'] -FileFilter $job['SourceFilter'] -ExcludeFilePattern $job['ExcludeFilePattern'] -ArchivePattern $job['IndividualArchivePattern'] -Parameters $job['ArhParameters'] -PCName $PCName -JobName $jobName
            
            $errF = ($indRes | Where-Object { $_.Status -eq 'Error' }).Count
            if ($errF -gt 0) { $errCount += $errF; $results[$jobName] = "Partial: $errF errors" }
            else { $okCount++; $results[$jobName] = "Success: $($indRes.Count) files" }
            
            # Копирование в сеть (упрощенно)
            if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
                foreach ($r in $indRes) {
                    if ($r.Status -eq 'Success') {
                        $dest = Join-Path $job['RemoteDest'] (Split-Path $r.ArchivePath -Leaf)
                        Copy-Item $r.ArchivePath $dest -Force
                    }
                }
            }
            continue
        }

        # 2. Индивидуальные папки
        if ($job['ArchiveIndividualFolders']) {
            Write-Log "Mode: Individual Folders" -ResultKey
            $indRes = Start-IndividualFolderArchive -ArchiverPath $config['Settings']['ArchiverPath'] -SourcePath $job['Source'] -DestinationPath $job['LocalDest'] -ArchivePattern $job['IndividualArchivePattern'] -FolderFilter $job['SourceFilter'] -ExcludeFolderPattern $job['ExcludeFolderPattern'] -Parameters $job['ArhParameters'] -PCName $PCName -JobName $jobName
            
            $errF = ($indRes | Where-Object { $_.Status -eq 'Error' }).Count
            if ($errF -gt 0) { $errCount += $errF; $results[$jobName] = "Partial: $errF errors" }
            else { $okCount++; $results[$jobName] = "Success: $($indRes.Count) folders" }
            
            # Копирование и ротация (упрощенно)
            if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
                 foreach ($r in $indRes) {
                    if ($r.Status -eq 'Success') {
                        $dest = Join-Path $job['RemoteDest'] (Split-Path $r.ArchivePath -Leaf)
                        Copy-Item $r.ArchivePath $dest -Force
                    }
                }
            }
            Remove-OldFiles -Path $job['LocalDest'] -DaysOld $job['LocalDestDaysOld'] -KeepCount $job['LocalDestKeepCount'] -Filter "*.rar"
            continue
        }

        # 3. Обычная архивация
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        $archName = "{0}_{1}_{2}.rar" -f $PCName, $jobName, $date
        if ($job['ArchivePattern']) {
            $archName = $job['ArchivePattern'] -replace '{PCName}', $PCName -replace '{JobName}', $jobName -replace '{Date}', $date
        }
        $archPath = Join-Path $job['LocalDest'] $archName
        Write-Log "Archive: $archName" -ResultKey

        $params = $job['ArhParameters']
        if (-not $params) { $params = @("a", "-m3", "-s", "-ep1", "-rr1p", "-r", "-dh", "-t") }
        
        Write-Log "Running RAR..."
        $r = Start-RarArchive -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archPath -SourcePath $job['Source'] -Params $params -Filter $job['SourceFilter']
        
        if ($r.ExitCode -ne 0) { throw "RAR Error: $(Get-RarExitCodeMeaning $r.ExitCode)" }
        Write-Log "Size: $($r.Size) MB" -ResultKey

        if (-not (Test-RarArchive -RarPath $config['Settings']['ArchiverPath'] -ArchivePath $archPath)) { throw "Test failed" }
        Write-Log "Test OK" -ResultKey

        if ($job['RemoteDest'] -and (Test-Path $job['RemoteDest'])) {
            $dest = Join-Path $job['RemoteDest'] $archName
            $c = Copy-BackupFile -SourcePath $archPath -DestinationPath $dest
            if ($c.Success) { Write-Log "Copied to network" -ResultKey }
            else { throw "Copy failed" }
        }
        
        Remove-OldFiles -Path $job['LocalDest'] -DaysOld $job['LocalDestDaysOld'] -KeepCount $job['LocalDestKeepCount'] -Filter "*.rar"
        if ($job['RemoveRemoteDestFlag']) { Remove-OldFiles -Path $job['RemoteDest'] -DaysOld $job['RemoteDestDaysOld'] -KeepCount $job['RemoteDestKeepCount'] -Filter "*.rar" }
        if ($job['RemoveSourceFlag']) { Remove-OldFiles -Path $job['Source'] -DaysOld $job['SourceDaysOld'] -KeepCount $job['SourceKeepCount'] -Filter "*" }

        $okCount++
        $results[$jobName] = "Success"
    }
    catch {
        Write-Log "ERROR: $_" -Level ERROR
        $results[$jobName] = "Error: $_"
        $errCount++
    }
}

# ФИНАЛ
$dur = [math]::Round(((Get-Date) - $scriptStartTime).TotalMinutes, 2)
Write-LogSection "FINISH"
Write-Log "Duration: $dur min. OK=$okCount, Err=$errCount" -ResultKey
Write-Log "Disks: $(Get-DiskSpaceReport)"

$body = ($Script:ReportEntries -join "`r`n") + "`r`nDisks: " + (Get-DiskSpaceReport)
$subj = "$PCName $ParentJobName : " + $(if ($errCount -gt 0) { "ERRORS" } else { "OK" })
$to = if ($errCount -gt 0) { "$AdminIS, $AdminOS" } else { $AdminIS }

Write-WinEventAppLog -StatusKey $(if ($errCount -gt 0) { "Error" } else { "Success" }) -MessageText "Finish. Errors: $errCount"

if ($SmtpServer) { Send-Email -SmtpServer $SmtpServer -From $PCNameMail -To $to -Subject $subj -Body $body }

Remove-OldFiles -Path $config['Settings']['LogPath'] -DaysOld $LogDaysOld -KeepCount $LogKeepCount -Filter "*.log"

if ($errCount -gt 0) { exit 1 } else { exit 0 }