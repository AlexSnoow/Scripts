# PowerShell 2.0 — Справочник по совместимости

## Обзор

Скрипт `Backup-ps2-v4.ps1` разработан для **PowerShell 2.0** и совместим с **Windows 7**.

---

## Ограничения PowerShell 2.0

### Недоступные возможности

| Возможность | PS 2.0 | PS 5.1+ | Альтернатива в скрипте |
|-------------|--------|---------|------------------------|
| `[System.IO.File]::WriteAllLines()` | ✅ | ✅ | Используется |
| `Get-FileHash` | ❌ | ✅ | `Get-FileHashCompat` |
| `[string]::IsNullOrWhiteSpace()` | ❌ | ✅ | `Test-StringIsNullOrWhiteSpace` |
| `ConvertFrom-Json` | ❌ | ✅ | XML вместо JSON |
| `Export-Csv -Encoding` | Ограничено | ✅ | Явное указание UTF8 |
| `New-Object System.Text.UTF8Encoding` | ✅ | ✅ | Используется |
| `PSCustomObject` | ❌ | ✅ | `New-Object PSObject` |
| `Try-Catch-Finally` | ✅ | ✅ | Используется |
| `Pipeline` | ✅ | ✅ | Используется |

---

## Паттерны совместимости

### 1. Вычисление хеша файла

**PS 5.1+:**
```powershell
$hash = Get-FileHash -Path "file.exe" -Algorithm SHA256
```

**PS 2.0 (используется в скрипте):**
```powershell
function Get-FileHashCompat {
    param([string]$Path, [string]$Algorithm = 'SHA256')
    $hashAlgo = [System.Security.Cryptography.SHA256]::Create()
    $fileStream = [System.IO.File]::OpenRead($Path)
    $hashBytes = $hashAlgo.ComputeHash($fileStream)
    $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
    return @{ Hash = $hashString.ToUpper(); Algorithm = $Algorithm; Path = $Path }
}
```

### 2. Проверка пустой строки

**PS 5.1+:**
```powershell
if ([string]::IsNullOrWhiteSpace($value)) { ... }
```

**PS 2.0 (используется в скрипте):**
```powershell
function Test-StringIsNullOrWhiteSpace {
    param([string]$Value)
    if ($Value -eq $null) { return $true }
    if ($Value -eq '') { return $true }
    if ($Value -match '^\s*$') { return $true }
    return $false
}
```

### 3. Создание объектов

**PS 5.1+:**
```powershell
$obj = [PSCustomObject]@{ Name = "Value" }
```

**PS 2.0 (используется в скрипте):**
```powershell
$obj = New-Object PSObject -Property @{ Name = "Value" }
```

### 4. Кодировка файлов

**В скрипте:**
```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
```

---

## Кодировки в скрипте

### OEM (CP866) — для логов

```powershell
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
```

**Применение:** Лог-файлы RAR, консольный вывод

### UTF8 без BOM — для отчётов

```powershell
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
```

**Применение:** XML, CSV, JSON отчёты

---

## Работа с XML

### Загрузка

```powershell
[xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
$b = $xmlDoc.BackupConfig
```

### Чтение узлов

```powershell
foreach ($jobNode in $b.Jobs.Job) {
    $name = $jobNode.Name
    $source = $jobNode.Source
}
```

### Чтение массивов

```powershell
$ap = @()
foreach ($p in $jobNode.ArhParameters.Param) { $ap += $p }
```

---

## Работа с процессами

### Запуск внешнего процесса

```powershell
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $RarPath
$psi.Arguments = $argsList -join ' '
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$process.Start() | Out-Null
$process.WaitForExit()
$exitCode = $process.ExitCode
```

---

## Обработка исключений

### Try-Catch-Finally

```powershell
try {
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $hashBytes = $hashAlgo.ComputeHash($fileStream)
}
catch {
    throw "Ошибка: $($_.Exception.Message)"
}
finally {
    $fileStream.Dispose()
}
```

### ErrorAction

```powershell
New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop
```

---

## Сетевые операции

### Проверка сетевого пути

```powershell
if (Test-Path -LiteralPath $targetPath -PathType Container) {
    # Путь существует
}
```

### Создание сетевой папки

```powershell
if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
    New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
```

---

## EventLog

### Проверка существования источника

```powershell
if (-not ([System.Diagnostics.EventLog]::SourceExists($Source))) {
    Write-Log "EventLog: источник '$Source' не зарегистрирован." -Level WARNING
    return
}
```

### Запись события

```powershell
$eventLog = New-Object System.Diagnostics.EventLog('Application')
$eventLog.Source = $Source
$eventLog.WriteEntry($MessageText, [System.Diagnostics.EventLogEntryType]::Information, 3001)
```

---

## SMTP отправка (CDO.Message)

```powershell
$msg = New-Object -ComObject CDO.Message
$msg.From = "from@domain.loc"
$msg.To = "to@domain.loc"
$msg.Subject = "Subject"
$msg.TextBody = "Body text"

$cfg = $msg.Configuration
$cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserver") = "smtp.domain.loc"
$cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = 25
$cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
$cfg.Fields.Update()

$msg.Send()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($msg) | Out-Null
```

---

## Переменные окружения

```powershell
$PCName = $env:COMPUTERNAME
$PSModulePath = $env:PSModulePath
```

---

## Даты и время

### Форматирование

```powershell
Get-Date -Format 'yyyyMMdd_HHmmss'      # 20260412_205449
Get-Date -Format 'yyyy-MM-dd HH:mm:ss'  # 2026-04-12 20:54:49
Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'  # 2026-04-12T20:54:49 (ISO 8601)
```

### Вычитание дней

```powershell
$cutoffDate = (Get-Date).AddDays(-7)
```

### Разница во времени

```powershell
$duration = [math]::Round(($processEnd - $processStart).TotalMinutes, 2)
```

---

## Файловая система

### Получение размера файла

```powershell
$size = (Get-Item -LiteralPath $filePath).Length
$sizeMB = [math]::Round($size / 1MB, 2)
```

### Рекурсивный список файлов

```powershell
$items = Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue |
         Where-Object { -not $_.PSIsContainer }
```

### Исключение символических ссылок

```powershell
$items = $items | Where-Object {
    -not ($_.Attributes.Value -band [System.IO.FileAttributes]::ReparsePoint)
}
```

---

## Массивы и хеш-таблицы

### Создание массива

```powershell
$files = @()
$files += $item
```

### Хеш-таблица

```powershell
$hash = @{
    Key1 = "Value1"
    Key2 = "Value2"
}
```

### Проверка наличия ключа

```powershell
if ($hash.ContainsKey($key)) { ... }
```

---

## Строковые операции

### Замена

```powershell
$safeName = $name -replace '[\\/:*?"<>|]', '-'
```

### Склеивание

```powershell
$logEntry = "[$timestamp] $levelPrefix $safeMessage"
$report = ($entries -join "`r`n")
```

### Проверка начала строки

```powershell
if ($lowerFull.StartsWith($lowerRoot)) { ... }
```

---

## Лучшие практики для PS 2.0

1. **Всегда указывайте типы параметров** — `[string]`, `[int]`, `[bool]`
2. **Используйте `-LiteralPath`** вместо `-Path` для путей с спецсимволами
3. **Явно указывайте кодировку** — `UTF8Encoding $false` для UTF8 без BOM
4. **Dispose ресурсов** — вызывайте `.Dispose()` для файловых потоков
5. **ErrorAction Stop** — для критических операций в try-catch
6. **Where-Object вместо Where** — полная совместимость
7. **New-Object PSObject** — вместо PSCustomObject
8. **XML вместо JSON** — ConvertFrom-Json недоступен в PS 2.0

---

## Отладка

### Write-Verbose

```powershell
Write-Verbose "Отладочное сообщение"
```

Запуск с `-Verbose`:
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\Backup-ps2-v4.ps1 -Verbose
```

### Write-Debug

```powershell
Write-Debug "Детали: $variable"
```

### Write-Warning

```powershell
Write-Warning "Предупреждение"
```

---

## Запуск скрипта

### Прямой запуск

```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-v4.ps1
```

### С тестовым режимом

```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-v4.ps1 -testmode
```

### Из PowerShell 5.1+

```powershell
& powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-v4.ps1
```

---

## См. также

- [README.md](README.md) — Общая документация
- [Backup_Config_Reference.md](Backup_Config_Reference.md) — Конфигурация
- [Backup_API_Reference.md](Backup_API_Reference.md) — API функций
