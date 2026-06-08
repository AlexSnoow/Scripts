# Common Functions

Функции, переиспользуемые между скриптами Backup, Copy и другими модулями.

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

## Test-Empty
Проверка на null или пустую строку:
```powershell
function Test-Empty {
    param([string]$s)
    return ($s -eq $null -or $s.Trim().Length -eq 0)
}
```

## To-Bool
Конвертация значения в boolean (case-insensitive "true"/"false"):
```powershell
function To-Bool {
    param($v)
    if ($v -eq $null) { return $false }
    return ($v.ToString().ToLower() -eq "true")
}
```

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

## Get-FilesFast / Get-FoldersFast
Быстрое сканирование файлов через .NET `System.IO.DirectoryInfo` (оптимизация для PS 2.0):
```powershell
function Get-FilesFast {
    param($Path, $Filter)
    $list = New-Object System.Collections.ArrayList
    $dir = New-Object System.IO.DirectoryInfo($Path)
    foreach ($f in $dir.GetFiles($Filter)) {
        [void]$list.Add($f)
    }
    return $list
}
```
Быстрее `Get-ChildItem` в PS 2.0.

## Resolve-Name
Разрешение имён с плейсхолдерами:
```powershell
function Resolve-Name {
    param($Pattern, $PC, $Job, $Date, $Name)
    $r = $Pattern
    $r = $r -replace "{PCName}", $PC
    $r = $r -replace "{JobName}", $Job
    $r = $r -replace "{Date}", $Date
    $r = $r -replace '[\\/:*?"<>|]', '_'
    return $r
}
```
Плейсхолдеры: `{PCName}`, `{JobName}`, `{Date}`, `{LastWriteTime}`, `{SourceFileName}`, `{SourceFolderName}`, `{arhiveExt}`.

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
