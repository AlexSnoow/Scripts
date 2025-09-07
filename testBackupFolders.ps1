<# file testBackupFolders.ps1
.SYNOPSIS
    �������� ������ ��� ������������� ���������� ����� � ������� ������ CreateBackupRAR

.DESCRIPTION
    ������ ��������� ������ ���������, �������� ������ ��� 4 ��������� �����
    � �������� ���� � ��������� ����������.
#>

# ������������� ��������� ������ ������� � UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
$archiveFolder = "C:\test\rar"
$logFolder = "C:\test\logs"

# ������ ����� ��� ���������
$foldersToArchive = @(
    "C:\test\backup1",
    "C:\test\backup2", 
    "C:\test\backup3",
    "C:\test\backup4"
)

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

# �������� ������������� �������� �����
$existingFolders = @()
foreach ($folder in $foldersToArchive) {
    if (Test-Path $folder -PathType Container) {
        $existingFolders += $folder
        Write-Host "������� ����� ��� ���������: $folder" -ForegroundColor Green
    } else {
        Write-Host "����� �� ������� (����� ���������): $folder" -ForegroundColor Yellow
    }
}

if ($existingFolders.Count -eq 0) {
    Write-Host "�� ������� �� ����� ����� ��� ���������." -ForegroundColor Yellow
    exit 0
}

Write-Host "������� ����� ��� ���������: $($existingFolders.Count)" -ForegroundColor Green
Write-Host "�������� ������� ���������..."
Write-Host ""

# �������� ��� ����������
$successCount = 0
$errorCount = 0

# ��������� ������ �����
foreach ($folder in $existingFolders) {
    $folderName = Split-Path $folder -Leaf
    $archiveName = "backup_$($folderName)_{Computer}_{DateTime}"
    $logName = "backup_$($folderName)_{Computer}_{DateTime}_log.txt"
    
    Write-Host "��������� �����: $folderName"
    
    try {
        $result = BackupWithRAR `
            -RarPath "C:\Program Files\WinRAR\Rar.exe" `
            -SourcePath $folder `
            -DestinationPath $archiveFolder `
            -ArchiveName $archiveName `
            -Keys "a -r -m5 -ep2" `
            -RarLogPath $logFolder `
            -RarLog $logName
        
        if ($result.Success) {
            Write-Host "? �����: ����� $folderName ������� ��������������" -ForegroundColor Green
            Write-Host "   �����: $($result.ArchivePath)" -ForegroundColor Gray
            
            # ��������� ������������� ������ ����� ���������� �������
            if (Test-Path $result.ArchivePath) {
                $archiveSize = [math]::Round((Get-Item $result.ArchivePath).Length / 1MB, 2)
                Write-Host "   ������: $archiveSize MB" -ForegroundColor Gray
            }
            
            $successCount++
        } else {
            Write-Host "? ������: �� ������� �������������� ����� $folderName" -ForegroundColor Red
            Write-Host "   ��� ������: $($result.ExitCode)" -ForegroundColor Red
            Write-Host "   ��������: $($result.ErrorDescription)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host "   ���: $($result.LogPath)" -ForegroundColor Gray
    }
    catch {
        Write-Host "? ����������: ��� ��������� ����� $folderName �������� ������" -ForegroundColor Red
        Write-Host "   ������: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# �������� ����������
Write-Host "=" * 50
Write-Host "����� ��������� �����:" -ForegroundColor Cyan
Write-Host "�������� ��������: $successCount" -ForegroundColor Green
Write-Host "������: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "����� ���������� �����: $($existingFolders.Count)" -ForegroundColor Cyan
Write-Host "������ ��������� �: $archiveFolder" -ForegroundColor Yellow
Write-Host "���� ��������� �: $logFolder" -ForegroundColor Yellow
Write-Host "=" * 50

# ���������� ��� ������ � ����������� �� ������� ������
if ($errorCount -gt 0) {
    exit 1
} else {
    exit 0
}