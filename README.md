# Backup Toolkit — Multi-Platform File Operations

**Набор скриптов для обработки файлов и каталогов по единому сценарию.**
**Применение резервное и обычного копирования файлов. Обработка файлов. PowerShell 2.0, Linux, Solaris.**

---

## Быстрый старт

### PowerShell Version 2.0 (Windows)

```powershell
# Резервное копирование с архиватором RAR
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\backup-ps2-v6.ps1

# Тестовый режим (без реальных операций)
powershell.exe -Version 2.0 -executionpolicy RemoteSigned -file .\app\ps\backup\backup-ps2-v6.ps1 -testmode

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

Актуальная структура проекта — [structure.md](docs/wiki/structure.md) (обновляется при изменениях).

---

## Архитектура

### Текущие Модули (будут увеличиваться по мере изменения проекта)

| Модуль         | Каталог           | Платформы       | Назначение                   |
| -------------- | ----------------- | --------------- | ---------------------------- |
| **PSBackup**   | `app/ps/backup/`  | Windows (PS2.0) | Архивация (RAR/7zip/zip)     |
| **PSCopy**     | `app/ps/copy/`    | Windows (PS2.0) | Копирование с верификацией   |
| **BashBackup** | `app/bash/backup/`| Linux/Solaris   | Архивация (tar.gz)           |

### 5-этапный пайплайн (Общий для всех режимов и ОС)

1. **Preparation** — Сканирование источников, проверка файлов по маскам
2. **Processing** — Главный этап. Создание архивов (RAR/7zip/tar.gz), Копирование каждого файла из Source в RemoteDest, Другие операции
3. **Verification** — Проверка целостности архивов, файлов, другие проверки при необходимости
4. **Post-Operations** — Копирование в сетное хранилище, ротация, удаление
5. **Reporting** — XML/CSV отчёты, отправка email

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

| Режим             | XML параметр                                                | Описание                          |
| ----------------- | ----------------------------------------------------------- | --------------------------------- |
| Normal            | (нет)                                                       | Весь источник в один архив        |
| ArchiveByDate     | `<ArchiveByDate>true</ArchiveByDate>`                       | Группировка по дате LastWriteTime |
| IndividualFiles   | `<ArchiveIndividualFiles>true</ArchiveIndividualFiles>`     | Каждый файл в отдельный архив     |
| IndividualFolders | `<ArchiveIndividualFolders>true</ArchiveIndividualFolders>` | Каждая папка в отдельный архив    |

### Bash (Backup)

| Режим              | Параметр             | Описание              |
| ------------------ | -------------------- | --------------------- |
| archive_by_date    | `archive_by_date`    | Группировка по дате   |
| individual_files   | `individual_files`   | Каждый файл отдельно  |
| individual_folders | `individual_folders` | Каждая папка отдельно |
| archive_all        | `archive_all`        | Всё рекурсивно        |

---

## Совместимость платформ

### PowerShell 2.0

| Функция                         | Статус | Примечание                    |
| ------------------------------- | ------ | ----------------------------- |
| `[CmdletBinding()]`             | ✅      | Поддерживается                |
| `New-Object PSObject`           | ✅      | Поддерживается                |
| `Get-FileHashCompat`            | ✅      | Кастомная реализация (SHA256) |
| `Test-StringIsNullOrWhiteSpace` | ✅      | Кастомная функция             |

### Bash 3.0+

| Конструкция                          | Статус | Примечание                   |
| ------------------------------------ | ------ | ---------------------------- |
| `mapfile`/`readarray`                | ❌      | Запрещено (bash 4+)          |
| `declare -A` (ассоциативные массивы) | ❌      | Запрещено (bash 4+)          |
| process substitution `<()`           | ❌      | Использовать временные файлы |
| `[[ ... =~ ... ]]` (regex)           | ⚠️      | Нестабильно на Solaris       |

---

## Шаблон имён архивов

| Переменная           | Описание               | Пример            |
| -------------------- | ---------------------- | ----------------- |
| `{PCName}`           | Имя компьютера         | `PC001`           |
| `{ParentJobName}`    | Имя всего задания      | `BackupAllXml`    |
| `{JobName}`          | Имя отдельного задания | `JOB1`            |
| `{Date}`             | Дата (YYYYMMDD)        | `20260412`        |
| `{Time}`             | Время (HHMMSS)         | `153045`          |
| `{Date_Time}`        | Дата+Время             | `20260412_153045` |
| `{SourceFileName}`   | Имя исходного файла    | `data.log`        |
| `{SourceFolderName}` | Имя исходной папки     | `20260410`        |
| `{LastWriteDate}`    | Дата LastWriteTime     | `20260330`        |

---

## Документация

- **Documentation:** `docs/` - Вся документация по проекту
- **User Raw Notes:** `docs/raw/` - Сырые заметки пользователя к документации
- **Knowledge base:** `docs/wiki/` - База знаний по проекту. Ведется и форматируется исключительно агентом.
- **Knowledge map:** `docs/wiki/index.md` - Основная карта знаний проекта.
- **Log Knowledge:** `docs/wiki/log.md` - Журнал автоматических правок агентов.
- **Dev plan:** `docs/roadmap.md` — План разработки по проекту
- **Process diagrams:** `docs/diagrams/` — Диаграммы работы скриптов

---

## История версий

### PowerShell Backup
| Версия | Статус       | Описание                                        |
| ------ | ------------ | ----------------------------------------------- |
| v4     | ✅ Актуальная | Unified Pipeline, RAR -df, архивация с ротацией |
| v3     | ⚠️ Устаревшая | Unified Pipeline для всех режимов               |
| v2     | ⚠️ Устаревшая | Сетевые отчёты через NetLogPath                 |
| v1     | ⚠️ Устаревшая | Initial Unified Pipeline                        |

### PowerShell Copy
| Версия | Статус       | Описание                                       |
| ------ | ------------ | ---------------------------------------------- |
| v4     | ✅ Актуальная | Копирование по XML с верификацией и архивацией |