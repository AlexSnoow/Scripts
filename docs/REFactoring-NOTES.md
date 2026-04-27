# Примечания к рефакторингу Backup Script

## Дата: 2026-04-12
## Версия: 3.3 (RAR -df без верификации)

---

## Основные изменения

### 1. Удаление верификации через RAR -df
- **Удалено**: Полный модуль верификации (`Invoke-Verification`, `Compare-FilesSourceArchive`)
- **Добавлено**: Параметр `-DeleteAfterArchive` в `Start-RarArchive`
- **Эффект**: RAR автоматически удаляет файлы после успешной архивации

### 2. Новый параметр в XML конфигурации
```xml
<RemoveSourceAfterArchive>true</RemoveSourceAfterArchive>
<RemoveSourceDaysOld>0</RemoveSourceDaysOld>
<RemoveSourceKeepCount>0</RemoveSourceKeepCount>
```

### 3. Упрощение `Get-ArchiveItems_ByDateGroups`
- Теперь правильно группирует файлы по дате `LastWriteTime`
- Использует `DateGroupArchivePattern` для имени архива
- Создаёт один архив на каждую дату группы

---

## Поддерживаемые режимы архивации

| Режим | XML параметр | Описание | Пример архива |
|-------|--------------|----------|---------------|
| **Normal** | (нет) | Весь источник в один архив | `PC001_Job1_20260412.rar` |
| **ArchiveByDate** | `<ArchiveByDate>true</ArchiveByDate>` | Группировка файлов по дате LastWriteTime | `PC001_Job1_20260330.rar` |
| **IndividualFiles** | `<ArchiveIndividualFiles>true</ArchiveIndividualFiles>` | Каждый файл в отдельный архив | `PC001_Job51_jzdo.log.2024.rar` |
| **IndividualFolders** | `<ArchiveIndividualFolders>true</ArchiveIndividualFolders>` | Каждая папка в отдельный архив | `PC001_Job6_20260410.rar` |

---

## Переменные для ArchivePattern

| Переменная | Описание | Пример |
|------------|----------|--------|
| `{PCName}` | Имя компьютера | `PC001` |
| `{JobName}` | Имя задания из XML | `JOB1` |
| `{Date}` | Текущая дата (YYYYMMDD) | `20260412` |
| `{Time}` | Текущее время (HHMMSS) | `153045` |
| `{Date_Time}` | Дата+Время | `20260412_153045` |
| `{SourceFileName}` | Имя исходного файла | `jzdo.log.2024` |
| `{SourceFolderName}` | Имя исходной папки | `20260410` |
| `{LastWriteDate}` | Дата LastWriteTime файла | `20260330` |

---

## Обновлённая конфигурация XML

### JOB1-4: ArchiveByDate (группировка по дате)
```xml
<Job Name="JOB1">
  <Source>C:\WORK\BackupAllXml\src\JOB1\</Source>
  <ArchiveByDate>true</ArchiveByDate>
  <ArchivePattern>{PCName}_{JobName}_{Date}.rar</ArchivePattern>
  <DateGroupArchivePattern>{PCName}_{JobName}_{LastWriteDate}.rar</DateGroupArchivePattern>
  <ExcludeTodayFiles>true</ExcludeTodayFiles>
  <SourceFilter>*.*</SourceFilter>
  <RemoveSourceAfterArchive>true</RemoveSourceAfterArchive>
  <RemoveSourceDaysOld>0</RemoveSourceDaysOld>
  <RemoveSourceKeepCount>0</RemoveSourceKeepCount>
  ...
</Job>
```

### JOB51: IndividualFiles
```xml
<Job Name="JOB51">
  <Source>C:\WORK\BackupAllXml\src\JOB51\</Source>
  <ArchiveIndividualFiles>true</ArchiveIndividualFiles>
  <SourceFilter>jzdo.log.20*</SourceFilter>
  <ExcludeFilePattern>jzdo.log</ExcludeFilePattern>
  <IndividualArchivePattern>{PCName}_{JobName}_{SourceFileName}.rar</IndividualArchivePattern>
  <RemoveSourceAfterArchive>true</RemoveSourceAfterArchive>
  ...
</Job>
```

### JOB6: IndividualFolders
```xml
<Job Name="JOB6">
  <Source>C:\Work\BackupAllXml\src\JOB6\</Source>
  <ArchiveIndividualFolders>true</ArchiveIndividualFolders>
  <IndividualArchivePattern>{PCName}_{JobName}_{SourceFolderName}.rar</IndividualArchivePattern>
  <ExcludeFolderPattern>today</ExcludeFolderPattern>
  <RemoveSourceAfterArchive>true</RemoveSourceAfterArchive>
  ...
</Job>
```

---

## Совместимость с PowerShell 2.0

| Функция | Статус | Примечание |
|---------|--------|------------|
| `[CmdletBinding()]` | ✅ | Поддерживается |
| `[ValidateScript()]` | ✅ | Поддерживается |
| `New-Object PSObject` | ✅ | Поддерживается |
| `Test-StringIsNullOrWhiteSpace` | ✅ | Кастомная функция вместо `[string]::IsNullOrWhiteSpace` |
| `Get-FileHashCompat` | ✅ | Алиас для PS 2.0 |
| `[System.Convert]::ToBoolean()` | ⚠️ | Заменено на сравнение с `'true'` |

---

## Команды запуска

### Обычный запуск
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-noVerification.ps1
```

### Тестовый режим (без архивации)
```powershell
powershell.exe -executionpolicy RemoteSigned -file .\app\Backup-ps2-noVerification.ps1 -testmode
```

---

## Отладка

### Проверка режима архивации
```powershell
# В логе будет строка:
# [INFO] Режим архивации: IndividualGroupByDate
# или
# [INFO] Режим архивации: IndividualFiles
# или
# [INFO] Режим архивации: IndividualFolders
# или
# [INFO] Режим архивации: Normal
```

### Проверка параметра -df
```powershell
# В логе будет строка:
# [DEBUG] Параметр -df активирован: файлы будут удалены после архивации
```

---

## Известные ограничения

1. **RAR -df удаляет только файлы, успешно добавленные в архив**
   - Файлы с ошибками доступа останутся в источнике
   - Рекомендуется проверять логи архиватора

2. **Для DateGroup режимов используется SourceFilter**
   - Все файлы в архиве соответствуют одному фильтру
   - Нельзя смешивать разные маски в одной группе дат

3. **IndividualFolders не удаляет пустые папки**
   - RAR -df удаляет только файлы, не папки
   - Для очистки пустых папок используйте отдельный скрипт

---

## Чек-лист перед продакшеном

- [ ] Проверить хеш XML конфигурации
- [ ] Проверить хеш RAR.exe
- [ ] Протестировать с `-testmode`
- [ ] Проверить создание директорий
- [ ] Проверить права доступа к источникам
- [ ] Проверить права доступа к назначениям
- [ ] Протестировать с реальными файлами (малое количество)
- [ ] Проверить логи после запуска
- [ ] Убедиться, что файлы удалены из источника
- [ ] Проверить отчётность в NetLogPath

---

## История версий

| Версия | Дата | Изменения |
|--------|------|-----------|
| 3.3 | 2026-04-12 | RAR -df вместо верификации, упрощение кода |
| 3.2 | 2026-04-12 | Сетевые отчёты через NetLogPath |
| 3.1 | 2026-04-11 | Unified Pipeline для всех режимов |
| 3.0 | 2026-04-10 | Initial Unified Pipeline |
