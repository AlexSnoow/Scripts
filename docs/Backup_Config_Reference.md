# Конфигурация Backup-Config-All.xml

## Описание

XML-файл конфигурации для скрипта `Backup-ps2-v4.ps1`. Определяет общие настройки, пути, получателей уведомлений и список заданий архивации.

## Структура

```xml
<BackupConfig>
  <General>...</General>     <!-- Общие настройки -->
  <Paths>...</Paths>         <!-- Пути к ресурсам -->
  <Recipients>...</Recipients> <!-- Получатели почты -->
  <Integrity>...</Integrity>   <!-- Хеш-контроль -->
  <Jobs>...</Jobs>           <!-- Задания архивации -->
</BackupConfig>
```

---

## Общие настройки (<General>)

```xml
<General>
  <JobName>BackupAllXml</JobName>
  <Domain>localdomain.loc</Domain>
  <SmtpServer>smtp.localdomain.loc</SmtpServer>
  <LogDaysOld>7</LogDaysOld>
  <LogKeepCount>7</LogKeepCount>
  <ArchiverType>RAR</ArchiverType>
  <DefaultRarParameters>
    <Param>a</Param>
    <Param>-m5</Param>
    <Param>-s</Param>
    <Param>-ep1</Param>
    <Param>-dh</Param>
    <Param>-rr1p</Param>
    <Param>-r</Param>
  </DefaultRarParameters>
</General>
```

### Параметры

| Параметр | Тип | Описание | Пример |
|----------|-----|----------|--------|
| `JobName` | string | Общее имя задания для всех бэкапов | `BackupAllXml` |
| `Domain` | string | Домен компьютера для email | `localdomain.loc` |
| `SmtpServer` | string | SMTP-сервер для уведомлений | `smtp.localdomain.loc` |
| `LogDaysOld` | int | Дней хранения лог-файлов | `7` |
| `LogKeepCount` | int | Макс. количество лог-файлов | `7` |
| `ArchiverType` | string | Тип архиватора (только RAR) | `RAR` |
| `DefaultRarParameters` | array | Параметры RAR по умолчанию | `a, -m5, -s...` |

### Параметры RAR

| Параметр | Описание |
|----------|----------|
| `a` | Добавить файлы в архив |
| `-m5` | Максимальное сжатие |
| `-s` | Создать SFX-архив (самораспаковывающийся) |
| `-ep1` | Исключить базовую папку из имён |
| `-dh` | Открывать файлы с общим доступом |
| `-rr1p` | Восстановление записей (процент) |
| `-r` | Рекурсивно |

---

## Пути (<Paths>)

```xml
<Paths>
  <LogPathRoot>C:\Work\BackupAllXml\logs</LogPathRoot>
  <NetLogPath>C:\work\BackupAllXml\logs\NetLogPath</NetLogPath>
  <RarPath>c:\work\rar.exe</RarPath>
</Paths>
```

### Параметры

| Параметр | Описание | Пример |
|----------|----------|--------|
| `LogPathRoot` | Корневая папка для лог-файлов | `C:\Work\BackupAllXml\logs` |
| `NetLogPath` | Сетевой путь для централизованных отчётов | `\\server\share\NetLogs` |
| `RarPath` | Полный путь к RAR.exe | `c:\work\rar.exe` |

---

## Получатели (<Recipients>)

```xml
<Recipients>
  <AdminIS>user1@head.localdomain.loc</AdminIS>
  <AdminOS>user2@head.localdomain.loc</AdminOS>
  <AdminMail>user3@head.localdomain.loc</AdminMail>
</Recipients>
```

### Параметры

| Параметр | Описание |
|----------|----------|
| `AdminIS` | Ответственный за информационные системы |
| `AdminOS` | Ответственный за операционные системы |
| `AdminMail` | Основной адрес для отчётов |

---

## Контроль целостности (<Integrity>)

```xml
<Integrity>
  <RarExeHash>2CE9D9F8CD10E8CEB3A943E1464938ECAB682313F8E4525DF17068B3EAE5B05B</RarExeHash>
</Integrity>
```

### Параметры

| Параметр | Описание |
|----------|----------|
| `RarExeHash` | SHA256 хеш RAR.exe (64 hex символа) |

> **Важно:** При обновлении RAR.exe необходимо обновить хеш в конфигурации.

---

## Задания (<Jobs>)

### Пример задания (Normal режим)

```xml
<Job Name="JOB1">
  <Source>C:\Work\BackupAllXml\src\JOB1</Source>
  <ListSourceFlag>csv</ListSourceFlag>
  <SourceCheckMasks>
    <Mask>*CTP*.*</Mask>
    <Mask>ACQ_ADV_*.*</Mask>
  </SourceCheckMasks>
  <RemoveSourceFlag>true</RemoveSourceFlag>
  <SourceDaysOld>0</SourceDaysOld>
  <SourceKeepCount>0</SourceKeepCount>
  <ArchivePattern>{PCName}_{JobName}_{Date_Time}.rar</ArchivePattern>
  <LocalDest>C:\Work\BackupAllXml\dst\Local\JOB1\</LocalDest>
  <LocalDestDaysOld>7</LocalDestDaysOld>
  <LocalDestKeepCount>7</LocalDestKeepCount>
  <RemoteDest>C:\Work\BackupAllXml\dst\Remote\</RemoteDest>
  <RemoveRemoteDestFlag>false</RemoveRemoteDestFlag>
  <ArhLog>true</ArhLog>
</Job>
```

### Пример задания (Individual Files режим)

```xml
<Job Name="JOB14">
  <Source>C:\Work\BackupAllXml\src\JOB14\</Source>
  <ArchiveIndividualFiles>true</ArchiveIndividualFiles>
  <FileFilter>fxserver.20*.log</FileFilter>
  <ExcludeFilePattern>fxserver.log</ExcludeFilePattern>
  <IndividualArchivePattern>{PCName}_{JobName}_{SourceFileName}.rar</IndividualArchivePattern>
  <RemoveSourceFlag>true</RemoveSourceFlag>
  <SourceDaysOld>0</SourceDaysOld>
  <SourceKeepCount>0</SourceKeepCount>
  <LocalDest>C:\Work\BackupAllXml\dst\Local\JOB14\</LocalDest>
  <LocalDestDaysOld>7</LocalDestDaysOld>
  <LocalDestKeepCount>7</LocalDestKeepCount>
  <RemoteDest>C:\Work\BackupAllXml\dst\Remote\</RemoteDest>
  <RemoveRemoteDestFlag>false</RemoveRemoteDestFlag>
  <ArhLog>true</ArhLog>
</Job>
```

### Пример задания (Individual Folders режим)

```xml
<Job Name="JOB6">
  <Source>C:\Work\BackupAllXml\src\JOB6\</Source>
  <ArchiveIndividualFolders>true</ArchiveIndividualFolders>
  <IndividualArchivePattern>{PCName}_{JobName}_{SourceFolderName}.rar</IndividualArchivePattern>
  <ExcludeFolderPattern>today</ExcludeFolderPattern>
  <RemoveSourceFlag>true</RemoveSourceFlag>
  <SourceDaysOld>0</SourceDaysOld>
  <SourceKeepCount>0</SourceKeepCount>
  <LocalDest>C:\Work\BackupAllXml\dst\Local\JOB6\</LocalDest>
  <LocalDestDaysOld>7</LocalDestDaysOld>
  <LocalDestKeepCount>7</LocalDestKeepCount>
  <RemoteDest>C:\Work\BackupAllXml\dst\Remote\</RemoteDest>
  <RemoveRemoteDestFlag>false</RemoveRemoteDestFlag>
  <ArhLog>true</ArhLog>
</Job>
```

---

## Параметры заданий

### Базовые параметры

| Параметр | Тип | Описание |
|----------|-----|----------|
| `Name` | string | Уникальное имя задания (атрибут Job) |
| `Source` | string | Исходная папка для архивации |
| `LocalDest` | string | Локальное хранилище архивов |
| `RemoteDest` | string | Сетевое хранилище архивов |
| `ArchivePattern` | string | Шаблон имени архива |

### Режимы архивации

| Параметр | Тип | Описание |
|----------|-----|----------|
| `ArchiveIndividualFolders` | bool | Режим: по папкам |
| `ArchiveIndividualFiles` | bool | Режим: по файлам |
| `IndividualArchivePattern` | string | Шаблон для индивидуальной архивации |

### Фильтрация

| Параметр | Тип | Описание |
|----------|-----|----------|
| `SourceFilter` | string | Фильтр файлов для архивации |
| `FileFilter` | string | Альтернатива SourceFilter |
| `ExcludeFilePattern` | string | Паттерн исключаемых файлов |
| `ExcludeFolderPattern` | string | Паттерн исключаемых папок (или `today`) |
| `SourceCheckMasks` | array | Маски для проверки наличия файлов |

### Ротация

| Параметр | Тип | Описание |
|----------|-----|----------|
| `RemoveSourceFlag` | bool | Удалить источник после верификации |
| `SourceDaysOld` | int | Дней хранения источников |
| `SourceKeepCount` | int | Количество источников для сохранения |
| `LocalDestDaysOld` | int | Дней хранения локальных архивов |
| `LocalDestKeepCount` | int | Количество локальных архивов |
| `RemoveRemoteDestFlag` | bool | Включить ротацию удалённого |
| `RemoteDestDaysOld` | int | Дней хранения удалённых архивов |
| `RemoteDestKeepCount` | int | Количество удалённых архивов |

### Отчёты и логи

| Параметр | Тип | Описание |
|----------|-----|----------|
| `ArhLog` | bool | Включить логирование RAR |
| `ListSourceFlag` | string | Создать список файлов (`txt`/`csv`) |
| `ArhParameters` | array | Индивидуальные параметры RAR |

---

## Шаблоны имён (<ArchivePattern>)

### Переменные

| Переменная | Описание | Пример |
|------------|----------|--------|
| `{PCName}` | Имя компьютера | `HOME-PC` |
| `{JobName}` | Имя задания | `JOB1` |
| `{Date}` | Дата YYYYMMDD | `20260412` |
| `{Time}` | Время HHMMSS | `205449` |
| `{Date_Time}` | Дата и время | `20260412_205449` |
| `{SourceFileName}` | Имя исходного файла | `info.log.2024` |
| `{SourceFolderName}` | Имя исходной папки | `2024-04-12` |

### Примеры

```xml
<!-- Ежедневный архив с временной меткой -->
<ArchivePattern>{PCName}_{JobName}_{Date_Time}.rar</ArchivePattern>

<!-- Индивидуальный архив по файлу -->
<IndividualArchivePattern>{PCName}_{JobName}_{SourceFileName}.rar</IndividualArchivePattern>

<!-- Индивидуальный архив по папке -->
<IndividualArchivePattern>{PCName}_{JobName}_{SourceFolderName}.rar</IndividualArchivePattern>
```

---

## Проверка масок (SourceCheckMasks)

Проверяет наличие файлов по заданным маскам. Если файлы не найдены — записывается ошибка.

```xml
<SourceCheckMasks>
  <Mask>*CTP*.*</Mask>
  <Mask>ACQ_ADV_*.*</Mask>
  <Mask>OAI_*.*</Mask>
  <Mask>CTL*.*</Mask>
</SourceCheckMasks>
```

> **Важно:** Используется только для проверки наличия файлов. Не влияет на архивацию.

---

## Исключения

### ExcludeFolderPattern

- Значение `today` — исключает папку с текущей датой (YYYYMMDD)
- Паттерн — исключает папки по маске (например, `temp_*`)

```xml
<ExcludeFolderPattern>today</ExcludeFolderPattern>
```

### ExcludeFilePattern

Исключает файлы по маске из индивидуальной архивации.

```xml
<ExcludeFilePattern>fxserver.log</ExcludeFilePattern>
```

---

## Валидация

### Требования

1. `ArchiverType` должен быть `RAR`
2. `RarPath` должен существовать
3. `RarExeHash` должен соответствовать SHA256 RAR.exe
4. XML должен быть валидным (UTF-8)
5. Все пути должны использовать обратные слеши `\`

### Ошибки конфигурации

| Ошибка | Последствие |
|--------|-------------|
| Непройдена проверка хеша | Остановка скрипта |
| Отсутствует RAR.exe | Остановка скрипта |
| Отсутствует Source | Пропуск задания |
| Нет прав на LocalDest | Пропуск задания |

---

## Пример полной конфигурации

См. файл `app/Backup-Config-All.xml` в проекте.
