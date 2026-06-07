#Requires -Version 2.0

# Test-7zFunctions.ps1
# Sandbox test for 7z archiver using Backup-Config.xml data
# Usage: powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\Test-7zFunctions.ps1

param(
    [string]$ConfigPath = "..\backup\Backup-Config.xml"
)

$ArhiveExt = "7z"
$PCName = $env:COMPUTERNAME

# Test tracking
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0
$script:TestLog = @()

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

function Test-Empty {
    param([string]$s)
    return ($s -eq $null -or $s.Trim().Length -eq 0)
}

function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}

# ============================================================
# 7Z FUNCTIONS (v5 candidates)
# ============================================================

function Get-7zParams {
    param($Config, $Job)
    $params = @()
    if ($Job.ArhParameters) {
        foreach ($p in $Job.ArhParameters.Param) {
            $params += $p
        }
    }
    else {
        foreach ($p in $Config.BackupConfig.General.Default7zParameters.Param) {
            $params += $p
        }
    }
    return ($params -join " ")
}

function Resolve-Name {
    param($Pattern, $PC, $JobName, $Date, $Name)
    if (Test-Empty $Pattern) { return $null }
    $r = $Pattern
    $r = $r -replace "{PCName}", $PC
    $r = $r -replace "{JobName}", $JobName
    $r = $r -replace "{LastWriteTime}", $Date
    $r = $r -replace "{Date}", $Date
    $r = $r -replace "{SourceFileName}", $Name
    $r = $r -replace "{SourceFolderName}", $Name
    $r = $r -replace "{arhiveExt}", $ArhiveExt
    $r = $r -replace '[\\/:*?"<>|]', '_'
    $r = $r -replace '_+', '_'
    $r = $r.Trim()
    if ($r -notmatch ("\." + $ArhiveExt + "$")) {
        $r += "." + $ArhiveExt
    }
    return $r
}

# ============================================================
# FILE IO FUNCTIONS
# ============================================================

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

# ============================================================
# PREPARE FUNCTIONS (adapted from v4 for 7z)
# ============================================================

function Prepare-ArchiveByDate {
    param($Source, $ExcludeToday)
    $files = Get-FilesFast $Source "*.*"
    $groups = @{}
    foreach ($f in $files) {
        if ($ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) { continue }
        $key = $f.LastWriteTime.ToString("yyyyMMdd")
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.ArrayList
        }
        [void]$groups[$key].Add($f.FullName)
    }
    return $groups
}

function Prepare-IndividualFiles {
    param($Source, $SourceFilter, $ExcludeToday)
    $files = Get-FilesFast $Source $SourceFilter
    $groups = @{}
    foreach ($f in $files) {
        if ($ExcludeToday -and $f.LastWriteTime.Date -eq (Get-Date).Date) { continue }
        $key = $f.Name
        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($f.FullName)
    }
    return $groups
}

function Prepare-IndividualFolders {
    param($Source, $ExcludeToday)
    $dirs = Get-FoldersFast $Source
    $groups = @{}
    $today = (Get-Date).ToString("yyyyMMdd")
    foreach ($d in $dirs) {
        if ($ExcludeToday -and $d.Name -eq $today) { continue }
        $key = $d.Name
        $groups[$key] = New-Object System.Collections.ArrayList
        [void]$groups[$key].Add($d.FullName)
    }
    return $groups
}

function Prepare-ArchiveAll {
    param($Source)
    $groups = @{}
    $key = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $list = New-Object System.Collections.ArrayList
    if (Test-Path $Source) {
        $dir = New-Object System.IO.DirectoryInfo($Source)
        foreach ($f in $dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) {
            [void]$list.Add($f.FullName)
        }
    }
    $groups[$key] = $list
    return $groups
}

# ============================================================
# HASH VALIDATION
# ============================================================

function Test-FileHash {
    param($FilePath, $ExpectedHash)
    if (-not (Test-Path $FilePath -PathType Leaf)) {
        return "NOT_FOUND"
    }
    try {
        $algo = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($FilePath)
        $hashBytes = $algo.ComputeHash($fs)
        $fs.Close()
        $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToUpper()
        if ($hashString -eq $ExpectedHash.ToUpper()) { return "MATCH" }
        else { return "MISMATCH:$hashString" }
    }
    catch {
        return "ERROR:$($_.Exception.Message)"
    }
}

# ============================================================
# TEST RUNNER
# ============================================================

function Run-Test {
    param($JobName, $TestName)
    $script:TotalTests++
    Write-Host "  [$script:TotalTests] $TestName..." -ForegroundColor "Gray"
}

function Pass-Test {
    param($Message)
    $script:PassedTests++
    Write-Host "    [PASS] $Message" -ForegroundColor "Green"
}

function Fail-Test {
    param($Message)
    $script:FailedTests++
    Write-Host "    [FAIL] $Message" -ForegroundColor "Red"
}

# ============================================================
# MAIN
# ============================================================

Write-Host "========================================" -ForegroundColor "Cyan"
Write-Host "  SANDBOX: Test 7z Functions" -ForegroundColor "Cyan"
Write-Host "========================================" -ForegroundColor "Cyan"

# ---- Load config ----
Run-Test "CONFIG" "Load XML config"
if (-not (Test-Path $ConfigPath)) {
    Fail-Test "Config not found: $ConfigPath"
    exit 1
}
[xml]$Config = Get-Content $ConfigPath
$ArchiverType = $Config.BackupConfig.General.ArchiverType
$Path7z = $Config.BackupConfig.Paths.Path7z
$Hash7z = $Config.BackupConfig.Paths.HASH7z
$ParentJobName = $Config.BackupConfig.General.ParentJobName
$Default7zParamsStr = Get-7zParams $Config $null
Pass-Test "Config loaded: ArchiverType=$ArchiverType JobName=$ParentJobName"

# ---- Display config ----
Write-Host "`n--- Config ---" -ForegroundColor "Cyan"
Write-Host "  ArchiverType : $ArchiverType" -ForegroundColor "Gray"
Write-Host "  Path7z       : $Path7z" -ForegroundColor "Gray"
Write-Host "  Hash7z       : $Hash7z" -ForegroundColor "Gray"
Write-Host "  Default Params: $Default7zParamsStr" -ForegroundColor "Gray"

# ---- Test 7z.exe hash ----
if ($ArchiverType -eq "7z") {
    Run-Test "CONFIG" "Validate 7z.exe SHA256"
    $hashResult = Test-FileHash $Path7z $Hash7z
    if ($hashResult -eq "MATCH") {
        Pass-Test "7z.exe hash matches config"
    }
    elseif ($hashResult -eq "NOT_FOUND") {
        Fail-Test "7z.exe not found: $Path7z"
    }
    else {
        Fail-Test "7z.exe hash mismatch: $hashResult"
    }
}

# ---- Test Get-7zParams with per-job override (JOB6) ----
Run-Test "CONFIG" "Get-7zParams override via ArhParameters"
$job6 = $null
foreach ($j in $Config.BackupConfig.Jobs.Job) {
    if ($j.Name -eq "JOB6") { $job6 = $j; break }
}
if ($job6 -ne $null) {
    $job6Params = Get-7zParams $Config $job6
    if ($job6Params -match "-sdel") {
        Pass-Test "JOB6 ArhParameters override contains -sdel: $job6Params"
    }
    else {
        Fail-Test "JOB6 ArhParameters should contain -sdel, got: $job6Params"
    }
}

# ---- Test Resolve-Name ----
Run-Test "CONFIG" "Resolve-Name with .7z extension"
$testName = Resolve-Name "{PCName}_{JobName}_{Date}.{arhiveExt}" $PCName "TESTJOB" "20250601" "testfile"
if ($testName -match "\.7z$") {
    Pass-Test "Resolve-Name returns .7z: $testName"
}
else {
    Fail-Test "Resolve-Name should return .7z, got: $testName"
}

# ---- Process each Job ----
Write-Host "`n========================================" -ForegroundColor "Cyan"
Write-Host "  PROCESSING JOBS" -ForegroundColor "Cyan"
Write-Host "========================================" -ForegroundColor "Cyan"

[array]$jobs = $Config.BackupConfig.Jobs.Job

foreach ($job in $jobs) {
    Write-Host "`n=== JOB: $($job.Name) ===" -ForegroundColor "Cyan"

    $Source = $job.Source
    $LocalDest = $job.LocalDest
    $RemoteDest = $job.RemoteDest
    $ExcludeToday = To-Bool $job.ExcludeToday
    $ErrorLog = To-Bool $job.ArhErrorLog
    $Pattern = if ($job.ArchivePattern) { $job.ArchivePattern } else { "{PCName}_{JobName}_{Date}.{arhiveExt}" }
    $SourceFilter = if ($job.SourceFilter) { $job.SourceFilter } else { "*.*" }

    $isArchiveAll = To-Bool $job.ArchiveAll
    $isArchiveByDate = To-Bool $job.ArchiveByDate
    $isIndividualFiles = To-Bool $job.ArchiveIndividualFiles
    $isIndividualFolders = To-Bool $job.ArchiveIndividualFolders

    # ---- Source exists ----
    Run-Test $job.Name "Source directory exists"
    if (Test-Path $Source -PathType Container) {
        Pass-Test "Source: $Source"
    }
    else {
        Fail-Test "Source not found: $Source"
        continue
    }

    # ---- Determine type ----
    $typeLabel = ""
    if ($isArchiveAll) { $typeLabel = "ArchiveAll" }
    elseif ($isArchiveByDate) { $typeLabel = "ArchiveByDate" }
    elseif ($isIndividualFiles) { $typeLabel = "ArchiveIndividualFiles" }
    elseif ($isIndividualFolders) { $typeLabel = "ArchiveIndividualFolders" }
    Write-Host "  Type: $typeLabel" -ForegroundColor "Yellow"

    $jobParams = Get-7zParams $Config $job
    Write-Host "  7z Params: $jobParams" -ForegroundColor "Gray"

    # ---- Ensure output dir ----
    if (-not (Test-Path $LocalDest -PathType Container)) {
        New-Item -ItemType Directory -Path $LocalDest -Force | Out-Null
        Write-Host "  Created: $LocalDest" -ForegroundColor "Yellow"
    }

    # ---- Prepare file groups ----
    $groups = @{}
    if ($isArchiveAll) {
        $groups = Prepare-ArchiveAll $Source
    }
    elseif ($isArchiveByDate) {
        $groups = Prepare-ArchiveByDate $Source $ExcludeToday
    }
    elseif ($isIndividualFiles) {
        $groups = Prepare-IndividualFiles $Source $SourceFilter $ExcludeToday
    }
    elseif ($isIndividualFolders) {
        $groups = Prepare-IndividualFolders $Source $ExcludeToday
    }

    if ($groups.Count -eq 0) {
        Write-Host "  No files/folders to archive" -ForegroundColor "Yellow"
        Run-Test $job.Name "No groups to process (skipped)"
        Pass-Test "Skipped (no data)"
        continue
    }

    Write-Host "  Groups to process: $($groups.Count)" -ForegroundColor "Gray"

    # ---- Process each group ----
    $jobErrors = 0
    $jobGroupsProcessed = 0

    foreach ($key in $groups.Keys) {
        [array]$items = $groups[$key]
        if ($items.Count -eq 0) { continue }

        $jobGroupsProcessed++
        $archiveName = Resolve-Name $Pattern $PCName $job.Name $key $key
        if (Test-Empty $archiveName) {
            Write-Host "  [SKIP] Empty archive name for key: $key" -ForegroundColor "Yellow"
            continue
        }

        $archivePath = Join-Path $LocalDest $archiveName
        $listFile = [System.IO.Path]::ChangeExtension($archivePath, ".txt")

        # Write list file
        $items | Out-File -Encoding ASCII $listFile

        # Build command string
        $argStr = "$jobParams `"$archivePath`" @`"$listFile`""
        $cmdStr = "`"$Path7z`" $argStr"

        Write-Host "  -- Archive: $archiveName" -ForegroundColor "White"
        Write-Host "     Files: $($items.Count)" -ForegroundColor "Gray"
        Write-Host "     List:  $listFile" -ForegroundColor "Gray"

        Run-Test $job.Name "7z: $archiveName"
        Write-Host "     Cmd: $cmdStr" -ForegroundColor "DarkGray"

        # Execute 7z
        $startTime = Get-Date
        $p = Start-Process -FilePath $Path7z -ArgumentList $argStr -Wait -PassThru -NoNewWindow
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

        if ($p.ExitCode -eq 0) {
            if (Test-Path $archivePath -PathType Leaf) {
                $size = (Get-Item $archivePath).Length
                Pass-Test "ExitCode=0 Size=$($size)B Time=${elapsed}s"
            }
            else {
                Pass-Test "ExitCode=0 (archive not found? $archivePath)"
            }
        }
        else {
            $jobErrors++
            Fail-Test "ExitCode=$($p.ExitCode) Time=${elapsed}s"
        }

        # ---- Error log support ----
        if ($ErrorLog -and $p.ExitCode -ne 0) {
            $errorLogFile = [System.IO.Path]::ChangeExtension($archivePath, "_error.log")
            $hashResult = Test-FileHash $errorLogFile $null
            Write-Host "     Error log requested, run with -ilog to capture" -ForegroundColor "DarkGray"
        }
    }

    # ---- Summary for this job ----
    if ($jobErrors -eq 0) {
        Write-Host "  >>> JOB $($job.Name): $jobGroupsProcessed group(s), 0 errors" -ForegroundColor "Green"
    }
    else {
        Write-Host "  >>> JOB $($job.Name): $jobGroupsProcessed group(s), $jobErrors errors" -ForegroundColor "Red"
    }
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n========================================" -ForegroundColor "Cyan"
Write-Host "  SUMMARY" -ForegroundColor "Cyan"
Write-Host "========================================" -ForegroundColor "Cyan"
Write-Host "  Total: $script:TotalTests" -ForegroundColor "Gray"
Write-Host "  Passed: $script:PassedTests" -ForegroundColor "Green"
Write-Host "  Failed: $script:FailedTests" -ForegroundColor $(if ($script:FailedTests -gt 0) { "Red" } else { "Green" })
Write-Host "========================================" -ForegroundColor "Cyan"

if ($script:FailedTests -gt 0) {
    Write-Host "  Some tests FAILED" -ForegroundColor "Red"
    exit 1
}
else {
    Write-Host "  ALL TESTS PASSED" -ForegroundColor "Green"
    exit 0
}
