#requires -version 2.0
param(
    [string]$ConfigPath = ".\Copy-Config.xml", 
    [switch]$TestMode
)

$XmlHash = "82D6A01903D634DD9E68602F7721EC88"
$script:GlobalLog = $null
$script:ReportsCsv = $null
$script:Crc32Table = $null

## Утилиты PS 2.0
function Test-Empty { param([string]$s); if ($s -eq $null -or $s.Trim() -eq "") { $true } else { $false } }

function Get-MD5Hash {
    param([string]$Path)
    if (Test-Empty $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $md5 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace('-','').ToUpper()
    } catch { return $null }
}

function Get-FileCrc32 {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath -PathType Leaf)) { return $null }
    
    # Таблица CRC32 один раз
    if (-not $script:Crc32Table) {
        $script:Crc32Table = New-Object UInt32[] 256
        for ($i = 0; $i -lt 256; $i++) {
            $crc = [UInt32]$i
            for ($j = 0; $j -lt 8; $j++) {
                if (($crc -band 1) -eq 1) { 
                    $crc = (($crc -shr 1) -bxor 0xEDB88320) 
                } else { 
                    $crc = $crc -shr 1 
                }
            }
            $script:Crc32Table[$i] = $crc
        }
    }
    
    $crc = 0xFFFFFFFF
    $buffer = New-Object byte[] 8192
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        while (($read = $stream.Read($buffer, 0, 8192)) -gt 0) {
            for ($n = 0; $n -lt $read; $n++) {
                $index = (($crc -bxor $buffer[$n]) -band 0xFF)
                $crc = (($script:Crc32Table[$index] -bxor ($crc -shr 8)) -band 0xFFFFFFFF)
            }
        }
    } finally { $stream.Close() }
    return (($crc -bxor 0xFFFFFFFF).ToString("X8"))
}

function Write-Type1Log { 
    param([string]$Message, [string]$JobName)
    if (Test-Empty $Message -or -not $script:GlobalLog) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts [$JobName] $Message" | Add-Content $script:GlobalLog -ErrorAction SilentlyContinue
}

function Write-Type2Log {
    param(
        [string]$JobName,
        [string]$JobStatus = "",
        [string]$FileName = "",
        [string]$Source = "",
        [string]$RemoteDest = "",
        [string]$RemoteDestStatus = "",
        [string]$Arhive = "",
        [string]$ArhiveStatus = "",
        [string]$Details
    )
    if (-not $script:ReportsCsv) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $csvLine = "`"$ts`";`"$JobName`";`"$JobStatus`";`"$FileName`";`"$Source`";`"$RemoteDest`";`"$RemoteDestStatus`";`"$Arhive`";`"$ArhiveStatus`";`"$Details`""
    Add-Content -Path $script:ReportsCsv -Value $csvLine -Encoding ASCII
}

function Send-EmailReport {
    param($Config, [string]$Subject, [string]$Body)
    try {
        $smtp = New-Object Net.Mail.SmtpClient($Config.CopyConfig.General.SmtpServer, 25)
        $msg = New-Object Net.Mail.MailMessage("$env:COMPUTERNAME@$($Config.CopyConfig.General.Domain)", $Config.CopyConfig.Recipients.AdminMail, $Subject, $Body)
        $smtp.Send($msg)
        return $true
    } catch { 
        return $false 
    }
}

function Test-WriteAccess {
    param([string]$Path)
    if (Test-Empty $Path) { return $false }
    try {
        $tf = Join-Path $Path "._t$([Guid]::NewGuid().Guid.Substring(0,8))"
        [System.IO.File]::WriteAllText($tf, "")
        Remove-Item $tf -Force -ErrorAction SilentlyContinue
        return $true
    } catch { 
        return $false 
    }
}

function Invoke-TestMode { 
    param($Config)
    Write-Host "[TEST MODE]" -ForegroundColor Cyan
    $errors = 0
    $logPath = $Config.CopyConfig.Paths.LogPathRoot
    
    if (-not (Test-Path $logPath) -or -not (Test-WriteAccess $logPath)) { 
        Write-Host "[FAIL] LogPathRoot" -ForegroundColor Red
        $errors++
    } else { 
        Write-Host "[OK] LogPathRoot" -ForegroundColor Green 
    }
    
    foreach ($job in $Config.CopyConfig.Jobs.Job) {
        Write-Host "Job $($job.Name):" -ForegroundColor Yellow
        if (-not (Test-Path $job.Source)) { 
            Write-Host "  [FAIL] Source" -ForegroundColor Red
            $errors++ 
        } elseif (-not (Test-WriteAccess $job.RemoteDest)) { 
            Write-Host "  [FAIL] RemoteDest" -ForegroundColor Red
        } else { 
            Write-Host "  [OK] Paths" -ForegroundColor Green 
        }
        $arcDir = Split-Path $job.Arhive -Parent
        if (-not (Test-WriteAccess $arcDir)) { 
            Write-Host "  [FAIL] Arhive" -ForegroundColor Red
        }
    }
    
    $sent = Send-EmailReport $Config "[TEST] $($Config.CopyConfig.General.ParentJobName)" "Test OK"
    $color = if($sent){"Green"}else{"Red"}
    Write-Host "[EMAIL $(if($sent){"OK"}else{"FAIL"})]" -ForegroundColor $color
    exit $errors
}

function Copy-FileVerified {
    param($SourceFile, [string]$RemoteDestPath, [string]$ArhivePath, [string]$JobName, [string]$SourcePath)
    $fileName = Split-Path $SourceFile -Leaf
    if (Test-Empty $fileName) { return $false }
    
    $destFile = Join-Path $RemoteDestPath $fileName
    $archiveFile = Join-Path $ArhivePath $fileName
    
    $srcHash = Get-FileCrc32 $SourceFile
    if (Test-Empty $srcHash) {
        Write-Type1Log "CRC32 FAIL: $fileName" $JobName
        Write-Type2Log $JobName "ERROR" $fileName $SourcePath $RemoteDestPath "ERROR" $ArhivePath "ERROR" "CRC32 fail"
        return $false
    }

    $remoteDestStatus = "ERROR"
    $archiveStatus = "ERROR"
    
    try {
        Copy-Item $SourceFile $destFile -Force -ErrorAction Stop
        $destHash = Get-FileCrc32 $destFile
        if ($srcHash -eq $destHash) { $remoteDestStatus = "SUCCESS" }

        if ($remoteDestStatus -eq "SUCCESS") {
            Move-Item $SourceFile $archiveFile -Force -ErrorAction Stop
            $archiveHash = Get-FileCrc32 $archiveFile
            if ($srcHash -eq $archiveHash) { $archiveStatus = "SUCCESS" }
        }
        
        $jobStatus = if(($remoteDestStatus -eq "SUCCESS") -and ($archiveStatus -eq "SUCCESS")){"SUCCESS"}else{"ERROR"}
        
        Write-Type1Log "$jobStatus`: $fileName CRC32=$srcHash" $JobName
        Write-Type2Log $JobName $jobStatus $fileName $SourcePath $RemoteDestPath $remoteDestStatus $ArhivePath $archiveStatus "CRC32=$srcHash"
        return ($jobStatus -eq "SUCCESS")
        
    } catch {
        if (Test-Path $destFile) { Remove-Item $destFile -Force -ErrorAction SilentlyContinue }
        Write-Type1Log "ERROR: $fileName $_" $JobName
        Write-Type2Log $JobName "ERROR" $fileName $SourcePath $RemoteDestPath "ERROR" $ArhivePath "ERROR" $_.Exception.Message
        return $false
    }
}

function Invoke-CopyJob {
    param($Job, $Config)
    $jobName = $Job.Name
    $success = 0
    $totalFiles = 0
    
    $today = Get-Date -Format "yyyyMMdd"
    $script:GlobalLog = Join-Path $Config.CopyConfig.Paths.LogPathRoot "$($Config.CopyConfig.General.ParentJobName)_$today_$((Get-Date).ToString('HHmm')).log"
    $script:ReportsCsv = Join-Path $Config.CopyConfig.Paths.LogPathRoot "reports_$today.csv"
    
    if (-not (Test-Path $script:ReportsCsv)) {
        "Time;JobName;JobStatus;FileName;Source;RemoteDest;RemoteDestStatus;Arhive;ArhiveStatus;Details" | Out-File $script:ReportsCsv -Encoding ASCII
    }
    
    Write-Type1Log "JOB START" $jobName
    Write-Type2Log $JobName "INFO" "" $Job.Source $Job.RemoteDest "INFO" $Job.Arhive "INFO" "Job started"
    
    if (-not (Test-Path $Job.Source)) {
        Write-Type1Log "SOURCE MISSING" $jobName
        Write-Type2Log $JobName "ERROR" "" $Job.Source $Job.RemoteDest "ERROR" $Job.Arhive "ERROR" "Source missing"
        return @{Success=0; Total=0; HasErrors=$true}
    }
    
    $files = Get-ChildItem $Job.Source | Where-Object { if ($_.PSIsContainer) { $false } else { $true } }
    $totalFiles = $files.Count
    
    if ($totalFiles -eq 0) {
        Write-Type1Log "NO FILES" $jobName
        Write-Type2Log $JobName "INFO" "" $Job.Source $Job.RemoteDest "INFO" $Job.Arhive "INFO" "No files in $($Job.Source)"
        return @{Success=0; Total=0; HasErrors=$false}
    }
    
    foreach ($file in $files) {
        if (Copy-FileVerified $file.FullName $Job.RemoteDest $Job.Arhive $jobName $Job.Source) {
            $success++
        }
    }
    
    $hasErrors = ($totalFiles - $success) -gt 0
    $jobResult = if($hasErrors){"ERROR:$($totalFiles-$success)F/$totalFiles"}else{"SUCCESS:$success/$totalFiles"}
    Write-Type1Log "JOB END: $success/$totalFiles" $jobName
    Write-Type2Log $JobName $jobResult "" $Job.Source $Job.RemoteDest "END" $Job.Arhive "END" "$success success / $($totalFiles-$success) fails"
    
    return @{Success=$success; Total=$totalFiles; HasErrors=$hasErrors}
}

function Send-DailyReport { 
    param($JobResults, $Config)
    $h = (Get-Date).Hour
    $m = (Get-Date).Minute
    if ($h -lt 16 -or ($h -eq 16 -and $m -lt 30) -or $h -ge 18) { return }
    
    $totalOK = ($JobResults | ForEach-Object { $_.Success } | Measure-Object -Sum).Sum
    $totalProcessed = ($JobResults | ForEach-Object { $_.Total } | Measure-Object -Sum).Sum
    $logTxt = if (Test-Path $script:GlobalLog) { 
        (Get-Content $script:GlobalLog | Out-String).Substring(0,4000) 
    } else { 
        "No log" 
    }
    
    $body = @"
Daily $($Config.CopyConfig.General.ParentJobName) $(Get-Date -Format 'yyyy-MM-dd HH:mm')
SUCCESS: $totalOK/$totalProcessed
CSV: $script:ReportsCsv
LOG: $logTxt
"@
    Send-EmailReport $Config "[DAILY] $totalOK/$totalProcessed" $body | Out-Null
}

## MAIN
if (-not (Test-Path $ConfigPath)) { 
    Write-Host "NO CONFIG" -ForegroundColor Red
    exit 1 
}
$configHash = Get-MD5Hash $ConfigPath
if ($configHash -ne $XmlHash) { 
    Write-Host "HASH FAIL! $configHash ? $XmlHash" -ForegroundColor Red
    exit 1 
}

[xml]$Config = Get-Content $ConfigPath
if ($TestMode) { 
    Invoke-TestMode $Config
    exit 
}

$logRoot = $Config.CopyConfig.Paths.LogPathRoot
if (-not (Test-Path $logRoot)) { 
    New-Item $logRoot -ItemType Directory -Force | Out-Null 
}

$results = @()
foreach ($job in $Config.CopyConfig.Jobs.Job) {
    $result = Invoke-CopyJob $job $Config
    $results += $result
    if ($result.HasErrors) {
        Send-EmailReport $Config "[ERROR] $($job.Name)" "Fails: $($result.Total-$result.Success)`nCSV: $script:ReportsCsv" | Out-Null
    }
}

Send-DailyReport $results $Config

# Ротация логов
$logs = Get-ChildItem $logRoot "*.log" | Sort-Object LastWriteTime -Descending
$keep = [int]$Config.CopyConfig.Paths.LogKeepCount
if ($logs.Count -gt $keep) { 
    $logs | Select-Object -Skip ($keep-1) | Remove-Item -Force -ErrorAction SilentlyContinue 
}

$hasErrors = ($results | Where-Object { $_.HasErrors }).Count -gt 0
exit $(if($hasErrors){1}else{0})