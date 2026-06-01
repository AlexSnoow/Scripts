# Common Functions and Code Patterns

## Write-Log

```powershell
function Write-Log {
    param([string]$Message)

    if (-not $Message -or -not $script:GlobalLog) { return }

    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " " + $Message
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}
```

## Send-Email

```powershell
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
```

## Get-FileHashCompat

```powershell
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
            throw "Hash calculation error for '$filePath': $($_.Exception.Message)"
        }
    }
}
```

## Test-FileIntegrity

```powershell
function Test-FileIntegrity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $false)][string]$FileType = "file"
    )
    process {
        if (-not ($ExpectedHash -match '^[A-F0-9a-f]{64}$')) {
            Write-Host "Invalid hash: expected 64 hex chars" -ForegroundColor Red
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
            Write-Host "Verifying integrity ($FileType): $FilePath..." -ForegroundColor Cyan
            $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpper()
            $expectedHashUpper = $ExpectedHash.ToUpper()
            Write-Host "  Expected : $expectedHashUpper"
            Write-Host "  Actual   : $actualHash"
            if ($actualHash -eq $expectedHashUpper) {
                Write-Host "  [OK] Hash match. File is intact." -ForegroundColor Green
                return $true
            }
            else {
                $errorMessage = @"
Integrity check FAILED!
File may be corrupted!
Type: $FileType
Path: $FilePath
Expected: $expectedHashUpper
Actual: $actualHash
"@
                Write-Host $errorMessage -ForegroundColor Red
                Write-Error $errorMessage
                return $false
            }
        }
        catch {
            $errorMsg = "Error verifying file for $FileType`: $($_.Exception.Message)"
            Write-Host $errorMsg -ForegroundColor Red
            Write-Error $errorMsg
            return $false
        }
    }
}
```

## Remove-OldFiles

```powershell
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
                } catch {
                    $results += "Error deleting: $($file.FullName) $_"
                }
            }
        } else {
            $results += "There are no files to delete."
        }

        $results += "Rotation is complete. Kept: $($allFiles.Count - $filesToDelete.Count) / Total: $($allFiles.Count)"
    } catch {
        $results += "Rotation error: $_"
    }

    return $results -join "`n"
}
```

## Get-DiskSpaceReport

```powershell
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
```

## Error Handling Patterns

### PowerShell (try/catch)

```powershell
try {
    # Critical operation
}
catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    throw
}
```

### Bash (set -euo pipefail + trap)

```bash
set -euo pipefail
trap 'log "ERROR on line $LINENO"' ERR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
```

## Encoding Reference

### PowerShell

```powershell
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
```

### Bash

```bash
export LANG=en_US.UTF-8
```

## PS 2.0 Alternatives

| PS 2.0 Limitation | Alternative |
|-------------------|-------------|
| `Get-FileHash` | `Get-FileHashCompat` (SHA256 through .NET) |
| `[string]::IsNullOrWhiteSpace()` | `Test-StringIsNullOrWhiteSpace` |
| `ConvertFrom-Json` | Use XML instead of JSON |
| `PSCustomObject` | `New-Object PSObject -Property @{}` |
