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
    Add-Content -Path $Path -Value $line
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

function Copy-Remoute {
	
}
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

        Write-Log $ctx.Log ("START " + $archiveName)

        $p = Start-Process -FilePath $ctx.RarPath `
                           -ArgumentList $args `
                           -Wait `
                           -PassThru `
                           -NoNewWindow

        Write-Log $ctx.Log ("END " + $archiveName + " CODE=" + $p.ExitCode)
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
        RarPath    = $Config.Paths.RarPath
        PCName     = $env:COMPUTERNAME
        Pattern    = ""
        Log        = ""
        ExcludeToday = To-Bool $Job.ExcludeToday
        SourceFilter = "*"
		ArchiveAll = To-Bool $Job.ArchiveAll
    }

    if (-not (Test-Path $ctx.Source)) { return }
    if (-not (Test-Path $ctx.Dest)) {
        New-Item -ItemType Directory -Path $ctx.Dest | Out-Null
    }

    if (-not (Test-Path $Config.Paths.LogPathRoot)) {
        New-Item -ItemType Directory -Path $Config.Paths.LogPathRoot | Out-Null
    }

    $ctx.Log = Join-Path $Config.Paths.LogPathRoot ($ctx.JobName + ".log")

    if ($Job.ArchivePattern) { $ctx.Pattern = $Job.ArchivePattern }
    if ($Job.IndividualArchivePattern) { $ctx.Pattern = $Job.IndividualArchivePattern }
    if ($Job.SourceFilter) { $ctx.SourceFilter = $Job.SourceFilter }

    Write-Log $ctx.Log "JOB START"

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

    Write-Log $ctx.Log "JOB END"
}

# ------------------------
# MAIN
# ------------------------

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found"
    exit
}

[xml]$xml = Get-Content $ConfigPath

foreach ($job in $xml.BackupConfig.Jobs.Job) {
    Invoke-Job $xml.BackupConfig $job
}