# PowerShell Backup Toolkit - Agent Guide

## Essential Commands

**Run backup script:**
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-v4.ps1
```

**Run in test mode:**
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-v4.ps1 -testmode
```

**Run tests with Pester:**
```powershell
Invoke-Pester .\app\tests\Backup.Tests.ps1
```

## Project Structure

- Main script: `app\Backup-ps2-v4.ps1`
- Configuration: `app\Backup-Config-All.xml`
- Tests: `app\tests\` (Pester framework)
- Documentation: `docs\`

## Backup Pipeline Stages

The script executes a unified 5-stage pipeline for all backup modes:

1. **Preparation** - Builds list of items to back up (files/folders/everything)
2. **Archiving** - Creates RAR archives using single mechanism
3. **Verification** - Validates archive integrity (including 0-byte files)
4. **Post-Operations** - Copy, rotation, cleanup operations
5. **Reporting** - Generates XML/CSV reports to network path

## Important Notes

- Requires PowerShell 2.0, Windows 7 compatible
- Uses RAR archiver (ensure RAR is installed and in PATH)
- Configuration XML defines backup jobs, paths, and retention policies
- Test mode runs verification without actual file operations
- Archive patterns support: {PCName}, {JobName}, {Date}, {Time}, {Date_Time}, {SourceFileName}, {SourceFolderName}