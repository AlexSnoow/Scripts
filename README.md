# PowerShell Backup Toolkit — Multi-Platform File Operations

**Набор скриптов резервного и обычного копирования файлов. PowerShell 2.0, Linux, Solaris.**

---

## Быстрый старт

### PowerShell (Windows)

```powershell
# Резервное копирование с архиватором RAR
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\Backup-ps2-g-v4.ps1

# Тестовый режим (без реальных операций)
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\Backup-ps2-g-v4.ps1 -testmode

# Обычное копирование без архиватора
powershell.exe -executionpolicy RemoteSigned -file .\app\ps\copy\copy-ps2-v4.ps1 -ConfigurationPath .\app\ps\copy\Copy-Config.xml
```

### Bash (Linux / Solaris)

```bash
# Резервное копирование с архиватором
bash app/bash/backup-g-v4.sh

# Тестовый режим
bash app/bash/backup-g-v4.sh --testmode
```

---

## Структура проекта

```
Scripts/
├── app/
│   ├── ps/
│   │   ├── backup/          # PowerShell — резервное копирование с архиватором
│   │   │   ├── Backup-ps2-g-v4.ps1    # Текущая версия (основная)
│   │   │   ├── Backup-ps2-g-v3.ps1    # Предыдущая версия
│   │   │   ├── Backup-ps2-g-v2.ps1    # Предыдущая версия
│   │   │   ├── Backup-ps2-g-v1.ps1    # Предыдущая версия
│   │   │   ├── Backup-Config.xml      # Конфигурация резервного копирования
│   │   │   └── Backup-StatusView.ps1  # Просмотр статуса backup
│   │   └── copy/            # PowerShell — обычное копирование без архиватора
│   │       ├── copy-ps2-v4.ps1          # Текущая версия (основная)
│   │       └── Copy-Config.xml          # Конфигурация копирования
│   └── bash/
│       ├── backup-g-v4.sh           # Текущая версия (основная, Linux/Solaris)
│       ├── backup-g-v3.sh           # Предыдущая версия
│       ├── backup-g-v2.sh           # Предыдущая версия
│       ├── backup-g-v1.sh           # Предыдущая версия
│       ├── backup.conf              # Конфигурация bash-скриптов
│       └── info.md                  # Описание bash-скриптов
├── docs/
│   ├── Backup_info.md              # Обзор резервного копирования
│   ├── PowerShell_info.md          # Совместимость с PS 2.0
│   ├── Backup_Config_Reference.md  # Справочник XML-конфигурации
│   ├── Backup_API_Reference.md     # API справочник функций (англ.)
│   ├── Backup_shema.md             # Диаграммы процесса (Mermaid/PlantUML)
│   ├── BACKUP_PIPELINE_OVERVIEW.md # Диаграммы 5-этапного пайплайна
│   ├── REFactoring-NOTES.md        # Примечания по рефакторингу
│   ├── FUNCTIONS_REFERENCE.md      # English function reference
│   ├── constitution.md             # Team constitution
│   └── copy/                       # Документация по модулю copy
│       ├── README.md               # Обзор модуля копирования
│       └── REFactoring-NOTES.md    # Примечания по копированию
├── README.md                      # Этот файл
└── AGENTS.md                      # Инструкция для AI-агентов
```

---

## Архитектура

### Модули

| Модуль | Каталог | Платформы | Назначение |
|--------|---------|-----------|------------|
| **Backup**  | `app/ps/backup/`  | Windows (PS2.0) | Архивация (RAR/7zip/zip) |
| **Copy**    | `app/ps/copy/`    | Windows (PS2.0) | Копирование с верификацией |
| **Sync**    | `app/ps/sync/`    | Windows (PS2.0) | Синхронизация source↔dest |
| **Cleanup** | `app/ps/cleanup/` | Windows (PS2.0) | Удаление по маскам/политикам |
| **Monitor** | `app/ps/monitor/` | Windows (PS2.0) | Проверка системы |
| **Backup**  | `app/bash/`       | Linux/Solaris   | Архивация (tar.gz) |
| **Sync**    | `app/bash/`       | Linux/Solaris   | Синхронизация source↔dest |
| **Cleanup** | `app/bash/`       | Linux/Solaris   | Удаление по маскам |
| **Monitor** | `app/bash/`       | Linux/Solaris   | Проверка системы |

### 5-этапный пайплайн (Backup)

1. **Preparation** — Сканирование источников, проверка файлов по маскам
2. **Archiving** — Создание архивов (RAR/7zip/tar.gz) (единый механизм `Invoke-ArchivePipeline`)
3. **Verification** — Проверка целостности архивов
4. **Post-Operations** — Копирование в сетное хранилище, ротация, удаление
5. **Reporting** — XML/CSV отчёты, отправка email

### Цикл работы (Copy)

1. **Preparation** — Чтение XML-конфигурации, инициализация
2. **Copying** — Копирование каждого файла из Source в RemoteDest
3. **Verification** — Проверка целостности (сравнение размеров)
4. **Archive** — Перемещение проверенного файла в Arhive
5. **Reporting** — Формирование отчёта `reports_YYYYMMDD.xml`

---

## Конфигурация

### Backup (Backup-Config-All.xml / app/ps/backup/Backup-Config.xml)

```xml
<BackupConfig>
  <General>
    <ArchiverType>RAR</ArchiverType>
    <PCName>PC001</PCName>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Jobs>
    <Job Name="JOB1">
      <Source>C:\WORK\BackupAllXml\src\JOB1\</Source>
      <LocalDest>C:\WORK\BackupAllXml\dst\local</LocalDest>
      <RemoteDest>\\server\share\dst\JOB1</RemoteDest>
      <ArchivePattern>{PCName}_{JobName}_{Date_Time}.rar</ArchivePattern>
      ...
    </Job>
  </Jobs>
</BackupConfig>
```

### Copy (app/ps/copy/Copy-Config.xml)

```xml
<CopyConfig>
  <General>
    <ParentJobName>CopyAllXml</ParentJobName>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Jobs>
    <Job Name="JOB1">
      <Source>C:\WORK\CopyAllXml\src\JOB1\</Source>
      <RemoteDest>C:\WORK\CopyAllXml\dst\</RemoteDest>
      <Arhive>C:\WORK\CopyAllXml\dst\arc\</Arhive>
    </Job>
  </Jobs>
</CopyConfig>
```

---

## Режимы архивации

### PowerShell (Backup)

| Режим | XML параметр | Описание |
|-------|-------------|----------|
| Normal | (нет) | Весь источник в один архив |
| ArchiveByDate | `<ArchiveByDate>true</ArchiveByDate>` | Группировка по дате LastWriteTime |
| IndividualFiles | `<ArchiveIndividualFiles>true</ArchiveIndividualFiles>` | Каждый файл в отдельный архив |
| IndividualFolders | `<ArchiveIndividualFolders>true</ArchiveIndividualFolders>` | Каждая папка в отдельный архив |

### Bash (Backup)

| Режим | Параметр | Описание |
|-------|---------|----------|
| archive_by_date | `archive_by_date` | Группировка по дате |
| individual_files | `individual_files` | Каждый файл отдельно |
| individual_folders | `individual_folders` | Каждая папка отдельно |
| archive_all | `archive_all` | Всё рекурсивно |

---

## Совместимость платформ

### PowerShell 2.0

| Функция | Статус | Примечание |
|---------|--------|------------|
| `[CmdletBinding()]` | ✅ | Поддерживается |
| `New-Object PSObject` | ✅ | Поддерживается |
| `Get-FileHashCompat` | ✅ | Кастомная реализация (SHA256) |
| `Test-StringIsNullOrWhiteSpace` | ✅ | Кастомная функция |

### Bash 3.0+

| Конструкция | Статус | Примечание |
|------------|--------|------------|
| `mapfile`/`readarray` | ❌ | Запрещено (bash 4+) |
| `declare -A` (ассоциативные массивы) | ❌ | Запрещено (bash 4+) |
| process substitution `<()` | ❌ | Использовать временные файлы |
| `[[ ... =~ ... ]]` (regex) | ⚠️ | Нестабильно на Solaris |

---

## Шаблон имён архивов

| Переменная | Описание | Пример |
|------------|----------|--------|
| `{PCName}` | Имя компьютера | `PC001` |
| `{JobName}` | Имя задания | `JOB1` |
| `{Date}` | Дата (YYYYMMDD) | `20260412` |
| `{Time}` | Время (HHMMSS) | `153045` |
| `{Date_Time}` | Дата+Время | `20260412_153045` |
| `{SourceFileName}` | Имя исходного файла | `data.log` |
| `{SourceFolderName}` | Имя исходной папки | `20260410` |
| `{LastWriteDate}` | Дата LastWriteTime | `20260330` |

---

## Документация

- `docs/Backup_info.md` — Обзор пайплайна резервного копирования
- `docs/Backup_Config_Reference.md` — Справочник XML-конфигурации
- `docs/Backup_API_Reference.md` — API справочник (рус.)
- `docs/Backup_shema.md` — Диаграммы процесса
- `docs/Powershell_info.md` — Совместимость с PS 2.0
- `docs/REFactoring-NOTES.md` — Примечания по рефакторингу
- `docs/FUNCTIONS_REFERENCE.md` — English function reference
- `docs/constitution.md` — Team constitution
- `docs/specify.md` — Domain specification (what and why)
- `docs/plan.md` — Architecture and tech stack
- `docs/PIPELINE_TEMPLATE.md` — Шаблон 5-Stage Pipeline
- `docs/patterns/COMMON_FUNCTIONS.md` — Общие функции и паттерны кода
- `docs/copy/README.md` — Документация модуля Copy
- `docs/copy/REFactoring-NOTES.md` — Примечания по Copy рефакторингу
- `app/bash/info.md` — Описание bash-скриптов

---

## История версий

### PowerShell Backup
| Версия | Статус | Описание |
|--------|--------|----------|
| v4 | ✅ Актуальная | Unified Pipeline, RAR -df, архивация с ротацией |
| v3 | ⚠️ Устаревшая | Unified Pipeline для всех режимов |
| v2 | ⚠️ Устаревшая | Сетевые отчёты через NetLogPath |
| v1 | ⚠️ Устаревшая | Initial Unified Pipeline |

### PowerShell Copy
| Версия | Статус | Описание |
|--------|--------|----------|
| v4 | ✅ Актуальная | Копирование по XML с верификацией и архивацией |