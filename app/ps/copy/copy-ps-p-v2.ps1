#requires -version 2.0
<#
.SYNOPSIS
    Copy-Job - Копирование файлов с верификацией (PS 2.0).
.DESCRIPTION
    Копирование Source?RemoteDest с MD5. Успех?Arhive. CSV-лог + email.
.PARAMETER ConfigPath
    Путь к XML (по умолчанию .\Copy-Config.xml).
.PARAMETER TestMode
    Тест путей+прав+email.
.EXAMPLE
    powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\copy-ps-p-v2.ps1 -TestMode
#>

param([string]$ConfigPath = ".\Copy-Config.xml", [switch]$TestMode)

# ?? НОВЫЙ ХЕШ ВАШЕГО XML (замените после расчета!)
$XmlHash = "82D6A01903D634DD9E68602F7721EC88" 
$script:GlobalLog = $null
$script:ReportsCsv = $null

## Утилиты PS 2.0
function Test-Empty { param([string]$s); if ($s -eq $null -or $s.Trim() -eq "") { $true } else { $false } }
function Get-MD5Hash {
    param([string]$Path)
    if (Test-Empty $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $md5 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace('-','').ToUpper()
        return $hash
    } catch { return $null }
}

function Get-CRC32Hash {
    param([string]$Path)
    if (Test-Empty $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $crc32 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace('-','').ToUpper()
        return $hash
    } catch { return $null }
}

#функция вычисления CRC32 файла если это будет быстрее на более 1000 файлах
#пример кода для вычисления CRC32
# $crc32 = add-type '
# [DllImport("ntdll.dll")]
# public static extern uint RtlComputeCrc32(uint dwInitial, byte[] pData, int iLen);
# ' -Name crc32 -PassThru

# $str = "123456789"
# $arr = [System.Text.Encoding]::UTF8.GetBytes($str)
# $crc = $crc32::RtlComputeCrc32(0, $arr, $arr.Count)
# $crc.ToString("X8")


function Get-FileCrc32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    process {
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "Файл не найден: $FilePath"
        }
        
        # Таблица CRC32 (полином 0xEDB88320)
        if (-not $script:Crc32Table) {
            $script:Crc32Table = New-Object UInt32[] 256
            for ($i = 0; $i -lt 256; $i++) {
                $crc = [UInt32]$i
                for ($j = 0; $j -lt 8; $j++) {
                    if (($crc -band 1) -eq 1) {
                        $crc = ($crc -shr 1) -bxor 0xEDB88320
                    }
                    else {
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
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                for ($n = 0; $n -lt $read; $n++) {
                    $byte = $buffer[$n]
                    $index = ($crc -bxor $byte) -band 0xFF
                    $crc = ($script:Crc32Table[$index] -bxor ($crc -shr 8)) -band 0xFFFFFFFF
                }
            }
        }
        finally {
            $stream.Close()
        }
        
        return ($crc -bxor 0xFFFFFFFF).ToString("X8")
    }
}

function Write-Type1Log { param([string]$Message, [string]$JobName)
    if (Test-Empty $Message -or -not $script:GlobalLog) { return }
    $ts = Get-Date -f "yyyy-MM-dd HH:mm:ss"
    "$ts [$JobName] $Message" | Add-Content $script:GlobalLog -ErrorAction SilentlyContinue
}

function Write-Type2Log {
    param(
        [string]$JobName,
        [string]$JobStatus = "",        # SUCCESS/ERROR/INFO где SUCCESS значит что RemoteDestStatus=SUCCESS и ArhiveStatus=SUCCESS ; ERROR где то ошибки RemoteDestStatus или ArhiveStatus ; INFO в Source нет файлов для копирования
        [string]$FileName = "",         # Имя файла или ""
        [string]$Source = "",           # Имя в каталога из XML
        [string]$RemoteDest = "",       # Имя в каталога из XML
        [string]$RemoteDestStatus = "", # SUCCESS/ERROR/INFO
        [string]$Arhive = "",           # Имя в каталога из XML
        [string]$ArhiveStatus = "",     # SUCCESS/ERROR/INFO
        [string]$Details
    )
    if (-not $script:ReportsCsv) { return }
    
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $csvLine = "`"$ts`";`"$JobName`";`"$JobStatus`";`"$SourceFileName`";`"$DestFileName`";`"$ArchiveFileName`";`"$Status`";`"$Details`""
    Add-Content -Path $script:ReportsCsv -Value $csvLine -Encoding ASCII
}

function Send-EmailReport {
    param($Config, [string]$Subject, [string]$Body)
    try {
        $smtp = New-Object Net.Mail.SmtpClient($Config.CopyConfig.General.SmtpServer, 25)
        $msg = New-Object Net.Mail.MailMessage(
            "$env:COMPUTERNAME@$($Config.CopyConfig.General.Domain)",
            $Config.CopyConfig.Recipients.AdminMail, $Subject, $Body
        )
        $smtp.Send($msg); return $true
    } catch { return $false }
}

function Test-WriteAccess {
    param([string]$Path)
    if (Test-Empty $Path) { return $false }
    try {
        $tf = Join-Path $Path "._t$([Guid]::NewGuid().Guid.SubString(0,8))"
        [IO.File]::WriteAllText($tf, ""); Remove-Item $tf -Force -ea SilentlyContinue
        return $true
    } catch { return $false }
}

## Тест-режим
function Invoke-TestMode { param($Config)
    Write-Host "[TEST MODE]" -f Cyan; $errors = 0; $logPath = $Config.CopyConfig.Paths.LogPathRoot
    if (-not (Test-Path $logPath) -or -not (Test-WriteAccess $logPath)) {
        Write-Host "[FAIL] LogPathRoot" -f Red; $errors++
    } else { Write-Host "[OK] LogPathRoot" -f Green }

    foreach ($job in $Config.CopyConfig.Jobs.Job) {
        Write-Host "Job $($job.Name):" -f Yellow
        if (-not (Test-Path $job.Source)) { Write-Host "  [FAIL] Source" -f Red; $errors++ }
        elseif (-not (Test-WriteAccess $job.RemoteDest)) { Write-Host "  [FAIL] RemoteDest" -f Red; $errors++ }
        else { Write-Host "  [OK] Paths" -f Green }
        $arcDir = Split-Path $job.Arhive -Parent
        if (-not (Test-WriteAccess $arcDir)) { Write-Host "  [FAIL] Arhive" -f Red; $errors++ }
    }

    $sent = Send-EmailReport $Config "[TEST] $($Config.CopyConfig.General.ParentJobName)" "Test OK"
    Write-Host "[EMAIL $(if($sent){'OK'}else{'FAIL'})]" -f $(if($sent){'Green'}else{'Red'})
    exit $errors
}

## Копирование с MD5
function Copy-FileVerified {
    param($SourceFile, [string]$RemoteDest, [string]$Arhive, [string]$JobName)
    
    $fileName = Split-Path $SourceFile -Leaf
    if (Test-Empty $fileName) { return $false }
    
    $destFile = Join-Path $RemoteDest $fileName
    $archiveFile = Join-Path $Arhive $fileName
    $srcHash = Get-MD5Hash $SourceFile
    
    if (Test-Empty $srcHash) {
        Write-Type1Log "MD5 FAIL: $fileName" $JobName
        Write-Type2Log $JobName "" "" "" "" "MD5_FAIL" "Cannot compute MD5: $fileName"
        return $false
    }

    try {
        Copy-Item $SourceFile $destFile -Force -ErrorAction Stop
        $destHash = Get-MD5Hash $destFile
        
        if ($srcHash -eq $destHash) {
            Move-Item $SourceFile $archiveFile -Force -ErrorAction Stop
            Write-Type1Log "SUCCESS: $fileName MD5=$srcHash" $JobName
            Write-Type2Log $JobName "" $fileName $fileName $fileName "SUCCESS" "MD5=$srcHash"
            return $true
        } else {
            Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            Write-Type1Log "MISMATCH: $fileName (src:$srcHash?dest:$destHash)" $JobName
            Write-Type2Log $JobName "" $fileName $fileName "" "MISMATCH" "src:$srcHash dest:$destHash"
            return $false
        }
    }
    catch {
        Write-Type1Log "COPY ERROR: $fileName $_" $JobName
        Write-Type2Log $JobName "" $fileName $fileName "" "ERROR" $_.Exception.Message
        return $false
    }
}

## Выполнение задания
function Invoke-CopyJob {
    param($Job, $Config)
    $jobName = $Job.Name
    $success = 0
    $fails = @()
    
    # Логи за день
    $today = Get-Date -Format "yyyyMMdd"
    $script:GlobalLog = Join-Path $Config.CopyConfig.Paths.LogPathRoot "$($Config.CopyConfig.General.ParentJobName)_$today_$((Get-Date).ToString('HHmm')).log"
    $script:ReportsCsv = Join-Path $Config.CopyConfig.Paths.LogPathRoot "reports_$today.csv"
    
    if (-not (Test-Path $script:ReportsCsv)) {
        "Time;JobName;JobStatus;FileName;Source;RemoteDest;RemoteDestStatus;Arhive;ArhiveStatus;Details" | 
        Out-File $script:ReportsCsv -Encoding ASCII
    }
    
    # ? JOB START
    Write-Type1Log "JOB START" $jobName
    Write-Type2Log $JobName "START" "" "" "" "START" "Job started"

    if (-not (Test-Path $Job.Source)) {
        Write-Type1Log "SOURCE MISSING" $jobName
        Write-Type2Log $JobName "SOURCE_MISSING" "" "" "" "ERROR" "Source missing: $($Job.Source)"
        return @{Success=0; Fails=@(); HasErrors=$true}
    }

    $files = Get-ChildItem $Job.Source | Where-Object { -not $_.PSIsContainer }
    
    foreach ($file in $files) {
        if (Copy-FileVerified $file.FullName $Job.RemoteDest $Job.Arhive $jobName) {
            $success++
        } else {
            $fails += $file.Name
        }
    }

    # ? JOB END
    $hasErrors = $fails.Count -gt 0
    $jobResult = if($hasErrors){"ERROR:$($fails.Count)F"}else{"OK:$success"}
    Write-Type1Log "JOB END: Success=$success Fails=$($fails.Count)" $jobName
    Write-Type2Log $JobName $jobResult "" "" "" "END" "Success=$success Fails=$($fails.Count)"
    
    return @{Success=$success; Fails=$fails; HasErrors=$hasErrors}
}

## Ежедневный отчет (16:30-18:00)
function Send-DailyReport { param($JobResults, $Config)
    $h = (Get-Date).Hour; $m = (Get-Date).Minute
    if ($h -lt 16 -or ($h -eq 16 -and $m -lt 30) -or $h -ge 18) { return }
    
    $totalOK = ($JobResults | % Success | Measure -Sum).Sum
    $allFails = ($JobResults | % Fails | ?{ $_ })
    $logTxt = if (Test-Path $script:GlobalLog) { (Get-Content $script:GlobalLog | Out-String).Substring(0,4000) } else { "No log" }
    
    $body = @"
Daily $($Config.CopyConfig.General.ParentJobName) $(Get-Date -f 'yyyy-MM-dd HH:mm')
SUCCESS: $totalOK | FAILS: $($allFails.Count)
Failed: $($allFails -join ';')
LOG: $logTxt
"@
    
    Send-EmailReport $Config "[DAILY] $totalOK OK / $($allFails.Count) FAIL" $body | Out-Null
}

## MAIN
if (-not (Test-Path $ConfigPath)) { Write-Host "NO CONFIG" -f Red; exit 1 }
$configHash = Get-MD5Hash $ConfigPath
if ($configHash -ne $XmlHash) { 
    Write-Host "HASH FAIL! Got: $configHash ? $XmlHash" -f Red; exit 1 
}

[xml]$Config = Get-Content $ConfigPath
if ($TestMode) { Invoke-TestMode $Config; exit }

$logRoot = $Config.CopyConfig.Paths.LogPathRoot
if (-not (Test-Path $logRoot)) { mkdir $logRoot -Force | Out-Null }

$results = @()
foreach ($job in $Config.CopyConfig.Jobs.Job) {
    $result = Invoke-CopyJob $job $Config; $results += $result
    if ($result.HasErrors) {
        Send-EmailReport $Config "[ERROR] $($job.Name)" "Fails: $($result.Fails -join ', ')`nLog: $script:GlobalLog" | Out-Null
    }
}

Send-DailyReport $results $Config

# Ротация (14 файлов)
$logs = gci $logRoot "*.log" | sort LastWriteTime -Desc
if ($logs.Count -gt [int]$Config.CopyConfig.Paths.LogKeepCount) {
    $logs | select -Skip ([int]$Config.CopyConfig.Paths.LogKeepCount-1) | ri -Force -ea 0 | Out-Null
}

$hasAnyErrors = ($results | Where-Object { $_.HasErrors }).Count -gt 0
exit $(if($hasAnyErrors){1}else{0})