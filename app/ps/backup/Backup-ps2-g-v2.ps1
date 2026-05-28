param(
    [string]$ConfigPath = "C:\Work\BackupAllXml\Backup-Config.xml"
)

# ------------------------
# UTILS
# ------------------------

function Test-Empty {
    param([string]$s)
    return ($s -eq $null -or $s.Trim().Length -eq 0)
}

function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}

function Write-Log {
    param($Path, $Message)

    if (Test-Empty $Path) { return }

    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message
    Add-Content -Path $GlobalLog -Value $line
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

    Write-Log $GlobalLog ("COPY REMOTE: " + $destPath)
}

# ==============================================================================
#region ÐÎÒÀÖÈß ÔÀÉËÎÂ (PS 2.0 SAFE)
# ==============================================================================

function Remove-OldFiles {
    param(
        [string]$Path,
        [int]$DaysOld,
        [int]$KeepCount,
        [string]$Filter
    )

    if (Test-Empty $Path) { return }

    Write-Log $Path ("Rotation: " + $Path + " DaysOld=" + $DaysOld + " Keep=" + $KeepCount + " Filter=" + $Filter)

    if (-not (Test-Path $Path)) {
        Write-Log $Path ("The directory does not exist: " + $Path)
        return
    }

    try {
        # cutoff date
        $cutoffDate = (Get-Date)
        if ($DaysOld -gt 0) {
            $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        }
        else {
            $cutoffDate = [DateTime]::MaxValue
        }

        # get files
        $allFiles = Get-ChildItem -Path $Path -Filter $Filter |
                    Where-Object { $_ -ne $null -and -not $_.PSIsContainer } |
                    Sort-Object LastWriteTime -Descending

        if ($allFiles -eq $null -or $allFiles.Count -eq 0) {
            Write-Log $Path "There are no files to process"
            return
        }

        Write-Log $Path ("Files found: " + $allFiles.Count)

        # keep list
        $filesToKeep = @()
        if ($KeepCount -gt 0) {
            $filesToKeep = $allFiles | Select-Object -First $KeepCount
        }

        # delete list
        $filesToDelete = @()

        foreach ($f in $allFiles) {

            $keep = $false

            if ($filesToKeep -ne $null) {
                foreach ($k in $filesToKeep) {
                    if ($k -ne $null -and $k.FullName -eq $f.FullName) {
                        $keep = $true
                        break
                    }
                }
            }

            if (-not $keep -and $f.LastWriteTime -lt $cutoffDate) {
                $filesToDelete += $f
            }
        }

        # delete
        if ($filesToDelete.Count -gt 0) {

            Write-Log $Path ("Files to delete: " + $filesToDelete.Count)

            foreach ($file in $filesToDelete) {

                try {
                    Remove-Item $file.FullName -Force
                    Write-Log $Path ("Removed: " + $file.Name)
                }
                catch {
                    Write-Log $Path ("Error deleting: " + $file.FullName + " " + $_)
                }
            }
        }
        else {
            Write-Log $Path "There are no files to delete."
        }

        Write-Log $Path ("Rotation is complete. Total: " + $allFiles.Count)
    }
    catch {
        Write-Log $Path ("Rotation error: " + $_)
    }
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
    } else {
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

    $files = Get-FilesFast $ctx.Source "*"
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

        $key = $f.Name  # ÂÀÆÍÎ: ïîëíûé óíèêàëüíûé êëþ÷

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

        Write-Log $GlobalLog ("START " + $archivePath)

        $p = Start-Process -FilePath $ctx.RarPath `
                           -ArgumentList $args `
                           -Wait `
                           -PassThru `
                           -NoNewWindow

        Write-Log $GlobalLog ("END " + $archivePath + " CODE=" + $p.ExitCode)
		if ($p.ExitCode -eq 0) {
			Copy-Remote $ctx $archivePath
		}
    }
}

# ------------------------
# JOB RUNNER
# ------------------------
function Invoke-Job {
    param($Config, $Job)

    $ctx = @{
        Config     = $Config
        Job        = $Job
        JobName    = $Job.Name
        Source     = $Job.Source
        Dest       = $Job.LocalDest
		LocalDestDaysOld = [int]$Job.LocalDestDaysOld
		LocalDestKeepCount = [int]$Job.LocalDestKeepCount
        RarPath    = $Config.Paths.RarPath
        PCName     = $env:COMPUTERNAME
        Pattern    = ""
        Log        = ""
        ExcludeToday = To-Bool $Job.ExcludeToday
        SourceFilter = "*"
		ArchiveAll = To-Bool $Job.ArchiveAll
		RemoteDest = $Job.RemoteDest
    }

    if (-not (Test-Path $ctx.Source)) { return }
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

    Write-Log $GlobalLog "JOB START"

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

    Invoke-Archiving $ctx $groups
	
    Remove-OldFiles `
        -Path $ctx.Dest `
        -DaysOld $ctx.LocalDestDaysOld `
        -KeepCount $ctx.LocalDestKeepCount `
        -Filter "*.*"

    Write-Log $GlobalLog "JOB END"
}

# ------------------------
# MAIN
# ------------------------

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found"
    exit
}

[xml]$xml = Get-Content $ConfigPath
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")

$GlobalLog = Join-Path $xml.BackupConfig.Paths.LogPathRoot ($env:COMPUTERNAME + "_" + $xml.BackupConfig.General.JobName + "_" + $DateLog + ".log")

foreach ($job in $xml.BackupConfig.Jobs.Job) {
    Invoke-Job $xml.BackupConfig $job
}

# ------------------------
# Post
# ------------------------

$DiskInfo = Get-DiskSpaceReport

Write-Log $GlobalLog $DiskInfo