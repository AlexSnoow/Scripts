Обновление docs/constitution.md
Создание отдельных файлов:
docs/specify.md - Focus on the what and why, not the tech stack
docs/plan.md - tech stack and architecture choices

Цель
Привести конституцию в соответствие с мультиплатформенной архитектурой (PS 2.0 + Bash 3.0+), поддержкой нескольких архиваторов (RAR, 7zip, PowerShell zip, tar.gz) и 5 типами скриптов (Backup, Copy, Sync, Cleanup, Monitor).
Файлы для изменения
Файл	Действие	Причина
docs/constitution.md	Изменить	Основная цель
README.md	Изменить	Ссылается на "два модуля" с RAR
AGENTS.md	Изменить	Ссылается на "RAR archives", нет Bash sync/cleanup/monitor
docs/patterns/COMMON_FUNCTIONS.md	Создать	Хранилище примеров кода (Write-Log, Send-Email, ...)
docs/DEVELOPMENT_PLAN.md	Отложить	Не входит в текущий спринт, отметить отдельно
docs/PIPELINE_TEMPLATE.md:142	Отложить	Start-RarArchive → Invoke-Archiving, отдельный спринт
ЧАСТЬ A: docs/constitution.md (262 строки → ~310 строк)
A1. Строка 1: Заголовок
БЫЛО:  # Конституция проекта резервного копирования PowerShell
СТАЛО: # Конституция проекта PowerShell Backup Toolkit
A2. Строки 5-8: Раздел 1 "Назначение"
БЫЛО (строка 6):
1.1. Проект реализует сценарии резервного копирования файлов и папок под Windows
с использованием единого монолитного PowerShell-скрипта Backup-ps2-v4.ps1.
Он обеспечивает создание локальных RAR-архивов...

СТАЛО:
1.1. Проект реализует сценарии автоматизации файловых операций (резервное копирование,
копирование, синхронизация, очистка, мониторинг) на двух платформах:
- PowerShell 2.0 (Windows 7+)
- Bash 3.0+ (Linux / Solaris 10+)

Архиваторы: RAR, 7zip, PowerShell zip (Compress-Archive), tar.gz.
Строка 8 — без изменений.
A3. Строка 11: Раздел 2.1 — переименовать
БЫЛО:  ### 2.1. PowerShell 2.0 и совместимость с Windows 7
СТАЛО: ### 2.1. Совместимость платформ
A4. Строки 12-15: Текст раздела 2.1
БЫЛО:
- Весь код должен быть написан на PowerShell и быть 100% совместимым с PowerShell 2.0 и Windows 7.
- Запрещено использовать возможности PS 3.0+ без совместимых альтернатив.
- Использование внешних CLI-утилит (RAR) допускается только через изолированные функции-обёртки.

СТАЛО:
**PowerShell (Windows):**
- Весь код PowerShell должен быть 100% совместимым с PowerShell 2.0 и Windows 7.
- Запрещено использовать возможности PS 3.0+ без совместимых альтернатив.

**Bash (Linux / Solaris):**
- Весь код Bash должен быть совместимым с bash 3.0+ и Solaris 10.
- Запрещено использовать конструкции bash 4+ без fallback: mapfile, readarray, declare -A (associative arrays), process substitution <() без альтернативы.
- На Solaris: избегать регулярных выражений в [[ ... ]] с оператором =~ (нестабильная поддержка).

**Общее:**
- Использование внешних CLI-утилит (RAR, 7zip, tar, gzip) допускается только через изолированные функции-обёртки с чётким интерфейсом.
A5. Строки 17-23: Таблица "Недоступные возможности PS 2.0"
УДАЛИТЬ полностью. Перенести в docs/patterns/COMMON_FUNCTIONS.md.
A6. Строка 31: Раздел 2.3 "DRY"
БЫЛО:  Архитектура проекта: единый монолитный скрипт с внутренними функциями-модулями в регионах (#region).
СТАЛО: Архитектура проекта: монолитный скрипт для каждого типа операции (Backup/Copy/Sync/Cleanup/Monitor).
Общие функции (Write-Log, Send-Email, Remove-OldFiles) вынесены в docs/patterns/COMMON_FUNCTIONS.md
и переиспользуются между скриптами.
A7. Строки 35-37: Раздел 2.4 "SOLID" — примеры функций
БЫЛО:
- Start-RarArchive — только архивация
- Invoke-Verification — только проверка
- Remove-OldFiles — только ротация

СТАЛО:
- Invoke-Archiving — только основная операция (архивация/копирование/синхронизация)
- Invoke-Verification — только проверка
- Remove-OldFiles — только ротация
- Copy-Remote — только копирование в удалённое хранилище
A8. Строка 40: Раздел 2.5 "YAGNI"
БЫЛО:  в конфигурации Backup-Config-All.xml
СТАЛО: в конфигурации скрипта (XML для PS, shell conf для Bash)
A9. После строки 65: Раздел 2.8 — добавить про Bash
ДОБАВИТЬ:
**Для Bash-функций:** обязательный комментарий-описание перед функцией.
Формат: `# Описание: назначение, входы, выходы`.
A10. После строки 72: Раздел 2.9 — добавить про Bash
ДОБАВИТЬ:
**Для Bash:** UTF-8 (LANG=en_US.UTF-8), логи и отчёты в UTF-8.
Кириллица в именах файлов допускается.
A11. Строка 74: Заголовок раздела 3
БЫЛО:  ## 3. Архитектура и структура скрипта
СТАЛО: ## 3. Архитектура проекта
A12. Строки 75-88: Подраздел 3.1 — полная замена
БЫЛО (строка 76): Текущая архитектура: единый скрипт Backup-ps2-v4.ps1 с функциями...
СТАЛО:
### 3.1. Структура проекта

app/
├── ps/
│   ├── backup/    Backup-ps2-g-v4.ps1, Backup-Config.xml
│   ├── copy/      copy-ps2-v4.ps1, Copy-Config.xml
│   ├── sync/      sync-ps-v4.ps1, Sync-Config.xml
│   ├── cleanup/   cleanup-ps2-v4.ps1, Cleanup-Config.xml
│   └── monitor/   monitor-ps2-v4.ps1, Monitor-Config.xml
├── bash/
│   ├── backup-g-v4.sh, backup.conf
│   ├── sync-bash-v4.sh, Sync-Config.conf
│   ├── cleanup-bash-v4.sh, Cleanup-Config.conf
│   └── monitor-bash-v4.sh, Monitor-Config.conf
├── tests/
│   ├── *.Tests.ps1 (Pester)
│   └── *.sh (bash unit)
docs/
├── patterns/COMMON_FUNCTIONS.md
├── PIPELINE_TEMPLATE.md
├── constitution.md
└── ...
A13. Строки 90-97: Подраздел 3.2 — расширить до 5 этапов
БЫЛО (4 этапа):
1. Подготовка элементов — Prepare-ArchiveItems
2. Архивация — Invoke-ArchivePipeline
3. Верификация — Invoke-Verification
4. Пост-операции — Invoke-PostOperations

СТАЛО (5 этапов, англ. названия):
1. Preparation — загрузка конфига, валидация, инициализация
2. Main Operation — профильная операция (архивация/копирование/синхронизация)
3. Verification — проверка результата
4. Post-Operations — ротация, копирование в удалённое хранилище
5. Reporting — отчёты, email

Подробнее: docs/PIPELINE_TEMPLATE.md
A14. Строки 99-105: Подраздел 3.3 — расширить
БЫЛО: три режима (Normal, IndividualFiles, IndividualFolders)
СТАЛО:
**Режимы архивации (PS):**
- Normal — весь источник в один архив
- IndividualFiles — каждый файл отдельный архив
- IndividualFolders — каждая папка отдельный архив

**Режимы архивации (Bash):**
- archive_by_date — группировка по дате
- individual_files — каждый файл отдельно
- individual_folders — каждая папка отдельно
- archive_all — всё рекурсивно

**Режимы синхронизации:**
- incremental — только новые/изменённые файлы
- full — полная копия + удаление лишнего в dest
A15. ДОБАВИТЬ подраздел 3.4 "Совместимость архиваторов"
НОВЫЙ ПОДРАЗДЕЛ:

| Архиватор | Платформа | Тип | Проверка возврата | Проверка целостности |
|-----------|-----------|-----|-------------------|---------------------|
| RAR | PS (Windows) | Внешний | ExitCode -eq 0 | rar t archive |
| 7zip | PS (Windows) | Внешний | .ExitCode -eq 0 | 7z t archive |
| PowerShell zip | PS (Windows) | Встроенный | try/catch | Проверка наличия и размера |
| tar.gz | Bash (Linux/Solaris) | Встроенный | $? -eq 0 | tar -tf + gzip -t |
A16. ДОБАВИТЬ подраздел 3.5 "Типы скриптов"
НОВЫЙ ПОДРАЗДЕЛ:

| Тип | Назначение | PS | Bash |
|-----|-----------|-----|------|
| Backup | Архивация файлов | ✅ | ✅ |
| Copy | Копирование с верификацией | ✅ | — |
| Sync | Синхронизация source↔dest | ✅ | ✅ |
| Cleanup | Удаление по маскам/политикам | ✅ | ✅ |
| Monitor | Проверка системы (диски, пути) | ✅ | ✅ |
A17. ДОБАВИТЬ подраздел 3.6 "Форматы конфигурации"
НОВЫЙ ПОДРАЗДЕЛ:

| Платформа | Формат | Расширение | Корневой тег |
|-----------|--------|------------|--------------|
| PS | XML | {type}-Config.xml | BackupConfig, SyncConfig, CleanupConfig, MonitorConfig |
| Bash | Shell conf (key=value) | {type}-Config.conf | PARENT_JOB_NAME, JOBS, JOB*_SOURCE, ... |
A18. Строка 110: Раздел 4.1 — обобщить
БЫЛО:  1. Архив создаётся локально → проверяется → затем копируется в сеть
СТАЛО: 1. Результат создаётся локально (архив, копия, синхронизация) → проверяется → затем копируется в сеть
A19. Строка 116: Раздел 4.2 — расширить архиваторы
БЫЛО:  - Проверки кода возврата RAR (ExitCode = 0)
СТАЛО: - Проверки кода возврата архиватора (RAR: ExitCode=0, 7zip: .ExitCode=0, tar: $?=0)
A20. Строки 128-131: Раздел 4.4 — уточнить для Bash
ДОБАВИТЬ после строки 131:
Для Bash: лог-файл обязателен, XML/CSV отчёты опциональны.
A21. Строка 137: Раздел 5.1 — уточнить
БЫЛО:  Все ключевые этапы логгируются:
СТАЛО: Все ключевые этапы логируются (для PS — levels INFO/WARNING/ERROR/SUCCESS/DEBUG, для Bash — префиксы [INFO]/[WARN]/[ERROR]/[OK]):
A22. Строка 146-155: Раздел 5.2 — добавить Bash пример
ДОБАВИТЬ после блока try/catch (строка 155):

Для Bash:
set -euo pipefail
log "ERROR: $1"
exit 1
A23. Строка 174: Раздел 6.1 — расширить
БЫЛО:  ### 6.1. XML-конфигурация (единый источник правды)
СТАЛО: ### 6.1. Конфигурация (единый источник правды)
A24. Строка 175: Раздел 6.1 — расширить
БЫЛО:  Файл: Backup-Config-All.xml
СТАЛО: Форматы:
- PS: XML ({type}-Config.xml)
- Bash: Shell conf ({type}-Config.conf, key=value)
A25. Строка 188: Раздел 6.1 — уточнить
БЫЛО:  Все пути, параметры и настройки — только в XML.
СТАЛО: Все пути, параметры и настройки — только в XML/conf (хардкод в скрипте запрещён).
A26. Строка 194: Раздел 6.2 — расширить
БЫЛО:  2. Хеш RAR.exe (RarExeHash в конфиге)
СТАЛО: 2. Хеш внешнего архиватора (RAR: RarExeHash, 7zip: SevenZipHash — в конфиге)
A27. Строка 200: Раздел 6.3 — расширить
БЫЛО:  - RAR.exe (указан в конфиге)
СТАЛО: - RAR.exe, 7z.exe, tar, gzip (внешние утилиты указываются в конфиге)
A28. Строка 219: Раздел 6.5 — расширить
БЫЛО:  - Выполнение: RAR.exe
СТАЛО: - Выполнение: внешний архиватор (RAR/7z/tar)
A29. Строка 224: Раздел 7.1 — расширить
БЫЛО:  - Pester тесты в app/tests/Backup.Tests.ps1
СТАЛО: - Pester тесты в app/tests/*.Tests.ps1, Bash unit тесты в app/tests/*.sh
A30. Строка 225: Раздел 7.1 — уточнить
БЫЛО:  - Покрытие: пустые директории, недоступное хранилище, ошибки RAR
СТАЛО: - Покрытие: пустые директории, недоступное хранилище, ошибки архиватора, корректность конфига
A31. Строка 243: Раздел 7.4 — обновить
БЫЛО:  1. Соответствовать текущей архитектуре (монолит, PS 2.0)
СТАЛО: 1. Соответствовать мультиплатформенной архитектуре (PS 2.0, Bash 3.0+)
A32. Строка 251: Раздел 7.5 — расширить
БЫЛО:  - Добавлять PS 3.0+ возможности без совместимости
СТАЛО: - Добавлять PS 3.0+ возможности без совместимости
- Добавлять Bash 4+ конструкции (mapfile, declare -A, =~) без fallback
A33. Строка 253: Раздел 7.5 — уточнить
БЫЛО:  - Хардкодить пути и настройки (только через XML)
СТАЛО: - Хардкодить пути и настройки (только через XML/conf)
A34. ДОБАВИТЬ пункт в раздел 7.5
НОВЫЙ ПУНКТ:
- Смешивать логику платформ в одном скрипте (PS-скрипт = только PS, Bash-скрипт = только Bash)
A35. ДОБАВИТЬ раздел 8 "Процесс разработки"
НОВЫЙ РАЗДЕЛ (после раздела 7):

## 8. Процесс разработки

### 8.1. Pipeline разработки
Задача → План → Реализация → Тесты → Верификация → Документация

### 8.2. Этапы
1. Определить тип скрипта (Backup/Copy/Sync/Cleanup/Monitor)
2. Определить платформу (PS/Bash/обе)
3. Создать конфигурацию (XML/conf)
4. Реализовать скрипт по docs/PIPELINE_TEMPLATE.md
5. Написать тесты (Pester/bash unit)
6. Проверить testmode
7. Обновить документацию

### 8.3. Чек-лист готовности
- [ ] Скрипт проходит testmode
- [ ] Тесты пройдены
- [ ] Линтер пройден (для PS)
- [ ] Документация обновлена
- [ ] Конфигурация работает на целевой платформе
A36. ДОБАВИТЬ раздел 9 "Паттерны и примеры кода"
НОВЫЙ РАЗДЕЛ (после раздела 8):

## 9. Паттерны и примеры кода

Подробные примеры реализации общих функций (Write-Log, Send-Email,
Remove-OldFiles, Test-FileIntegrity, Get-FileHashCompat и др.)
см. в docs/patterns/COMMON_FUNCTIONS.md.

Паттерны обработки ошибок, логирования и кодировок — там же.
A37. Строка 259: Футер — метаданные
БЫЛО:  **Version**: 3.2 | **Ratified**: 2026-04-12 | **Last Amended**: 2026-04-12
СТАЛО: **Version**: 4.0 | **Ratified**: 2026-04-12 | **Last Amended**: 2026-06-01
A38. Строка 260: Футер — архитектура
БЫЛО:  **Архитектура**: Монолитный скрипт (Backup-ps2-v4.ps1)
СТАЛО: **Архитектура**: Мультиплатформенная (PS 2.0 + Bash 3.0+)
A39. Строка 261: Футер — совместимость
БЫЛО:  **Совместимость**: PowerShell 2.0, Windows 7
СТАЛО: **Совместимость**: PowerShell 2.0 / Windows 7, Bash 3.0+ / Linux / Solaris 10
A40. Строка 262: Футер — архиватор
БЫЛО:  **Архиватор**: RAR (только)
СТАЛО: **Архиваторы**: RAR, 7zip, PowerShell zip, tar.gz
ЧАСТЬ B: README.md (213 строки)
B1. Строка 2: Заголовок
БЫЛО:  # PowerShell Backup Toolkit
СТАЛО: # PowerShell Backup Toolkit — Multi-Platform File Operations
B2. Строки 80-84: Таблица модулей
БЫЛО:
| Backup | app/ps/backup/ | Windows (PS2.0) | Резервное копирование с архиватором RAR |
| Copy   | app/ps/copy/   | Windows (PS2.0) | Обычное копирование без архиватора |
| Backup | app/bash/      | Linux/Solaris   | Резервное копирование с архиватором |

СТАЛО:
| Backup  | app/ps/backup/  | Windows (PS2.0) | Архивация (RAR/7zip/zip) |
| Copy    | app/ps/copy/    | Windows (PS2.0) | Копирование с верификацией |
| Sync    | app/ps/sync/    | Windows (PS2.0) | Синхронизация source↔dest |
| Cleanup | app/ps/cleanup/ | Windows (PS2.0) | Удаление по маскам/политикам |
| Monitor | app/ps/monitor/ | Windows (PS2.0) | Проверка системы |
| Backup  | app/bash/       | Linux/Solaris   | Архивация (tar.gz) |
| Sync    | app/bash/       | Linux/Solaris   | Синхронизация source↔dest |
| Cleanup | app/bash/       | Linux/Solaris   | Удаление по маскам |
| Monitor | app/bash/       | Linux/Solaris   | Проверка системы |
B3. Строки 88-92: Pipeline Backup
БЫЛО:  2. Archiving — Создание RAR-архивов
СТАЛО: 2. Archiving — Создание архивов (RAR/7zip/tar.gz)
B4. Строки 146-155: Режимы архивации
БЫЛО: только PS-режимы
СТАЛО: добавить Bash-режимы (archive_by_date, individual_files, individual_folders, archive_all)
B5. Строки 158-166: Совместимость PS 2.0
БЫЛО: только PS
СТАЛО: добавить "Совместимость с Bash 3.0+" аналогичную таблицу
B6. Строки 184-196: Документация
ДОБАВИТЬ в список:
- docs/PIPELINE_TEMPLATE.md — Шаблон 5-Stage Pipeline
- docs/patterns/COMMON_FUNCTIONS.md — Общие функции и паттерны кода
ЧАСТЬ C: AGENTS.md (92 строки)
C1. Строки 20-23: Bash backup
БЫЛО:  Run backup script (Bash/Linux)
СТАЛО: Run backup script (Bash/Linux/Solaris)
C2. Строки 34-42: Project Structure
ДОБАВИТЬ:
- Sync script: app/ps/sync/sync-ps-v4.ps1
- Sync config: app/ps/sync/Sync-Config.xml
- Cleanup script: app/ps/cleanup/cleanup-ps2-v4.ps1
- Monitor script: app/ps/monitor/monitor-ps2-v4.ps1
- Bash sync: app/bash/sync-bash-v4.sh
- Bash cleanup: app/bash/cleanup-bash-v4.sh
- Bash monitor: app/bash/monitor-bash-v4.sh
C3. Строки 48-51: Backup Pipeline
БЫЛО:  2. Archiving — Creates RAR archives
СТАЛО: 2. Archiving — Creates archives (RAR/7zip/tar.gz)
C4. Строки 70-71: Important Notes
БЫЛО:  - Uses RAR archiver (ensure RAR is installed and in PATH)
СТАЛО: - Uses archiver (RAR, 7zip, or tar.gz — ensure installed and in PATH)
ЧАСТЬ D: docs/patterns/COMMON_FUNCTIONS.md (НОВЫЙ ФАЙЛ)
Содержимое — примеры кода общих функций:
# Common Functions and Code Patterns

## Write-Log
[пример из Backup-ps2-g-v4.ps1 строк 14-22]

## Send-Email
[пример из Backup-ps2-g-v4.ps1 строк 24-81]

## Get-FileHashCompat
[пример из Backup-ps2-g-v4.ps1 строк 191-235]

## Test-FileIntegrity
[пример из Backup-ps2-g-v4.ps1 строк 241-293]

## Remove-OldFiles
[пример из Backup-ps2-g-v4.ps1 строк 354-422]

## Get-DiskSpaceReport
[пример из Backup-ps2-g-v4.ps1 строк 426-457]

## Error Handling Patterns
### PowerShell (try/catch)
[code example]

### Bash (set -euo pipefail + trap)
[code example]

## Encoding Reference
### PowerShell
$Script:EncodingOEM = [System.Text.Encoding]::GetEncoding(866)
$Script:EncodingUTF8NoBOM = New-Object System.Text.UTF8Encoding $false

### Bash
export LANG=en_US.UTF-8

## PS 2.0 Alternatives
[таблица из конституции строк 17-23 — перенесена сюда]
Сводная таблица
Часть	Файл	Кол-во изменений
A	constitution.md	40 изменений (A1-A40)
B	README.md	6 изменений (B1-B6)
C	AGENTS.md	4 изменения (C1-C4)
D	patterns/COMMON_FUNCTIONS.md	1 новый файл
Порядок реализации
1. D — Создать docs/patterns/COMMON_FUNCTIONS.md (нужен для ссылок из конституции)
2. A — Изменить docs/constitution.md (40 изменений)
3. B — Изменить README.md (6 изменений)
4. C — Изменить AGENTS.md (4 изменения)
Отложено (отдельный спринт)
Файл	Что
docs/PIPELINE_TEMPLATE.md:142	Start-RarArchive → Invoke-Archiving
docs/DEVELOPMENT_PLAN.md	Обновить таблицу модулей (5 типов вместо 2)