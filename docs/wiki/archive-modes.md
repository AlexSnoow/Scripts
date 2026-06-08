# Archive Modes

Скрипт Backup поддерживает 4 режима архивации, определяемые в XML-конфигурации задания.

## Normal
Весь источник архивируется в один архив.
```xml
<ArchivePattern>{PCName}_{JobName}_{Date_Time}.rar</ArchivePattern>
```

## ArchiveByDate
Группировка файлов по дате `LastWriteTime`. Каждая дата — отдельный архив.
```xml
<ArchiveByDate>true</ArchiveByDate>
<DateGroupArchivePattern>{PCName}_{JobName}_{LastWriteDate}.rar</DateGroupArchivePattern>
```

## IndividualFiles
Каждый файл становится отдельным архивом. Поддерживает `FileFilter` и `ExcludeFilePattern`.
```xml
<ArchiveIndividualFiles>true</ArchiveIndividualFiles>
<FileFilter>fxserver.20*.log</FileFilter>
<ExcludeFilePattern>fxserver.log</ExcludeFilePattern>
<IndividualArchivePattern>{PCName}_{JobName}_{SourceFileName}.rar</IndividualArchivePattern>
```

## IndividualFolders
Каждая подпапка — отдельный архив. Поддерживает `ExcludeFolderPattern` (значение `today` исключает папку с текущей датой).
```xml
<ArchiveIndividualFolders>true</ArchiveIndividualFolders>
<ExcludeFolderPattern>today</ExcludeFolderPattern>
<IndividualArchivePattern>{PCName}_{JobName}_{SourceFolderName}.rar</IndividualArchivePattern>
```

## Переменные ArchivePattern
| Переменная | Описание | Пример |
|------------|----------|--------|
| `{PCName}` | Имя компьютера | `HOME-PC` |
| `{JobName}` | Имя задания | `JOB1` |
| `{Date}` | Дата YYYYMMDD | `20260412` |
| `{Time}` | Время HHMMSS | `205449` |
| `{Date_Time}` | Дата+время | `20260412_205449` |
| `{SourceFileName}` | Имя исходного файла | `info.log.2024` |
| `{SourceFolderName}` | Имя исходной папки | `2024-04-12` |
| `{LastWriteDate}` | Дата LastWriteTime файла | `20260330` |

## ArchiveItem (внутренняя структура)
Единая структура данных для всех режимов пайплайна:
- `SourceType='Directory'` — Normal
- `SourceType='File'` — IndividualFiles
- `SourceType='Folder'` — IndividualFolders

Поля: `SourcePath`, `SourceName`, `ArchiveName`, `SourceType`, `SourceRoot`, `SourceFilter`.
