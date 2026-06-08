# Common Functions

Функции, переиспользуемые между скриптами Backup и Copy.

## Write-Log
```powershell
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $Message -or -not $script:GlobalLog) { return }
    $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " [" + $Level + "] " + $Message
    Add-Content -Path $script:GlobalLog -Value $line -ErrorAction SilentlyContinue
}
```

## Send-Email (через Net.Mail.SmtpClient)
Параметры: `$Config`, `$SmtpServer`, `$From`, `$To`, `$Subject`, `$Body`, `$Port` (default 25), `$UseSSL`. Если не указаны — берутся из `$Config`. Возвращает `[bool]`.

## Get-FileHashCompat
Вычисляет SHA256 (и др.) через .NET. Параметры: `-Path`/`-LiteralPath`, `-Algorithm` (SHA1|SHA256|SHA384|SHA512|MD5). Возвращает `[PSObject]` с `Hash`, `Algorithm`, `Path`.

См. [[ps2-compatibility]] для деталей.

## Test-FileIntegrity
Проверяет файл по SHA256 хешу. Параметры: `$FilePath`, `$ExpectedHash`, `$FileType`. Возвращает `[bool]`. Валидирует формат хеша (64 hex символа).

## Remove-OldFiles
Ротация файлов по DaysOld и KeepCount. Параметры: `$Path`, `$DaysOld`, `$KeepCount`, `$Filter`. Приоритет: KeepCount > DaysOld. Поддерживает `-WhatIf`.

Алгоритм:
1. Сортировка файлов по LastWriteTime (DESC)
2. KeepCount первых файлов сохраняются всегда
3. Остальные удаляются если старше DaysOld

## Get-DiskSpaceReport
Собирает информацию о всех жёстких дисках > 1 GB. Возвращает строку вида: `"Drive C Total(GB)=500.0 Free(GB)=150.5 Free=30.1%"`.

## Error Handling
**PowerShell:**
```powershell
try { ... }
catch { Write-Log "Error: $($_.Exception.Message)" -Level ERROR; throw }
```

**Bash:**
```bash
set -euo pipefail
trap 'log "ERROR on line $LINENO"' ERR
```

## PS 2.0 Совместимость
См. [[ps2-compatibility]] для полного списка ограничений и альтернатив.
