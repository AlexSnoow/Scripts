#Requires -Version 2.0
# =============================================================================
# backup-ps2-v5.ps1
# Универсальный backup-скрипт с поддержкой RAR и 7z
# Usage:
#   powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\backup-ps2-v5.ps1
#   powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\backup-ps2-v5.ps1 -testmode
# =============================================================================

param(
    [string]$ConfigPath = ".\Backup-Config.xml",
    [switch]$testmode
)

$XmlHash = ""

# ====================
# UTILS
# ====================

function Write-Log {
    param([string]$Message)
    if (-not $Message -or -not $script:GlobalLog) { return }
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " -> " + $Message
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
        [Parameter(Mandatory = $false)][bool]$UseSSL = $false,
        [Parameter(Mandatory = $false)][string]$Username,
        [Parameter(Mandatory = $false)][string]$Password,
        [Parameter(Mandatory = $false)][bool]$IsBodyHtml = $false
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
        Write-Host "[MAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        $msg = $null; $smtp = $null
    }
}

function Test-WritePermission {
    param([string]$Path)
    if (Test-Empty $Path) { return $false }
    try {
        $testFile = Join-Path $Path "._perm_test_$([System.Guid]::NewGuid().ToString().Substring(0,8))"
        $fs = [System.IO.File]::OpenWrite($testFile)
        $fs.Close()
        [System.IO.File]::Delete($testFile)
        return $true
    }
    catch {
        return $false
    }
}

# ====================
# TEST MODE
# ====================

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
            if (Test-WritePermission -Path $dest) {
                Write-Host "  [OK] Write permission: $dest" -ForegroundColor Green
            }
            else {
                Write-Host "  [FAIL] No write permission: $dest" -ForegroundColor Red
                $checkErrors++
            }
        }
        if ($job.RemoteDest -and -not (Test-Empty $job.RemoteDest)) {
            if (-not (Test-Path -LiteralPath $job.RemoteDest -PathType Container)) {
                try { New-Item -ItemType Directory -Path $job.RemoteDest -Force | Out-Null } catch { }
            }
            if (Test-Path -LiteralPath $job.RemoteDest -PathType Container) {
                if (Test-WritePermission -Path $job.RemoteDest) {
                    Write-Host "  [OK] Write permission remote: $($job.RemoteDest)" -ForegroundColor Green
                }
                else {
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
        $ExitCode = 0
    }
    else {
        $Status = "FAIL"
        $StatusText = "Errors found ($checkErrors)"
        $Color = "Red"
        $ExitCode = 1
    }
    Write-Host "  $StatusText" -ForegroundColor $Color
    $SubjectMail = "[$Status] $script:JobName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $BodyMail = "Job: $script:JobName`nPC: $env:COMPUTERNAME`nStatus: $StatusText`nErrors: $checkErrors`nTime: $(Get-Date)"
    Send-Email -Config $Config -Subject $SubjectMail -Body $BodyMail
    exit $ExitCode
}

# ====================
# SHA256 HASH
# ====================

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
                throw "File not found: $filePath"
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
            throw "Hash error '$filePath': $($_.Exception.Message)"
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
        [Parameter(Mandatory = $false)][string]$FileType = "File"
    )
    process {
        if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) {
            Write-Host "Invalid hash format for $FileType" -ForegroundColor Red
            Write-Error "Invalid hash for $FileType"
            return $false
        }
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            $msg = "Error: file not found: $FilePath"
            Write-Host $msg -ForegroundColor Red
            Write-Error $msg
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
            else {
                $errorMessage = @"
Integrity check FAILED!
File does not match expected hash!
Type: $FileType
File: $FilePath
Expected: $expectedHashUpper
Actual: $actualHash
"@
                Write-Host $errorMessage -ForegroundColor Red
                Write-Error $errorMessage
                return $false
            }
        }
        catch {
            $errorMsg = "Hash error for $FileType`: $($_.Exception.Message)"
            Write-Host $errorMsg -ForegroundColor Red
            Write-Error $errorMsg
            return $false
        }
    }
}

# ====================
# HELPERS
# ====================

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
    $r = $r -replace "{arhiveExt}", $script:ArhiveExt
    $r = $r -replace '[\\/:*?"<>|]', '_'
    $r = $r -replace '_+', '_'
    $r = $r.Trim()
    if ($r -notmatch ("\." + $script:ArhiveExt + "$")) {
        $r += "." + $script:ArhiveExt
    }
    return $r
}

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

# ====================
# ROTATION (PS 2.0 SAFE)
# ====================

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

# ====================
# DISK SPACE
# ====================

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

# ====================
# ARCHIVER ABSTRACTION
# ====================

function Get-ArchiverType {
    param($Config)
    $t = $Config.BackupConfig.General.ArchiverType
    if (Test-Empty $t) { return "RAR" }
    return $t
}

function Get-ArchiveExt {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return "7z" }
    return "rar"
}

function Get-ArchiverPath {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return $Config.BackupConfig.Paths.Path7z }
    return $Config.BackupConfig.Paths.RarPath
}

function Get-ArchiverHash {
    param($Config)
    $t = Get-ArchiverType $Config
    if ($t -eq "7z") { return $Config.BackupConfig.Paths.HASH7z }
    return $Config.BackupConfig.Paths.RarHASH
}

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

# ====================
# FAST IO
# ====================

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

# ====================
# PREPARE: ArchiveByDate
# ====================

function Prepare-ArchiveByDate {
    param($ctx)
    $files = Get-FilesFast $ctx.Source "*.*"
    $groups = @{}
    foreach ($f in $files) {
        if ($ctx.ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) { continue }
        # ExcludeFilePattern support
        if ($ctx.ExcludeFilePattern -and $f.Name -like $ctx.ExcludeFilePattern) { continue }
        $key = $f.LastWriteTime.ToString("yyyyMMdd")
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.ArrayList
        }
        [void]$groups[$key].Add($f.FullName)
    }
    return $groups
}

# ====================
# PREPARE: ArchiveIndividualFiles
# ====================

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

# ====================
# PREPARE: ArchiveIndividualFolders
# ====================

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

# ====================
# PREPARE: ArchiveAll
# ====================

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

# ====================
# ARCHIVE ENGINE
# ====================

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
        # If archive exists, add index suffix (_1, _2, ...)
        $baseName = $archiveName
        $basePath = $archivePath
        $idx = 0
        while (Test-Path -LiteralPath $archivePath) {
            $idx++
            $ext = [System.IO.Path]::GetExtension($basePath)
            $nameOnly = [System.IO.Path]::GetFileNameWithoutExtension($basePath)
            $archiveName = $nameOnly + "_$idx" + $ext
            $archivePath = Join-Path $ctx.Dest $archiveName
        }
        $listFile = [System.IO.Path]::ChangeExtension($archivePath, ".txt")
        $items | Out-File -Encoding ASCII $listFile
        $paramsStr = Get-ArchiverParams $ctx.Config $ctx.Job
        $argStr = "$paramsStr `"$archivePath`" @`"$listFile`""
        Write-Log ("START " + $archivePath)
        $startTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $jobLog += ("$startTime START " + $archivePath)
        $p = Start-Process -FilePath $ctx.ArchiverPath `
            -ArgumentList $argStr `
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
            Write-Host "  [OK] Archive created: $archiveName" -ForegroundColor Green
        }
        else {
            $checkErrors++
            Write-Host "  [FAIL] Archive error: $archiveName (CODE=$($p.ExitCode))" -ForegroundColor Red
        }
    }
    return $checkErrors
}

# ====================
# JOB RUNNER
# ====================

function Invoke-Job {
    param($Config, $Job)
    $checkErrors = 0
    $jobLog = @()
    $bc = $Config.BackupConfig
    $archiverType = Get-ArchiverType $Config
    $ctx = @{
        Config             = $Config
        Job                = $Job
        JobName            = $Job.Name
        Source             = $Job.Source
        Dest               = $Job.LocalDest
        LocalDestDaysOld   = [int]$Job.LocalDestDaysOld
        LocalDestKeepCount = [int]$Job.LocalDestKeepCount
        ArchiverType       = $archiverType
        ArchiverPath       = Get-ArchiverPath $Config
        ArchiverHash       = Get-ArchiverHash $Config
        PCName             = $PCName
        Pattern            = ""
        Log                = ""
        ExcludeToday       = To-Bool $Job.ExcludeToday
        ExcludeFilePattern = if ($Job.ExcludeFilePattern) { $Job.ExcludeFilePattern } else { $null }
        SourceFilter       = "*"
        ArchiveAll         = To-Bool $Job.ArchiveAll
        RemoteDest         = $Job.RemoteDest
    }
    if (-not (Test-Path $ctx.Source)) {
        $msg = "  [WARN] Source not found: $($ctx.Source)"
        Write-Host $msg -ForegroundColor Yellow
        $jobLog += ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $msg)
        $checkErrors++
        return @{ Errors = $checkErrors; Log = $jobLog }
    }
    if (-not (Test-Path $ctx.Dest)) {
        New-Item -ItemType Directory -Path $ctx.Dest | Out-Null
    }
    if ($ctx.RemoteDest -and -not (Test-Empty $ctx.RemoteDest) -and -not (Test-Path $ctx.RemoteDest)) {
        New-Item -ItemType Directory -Path $ctx.RemoteDest | Out-Null
    }
    if (-not (Test-Path $bc.Paths.LogPathRoot)) {
        New-Item -ItemType Directory -Path $bc.Paths.LogPathRoot | Out-Null
    }
    if ($Job.ArchivePattern) { $ctx.Pattern = $Job.ArchivePattern }
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

# ====================
# MAIN
# ====================

# Load config
if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

# Optional XML integrity check
if ($XmlHash) {
    if (-not (Test-FileIntegrity -FilePath $ConfigPath -ExpectedHash $XmlHash -FileType $ConfigPath)) {
        Write-Host "Config XML integrity check failed." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[WARN] XmlHash is empty, skipping XML integrity check" -ForegroundColor Yellow
}

[xml]$script:Config = Get-Content $ConfigPath

# === Globals from XML ===
$script:General = $script:Config.BackupConfig.General
$script:Paths = $script:Config.BackupConfig.Paths
$script:Recipients = $script:Config.BackupConfig.Recipients

$script:JobName = $script:General.ParentJobName
$script:Domain = $script:General.Domain
$script:SmtpServer = $script:General.SmtpServer
$script:LogPathRoot = $script:Paths.LogPathRoot
$script:LogDaysOld = [int]$script:Paths.LogDaysOld
$script:LogKeepCount = [int]$script:Paths.LogKeepCount

# Archiver-specific globals
$script:ArhiveExt = Get-ArchiveExt $script:Config
$script:ArchiverType = Get-ArchiverType $script:Config
$script:ArchiverPath = Get-ArchiverPath $script:Config
$script:ArchiverHash = Get-ArchiverHash $script:Config

$PCName = $env:COMPUTERNAME

# === Log setup ===
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$script:GlobalLog = Join-Path $script:LogPathRoot ("$PCName" + "_" + $script:JobName + "_" + $DateLog + ".log")

if (-not (Test-Path $script:LogPathRoot)) {
    New-Item -ItemType Directory -Path $script:LogPathRoot | Out-Null
}

Write-Log (" PCNAME: " + $PCName)
Write-Log (" ARCHIVER: " + $script:ArchiverType)

# === Archiver integrity check ===
if (-not (Test-FileIntegrity -FilePath $script:ArchiverPath -ExpectedHash $script:ArchiverHash -FileType $script:ArchiverPath)) {
    Write-Host "Archiver integrity check failed: $script:ArchiverPath" -ForegroundColor Red
    Write-Log (" ERROR ArchiverHASH: " + $script:ArchiverPath)
    exit 1
}

if ($testmode) {
    Invoke-TestMode -Config $script:Config
    exit
}

# === Run Jobs ===
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
    $jobLog = $result.Log
    $jobResults[$job.Name] = @{
        Errors = $jobErrors
        Log    = $jobLog
    }
    $totalErrors = $totalErrors + $jobErrors
    if ($jobErrors -eq 0) {
        Write-Host ">> [OK] $($job.Name) - errors: $jobErrors" -ForegroundColor Green
    }
    else {
        Write-Host ">> [FAIL] $($job.Name) - errors: $jobErrors" -ForegroundColor Red
    }
}

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

# POST operations
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
