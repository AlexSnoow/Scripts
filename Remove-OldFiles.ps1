<# file Remove-OldFiles.ps1
.SYNOPSIS
��������� ��������� ������ �� ����� ��������

.DESCRIPTION
������� ��� �������������� ������� ������ ������ � ��������� ���������� 
������������ ���������� ��������� ������. ������������ ������������� ��������.

.PARAMETER Path
������� ���������� (������������)

.PARAMETER DaysOld
������������ ������� ������ � ���� (1-3650)

.PARAMETER KeepCount
����������� ���������� ����������� ������ (1-1000)

.EXAMPLE
    ��������� ������� � ������
    . C:\Scripts\Remove-OldFiles.ps1
    ����� �������
    Remove-OldFiles -Path "D:\Backups" -DaysOld 180
    ������� ����� ������ 6 �������, �������� �� ��������� 5 ���������

.EXAMPLE
    Remove-OldFiles -Path "C:\Logs" -KeepCount 10 -WhatIf
    �������� ������: �������� ����� ����� ����� ������� ��� ��������� ��������

.EXAMPLE
    ����� �� ������� �������
    # ������ MainScript.ps1
    try {
        # ������ �������
        . "C:\Scripts\Remove-OldFiles.ps1"
    
        # ����� � �����������
        Remove-OldFiles -Path "E:\AppLogs" -DaysOld 90 -KeepCount 3
    
        Write-Host "������� ��������� �������"
    }
    catch {
        Write-Error "������: $_"
    }

.NOTES
�����: ������
������: 1.0 (2025-08-18)
#>

function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [ValidateRange(1, 3650)]
        [int]$DaysOld = 30,
        
        [ValidateRange(1, 1000)]
        [int]$KeepCount = 5
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "���������� $Path �� ���������� ��� ����������"
        return
    }

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $allFiles = @(Get-ChildItem -Path $Path -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
        
        if ($allFiles.Count -eq 0) {
            Write-Host "� ���������� ��� ������ ��� ���������"
            return
        }

        # 1. ��������� TOP-$KeepCount ����� ����� ������ (������)
        $filesToKeep = $allFiles | Select-Object -First $KeepCount

        # 2. ��������� ������ ��� ��������:
        #   - ����� ������ $cutoffDate
        #   - ��������� ����� �� $filesToKeep
        $filesToDelete = $allFiles | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and
            $filesToKeep.FullName -notcontains $_.FullName
        }

        # �������� � ��������������
        if ($filesToDelete.Count -gt 0) {
            Write-Host "������� ������ ��� ��������: $($filesToDelete.Count)"
            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "�������� �����")) {
                    Remove-Item $file.FullName -Force -ErrorAction Continue
                }
            }
            Write-Host "������� ������: $($filesToDelete.Count)"
        } else {
            Write-Host "��� ������ ��� ��������"
        }
        
        # ����� ����������
        Write-Host "��������� ������: $($allFiles.Count - $filesToDelete.Count)"
    }
    catch {
        Write-Error "������ ��� ��������� ������: $_"
    }
}