#requires -version 2.0
param([string]$ConfigPath = ".\Copy-Config.xml", [switch]$TestMode)

$XmlHash = "82D6A01903D634DD9E68602F7721EC88"
$script:GlobalLog = $null
$script:ReportsCsv = $null
$script:Crc32Table = $null

## Утилиты PS 2.0
function Test-Empty { 
    param([string]$s) 
    if ($s -eq $null -or $s.Trim() -eq "") { $true } 
    else { $false } 
}

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
    if (-not (Test-Path $FilePath)) { return $null }
    
    # Инициализация таблицы CRC32
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
    $stream = [IO.File]::OpenRead($FilePath)
    try {
        while (($read = $stream.Read($buffer, 0, 8192)) -gt 0) {
            for ($n = 0; $n -lt $read; $n++) {
                $index = (($crc -bxor $buffer[$n]) -band 0xFF)
                $crc = (($script:Crc32Table[$index] -bxor ($crc -shr 8)) -band 0xFFFFFFFF)
            }
        }
    } finally { $stream.Close() }
    return bitconverter::tostring([byte[]][byte]($crc -shr 24), [byte]($crc -shr 16), [byte]($crc -shr 8), [byte]$crc).replace('-','').toupper()
}

function Write-Type1Log { 
    param([string]$Message, [string]$JobName)
    if (Test-Empty $Message -or -not $script:GlobalLog) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts [$JobName] $Message" | Add-Content $script:GlobalLog -ErrorAction SilentlyContinue
}

function Write-Type2Log {
    param(
        [string]$JobName, [string]$JobStatus = "", [string]$FileName = "",
        [string]$Source = "", [string]$RemoteDest = "", [string]$RemoteDestStatus = "",
        [string]$Arhive = "", [string]$ArhiveStatus = "", [string]$Details = ""
    )
    if (-not $script:ReportsCsv) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $csvLine = "`"$ts`";`"$JobName`";`"$JobStatus`";`"$FileName`";`"$Source`";`"$RemoteDest`";`"$RemoteDestStatus`";`"$Arhive`";`"$ArhiveStatus`";`"$Details`""
    Add-Content -Path $script:ReportsCsv -Value $csvLine -Encoding ASCII
}

function Test-WriteAccess {
    param([string]$Path)
    if (Test-Empty $Path) { return $false }
    try {
        $tf = Join-Path $Path "._t$([guid]::newguid().tostring().substring(0,8))"
        [IO.File]::WriteAllText($tf, ""); Remove-Item $tf -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

## Тест-режим PS 2.0
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
        }
        elseif (-not (Test-WriteAccess $job.RemoteDest)) { 
            Write-Host "  [FAIL] RemoteDest" -ForegroundColor Red
        }
        else { 
            Write-Host "  [OK] Paths" -ForegroundColor Green 
        }
    }
    
    exit $errors
}

## MAIN PS 2.0
Write-Host "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor Green

if (-not (Test-Path $ConfigPath)) { 
    Write-Host "NO CONFIG: $ConfigPath" -ForegroundColor Red; 
    exit 1 
}

$configHash = Get-MD5Hash $ConfigPath
if ($configHash -ne $XmlHash) { 
    Write-Host "HASH FAIL! $configHash ? $XmlHash" -ForegroundColor Red; 
    exit 1 
}

[xml]$Config = Get-Content $ConfigPath

if ($TestMode) { 
    Invoke-TestMode $Config; 
    exit 
}

Write-Host "Starting Copy Job..." -ForegroundColor Yellow