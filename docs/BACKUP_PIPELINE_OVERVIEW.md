# Overview of Backup Pipeline

This document describes the core functions that implement the unified backup pipeline in Backup-ps2-v4.ps1.

## Pipeline Stages

The backup process follows a unified 5-stage pipeline for all backup modes:

### 1. Preparation Stage
**Purpose:** Build the list of items to be backed up (files, folders, or everything)

Key Functions:
- `Get-FileList` - Scans a folder and returns all files
- `Get-FilterFileList` - Finds files matching a mask (e.g., *.log)
- `Prepare-ArchiveItems` - Prepares elements for archivation based on job configuration

### 2. Archiving Stage
**Purpose:** Create RAR archives using a single mechanism for all items

Key Functions:
- `Start-RarArchive` - Creates a RAR archive with specified parameters
- `Invoke-ArchivePipeline` - Executes archivation of all prepared items
- `Get-FileArhListRar` - Reads contents of a RAR archive for verification

### 3. Verification Stage
**Purpose:** Verify archive integrity including 0-byte files

Key Functions:
- `Test-RarArchive` - Tests RAR archive integrity
- `Compare-FilesSourceArchive` - Compares source files vs archive contents
- `Invoke-Verification` - Executes verification for all archives
- `Get-FileHashCompat` - Computes SHA256 hash (PowerShell 2.0 compatible)
- `Test-FileIntegrity` - Verifies file integrity by hash comparison

### 4. Post-Operations Stage
**Purpose:** Perform copy, rotation, and cleanup operations

Key Functions:
- `Invoke-PostOperations` - Executes post-archivation operations
- `Remove-OldFiles` - Rotates files based on age and count policies
- `Copy-BackupFile` - Copies files with timing and size validation
- `Format-FileSize` - Formats file sizes in human-readable form

### 5. Reporting Stage
**Purpose:** Generate and save reports (XML, CSV) to network path

Key Functions:
- `Save-RemoteReports` - Saves XML/CSV reports to NetLogPath
- `Initialize-Logging` - Initializes logging system
- `Write-Log` - Writes messages to log file
* `Write-LogSection` - Adds section headers to log
* `Get-LogResults` - Retrieves log summary for reports
* `Get-LogFilePath` - Returns current log file path

## Supporting Functions

### Configuration
- `Get-BackupConfiguration` - Loads configuration from XML
- `Test-Configuration` - Validates configuration correctness

### Windows Integration
- `Write-WinEventAppLog` - Writes to Windows Event Log
- `Send-Email` - Sends email notifications via SMTP

### Helper Utilities
- `Get-DiskSpaceReport` - Reports free space on drives
- `Get-FileInfoDetails` - Gets summary information about files in folder
- `Resolve-ArchivePattern` - Resolves archive name patterns with variables
- `Get-ArchiveMode` - Determines archiving mode for a job

## Important Notes

- All functions are compatible with **PowerShell 2.0**
- Uses only built-in .NET Framework classes
- No external dependencies
- Strings are processed in UTF8 without BOM
- Logging uses OEM encoding (CP866) for Cyrillic support
- Archive patterns support: {PCName}, {JobName}, {Date}, {Time}, {Date_Time}, {SourceFileName}, {SourceFolderName}

For detailed parameter information, return values, and examples, see `Backup_API_Reference.md`.