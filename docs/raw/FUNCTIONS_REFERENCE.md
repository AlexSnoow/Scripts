# PowerShell Backup Toolkit - Function Reference

## Core Pipeline Functions

### Preparation Stage
- **Get-FileList** - Scans folder and returns all files
  - Parameters: `-Path` (string)
  - Returns: `[PSObject[]]` with RelativePath, Length, LastWriteTime, FullName

- **Get-FilterFileList** - Finds files matching a mask
  - Parameters: `-Path` (string), `-Filter` (string)
  - Returns: `[PSObject[]]` - filtered file list

- **Prepare-ArchiveItems** - Prepares elements for archivation
  - Parameters: `-Job` (hashtable), `-PCName` (string)
  - Returns: `[PSObject[]]` - list of ArchiveItem objects

### Archiving Stage
- **Start-RarArchive** - Creates RAR archive
  - Parameters: `-RarPath`, `-ArchivePath`, `-SourcePath`, `-Parameters` (string[]), `-LogPath` (optional)
  - Returns: `[PSObject]` with ExitCode, Duration, ArchiveSize, LogContent

- **Invoke-ArchivePipeline** - Executes archivation of all items
  - Parameters: `-ArchiveItems`, `-Job`, `-Config`, `-LogDir`
  - Returns: `[hashtable]` with Results array, SuccessCount, ErrorCount

- **Get-FileArhListRar** - Reads contents of RAR archive
  - Parameters: `-RarPath`, `-ArchivePath`
  - Returns: `[PSObject[]]` - list of files in archive

### Verification Stage
- **Test-RarArchive** - Tests RAR archive integrity
  - Parameters: `-RarPath`, `-ArchivePath`
  - Returns: `[PSObject]` with ExitCode, IsValid

- **Compare-FilesSourceArchive** - Compares source vs archive
  - Parameters: `-SourceList`, `-ArchiveList`, `-SourcePath` (optional)
  - Returns: `[PSObject]` with IsIdentical, TotalSource, TotalArchive, MissingInArchive, SizeMismatch, Report

- **Invoke-Verification** - Executes verification for all archives
  - Parameters: `-ArchiveResults`, `-Job`, `-Config`
  - Returns: `[hashtable]` with Verified array, FailedCount, TotalCount, AllPassed

### Post-Operations Stage
- **Invoke-PostOperations** - Executes post-archivation operations
  - Parameters: `-ArchiveResults`, `-Job`, `-Config`, `-VerificationResult`, `-PipelineSuccessCount`, `-PipelineErrorCount`

- **Remove-OldFiles** - Rotates files based on age/count policies
  - Parameters: `-Path`, `-DaysOld`, `-KeepCount`, `-Filter` (supports -WhatIf)

- **Copy-BackupFile** - Copies file with timing validation
  - Parameters: `-SourcePath`, `-DestinationPath`
  - Returns: `[PSObject]` with Success, Duration, SourceSize, DestinationSize

### Reporting Stage
- **Save-RemoteReports** - Saves XML/CSV reports to network path
  - Parameters: `-PCName`, `-JobName`, `-JobStatus`, `-Duration`, `-SourceFiles`, `-ArchiveSizeMB`, `-Verification`, `-Errors`, `-Warnings`, `-LocalLogPath`, `-SourceFileList`, `-NetPath` (optional)
  - Creates: `<PCName>_<JobName>_<timestamp>.xml`, `<PCName>_<JobName>_<timestamp>.csv`, `<PCName>_summary.xml`

- **Initialize-Logging** - Initializes logging system
  - Parameters: `-LogPath`, `-PCName`, `-JobName`
  - Returns: `[bool]` - success

- **Write-Log** - Writes message to log file
  - Parameters: `-Message` (string), `-Level` (INFO|WARNING|ERROR|SUCCESS|DEBUG), `-ResultKey` (switch)
  - Adds to report if `-ResultKey` used

- **Get-LogResults** - Retrieves log summary for reports
  - Returns: `[string]` - summary of messages with ResultKey

## Supporting Functions

### Configuration
- **Get-BackupConfiguration** - Loads configuration from XML
  - Returns: `[hashtable]` with Settings and Jobs

- **Test-Configuration** - Validates configuration correctness
  - Returns: `[hashtable]` with IsValid, Errors

### Windows Integration
- **Write-WinEventAppLog** - Writes to Windows Event Log
  - Parameters: `-StatusKey` (Start|Success|Warning|Error|End), `-MessageText`, `-Source` (optional)

- **Send-Email** - Sends email via SMTP
  - Parameters: `-SmtpServer`, `-From`, `-To`, `-Subject`, `-Body`, `-Port` (optional, default 25), `-UseSSL` (optional)
  - Returns: `[bool]` - true if sent

### Helper Utilities
- **Get-DiskSpaceReport** - Reports free space on drives
  - Parameters: `-ComputerName` (optional)
  - Returns: `[string]` - disk space summary

- **Get-FileInfoDetails** - Gets summary info about files in folder
  - Parameters: `-Path`
  - Returns: `[PSObject]` with FileCount, TotalSizeMB, FileSamples, HasMoreFiles, MoreFilesCount

- **Resolve-ArchivePattern** - Resolves archive name patterns
  - Parameters: `-Pattern`, `-PCName`, `-JobName`, `-SourceFileName` (optional), `-SourceFolderName` (optional)
  - Returns: `[string]` - resolved archive name

- **Get-ArchiveMode** - Determines archiving mode for job
  - Parameters: `-Job` (hashtable)
  - Returns: `[string]` - 'Normal', 'IndividualFiles', or 'IndividualFolders'

## Hash Functions (PowerShell 2.0 Compatible)
- **Get-FileHashCompat** - Computes file hash
  - Parameters: `-Path` or `-LiteralPath`, `-Algorithm` (SHA1|SHA256|SHA384|SHA512|MD5)
  - Returns: `[PSObject]` with Hash, Algorithm, Path

- **Test-FileIntegrity** - Verifies file integrity by hash
  - Parameters: `-FilePath`, `-ExpectedHash`, `-FileType` (for reporting)
  - Returns: `[bool]` - true if hash matches

## Important Notes
- All functions compatible with **PowerShell 2.0**
- Uses only built-in .NET Framework classes
- No external dependencies
- Strings processed in UTF8 without BOM
- Logging uses OEM encoding (CP866) for Cyrillic support
- Archive patterns support: {PCName}, {JobName}, {Date}, {Time}, {Date_Time}, {SourceFileName}, {SourceFolderName}

See `Backup_API_Reference.md` for complete details, examples, and additional functions.