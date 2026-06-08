# 5-Stage Pipeline Template

Мета-шаблон для создания скриптов с единым конвейером на PowerShell (Windows) и Bash (Linux/Solaris). Охват: Backup, Copy, Sync, Cleanup, Monitor.

## Принципы (из [[../constitution]])
- PS 2.0 совместимость
- KISS — каждый этап = одна функция с single responsibility
- Единый конвейер — нарушение порядка этапов запрещено
- DRY — Write-Log, Send-Email, Remove-OldFiles общие для всех скриптов
- YAGNI — только то, что в конфиге
- Обработка ошибок — try/catch с логированием, запрещён SilentContinue

## Этапы

### 1. Preparation
Загрузка конфигурации, валидация, инициализация окружения, создание директорий.

### 2. Main Operation
Профильная операция: архивация (RAR/7zip/PSZip/tar.gz), копирование, синхронизация (Compare-Object/rsync), очистка, сбор метрик.

### 3. Verification
Проверка целостности результата:
- Backup: код возврата, тест архива, сравнение списков
- Copy: сравнение размеров
- Sync: проверка что все файлы синхронизированы
- Cleanup: проверка удаления
- Monitor: проверка метрик по порогам

### 4. Post-Operations
Ротация (DaysOld/KeepCount), копирование в RemoteDest, перемещение в Arhive, очистка временных файлов.

### 5. Reporting
XML/CSV отчёты, email-уведомления, лог итогов. Выход: exit 0 (успех) / exit 1 (ошибки).

## Схема потока
```
[Preparation] -> [Main Operation] -> [Verification] -> [Post-Operations] -> [Reporting]
```

## Реализация для Sync (эталон)
Скрипт `sync-ps-v4.ps1` содержит полную реализацию шаблона с функциями: `Write-Log`, `Send-Email`, `Get-FileHashCompat`, `Remove-OldFiles`, `Get-DiskSpaceReport`, `Sync-Job`. Поддерживает full/incremental режимы через `Compare-Object`.

## Реализация для Cleanup
Скрипт `cleanup-ps-v4.ps1` с функциями: `Invoke-CleanupJob` (фильтрация по маскам, DaysOld/KeepCount, рекурсивно). TODO: проверка опасных путей, белый список исключений.

## Реализация для Monitor
Скрипт `monitor-ps-v4.ps1` с типами проверок: `FreeSpace`, `PathExists`, `MaxSize`. TODO: проверка процессов, Event Log, служб Windows.

## Bash-аналоги
- `sync-bash-v4.sh` — полный рабочий скрипт (bash 3.0+, Solaris 10)
- `cleanup-bash-v4.sh` — с TODO-маркерами

См. [[common-functions]] для реализации общих функций.
