<#
.SYNOPSIS
    Universal backup script supporting RAR and 7z archivers.

.DESCRIPTION
    Executes a 5-stage pipeline: Preparation -> Main Operation (archiving) ->
    Verification (archive integrity) -> Post-Operations (rotation, remote copy) ->
    Reporting (log, email). Compatible with PowerShell 2.0 / Windows 7.

.PARAMETER ConfigPath
    Path to Backup-Config.xml configuration file.

.PARAMETER testmode
    Run in test mode: validate configuration without creating archives.

.EXAMPLE
    powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\backup-ps2-v6.ps1
    Normal run with default config path.

.EXAMPLE
    powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\backup-ps2-v6.ps1 -testmode
    Validate configuration only.
#>
#Requires -Version 2.0

param(
    [string]$ConfigPath = ".\Backup-Config.xml",
    [switch]$testmode
)

# ============================================================================
# ENCODING (PS 2.0 safe)
# ============================================================================
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false

# ============================================================================
# COMMON FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Writes a timestamped message to the global log file.
.DESCRIPTION
    Appends "yyyy-MM-dd HH:mm:ss -> message" to $script:GlobalLog.
    Silently continues on error.
#>
function Write-Log {
    param([string]$Message)
    if (-not $Message -or -not $script:GlobalLog) { return }
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " -> " + $Message
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    Sends an email report via SMTP.
.DESCRIPTION
    Reads SmtpServer, Domain, and AdminMail from config if not specified.
    Supports SSL, custom port, and credentials.
#>
function Send-Email {
    param(
        $Config,
        [string]$SmtpServer,
        [string]$From,
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [int]$Port = 25,
        [bool]$UseSSL = $false,
        [string]$Username,
        [string]$Password,
        [bool]$IsBodyHtml = $false
    )
    if (-not $SmtpServer) { $SmtpServer = $Config.BackupConfig.General.SmtpServer }
    if (-not $From) { $From = "$env:COMPUTERNAME@$($Config.BackupConfig.General.Domain)" }
    if (-not $To) { $To = $Config.BackupConfig.Recipients.AdminMail }
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
        Write-Host "[MAIL] Sent: $Subject" -ForegroundColor Green
        return $true
    }
    catch {
        $mailErr = $_.Exception.Message
        Write-Host "[MAIL] Error: $mailErr" -ForegroundColor Red
        return $false
    }
    finally {
        $msg = $null
        $smtp = $null
    }
}

<#
.SYNOPSIS
    Tests if a string is null or empty.
#>
function Test-Empty {
    param([string]$s)
    return ($s -eq $null -or $s.Trim().Length -eq 0)
}

<#
.SYNOPSIS
    Converts a value to boolean (case-insensitive "true"/"false").
#>
function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}

# ============================================================================
# HASH FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Computes SHA256 hash of a file using .NET (PS 2.0 compatible).
.DESCRIPTION
    Used as a fallback when Get-FileHash is not available.
    Supports SHA1, SHA256, SHA384, SHA512, MD5.
#>
function Get-FileHashCompat {
    param(
        [string]$Path,
        [string]$LiteralPath,
        [string]$Algorithm = 'SHA256'
    )
    $filePath = $Path
    if ($LiteralPath) { $filePath = $LiteralPath }
    try {
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "File not found: $filePath"
        }
        $hashAlgo = switch ($Algorithm.ToUpper()) {
            'SHA1'   { [System.Security.Cryptography.SHA1]::Create() }
            'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
            'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
            'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
            'MD5'    { [System.Security.Cryptography.MD5]::Create() }
            default  { [System.Security.Cryptography.SHA256]::Create() }
        }
        $fileStream = [System.IO.File]::OpenRead($filePath)
        try {
            $hashBytes = $hashAlgo.ComputeHash($fileStream)
            $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
            return (New-Object PSObject -Property @{
                Hash      = $hashString.ToUpper()
                Algorithm = $Algorithm.ToUpper()
                Path      = (Resolve-Path -LiteralPath $filePath).Path
            })
        }
        finally {
            $fileStream.Dispose()
        }
    }
    catch {
        $hashErr = $_.Exception.Message
        throw "Hash error '$filePath': $hashErr"
    }
}

if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    Set-Alias -Name Get-FileHash -Value Get-FileHashCompat -Scope Global -Force
}

<#
.SYNOPSIS
    Verifies file integrity via SHA256 hash comparison.
.DESCRIPTION
    Returns $true if the actual file hash matches the expected hash.
    Used for config XML and archiver binary integrity checks.
#>
function Test-FileIntegrity {
    param(
        [string]$FilePath,
        [string]$ExpectedHash,
        [string]$FileType = "File"
    )
    if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) {
        Write-Host "Invalid hash format for $FileType" -ForegroundColor Red
        return $false
    }
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-Host "Error: file not found: $FilePath" -ForegroundColor Red
        return $false
    }
    try {
        Write-Host "Checking integrity ($FileType): $FilePath..." -ForegroundColor Cyan
        $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpper()
        $expectedHashUpper = $ExpectedHash.ToUpper()
        Write-Host "  Expected : $expectedHashUpper"
        Write-Host "  Actual   : $actualHash"
        if ($actualHash -eq $expectedHashUpper) {
            Write-Host "  [OK] Hash match." -ForegroundColor Green
            return $true
        }
        Write-Host "  [FAIL] Hash mismatch!" -ForegroundColor Red
        return $false
    }
    catch {
        $intErr = $_.Exception.Message
        Write-Host ("Hash error for " + $FileType + ": " + $intErr) -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# HELPERS
# ============================================================================

<#
.SYNOPSIS
    Resolves archive name pattern by replacing placeholders.
.DESCRIPTION
    Supports {PCName}, {JobName}, {Date}, {LastWriteTime}, {SourceFileName},
    {SourceFolderName}, {arhiveExt}. Removes invalid filesystem characters.
#>
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
    $r = $r -replace "{arhiveExt}", $script:ArhiveExt
    $r = $r -replace '[\\/:*?"<>|]', '_'
    $r = $r -replace '_+', '_'
    $r = $r.Trim()
    if ($r -notmatch ("\." + $script:ArhiveExt + "$")) {
        $r += "." + $script:ArhiveExt
    }
    return $r
}

<#
.SYNOPSIS
    Copies archive to RemoteDest if configured.
#>
function Copy-Remote {
    param($ctx, $archivePath)
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

# ============================================================================
# ROTATION
# ============================================================================

<#
.SYNOPSIS
    Removes old files based on age (DaysOld) and count (KeepCount).
.DESCRIPTION
    Sorts files by LastWriteTime descending. Keeps the newest $KeepCount files,
    then deletes files older than $DaysOld. Returns a summary string.
#>
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
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        if ($DaysOld -le 0) { $cutoffDate = [DateTime]::MaxValue }
        [array]$allFiles = Get-ChildItem -Path $Path -Filter $Filter |
            Where-Object { -not $_.PSIsContainer } |
            Sort-Object LastWriteTime -Descending
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
                }
                catch {
                    $results += "Error deleting: $($file.FullName) $_"
                }
            }
        }
        else {
            $results += "There are no files to delete."
        }
        $results += "Rotation is complete. Kept: $($allFiles.Count - $filesToDelete.Count) / Total: $($allFiles.Count)"
    }
    catch {
        $results += "Rotation error: $_"
    }
    return $results -join "`n"
}

# ============================================================================
# DISK SPACE
# ============================================================================

<#
.SYNOPSIS
    Reports free/used space for all fixed drives > 1 GB.
#>
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

# ============================================================================
# ARCHIVER ABSTRACTION
# ============================================================================

<#
.SYNOPSIS
    Returns archiver type string from config (default: RAR).
#>
function Get-ArchiverType {
    param($Config)
    $t = $Config.BackupConfig.General.ArchiverType
    if (Test-Empty $t) { return "RAR" }
    return $t
}

<#
.SYNOPSIS
    Returns file extension for the configured archiver.
#>
function Get-ArchiveExt {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return "7z" }
    return "rar"
}

<#
.SYNOPSIS
    Returns path to archiver executable.
#>
function Get-ArchiverPath {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return $Config.BackupConfig.Paths.Path7z }
    return $Config.BackupConfig.Paths.RarPath
}

<#
.SYNOPSIS
    Returns expected SHA256 hash of the archiver executable.
#>
function Get-ArchiverHash {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return $Config.BackupConfig.Paths.HASH7z }
    return $Config.BackupConfig.Paths.RarHASH
}

<#
.SYNOPSIS
    Builds parameter string for the archiver from config.
.DESCRIPTION
    Uses job-specific ArhParameters if present, otherwise falls back
    to DefaultRarParameters / Default7zParameters from General section.
#>
function Get-ArchiverParams {
    param($Config, $Job)
    $params = @()
    $bc = $Config.BackupConfig
    $t = Get-ArchiverType $Config
    if ($Job.ArhParameters) {
        foreach ($p in $Job.ArhParameters.Param) {
            $params += $p
        }
    }
    else {
        $paramSectionName = if ($t -eq "7z") { "Default7zParameters" } else { "DefaultRarParameters" }
        $paramSection = $bc.General.$paramSectionName
        if ($paramSection) {
            foreach ($p in $paramSection.Param) {
                $params += $p
            }
        }
    }
    return ($params -join " ")
}

<#
.SYNOPSIS
    Verifies archive integrity using the archiver's test command.
.DESCRIPTION
    For RAR: runs "rar t archive"; for 7z: runs "7z t archive".
    Returns $true if the archive passes integrity check.
#>
function Test-ArchiveIntegrity {
    param(
        $Config,
        [string]$ArchivePath,
        [string]$ArchiveName
    )
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        Write-Host "  [FAIL] Archive not found for verification: $ArchiveName" -ForegroundColor Red
        return $false
    }
    $archiverPath = Get-ArchiverPath $Config
    Write-Host "  [VERIFY] Testing archive integrity: $ArchiveName..." -ForegroundColor Cyan
    Write-Log ("VERIFY START " + $ArchivePath)
    $p = Start-Process -FilePath $archiverPath `
        -ArgumentList "t `"$ArchivePath`"" `
        -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) {
        Write-Host "    [OK] Integrity check passed: $ArchiveName" -ForegroundColor Green
        Write-Log ("VERIFY OK " + $ArchivePath)
        return $true
    }
    Write-Host "    [FAIL] Integrity check failed: $ArchiveName (CODE=$($p.ExitCode))" -ForegroundColor Red
    Write-Log ("VERIFY FAIL " + $ArchivePath + " CODE=" + $p.ExitCode)
    return $false
}

# ============================================================================
# FAST IO (PS 2.0 optimized using .NET directly)
# ============================================================================

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

# ============================================================================
# PREPARE FUNCTIONS (Stage 1: grouping files for archiving)
# ============================================================================

<#
.SYNOPSIS
    Groups files by date (yyyyMMdd). Excludes today if ExcludeToday is set.
#>
function Prepare-ArchiveByDate {
    param($ctx)
    $files = Get-FilesFast $ctx.Source "*.*"
    $groups = @{}
    foreach ($f in $files) {
        if ($ctx.ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) { continue }
        if ($ctx.ExcludeFilePattern -and $f.Name -like $ctx.ExcludeFilePattern) { continue }
        $key = $f.LastWriteTime.ToString("yyyyMMdd")
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.ArrayList
        }
        [void]$groups[$key].Add($f.FullName)
    }
    return $groups
}

<#
.SYNOPSIS
    Groups each file by its name (individual archives).
    Filters by SourceFilter and excludes ExcludeFilePattern.
#>
function Prepare-IndividualFiles {
    param($ctx)
    $files = Get-FilesFast $ctx.Source $ctx.SourceFilter
    $groups = @{}
    foreach ($f in $files) {
        if ($ctx.ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) { continue }
        if ($ctx.ExcludeFilePattern -and $f.Name -like $ctx.ExcludeFilePattern) { continue }
        $key = $f.Name
        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($f.FullName)
    }
    return $groups
}

<#
.SYNOPSIS
    Groups each subfolder by its name (individual archives).
    Excludes folders matching today's date if ExcludeToday is set.
#>
function Prepare-IndividualFolders {
    param($ctx)
    $dirs = Get-FoldersFast $ctx.Source
    $groups = @{}
    $today = (Get-Date).ToString("yyyyMMdd")
    foreach ($d in $dirs) {
        if ($d -eq $null) { continue }
        $key = $d.Name
        if (Test-Empty $key) { continue }
        if ($ctx.ExcludeToday -and $key -eq $today) { continue }
        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($d.FullName)
    }
    return $groups
}

<#
.SYNOPSIS
    Groups all files recursively into a single archive group.
#>
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

# ============================================================================
# ARCHIVE ENGINE (Stage 2 + Stage 3: Main Operation + Verification)
# ============================================================================

<#
.SYNOPSIS
    Creates archives for each group and verifies integrity.
.DESCRIPTION
    For each group: resolves archive name, creates list file, runs archiver,
    verifies archive integrity (rar t / 7z t), copies to RemoteDest.
    If an archive file already exists, appends _1, _2, etc. suffix.
#>
function Invoke-Archiving {
    param($ctx, $groups)
    $checkErrors = 0
    foreach ($key in $groups.Keys) {
        [array]$items = $groups[$key]
        if ($items.Count -eq 0) { continue }
        $archiveName = Resolve-Name `
            $ctx.Pattern `
            $ctx.PCName `
            $ctx.JobName `
            $key `
            $key
        if (Test-Empty $archiveName) { continue }
        $archivePath = Join-Path $ctx.Dest $archiveName
        # --- Check for existing archive, add index suffix (_1, _2, ...) ---
        $basePath = $archivePath
        $idx = 0
        while (Test-Path -LiteralPath $archivePath) {
            $idx++
            $ext = [System.IO.Path]::GetExtension($basePath)
            $nameOnly = [System.IO.Path]::GetFileNameWithoutExtension($basePath)
            $archiveName = $nameOnly + "_$idx" + $ext
            $archivePath = Join-Path $ctx.Dest $archiveName
        }
        # --- STAGE 2: Main Operation (archiving) ---
        $listFile = [System.IO.Path]::ChangeExtension($archivePath, ".txt")
        $items | Out-File -Encoding ASCII $listFile
        $paramsStr = Get-ArchiverParams $ctx.Config $ctx.Job
        $argStr = "$paramsStr `"$archivePath`" @`"$listFile`""
        Write-Log ("START " + $archivePath)
        $p = Start-Process -FilePath $ctx.ArchiverPath `
            -ArgumentList $argStr `
            -Wait -PassThru -NoNewWindow
        $exitCode = $p.ExitCode
        Write-Log ("END " + $archivePath + " CODE=" + $exitCode)
        if ($exitCode -ne 0) {
            $checkErrors++
            Write-Host "  [FAIL] Archive error: $archiveName (CODE=$exitCode)" -ForegroundColor Red
            continue
        }
        Write-Host "  [OK] Archive created: $archiveName" -ForegroundColor Green
        # --- STAGE 3: Verification (archive integrity test) ---
        $verified = Test-ArchiveIntegrity -Config $ctx.Config -ArchivePath $archivePath -ArchiveName $archiveName
        if (-not $verified) {
            $checkErrors++
            continue
        }
        # --- STAGE 4: Post-Operations (remote copy) ---
        Copy-Remote $ctx $archivePath
    }
    return $checkErrors
}

# ============================================================================
# JOB RUNNER
# ============================================================================

<#
.SYNOPSIS
    Executes a single backup job through the 5-stage pipeline.
.DESCRIPTION
    Stage 1 (Preparation): load config, create context, validate paths,
    select prepare mode, group files.
    Stage 2-4: see Invoke-Archiving.
    Stage 4 (Post-Ops): local rotation.
    Returns hashtable with Errors and Log array.
#>
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
        ArchiverPath       = Get-ArchiverPath $Config
        PCName             = $PCName
        Pattern            = ""
        ExcludeToday       = To-Bool $Job.ExcludeToday
        ExcludeFilePattern = if ($Job.ExcludeFilePattern) { $Job.ExcludeFilePattern } else { $null }
        SourceFilter       = "*"
        ArchiveAll         = To-Bool $Job.ArchiveAll
        RemoteDest         = $Job.RemoteDest
    }
    # --- STAGE 1: Preparation ---
    Write-Log ("===== JOB START " + $ctx.JobName + " =====")
    $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " ===== JOB START " + $ctx.JobName + " =====")
    if (-not (Test-Path $ctx.Source)) {
        $msg = "  [WARN] Source not found: $($ctx.Source)"
        Write-Host $msg -ForegroundColor Yellow
        $checkErrors++
        return @{ Errors = $checkErrors; Log = $jobLog }
    }
    if (-not (Test-Path $ctx.Dest)) {
        New-Item -ItemType Directory -Path $ctx.Dest | Out-Null
    }
    if ($ctx.RemoteDest -and -not (Test-Empty $ctx.RemoteDest) -and -not (Test-Path $ctx.RemoteDest)) {
        New-Item -ItemType Directory -Path $ctx.RemoteDest | Out-Null
    }
    if ($Job.ArchivePattern) { $ctx.Pattern = $Job.ArchivePattern }
    if ($Job.SourceFilter) { $ctx.SourceFilter = $Job.SourceFilter }
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
    # --- STAGES 2-4: Archiving, Verification, Remote Copy ---
    $archivingErrors = Invoke-Archiving $ctx $groups
    if ($archivingErrors -is [int]) {
        $checkErrors = $checkErrors + $archivingErrors
    }
    # --- STAGE 4: Post-Operations (local rotation) ---
    $null = Remove-OldFiles `
        -Path $ctx.Dest `
        -DaysOld $ctx.LocalDestDaysOld `
        -KeepCount $ctx.LocalDestKeepCount `
        -Filter "*.*"
    Write-Log ("===== /JOB END " + $ctx.JobName + " =====")
    $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " ===== /JOB END " + $ctx.JobName + " =====")
    return @{ Errors = $checkErrors; Log = $jobLog }
}

# ============================================================================
# TEST MODE
# ============================================================================

<#
.SYNOPSIS
    Validates configuration without creating archives.
.DESCRIPTION
    Checks: source path existence, destination writability,
    remote destination writability, archiver integrity.
    Sends email with results.
#>
function Invoke-TestMode {
    param($Config)
    Write-Host "`n[TEST MODE] Checking configuration..." -ForegroundColor Cyan
    $checkErrors = 0
    $archiverType = Get-ArchiverType $Config
    Write-Host "Archiver: $archiverType" -ForegroundColor Cyan
    foreach ($job in $Config.BackupConfig.Jobs.Job) {
        Write-Host "`nJob: $($job.Name)" -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $job.Source -PathType Container)) {
            Write-Host "  [FAIL] Source not found: $($job.Source)" -ForegroundColor Red
            $checkErrors++
        }
        else {
            Write-Host "  [OK] Source exists: $($job.Source)" -ForegroundColor Green
        }
        $dest = $job.LocalDest
        if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Write-Host "  [OK] Dest created: $dest" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL] Cannot create dest: $dest" -ForegroundColor Red
                $checkErrors++
            }
        }
        if (Test-Path -LiteralPath $dest -PathType Container) {
            $testFile = Join-Path $dest "._perm_test_"
            try {
                $fs = [System.IO.File]::OpenWrite($testFile)
                $fs.Close()
                [System.IO.File]::Delete($testFile)
                Write-Host "  [OK] Write permission: $dest" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL] No write permission: $dest" -ForegroundColor Red
                $checkErrors++
            }
        }
        if ($job.RemoteDest -and -not (Test-Empty $job.RemoteDest)) {
            if (-not (Test-Path -LiteralPath $job.RemoteDest -PathType Container)) {
                try { New-Item -ItemType Directory -Path $job.RemoteDest -Force | Out-Null } catch { }
            }
            if (Test-Path -LiteralPath $job.RemoteDest -PathType Container) {
                $testFile = Join-Path $job.RemoteDest "._perm_test_"
                try {
                    $fs = [System.IO.File]::OpenWrite($testFile)
                    $fs.Close()
                    [System.IO.File]::Delete($testFile)
                    Write-Host "  [OK] Write permission remote: $($job.RemoteDest)" -ForegroundColor Green
                }
                catch {
                    Write-Host "  [WARN] No write permission remote: $($job.RemoteDest)" -ForegroundColor Yellow
                    $checkErrors++
                }
            }
        }
    }
    Write-Host "`n[TEST MODE] Result:" -ForegroundColor Cyan
    if ($checkErrors -eq 0) {
        $Status = "OK"
        $StatusText = "All checks passed"
        $Color = "Green"
    }
    else {
        $Status = "FAIL"
        $StatusText = "Errors found ($checkErrors)"
        $Color = "Red"
    }
    Write-Host "  $StatusText" -ForegroundColor $Color
    $SubjectMail = "[$Status] $script:JobName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $BodyMail = "Job: $script:JobName`nPC: $env:COMPUTERNAME`nStatus: $StatusText`nErrors: $checkErrors`nTime: $(Get-Date)"
    Send-Email -Config $Config -Subject $SubjectMail -Body $BodyMail
    if ($checkErrors -eq 0) { exit 0 } else { exit 1 }
}

# ============================================================================
# MAIN — 5-STAGE PIPELINE
# ============================================================================

# --- STAGE 1: Preparation (config loading, validation, initialization) ---

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

[xml]$script:Config = Get-Content $ConfigPath

$script:General     = $script:Config.BackupConfig.General
$script:Paths       = $script:Config.BackupConfig.Paths
$script:Recipients  = $script:Config.BackupConfig.Recipients
$script:JobName     = $script:General.ParentJobName
$script:LogPathRoot = $script:Paths.LogPathRoot
$script:LogDaysOld  = [int]$script:Paths.LogDaysOld
$script:LogKeepCount = [int]$script:Paths.LogKeepCount

# Archiver globals (cached to avoid repeated config reads)
$script:ArhiveExt    = Get-ArchiveExt $script:Config
$script:ArchiverType = Get-ArchiverType $script:Config
$script:ArchiverPath = Get-ArchiverPath $script:Config
$script:ArchiverHash = Get-ArchiverHash $script:Config

$PCName = $env:COMPUTERNAME

$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:JobName + "_" + $DateLog + ".log")

if (-not (Test-Path $script:LogPathRoot)) {
    New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null
}

# Log file is written in CP866 (OEM) for Windows console compatibility
$logHeader = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " -> LOG START PCNAME: " + $PCName
Add-Content -Path $script:GlobalLog -Value $logHeader -ErrorAction SilentlyContinue

Write-Host "[INFO] Log: $script:GlobalLog" -ForegroundColor Cyan
Write-Host "[INFO] Archiver: $script:ArchiverType ($script:ArchiverPath)" -ForegroundColor Cyan

# Archiver binary integrity check
if (-not (Test-FileIntegrity -FilePath $script:ArchiverPath -ExpectedHash $script:ArchiverHash -FileType $script:ArchiverPath)) {
    Write-Host "Archiver integrity check failed: $script:ArchiverPath" -ForegroundColor Red
    Write-Log "ERROR ArchiverHASH mismatch: $script:ArchiverPath"
    exit 1
}

if ($testmode) {
    Invoke-TestMode -Config $script:Config
    exit
}

# --- STAGE 2-4: Main Operation + Verification + Post-Ops (per job) ---

$totalErrors = 0
$jobResults = @{}

[array]$jobs = $script:Config.BackupConfig.Jobs.Job
if ($jobs.Count -eq 0 -or $jobs -eq $null) {
    Write-Host "[ERROR] No jobs found in config" -ForegroundColor Red
    Write-Log "ERROR: No jobs found in config"
    exit 1
}

foreach ($job in $jobs) {
    Write-Host "`n>>> Processing job: $($job.Name) <<<" -ForegroundColor Cyan
    $result = Invoke-Job $script:Config $job
    $jobErrors = $result.Errors
    $jobResults[$job.Name] = @{
        Errors = $jobErrors
        Log    = $result.Log
    }
    $totalErrors = $totalErrors + $jobErrors
    if ($jobErrors -eq 0) {
        Write-Host ">> [OK] $($job.Name) - errors: $jobErrors" -ForegroundColor Green
    }
    else {
        Write-Host ">> [FAIL] $($job.Name) - errors: $jobErrors" -ForegroundColor Red
    }
}

# --- STAGE 4: Post-Operations (log rotation, disk info) ---

$RemoveOldLogs = Remove-OldFiles `
    -Path $script:LogPathRoot `
    -DaysOld $script:LogDaysOld `
    -KeepCount $script:LogKeepCount `
    -Filter "*.*"
Write-Log $RemoveOldLogs

$DiskInfo = Get-DiskSpaceReport
Write-Log "DISK: $DiskInfo"

# --- STAGE 5: Reporting (console summary, email) ---

foreach ($jobName in $jobResults.Keys) {
    $result = $jobResults[$jobName]
    $errors = $result.Errors
    $jobLog = $result.Log
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Job: $jobName | Errors: $errors" -ForegroundColor $(if ($errors -eq 0) { "Green" } else { "Red" })
    Write-Host "========================================" -ForegroundColor Cyan
    foreach ($logLine in $jobLog) {
        Write-Host "  $logLine" -ForegroundColor $(if ($logLine -match "FAIL|ERROR") { "Red" } elseif ($logLine -match "OK|START") { "Green" } else { "Gray" })
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "[TOTAL] Jobs: $($jobResults.Count)" -ForegroundColor Cyan
Write-Host "[TOTAL] Errors: $totalErrors" -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

Write-Log "[TOTAL] JOBS: $($jobResults.Count)"
Write-Log "[TOTAL] ERRORS: $totalErrors"

$BodyMailLog = Get-Content $script:GlobalLog
$BodyMailLog = [string]::Join("`n", $BodyMailLog)

if ($totalErrors -eq 0) {
    $SubjectMail = "BACKUP SUCCESS $script:JobName $PCName $script:ArchiverType"
    $exitcode = 0
}
else {
    $SubjectMail = "BACKUP ERRORS: $totalErrors $script:JobName $PCName $script:ArchiverType"
    $exitcode = 1
}

Send-Email -Config $script:Config -Subject $SubjectMail -Body $BodyMailLog

exit $exitcode
