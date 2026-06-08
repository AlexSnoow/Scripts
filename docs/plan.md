# Plan — Технологический стек и архитектура

> **Version**: 2.0 | **Date**: 2026-06-08
>
> Этот файл описывает техническую архитектуру проекта: структуру файлов, pipeline, режимы работы, форматы конфигурации и требования к платформам.
> Доменные инварианты — `docs/specify.md` [[specify.md]], руководящие принципы — `docs/constitution.md` [[constitution]], план развития — `docs/roadmap.md` [[roadmap]].

## 1. Архитектура проекта

### 1.1. Структура проекта

Актуальная структура проекта — [[structure.md]] (обновляется при изменениях).

### 1.2. Unified Pipeline (5 этапов)

**Обязательный порядок выполнения:**
1. **Preparation** — загрузка конфига, валидация, инициализация
2. **Main Operation** — профильная операция (архивация/копирование/синхронизация)
3. **Verification** — проверка результата
4. **Post-Operations** — ротация, копирование в удалённое хранилище
5. **Reporting** — отчёты, email

Подробнее: [[wiki\pipeline-template]] (шаблон в базе знаний).

Нарушение порядка **запрещено**.

### 1.3. Режимы обработки файлов

**Режимы PS и Bash формирования списка файлов для обработки:**
- ByDate — группировка по дате LastWriteTime, файлы с одинаковой датой в одну операцию (архив/копирование). Исключение: файлы с текущей датой не обрабатываются.
- IndividualFiles — каждый файл из источника по маске обрабатывается отдельно (например `file.log.20*`)
- IndividualFolders — каждый каталог в источнике обрабатывается отдельно. Исключение: каталог с текущей датой.
- All — все файлы и каталоги рекурсивно в единую операцию.

### 1.4. Совместимость архиваторов

| Архиватор      | Платформа            | Тип        | Проверка возврата | Проверка целостности       |
| -------------- | -------------------- | ---------- | ----------------- | -------------------------- |
| RAR            | PS (Windows)         | Внешний    | ExitCode -eq 0    | rar t archive              |
| 7zip           | PS (Windows)         | Внешний    | .ExitCode -eq 0   | 7z t archive               |
| PowerShell zip | PS5.1+ (Windows)     | Встроенный | try/catch         | Проверка наличия и размера |
| tar.gz         | Bash (Linux/Solaris) | Встроенный | $? -eq 0          | tar -tf + gzip -t          |

### 1.5. Типы скриптов (фактическое состояние)

| Тип    | Назначение                 | PS   | Bash | Статус                                 |
| ------ | -------------------------- | ---- | ---- | -------------------------------------- |
| Backup | Архивация файлов           | ✅ v6 | ✅ v4 | Работает                               |
| Copy   | Копирование с верификацией | ✅ v4 | —    | Работает, нужны: email, маски, ротация |

### 1.6. Форматы конфигурации

| Платформа | Формат                 | Расширение         | Корневой тег/ключи                      |
| --------- | ---------------------- | ------------------ | --------------------------------------- |
| PS        | XML                    | {type}-Config.xml  | BackupConfig, CopyConfig                |
| Bash      | Shell conf (key=value) | {type}-Config.conf | PARENT_JOB_NAME, JOBS, JOB*_SOURCE, ... |

## 2. Технологический стек

### 2.1. Платформы

| Платформа  | Версия                                               | ОС                 |
| ---------- | ---------------------------------------------------- | ------------------ |
| PowerShell | 2.0 (базовый синтаксис скриптов)                     | Windows 7+         |
| PowerShell | 5.1+ (для Compress-Archive при `ArchiverType=PSZip`) | Windows 10+        |
| Bash       | 3.0+                                                 | Linux, Solaris 10+ |

### 2.2. Архиваторы

| Инструмент       | Платформа     | Тип                    |
| ---------------- | ------------- | ---------------------- |
| RAR.exe          | Windows       | Внешняя CLI-утилита    |
| 7z.exe           | Windows       | Внешняя CLI-утилита    |
| Compress-Archive | Windows       | Встроенный (PS5.1+)    |
| tar + gzip       | Linux/Solaris | Встроенные CLI-утилиты |

### 2.3. Инструменты тестирования

- PowerShell: Pester
- Bash: shell unit-тесты (bash unit / bats)

### 2.4. Кодировки

- PowerShell: CP866 (логи), UTF-8 без BOM (отчёты)
- Bash: UTF-8 (LANG=en_US.UTF-8)

## 3. Стандарты оформления кода

### 3.1. Comment-based help

**Для PowerShell (PS 2.0):** каждая публичная функция обязана содержать блок help:
```powershell
<#
.SYNOPSIS
    Краткое описание (одна строка)
.DESCRIPTION
    2-5 строк с основными сценариями
.PARAMETER Name
    Описание параметра
.EXAMPLE
    Get-Function -Param "Value"
#>
```
**Минимум:** `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`

**Для Bash-функций:** обязательный комментарий-описание перед функцией.
Формат: `# Описание: назначение, входы, выходы`.

### 3.2. Работа с кодировками и русскими символами

**Для PowerShell:**
- **Логи (OEM/CP866):** `$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)`
- **Отчёты (UTF8 без BOM):** `$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false`

**Для Bash:** UTF-8 (LANG=en_US.UTF-8), логи и отчёты в UTF-8.

Кириллица в именах файлов допускается.

## 4. Качество, тестирование и эволюция

### 4.1. Тестирование
**Обязательно:**
- Pester тесты в app/tests/*.Tests.ps1, Bash unit тесты в app/tests/*.sh
- Покрытие: пустые директории, недоступное хранилище, ошибки архиватора, корректность конфига

### 4.2. Линтер
**Обязательная проверка:**
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\PS_linter.ps1
```

### 4.3. Тестовый режим
**Всегда доступен:**
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\ps\backup\backup-ps2-v6.ps1 -testmode
```

Проверяет: архиватор, источники, права записи, SMTP.

### 4.4. Эволюция архитектуры
Все изменения должны:
1. Соответствовать мультиплатформенной архитектуре (PS 2.0, Bash 3.0+)
2. Не нарушать доменные инварианты
3. Фиксироваться с мотивацией

### 4.5. Ограничения для AI-агента
**AI-агенту ЗАПРЕЩЕНО:**
- Отключать логирование и обработку ошибок
- Нарушать порядок Unified Pipeline
- Добавлять PS 3.0+ возможности без совместимости
- Добавлять Bash 4+ конструкции (mapfile, declare -A, =~) без fallback
- Добавлять внешние зависимости без явного запроса
- Хардкодить пути и настройки (только через XML/conf)
- Смешивать логику платформ в одном скрипте (PS-скрипт = только PS, Bash-скрипт = только Bash)

**При неоднозначности выбирать:** KISS, PS 2.0 совместимость, безопасность данных.

## 5. Процесс разработки

### 5.1. Pipeline разработки
Задача → План → Реализация → Тесты → Верификация → Документация

### 5.2. Этапы
1. Определить тип скрипта (Backup/Copy)
2. Определить платформу (PS/Bash/обе)
3. Создать конфигурацию (XML/conf)
4. Реализовать скрипт по [[wiki\pipeline-template]]
5. Написать тесты (Pester/bash unit)
6. Проверить testmode
7. Обновить документацию

### 5.3. Чек-лист готовности
- [ ] Скрипт проходит testmode
- [ ] Тесты пройдены
- [ ] Линтер пройден (для PS)
- [ ] Документация обновлена
- [ ] Конфигурация работает на целевой платформе

## 6. Паттерны и примеры кода

### 6.1. Паттерны обработки ошибок

#### PowerShell v2.0: try/catch

`try/catch/finally` введены в PowerShell v2.0 и **гарантированно работают** на Windows 7 (PS v2.0 — системный компонент по умолчанию). В PS v1.0 этих конструкций не было (использовались только `trap`).

**Важно:** `try/catch` перехватывает **только прерывающие ошибки** (terminating errors). Большинство командлетов по умолчанию генерируют непрерывающие ошибки (выводят красную строку, но продолжают работу) — `catch` их **проигнорирует**.

**Вариант 1 — Глобальный (рекомендуется для скриптов):**
```powershell
$ErrorActionPreference = "Stop"
try {
    # Любая ошибка гарантированно попадёт в catch
    Get-Item -Path "C:\НесуществующийФайл.txt"
}
catch {
    Write-Log "Ошибка: $($_.Exception.Message)" -Level ERROR
    throw
}
```

**Вариант 2 — Локальный (для конкретного командлета):**
```powershell
try {
    Get-Content -Path "C:\Data.txt" -ErrorAction Stop
}
catch {
    Write-Log "Не удалось прочитать файл: $($_.Exception.Message)" -Level ERROR
    throw
}
```

**Проверка версии PS на целевой машине:**
```powershell
$PSVersionTable.PSVersion  # Major >= 2 — try/catch работает
```

#### Bash: обработка ошибок
```bash
set -euo pipefail
log "ERROR: $1"
exit 1
```

Подробнее: [[wiki\common-functions]].

### 6.2. Общие функции (переиспользуемые во всех скриптах)

Все функции совместимы с PS 2.0. Полные примеры — см. [[wiki\common-functions]].

| Функция | Назначение | Входы | Выход |
|---------|-----------|-------|-------|
| `Write-Log` | Запись в лог-файл | `$Message`, `$Level` | void |
| `Send-Email` | Отправка email через SMTP | `$Config`, `$Subject`, `$Body` | `[bool]` |
| `Get-FileHashCompat` | SHA256 через .NET (PS 2.0) | `$Path`, `$Algorithm` | `[PSObject]` |
| `Test-FileIntegrity` | Проверка хеша файла | `$FilePath`, `$ExpectedHash` | `[bool]` |
| `Remove-OldFiles` | Ротация по DaysOld/KeepCount | `$Path`, `$DaysOld`, `$KeepCount` | `[string]` |
| `Get-DiskSpaceReport` | Информация о дисках | `$ComputerName` | `[string]` |
| `Test-Empty` | Проверка null/пустой строки | `$s` | `[bool]` |
| `To-Bool` | Конвертация в boolean | `$v` | `[bool]` |

### 6.3. Паттерны реализации

#### Инициализация кодировок (PS 2.0 safe)
```powershell
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false
```
Логи — CP866 (OEM) для совместимости с консолью Windows. Отчёты — UTF-8 без BOM.

#### Кэширование конфигурации
```powershell
[xml]$script:Config = Get-Content $ConfigPath
$script:General    = $script:Config.BackupConfig.General
$script:Paths      = $script:Config.BackupConfig.Paths
$script:Recipients = $script:Config.BackupConfig.Recipients
```
Все пути и настройки читаются из XML **один раз** в начале, далее используются через script-level переменные.

#### Контекст задания ($ctx)
```powershell
$ctx = @{
    Config   = $Config
    Job      = $Job
    JobName  = $Job.Name
    Source   = $Job.Source
    Dest     = $Job.LocalDest
    # ... стандартные ключи
}
```
Хештаблица контекста передаётся между функциями. Стандартные ключи:
- `Config`, `Job`, `JobName` — конфигурация
- `Source`, `Dest` — пути
- `RemoteDest` — удалённое хранилище (опционально)

#### Быстрое сканирование файлов (PS 2.0 optimized)
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
Использует .NET `System.IO.DirectoryInfo` вместо `Get-ChildItem` — быстрее в PS 2.0.

#### Разрешение имён с плейсхолдерами
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
Поддерживаемые плейсхолдеры: `{PCName}`, `{JobName}`, `{Date}`, `{LastWriteTime}`, `{SourceFileName}`, `{SourceFolderName}`, `{arhiveExt}`.

#### Тестовый режим
```powershell
function Invoke-TestMode {
    param($Config)
    # Проверка: источники, назначения, права записи, архиватор
    # Без реальных операций — только валидация
    # Отправка email с результатом
}
```
Проверяет: существование каталогов, права на запись, целостность архиватора. Выход: `exit 0` (OK) / `exit 1` (ошибки).

#### Runner задания
```powershell
function Invoke-Job {
    param($Config, $Job)
    # Stage 1: Preparation
    # Stage 2-4: Processing + Verification + Post-Operations
    # Stage 5: Reporting
    return @{ Errors = $checkErrors; Log = $jobLog }
}
```
Каждое задание выполняется через `Invoke-Job`. Возвращает хештаблицу с `Errors` (int) и `Log` (array).

### 6.4. Паттерны общих функций

Подробные примеры реализации общих функций (Write-Log, Send-Email,
Remove-OldFiles, Test-FileIntegrity, Get-FileHashCompat и др.)
см. в [[wiki\common-functions]].
