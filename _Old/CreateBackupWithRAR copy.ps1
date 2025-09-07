<# file CreateBackupWithRAR.ps1
.SYNOPSIS
    ��������� ��������� ������ � ������� RAR

.DESCRIPTION
    ������ ��� �������������� ��������� ������ � ����� � �������������� RAR.
    ������������ ���������� ����/������� � ��� ������, ������� ���� � ��������� ����� ���������.
    ����� ���� ������� �������������� ��� ����������� ��� ������� � ������ ��������.

.PARAMETER SourcePath
    ��������: ���� ��� ����� ��� ���������

.PARAMETER DestinationPath
    ����� ���������� ��� ���������� ������

.PARAMETER ArchiveName
    ��� ������ (����� ��������� ������������ {SourceFolder}, {Computer}, {Date}, {Time}, {DateTime})

.PARAMETER RarPath
    ���� � ������������ ����� RAR

.PARAMETER Keys
    ����� � ������� ��� RAR

.PARAMETER ArchiveExtension
    ���������� ������

.PARAMETER WhatIf
    ��������, ��� ����� �������, ��� ����������

.EXAMPLE
    BackupWithRAR -SourcePath "C:\test\backup2" -DestinationPath "C:\test\rar" -ArchiveName "Backup-{SourceFolder}_{Computer}_{DateTime}"

.EXAMPLE
    BackupWithRAR -SourcePath "C:\Data" -DestinationPath "D:\Backups" -WhatIf

.NOTES
    �����: ������
    ������: 4.0 (2025-08-24)
    ���������: RAR ������������� � �������
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Default")]
    [ValidateScript({
            if (-not (Test-Path $_)) { throw "�������� �� ����������: $_" }
            $true
        })]
    [Alias("SRC")]
    [string]$SourcePath,

    [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Default")]
    [Alias("DST")]
    [string]$DestinationPath,

    [Parameter(Mandatory = $false, ParameterSetName = "DirectCall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Default")]
    [string]$ArchiveName = "backup_{SourceFolder}_{Computer}_{DateTime}",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if (-not (Test-Path $_)) { throw "RAR �� ������ �� ���������� ����: $_" }
            $true
        })]
    [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",

    [Parameter(Mandatory = $false)]
    [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

    [Parameter(Mandatory = $false)]
    [ValidateSet("rar", "zip")]
    [string]$ArchiveExtension = "rar",

    [Parameter(Mandatory = $false, ParameterSetName = "DirectCall")]
    [switch]$WhatIf
)

# ������������ ������� ��� ������� ��� ������
function BackupWithRAR {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "�������� �� ����������: $_" }
                $true
            })]
        [Alias("SRC")]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [Alias("DST")]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [string]$ArchiveName = "backup_{SourceFolder}_{Computer}_{DateTime}",

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                if (-not (Test-Path $_)) { throw "RAR �� ������ �� ���������� ����: $_" }
                $true
            })]
        [string]$RarPath = "C:\Program Files\WinRAR\Rar.exe",

        [Parameter(Mandatory = $false)]
        [string]$Keys = "a -t -r -m5 -dh -tl -rr1p -s -ep2",

        [Parameter(Mandatory = $false)]
        [ValidateSet("rar", "zip")]
        [string]$ArchiveExtension = "rar"
    )

    begin {
        Write-Verbose "������ ���������� ���������"
        
        # ������������ �����
        $SourcePath = (Resolve-Path $SourcePath -ErrorAction Stop).Path
        $DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)

        # �������� ����� ���������� ���� �� ����������
        if (-not (Test-Path $DestinationPath)) {
            if ($PSCmdlet.ShouldProcess($DestinationPath, "�������� ����� ����������")) {
                Write-Verbose "�������� ����� ����������: $DestinationPath"
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            }
        }

        # ���������� �������������
        $placeholders = @{
            "{SourceFolder}" = (Split-Path -Leaf $SourcePath) -replace '[<>:"|?*]', '_'
            "{Computer}"     = $env:COMPUTERNAME
            "{Date}"         = (Get-Date -Format "yyyyMMdd")
            "{Time}"         = (Get-Date -Format "HHmmss")
            "{DateTime}"     = (Get-Date -Format "yyyyMMdd-HHmmss")
        }

        # ����������� ������������� � ��� ������
        $finalArchiveName = $ArchiveName
        foreach ($ph in $placeholders.Keys) {
            $finalArchiveName = $finalArchiveName -replace [regex]::Escape($ph), $placeholders[$ph]
        }

        # ������� �������� � ��������� �������� � �����
        $finalArchiveName = $finalArchiveName.Trim().TrimEnd('.', ' ', '-', '_')

        # �������� ��������� ����� �� ������������ �������
        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
        $invalidPattern = '[' + [regex]::Escape(($invalidChars -join '')) + ']'
        if ($finalArchiveName -match $invalidPattern) {
            throw "�������� ��� ������ �������� ������������ �������: '$finalArchiveName'. �������� ��� ������ ��� ����� ���������."
        }

        # �������� �� ����������������� ����� Windows
        $reserved = 'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
        if ($reserved -contains $finalArchiveName.ToUpperInvariant()) {
            throw "�������� ��� ������ ��������������� ��������: '$finalArchiveName'. �������� ��� ������."
        }

        # ������������ ������ �����
        $archivePath = Join-Path $DestinationPath "$finalArchiveName.$ArchiveExtension"
        $logPath = Join-Path $DestinationPath "$finalArchiveName.log.txt"
        $logErrPath = Join-Path $DestinationPath "$finalArchiveName.err.txt"

        # ����������� ����� ���� (��� Windows MAX_PATH)
        $maxPathLen = 250
        while ($archivePath.Length -gt $maxPathLen -or $logPath.Length -gt $maxPathLen -or $logErrPath.Length -gt $maxPathLen) {
            Write-Verbose "���� ������� �������. ������ ��� ������ ��� ���������� ������."
            # ����������� ��� ������ �� 5 ��������
            $finalArchiveName = $finalArchiveName.Substring(0, [Math]::Max(0, $finalArchiveName.Length - 5)).TrimEnd('.', ' ', '-', '_')
            # ���������� ����
            $archivePath = Join-Path $DestinationPath "$finalArchiveName.$ArchiveExtension"
            $logPath = Join-Path $DestinationPath "$finalArchiveName.log.txt"
            $logErrPath = Join-Path $DestinationPath "$finalArchiveName.err.txt"

            if ([string]::IsNullOrWhiteSpace($finalArchiveName)) {
                throw "��� ������ ������� ������� ��� ���������� ���� ����������. �������� ����� ��� ��� ������."
            }
        }

        # ������������� ����� � ���������
        $escapedArchivePath = '"{0}"' -f $archivePath
        $escapedSrcPath = '"{0}"' -f $SourcePath

        # ������������ ��������� ������
        $rarArgs = @(
            $Keys,
            $escapedArchivePath,
            $escapedSrcPath
        ) -join " "

        Write-Verbose "�������: $RarPath $rarArgs"
    }

    process {
        if (-not $PSCmdlet.ShouldProcess("�����: $archivePath", "�������� ������")) {
            Write-Host "������ ��������: ����� ������ ����� $archivePath �� $SourcePath"
            return 0
        }

        try {
            Write-Host "������ ���������..."
            
            # ������� ��������� ���� ��� ������
            $tempErrFile = [System.IO.Path]::GetTempFileName()

            $processInfo = @{
                FilePath               = $RarPath
                ArgumentList           = $rarArgs
                Wait                   = $true
                PassThru               = $true
                NoNewWindow            = $true
                RedirectStandardOutput = $logPath
                RedirectStandardError  = $tempErrFile
            }

            $process = Start-Process @processInfo

            # ���������, ���� �� ������
            $hasErrors = $process.ExitCode -ne 0
            $errorContent = if (Test-Path $tempErrFile) { 
                Get-Content $tempErrFile -Raw 
            } else { 
                $null 
            }

            # ���� ���� ������ ��� ���������� � stderr, ��������� ��� ������
            if ($hasErrors -or (-not [string]::IsNullOrWhiteSpace($errorContent))) {
                Move-Item -Path $tempErrFile -Destination $logErrPath -Force
                Write-Verbose "������ ��� ������: $logErrPath"
            } else {
                # ���� ������ ���, ������� ��������� ����
                Remove-Item $tempErrFile -Force -ErrorAction SilentlyContinue
            }

            # �������� ���� ��������
            if ($process.ExitCode -eq 0) {
                Write-Host "��������� ������� ���������!"
                Write-Host "�����: $archivePath"
                Write-Host "���: $logPath"

                # ����� ������� ������
                if (Test-Path $archivePath) {
                    $archiveSize = (Get-Item $archivePath).Length / 1MB
                    $sizeText = "������ ������: {0:N2} ��" -f $archiveSize
                    Write-Host $sizeText
                } else {
                    Write-Warning "�� ������� ���������� ������ ������."
                }
            } else {
                Write-Error "��������� ��������� � ����� ������: $($process.ExitCode)"
                if (Test-Path $logErrPath) {
                    Write-Error "��� ������: $logErrPath"
                }
            }

            return $process.ExitCode
        } catch {
            Write-Error "������ ��� ���������� ���������: $($_.Exception.Message)"
            return -1
        } finally {
            # �������� ���������� ����� ������, ���� �� �������
            if (Test-Path $tempErrFile) {
                Remove-Item $tempErrFile -Force -ErrorAction SilentlyContinue
            }
            
            # �������� ������� ���������� ����� ������, ���� ����������
            if (Test-Path "RAR_errors.txt") {
                Remove-Item "RAR_errors.txt" -Force -ErrorAction SilentlyContinue
            }
        }
    }

    end {
        Write-Verbose "���������� ���������� ���������"
    }
}

# --- ������� ������� ��� ������ ---
if ($MyInvocation.ScriptName -like "*.psm1") {
    Export-ModuleMember -Function BackupWithRAR
}

# --- ������ �������� ---
if ($PSCmdlet.ParameterSetName -eq "DirectCall") {
    # ������� ���-������� ���������� ��� �������� � �������
    $params = @{
        SourcePath      = $SourcePath
        DestinationPath = $DestinationPath
    }

    # ��������� �������������� ���������, ���� ��� �������
    if ($PSBoundParameters.ContainsKey('ArchiveName')) { $params.ArchiveName = $ArchiveName }
    if ($PSBoundParameters.ContainsKey('RarPath')) { $params.RarPath = $RarPath }
    if ($PSBoundParameters.ContainsKey('Keys')) { $params.Keys = $Keys }
    if ($PSBoundParameters.ContainsKey('ArchiveExtension')) { $params.ArchiveExtension = $ArchiveExtension }
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $params.WhatIf = $WhatIf }

    # �������� ������� � �����������
    BackupWithRAR @params
}