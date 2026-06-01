# PowerShell Backup Toolkit - Agent Guide

## Essential Commands

**Run backup script (PowerShell):**
```powershell
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\Backup-ps2-g-v4.ps1
```

**Run backup in test mode:**
```powershell
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\Backup-ps2-g-v4.ps1 -testmode
```

**Run copy script (PowerShell):**
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\ps\copy\copy-ps2-v4.ps1 -ConfigurationPath .\app\ps\copy\Copy-Config.xml
```

**Run backup script (Bash/Linux):**
```bash
bash app/bash/backup-g-v4.sh
```

**Run tests with Pester:**
```powershell
Invoke-Pester .\app\tests\Backup.Tests.ps1
```

---

## Project Structure

- **Backup script:** `app/ps/backup/Backup-ps2-g-v4.ps1`
- **Backup config:** `app/ps/backup/Backup-Config.xml`
- **Copy script:** `app/ps/copy/copy-ps2-v4.ps1`
- **Copy config:** `app/ps/copy/Copy-Config.xml`
- **Bash backup:** `app/bash/backup-g-v4.sh`
- **Bash config:** `app/bash/backup.conf`
- **Tests:** `app/tests/` (Pester framework)
- **Documentation:** `docs/`
- **Dev plan:** `docs/DEVELOPMENT_PLAN.md`

---

## Backup Pipeline Stages

The script executes a unified 5-stage pipeline for all backup modes:

1. **Preparation** — Scans sources, checks files by masks
2. **Archiving** — Creates RAR archives (single mechanism `Invoke-ArchivePipeline`)
3. **Verification** — Validates archive integrity (including 0-byte files)
4. **Post-Operations** — Copy to network storage, rotation, cleanup
5. **Reporting** — XML/CSV reports + email

## Copy Pipeline Stages

The copy script executes a unified pipeline for copying:

1. **Preparation** — Load XML config, validate Jobs section
2. **Copying** — Copy each file from Source to RemoteDest
3. **Verification** — Integrity check (size comparison)
4. **Archive** — Move verified file to Arhive directory
5. **Reporting** — Generate XML report

---

## Important Notes

- **PowerShell 2.0 compatibility required** — Windows 7 compatible
- Uses RAR archiver (ensure RAR is installed and in PATH)
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