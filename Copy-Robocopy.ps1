<# file Copy-Robocopy.ps1
.SYNOPSIS
    ��������� ����������� ������ � ������� ��������� Robocopy

.DESCRIPTION
    ������� ��� ��������������� ����������� ������ � ����� � �������������� Robocopy.
    ������������ ������� ����, ��������� ����� ����������� � ��������� ����� ��������.

.PARAMETER SRC
    ��������: ���� ��� ����� ��� ����������� (������������ ��������)

.PARAMETER DST
    ����� ���������� ��� ���������� ����� (������������ ��������)

.PARAMETER RobocopyPath
    ���� � ������������ ����� robocopy (�� ���������: "robocopy.exe" - ������������ ���������)

.PARAMETER LogName
    ��� ���� (����� ��������� ������������ {date}, {time}, {datetime})

.PARAMETER LogPath
    ���� ��� ���������� ����� (�� ���������: "C:\Logs\Robocopy")

.PARAMETER Keys
    ����� � ������� ��� robocopy (�� ���������: "/E /Z /COPYALL /R:2 /W:5 /NP /V")

.PARAMETER CheckFreeSpace
    ��������� ��������� ����� ����� ������������ (� ���������)

.EXAMPLE
    Copy-Robocopy -SRC "D:\Data" -DST "E:\Backup" -Keys "/MIR /Z /R:3 /W:10" -LogName "Mirror-{datetime}"
    ���������� ����������� � ����������� ����������� ��������� ������� � ���������� ��������

.EXAMPLE
    # ������������� � ������������ �������
    Program: powershell.exe
    Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Copy-Robocopy.ps1" -SRC "C:\Source" -DST "\\Server\Backup" -LogName "DailyBackup-{date}"

.EXAMPLE
    # ������������� � ������ �������
    # ������ �������
    . .\Copy-Robocopy.ps1
    
    # �������������� �����������
    $copyJobs = @(
        @{SRC = "C:\Websites"; DST = "D:\Backups\Web"; LogName = "WebBackup-{datetime}"},
        @{SRC = "C:\Databases"; DST = "D:\Backups\DB"; LogName = "DBBackup-{datetime}"; Keys = "/MIR /Z /R:3 /W:10"},
        @{SRC = "C:\Logs"; DST = "D:\Backups\Logs"; LogName = "LogsBackup-{datetime}"; Keys = "/E /Z /NP"}
    )

    foreach ($job in $copyJobs) {
        $result = Copy-Robocopy @job
        if ($result -ge 8) {
            Write-Error "������ ����������� $($job.SRC)"
            # �������������� �������� ��� ������
        }
    }

.EXAMPLE
    # ������������� ��� ������
    Import-Module .\Copy-Robocopy.ps1
    Copy-Robocopy -SRC "C:\Websites" -DST "\\Server\Backup\Web" -Keys "/MIR /Z /R:3 /W:10"

.NOTES
    �����: ������
    ������: 2.0 (2025-08-19)
    ���������: Windows (���������� Robocopy)
#>

function Copy-Robocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SRC,

        [Parameter(Mandatory = $true)]
        [string]$DST,

        [Parameter(Mandatory = $false)]
        [string]$RobocopyPath = "robocopy.exe",

        [Parameter(Mandatory = $false)]
        [string]$LogName = "RobocopyLog-{date}",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "C:\Logs\Robocopy",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "/E /Z /COPYALL /R:2 /W:5 /NP /V",

        [Parameter(Mandatory = $false)]
        [int]$CheckFreeSpace = 10
    )

    # ������ ������������� � ����� ����
    $dateString = Get-Date -Format "yyyyMMdd"
    $timeString = Get-Date -Format "HHmmss"
    $dateTimeString = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $finalLogName = $LogName `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # ������ ������������� � ���� �����
    $LogPath = $LogPath `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # �������� ����� ��� �����, ���� �� ����������
    if (-not (Test-Path $LogPath)) {
        Write-Verbose "�������� ����� ��� �����: $LogPath"
        try {
            New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "�� ������� ������� ����� ��� �����: $($_.Exception.Message)"
            return -1
        }
    }

    # ������������ ������� ���� � ���-�����
    $logFile = Join-Path $LogPath "$finalLogName.log"

    # �������� ���������� �����
    if ($CheckFreeSpace -gt 0) {
        try {
            $sourceSize = (Get-ChildItem $SRC -Recurse -File | Measure-Object Length -Sum).Sum
            $destinationDrive = (Get-Item $DST -ErrorAction Stop).PSDrive.Name
            $freeSpace = (Get-PSDrive -Name $destinationDrive -ErrorAction Stop).Free
            
            $requiredSpace = $sourceSize * (1 + ($CheckFreeSpace / 100))
            
            if ($freeSpace -lt $requiredSpace) {
                Write-Warning "���� ���������� ����� �� ������� �����. ���������: $([math]::Round($requiredSpace/1GB,2)) GB, ��������: $([math]::Round($freeSpace/1GB,2)) GB"
                $confirm = Read-Host "���������� �������� �� ���������� �����? (y/n)"
                if ($confirm -ne 'y') {
                    Write-Host "�������� �������� �������������" -ForegroundColor Yellow
                    return -2
                }
            }
        }
        catch {
            Write-Warning "�� ������� ��������� ��������� �����: $($_.Exception.Message)"
        }
    }

    # ������������ ��������� ������ Robocopy
    $robocopyArgs = @(
        "`"$SRC`"",
        "`"$DST`""
    )
    
    # ���������� ������
    $Keys.Split(" ") | Where-Object { $_ } | ForEach-Object {
        $robocopyArgs += $_
    }
    
    # ���������� ���������� �����������
    $robocopyArgs += "/LOG:`"$logFile`""
    $robocopyArgs += "/TEE"
    $robocopyArgs += "/UNILOG+"  # ������-�����������

    Write-Host "������ Robocopy..." -ForegroundColor Cyan
    Write-Host "��������: $SRC" -ForegroundColor Cyan
    Write-Host "����������: $DST" -ForegroundColor Cyan
    Write-Verbose "�������: $RobocopyPath $($robocopyArgs -join ' ')"

    # ���������� �����������
    try {
        $processInfo = @{
            FilePath = $RobocopyPath
            ArgumentList = $robocopyArgs
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardError = "robocopy_errors.txt"
        }
        
        $process = Start-Process @processInfo
        
        # ������ ���� �������� Robocopy
        $exitCode = $process.ExitCode
        Write-Host "Robocopy �������� � �����: $exitCode" -ForegroundColor Cyan
        
        # ������ ������, ���� ����
        if (Test-Path "robocopy_errors.txt") {
            $errors = Get-Content "robocopy_errors.txt" -Raw
            if ($errors) {
                Write-Warning "������ Robocopy: $errors"
                Add-Content -Path $logFile -Value "`n������:`n$errors" -Encoding UTF8
            }
            Remove-Item "robocopy_errors.txt" -Force
        }
        
        # ������������� ����� �������� Robocopy
        $successCodes = @(0, 1, 2, 3)  # �������� ����
        $warningCodes = @(4, 5, 6, 7)  # ���� � ����������������
        
        if ($exitCode -in $successCodes) {
            Write-Host "����������� ������� ���������!" -ForegroundColor Green
            if ($exitCode -gt 0) {
                Write-Host "����������: ��������� ����� ���� ��������� (���: $exitCode)" -ForegroundColor Yellow
            }
        }
        elseif ($exitCode -in $warningCodes) {
            Write-Warning "����������� ��������� � ���������������� (���: $exitCode)"
        }
        else {
            Write-Error "����������� ��������� � �������� (���: $exitCode)"
        }
        
        Write-Host "���-����: $logFile" -ForegroundColor Cyan
        
        # ������� ������ ���-�����
        if (Test-Path $logFile) {
            try {
                $logContent = Get-Content $logFile -Tail 20 -Encoding UTF8
                Write-Host "`n������� ����������:" -ForegroundColor Cyan
                $logContent | Where-Object { $_ -match "(Dirs|Files|Bytes|Times|Total|Copied|Skipped|Failed|Extras|Ended)" } | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Cyan
                }
            }
            catch {
                Write-Warning "�� ������� ��������� ���-����: $($_.Exception.Message)"
            }
        }
        
        return $exitCode
    }
    catch {
        Write-Error "������ ��� ���������� Robocopy: $($_.Exception.Message)"
        return -1
    }
}

# ���� ������ ������� �������� (�� ������������ ��� ������)
if ($MyInvocation.InvocationName -eq $MyInvocation.ScriptName) {
    param(
        [string]$SRC,
        [string]$DST
    )
    if (-not $SRC) { $SRC = Read-Host "������� ���� � ��������� (SRC)" }
    if (-not $DST) { $DST = Read-Host "������� ���� � ����� ���������� (DST)" }
    
    $params = @{
        SRC = $SRC
        DST = $DST
    }
    Copy-Robocopy @params
}
else {
    # ������� ������� ��� ������������� � ������ ��������
    Export-ModuleMember -Function Copy-Robocopy -Alias robocopy-backup
}