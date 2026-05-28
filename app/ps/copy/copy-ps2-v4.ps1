#requires -Version 2.0
param(
    [string]$ConfigPath = ".\Copy-Config.xml",
    [switch]$TestMode
)

$ExpectedXmlHash = "6C950642504D1134C89F8C1550ECF5881E206887D645EC3B02A6EC6C53A4EE16"

# ------------------------
# Get-FileHashCompat (полная версия)
# ------------------------
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
            throw "Ошибка хеша '$filePath': $($_.Exception.Message)"
        }
    }
}

Set-Alias Get-FileHash Get-FileHashCompat -Scope Global -Force

# ------------------------
# Полные утилиты
# ------------------------

function Write-Log {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($Message) -or -not $script:GlobalLog) { return }
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " $Message"
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}

function Test-WritePermission {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path $Path -PathType Container)) { return $false }
    try {
        $testFile = Join-Path $Path "._test_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Test-FileIntegrity {
    param([string]$SourcePath, [string]$DestPath)
    if ([string]::IsNullOrEmpty($SourcePath) -or [string]::IsNullOrEmpty($DestPath)) { return $false }
    try {
        $srcHash = (Get-FileHashCompat $SourcePath -ErrorAction SilentlyContinue).Hash
        $dstHash = (Get-FileHashCompat $DestPath -ErrorAction SilentlyContinue).Hash
        return ($srcHash -eq $dstHash -and -not [string]::IsNullOrEmpty($srcHash))
    } catch { return $false }
}

function Send-Email {
    param($Config, [string]$Subject, [string]$Body)
    if (-not $Config) { return $false }
    $smtpServer = $Config.CopyConfig.General.SmtpServer
    $domain = $Config.CopyConfig.General.Domain
    $to = $Config.CopyConfig.Recipients.AdminMail
    if ([string]::IsNullOrEmpty($smtpServer) -or [string]::IsNullOrEmpty($to)) { return $false }
    
    $from = "$env:COMPUTERNAME@$domain"
    try {
        $smtp = New-Object Net.Mail.SmtpClient($smtpServer, 25)
        $msg = New-Object Net.Mail.MailMessage($from, $to, $Subject, $Body)
        $smtp.Send($msg)
        Write-Host "[EMAIL OK]" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[EMAIL FAIL]: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function New-ReportXml {
    param([string]$ReportPath, [hashtable]$Stats)
    if ([string]::IsNullOrEmpty($ReportPath)) { return }
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Report Date="$(Get-Date -f 'yyyy-MM-dd')">
  <JobName>$($Stats.JobName)</JobName>
  <PCName>$($Stats.PCName)</PCName>
  <TotalFiles>$($Stats.Total)</TotalFiles>
  <Copied>$($Stats.Copied)</Copied>
  <Errors>$($Stats.Errors)</Errors>
  <Archived>$($Stats.Archived)</Archived>
  <TimeStart>$($Stats.Start)</TimeStart>
  <TimeEnd>$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')</TimeEnd>
</Report>
"@
    $xml | Out-File $ReportPath -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Log "REPORT: $ReportPath"
}

function Invoke-TestMode {
    param($Config, $Job)
    Write-Host "`n[TEST MODE] JOB1..." -ForegroundColor Cyan
    $errors = 0
    
    # Хеш XML
    try {
        $hashResult = Get-FileHashCompat -LiteralPath $ConfigPath
        Write-Host "XML Хеш: $($hashResult.Hash) [$($hashResult.Path)]" -ForegroundColor Green
    } catch {
        Write-Host "XML Хеш FAIL: $_" -ForegroundColor Red
        $errors++
    }
    
    # Пути с NULL-защитой
    $paths = @(
        @{Name="Source"; Path=$Job.Source; Required=$true},
        @{Name="RemoteDest"; Path=$Job.RemoteDest; Required=$true},
        @{Name="Archive"; Path=$Job.Arhive; Required=$true},
        @{Name="LogRoot"; Path=$Config.CopyConfig.Paths.LogPathRoot; Required=$true}
    )
    
    foreach ($p in $paths) {
        if ([string]::IsNullOrEmpty($p.Path)) {
            Write-Host "[$($p.Name)] NULL/ПУСТОЙ [FAIL]" -ForegroundColor Red
            $errors++
        } elseif (Test-Path $p.Path -PathType Container) {
            Write-Host "[$($p.Name)] OK: $($p.Path)" -ForegroundColor Green
            if (Test-WritePermission $p.Path) {
                Write-Host "  Запись OK" -ForegroundColor Green
            } else {
                Write-Host "  Запись FAIL" -ForegroundColor Red
                $errors++
            }
        } else {
            Write-Host "[$($p.Name)] НЕ НАЙДЕН: $($p.Path) [FAIL]" -ForegroundColor Red
            $errors++
        }
    }
    
    # Source файлы (PS2.0: без -File)
    if (Test-Path $Job.Source -PathType Container) {
        $srcFiles = Get-ChildItem $Job.Source | Where-Object { -not $_.PSIsContainer }
        Write-Host "[Source] Файлов: $($srcFiles.Count)" -ForegroundColor $(if ($srcFiles.Count -gt 0) { "Green" } else { "Yellow" })
    }
    
    $status = if ($errors -eq 0) { "OK" } else { "FAIL ($errors)" }
    Write-Host "`n[TEST] $status" -ForegroundColor $(if ($errors -eq 0) { "Green" } else { "Red" })
    exit $errors
}

# ------------------------
# Главная логика (PS2.0 безопасная)
# ------------------------

"=== ДИАГНОСТИКА XML ==="
"Config: $ConfigPath"

if (-not (Test-Path $ConfigPath -PathType Leaf)) { 
    "ОШИБКА: $ConfigPath НЕ НАЙДЕН!"
    exit 1 
}

$hashResult = Get-FileHashCompat -LiteralPath $ConfigPath
$currentHash = $hashResult.Hash
"? Найден: $($hashResult.Path)"
"ТЕКУЩИЙ: $currentHash"
"ОЖИДАЕМЫЙ: $ExpectedXmlHash"

if ($currentHash -ne $ExpectedXmlHash) { 
    "? ХЕШ FAIL! Обновите ExpectedXmlHash."
    exit 1
}

[xml]$Config = Get-Content $ConfigPath
$Job = $Config.CopyConfig.Jobs.Job
$PCName = $env:COMPUTERNAME
$LogRoot = $Config.CopyConfig.Paths.LogPathRoot
$DateLog = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$script:GlobalLog = Join-Path $LogRoot "Copy_${PCName}_$($Job.Name)`_$DateLog.log"

if ($TestMode) { Invoke-TestMode $Config $Job }

# NULL-защита путей
$Source = if ($Job.Source) { $Job.Source } else { "" }
$RemoteDest = if ($Job.RemoteDest) { $Job.RemoteDest } else { "" }
$Archive = if ($Job.Arhive) { $Job.Arhive } else { "" }

if ([string]::IsNullOrEmpty($Source) -or [string]::IsNullOrEmpty($RemoteDest)) {
    Write-Host "ОШИБКА: Source/RemoteDest пустые в XML!" -ForegroundColor Red
    exit 1
}

# Безопасное создание директорий
if (-not (Test-Path (Split-Path $RemoteDest))) {
    New-Item -ItemType Directory -Path (Split-Path $RemoteDest) -Force | Out-Null
}
if (-not (Test-Path $Archive)) {
    New-Item -ItemType Directory -Path $Archive -Force | Out-Null
}
if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

Write-Log "START: $Source -> $RemoteDest -> $Archive"

# Статистика
$stats = @{
    JobName = $Job.Name; PCName = $PCName; Start = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Total = 0; Copied = 0; Errors = 0; Archived = 0
}

# PS2.0: Get-ChildItem без -File
$sourceFiles = Get-ChildItem $Source | Where-Object { -not $_.PSIsContainer }
$stats.Total = $sourceFiles.Count

foreach ($file in $sourceFiles) {
    if ([string]::IsNullOrEmpty($RemoteDest)) { continue }
    
    $relPath = $file.FullName.Substring($Source.Length).TrimStart('\')
    $destFile = Join-Path $RemoteDest $relPath
    $destDir = Split-Path $destFile -Parent
    
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    
    try {
        Copy-Item $file.FullName $destFile -Force
        if (Test-FileIntegrity $file.FullName $destFile) {
            $stats.Copied++
            Write-Log "COPY OK: $relPath"
        } else {
            if (Test-Path $destFile) { Remove-Item $destFile -Force }
            $stats.Errors++
            Write-Log "COPY FAIL: $relPath"
        }
    } catch {
        $stats.Errors++
        Write-Log "COPY ERR: $relPath - $_"
    }
}

# Архивация
if (Test-Path $RemoteDest) {
    $copiedFiles = Get-ChildItem $RemoteDest | Where-Object { -not $_.PSIsContainer }
    foreach ($copied in $copiedFiles) {
        if ([string]::IsNullOrEmpty($Archive)) { continue }
        $arcFile = Join-Path $Archive $copied.Name
        Move-Item $copied.FullName $arcFile -Force -ErrorAction SilentlyContinue
        $stats.Archived++
        Write-Log "ARCH OK: $($copied.Name)"
    }
}

Write-Log "END: Errors=$($stats.Errors)"

# Отчёт
$reportDate = (Get-Date).ToString("yyyyMMdd")
$reportPath = Join-Path $LogRoot "reports_$reportDate.xml"
New-ReportXml $reportPath $stats

# Email (не критично)
$body = "JOB1`n" + (Get-Content $script:GlobalLog | Out-String) + "`n$reportPath"
$subject = "[COPY $($Job.Name)] $($stats.Errors)/$($stats.Total)"
Send-Email $Config $subject $body

# ИТОГО (PS2.0)
if ($stats.Errors -eq 0) {
    Write-Host "ИТОГО: $($stats.Copied)/$($stats.Total) OK" -ForegroundColor Green
} else {
    Write-Host "ИТОГО: $($stats.Copied)/$($stats.Total), ошибок: $($stats.Errors)" -ForegroundColor Red
}

exit $(if ($stats.Errors -gt 0) {1} else {0})