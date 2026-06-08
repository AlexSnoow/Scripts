# Модуль Copy — Обычное копирование файлов

## Назначение

Модуль **Copy** выполняет обычное копирование файлов из источника в место назначения по конфигурации XML. В отличие от модуля Backup, копирование происходит **без архивирования** — файлы копируются напрямую.

## Структура

```
app/ps/copy/
├── copy-ps2-v4.ps1         # Текущая версия (основная)
├── Copy-Config.xml          # Конфигурация копирования
└── Copy-Config-Example.xml  # Пример конфигурации
```

## Скрипт copy-ps2-v4.ps1

### Описание

PowerShell 2.0 совместимый скрипт для копирования файлов с верификацией.

### Использование

```powershell
# Обычное копирование
powershell.exe -executionpolicy RemoteSigned -file .\app\ps\copy\copy-ps2-v4.ps1 -ConfigurationPath .\app\ps\copy\Copy-Config.xml

# Через cmd
powershell -executionpolicy RemoteSigned -File .\app\ps\copy\copy-ps2-v4.ps1 -ConfigurationPath .\app\ps\copy\Copy-Config.xml
```

### Параметры

| Параметр | Обязательный | Описание |
|----------|-------------|----------|
| `-ConfigurationPath` | Да | Путь к XML-файлу конфигурации |

### Алгоритм работы

Для каждого задания (Job) из конфигурации:

1. **Preparation** — Загрузка XML-конфигурации, валидация секции Jobs
2. **Initialization** — Проверка/создание целевых директорий (RemoteDest, Arhive)
3. **Copying** — Копирование каждого файла из Source в RemoteDest
4. **Verification** — Проверка целостности (сравнение размеров файла)
5. **Archive** — Перемещение проверенного файла в Arhive директорию
6. **Reporting** — Формирование отчёта `reports_YYYYMMDD.xml`

### Конфигурация (Copy-Config.xml)

```xml
<CopyConfig>
  <General>
    <ParentJobName>CopyAllXml</ParentJobName>
    <ReportPath>C:\WORK\CopyAllXml\reports</ReportPath>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
    <ReportEmail>
      <Recipients>
        <Recipient>admin@localdomain.loc</Recipient>
        <Recipient>backup@localdomain.loc</Recipient>
      </Recipients>
      <EmailSubject>Copy Report: {PCName}_{JobName}_{Date}</EmailSubject>
      <EmailFrom>backup@localdomain.loc</EmailFrom>
    </ReportEmail>
  </General>
  <Jobs>
    <Job Name="JOB1">
      <Source>C:\WORK\CopyAllXml\src\JOB1\</Source>
      <RemoteDest>C:\WORK\CopyAllXml\dst\</RemoteDest>
      <Arhive>C:\WORK\CopyAllXml\dst\arc\</Arhive>
    </Job>
    <Job Name="JOB2">
      <Source>C:\WORK\CopyAllXml\src\JOB2\</Source>
      <RemoteDest>C:\WORK\CopyAllXml\dst\</RemoteDest>
      <Arhive>C:\WORK\CopyAllXml\dst\arc\</Arhive>
    </Job>
  </Jobs>
</CopyConfig>
```

### XML Schema

| Элемент | Описание | Обязательный |
|---------|----------|-------------|
| `<ParentJobName>` | Имя родительского задания | Да |
| `<ReportPath>` | Путь к отчётам | Да |
| `<SmtpServer>` | SMTP-сервер для email | Да |
| `<Recipients>` | Список получателей email | Да |
| `<EmailSubject>` | Тема email | Да |
| `<EmailFrom>` | Email отправителя | Да |
| `<Job Name>` | Имя задания | Да |
| `<Source>` | Исходная директория | Да |
| `<RemoteDest>` | Место назначения | Да |
| `<Arhive>` | Директория архива (перемещенных файлов) | Да |

### Постоперации

После успешного копирования и проверки:
- Файл **перемещается** (не копируется) из Source в Arhive директорию
- Исходный файл удаляется из Source

### Ошибки

| Код | Описание |
|-----|----------|
| FAIL | Файл не скопирован или проверка не пройдена |
| FATAL | Критическая ошибка скрипта |
| [OK] | Успешное завершение операции |

### Совместимость с PowerShell 2.0

- ✅ `Get-Item` для проверки размеров файлов (вместо `Get-FileHash`)
- ✅ `Test-Path` для проверки существования
- ✅ `New-Item` с параметром `ItemType Directory`
- ✅ `Copy-Item` / `Move-Item` — стандартные команды PS2.0
- ✅ `[xml]` тип для парсинга конфигурации
- ❌ `Get-FileHash` — недоступен в PS2.0

---

## Сравнение модулей

| Параметр | Backup | Copy |
|----------|--------|------|
| Архивирование | ✅ RAR | ❌ Нет (перемещение) |
| Конфигурация | Backup-Config.xml | Copy-Config.xml |
| Шаблон имён | `{PCName}_{JobName}_{Date_Time}.rar` | Имя исходного файла |
| Верификация | RAR-тест + проверка файлов | Сравнение размеров |
| Платформы | Windows (PS2.0), Linux, Solaris | Windows (PS2.0) |
| Ротация | ✅ | ❌ Нет |
| Отчёты | XML/CSV + email | XML + email |
| 5-этапный пайплайн | ✅ | ✅ |

---

## План развития модуля Copy

1. **[BACKLOG]** Добавить ротацию файлов в директории Arhive
2. **[BACKLOG]** Добавить логику email-отчётов
3. **[BACKLOG]** Создать bash-аналог (app/bash/copy-v4.sh) для Linux/Solaris
4. **[BACKLOG]** Добавить поддержку масок файлов (*.log, *.xml, etc.)
5. **[BACKLOG]** Добавить режим "только копирование" без перемещения в Arhive