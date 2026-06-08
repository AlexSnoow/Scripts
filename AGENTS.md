# Backup Toolkit - Agent Guide

## Essential Commands

**Run backup script (PowerShell v2.0):**
```powershell
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\<FileName>-<PSVersion>-<VersionScript>.ps1
```

**Run backup in test mode:**
```powershell
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\<FileName>-<PSVersion>-<VersionScript>.ps1 -testmode
```

**Run copy script (PowerShell v2.0):**
```powershell
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\copy\<FileName>-<PSVersion>-<VersionScript>.ps1
```

**Run backup script (Bash/Linux/Solaris):**
```bash
bash app/bash/<FileName>-<OS Linux/Solaris>-<VersionScript>.sh
```

**Run tests with Pester:**
```powershell
Invoke-Pester .\app\tests\<FileName>.Tests.ps1
```

---

## Project Structure

- **PS Backup script:** `app/ps/backup/<FileName>-<PSVersion>-<VersionScript>.ps1`
- **PS Backup config:** `app/ps/backup/<FileName>-Config.xml`
- **PS Copy script:** `app/ps/copy/<FileName>-<PSVersion>-<VersionScript>.ps1`
- **PS Copy config:** `app/ps/copy/<FileName>-Config.xml`
- **Bash Backup script:** `app/bash/backup/<FileName>-<OS Linux/Solaris>-<VersionScript>.sh`
- **Bash config:** `app/bash/backup/<FileName>.conf`
- **PS Sync script:** `app/ps/sync/<FileName>-<PSVersion>-<VersionScript>.ps1`
- **PS Sync config:** `app/ps/sync/<FileName>-Config.xml`
- **Bash Sync script:** `app/bash/<FileName>-<OS Linux/Solaris>-<VersionScript>.sh`
- **Bash Sync config:** `app/bash/sync/<FileName>.conf`
- **Tests:** `app/tests/` - Pester framework, Bash scripts for tests
- **Documentation:** `docs/` - all Documentation for project
- **User Raw Notes:** `docs/raw/` - user Notes for Documentation
- **Knowledge base:** `docs/wiki/` - Knowledge base. Managed and formatted exclusively by the agent.
- **Knowledge map:** `docs/wiki/index.md` - Main knowledge map of the project.
- **Log Knowledge:** `docs/wiki/log.md`- A log of your automatic edits.
- **Dev plan:** `docs/DEVELOPMENT_PLAN.md`
- **Process diagrams:** `docs/diagrams/`

---

## Pipeline Stages

The script executes a single 5-stage pipeline for all file processing modes:

1. **Preparation** — Scans sources, checks files by masks
2. **Processing ** — Main file processing mode: Creates archives (RAR/7zip/tar.gz), Copy files
3. **Verification** — Validates archive integrity (including 0-byte files)
4. **Post-Operations** — Copy to network storage, rotation, cleanup
5. **Reporting** — XML/CSV reports + email

## Important Notes

- **PowerShell 2.0 compatibility required** — Windows 7 compatible
- Uses archiver (RAR, 7zip, or tar.gz — ensure installed and in PATH)
- Configuration XML defines backup jobs, paths, and retention policies
- Test mode runs verification without actual file operations
- Archive patterns support: `{PCName}`, `{JobName}`, `{Date}`, `{Time}`, `{Date_Time}`, `{SourceFileName}`, `{SourceFolderName}`
- Copy module does NOT use archiver — it moves verified files to Arhive directory

---

## Development Plan

See `docs/DEVELOPMENT_PLAN.md` for the complete project roadmap.

### Current priorities:

| Priority | Task | Status |
|----------|------|--------|
| P0 | Email notifications for Copy module | ⏳ |
| P0 | Bash analog for Copy module | ⏳ |
| P1 | File masks support in Copy | ⏳ |
| P1 | Archive rotation in Copy | ⏳ |
| P2 | Unified configuration schema | ⏳ |
| P2 | Pester tests for Copy module | ⏳ |