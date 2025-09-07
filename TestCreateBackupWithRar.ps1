<# file TestCreateBackupWithRar.ps1
<#
.SYNOPSIS
    �������� ������ ��� ������ CreateBackupRAR

.DESCRIPTION
    ������ ��������� ������ ���������, �������� ������ ��� ������� �����
    � ��������� ����� � �������� ���� � ��������� ����������.
    ����� ��� ������������� � ������� ��������.
#>

# ���������� ���� � ������ (������������, ��� �� � ��� �� �����, ��� � ������)
$modulePath = Join-Path $PSScriptRoot "CreateBackupRAR.psm1"

# ��������� ������������� ������
if (-not (Test-Path $modulePath)) {
    Write-Error "������ �� ������ �� ����: $modulePath"
    Write-Host "���������, ��� ���� CreateBackupRAR.psm1 ��������� � ��� �� �����, ��� � ���� ������" -ForegroundColor Yellow
    exit 1
}

# ������ ������
try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "������ CreateBackupRAR ������� ��������" -ForegroundColor Green
}
catch {
    Write-Error "�� ������� ��������� ������ CreateBackupRAR: $($_.Exception.Message)"
    exit 1
}

# ����������� �����
$sourceFolder = "C:\test\backup1"
$archiveFolder = "C:\test\rar"
$logFolder = "C:\test\logs"

# �������� ������������� �������� �����
if (-not (Test-Path $sourceFolder)) {
    Write-Error "�������� ����� �� �������: $sourceFolder"
    exit 1
}

# ��������/�������� ����� ��� ������� � �����
foreach ($folder in $archiveFolder, $logFolder) {
    if (-not (Test-Path $folder)) {
        try {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Host "������� �����: $folder" -ForegroundColor Yellow
        }
        catch {
            Write-Error "�� ������� ������� ����� $folder : $($_.Exception.Message)"
            exit 1
        }
    }
}

# ��������� ������ ������ ��� ���������
try {
    $filesToArchive = Get-ChildItem -Path $sourceFolder -File -ErrorAction Stop
}
catch {
    Write-Error "�� ������� �������� ������ ������ �� $sourceFolder : $($_.Exception.Message)"
    exit 1
}

if ($filesToArchive.Count -eq 0) {
    Write-Host "� ����� $sourceFolder ��� ������ ��� ���������." -ForegroundColor Yellow
    exit 0
}

Write-Host "������� ������ ��� ���������: $($filesToArchive.Count)" -ForegroundColor Green
Write-Host "�������� ������� ���������..."
Write-Host ""

# �������� ��� ����������
$successCount = 0
$errorCount = 0

# ��������� ������� �����
foreach ($file in $filesToArchive) {
    $archiveName = "backup_$($file.BaseName)_{Computer}_{DateTime}"
    $logName = "backup_$($file.BaseName)_{Computer}_{DateTime}_log.txt"
    
    Write-Host "��������� �����: $($file.Name)"
    
    try {
        $result = BackupWithRAR `
            -RarPath "C:\Program Files\WinRAR\Rar.exe" `
            -SourcePath $file.FullName `
            -DestinationPath $archiveFolder `
            -ArchiveName $archiveName `
            -Keys "a -r -m0 -ep2" `
            -RarLogPath $logFolder `
            -RarLog $logName
        
        if ($result.Success) {
            Write-Host "? �����: ���� $($file.Name) ������� �������������" -ForegroundColor Green
            Write-Host "   �����: $($result.ArchivePath)" -ForegroundColor Gray
            
            # ��������� ������������� ������ ����� ���������� �������
            if (Test-Path $result.ArchivePath) {
                $archiveSize = [math]::Round((Get-Item $result.ArchivePath).Length / 1MB, 2)
                Write-Host "   ������: $archiveSize MB" -ForegroundColor Gray
            }
            
            $successCount++
        } else {
            Write-Host "? ������: �� ������� �������������� $($file.Name)" -ForegroundColor Red
            Write-Host "   ��� ������: $($result.ExitCode)" -ForegroundColor Red
            Write-Host "   ��������: $($result.ErrorDescription)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host "   ���: $($result.LogPath)" -ForegroundColor Gray
    }
    catch {
        Write-Host "? ����������: ��� ��������� $($file.Name) �������� ������" -ForegroundColor Red
        Write-Host "   ������: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# �������� ����������
Write-Host "=" * 50
Write-Host "����� ���������:" -ForegroundColor Cyan
Write-Host "�������� ��������: $successCount" -ForegroundColor Green
Write-Host "������: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "����� ���������� ������: $($filesToArchive.Count)" -ForegroundColor Cyan
Write-Host "������ ��������� �: $archiveFolder" -ForegroundColor Yellow
Write-Host "���� ��������� �: $logFolder" -ForegroundColor Yellow
Write-Host "=" * 50

# ���������� ��� ������ � ����������� �� ������� ������
if ($errorCount -gt 0) {
    exit 1
} else {
    exit 0
}