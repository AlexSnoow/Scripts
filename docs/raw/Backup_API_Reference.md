# API Справочник функций Backup-ps2-v4.ps1

## Обзор

Скрипт содержит 20+ функций для архивации, верификации, логирования и отчётности.

---

## Логирование

### Initialize-Logging

Инициализирует систему логирования.

```powershell
Initialize-Logging -LogPath "C:\Logs" -PCName "HOME-PC" -JobName "JOB1"
```

**Параметры:**
- `-LogPath` (string): Путь к папке логов
- `-PCName` (string): Имя компьютера
- `-JobName` (string): Имя задания

**Возвращает:** `[bool]` — успех инициализации

---

### Write-Log

Записывает сообщение в лог-файл.

```powershell
Write-Log -Message "Архивация завершена" -Level SUCCESS -ResultKey
```

**Параметры:**
- `-Message` (string): Текст сообщения
- `-Level` (string): `INFO`, `WARNING`, `ERROR`, `SUCCESS`, `DEBUG`
- `-ResultKey` (switch): Добавить в отчёт

**Примеры уровней:**
```powershell
Write-Log "Информационное сообщение" -Level INFO
Write-Log "Предупреждение" -Level WARNING
Write-Log "Ошибка" -Level ERROR
Write-Log "Успех" -Level SUCCESS
```

---

### Write-LogSection

Записывает разделитель в лог.

```powershell
Write-LogSection -Title "ШАГ 1: ПОДГОТОВКА"
Write-LogSection
```

**Параметры:**
- `-Title` (string): Заголовок раздела
- `-ResultKey` (switch): Добавить в отчёт

---

### Get-LogFilePath

Возвращает путь к текущему лог-файлу.

```powershell
$logPath = Get-LogFilePath
```

**Возвращает:** `[string]` — полный путь к лог-файлу

---

### Get-LogResults

Получает сводку результатов для отчёта.

```powershell
$summary = Get-LogResults
```

**Возвращает:** `[string]` — сводка сообщений с ResultKey

---

## RAR Операции

### Start-RarArchive

Создает RAR архив.

```powershell
$result = Start-RarArchive `
    -RarPath "c:\work\rar.exe" `
    -ArchivePath "C:\Backup\archive.rar" `
    -SourcePath "C:\Source" `
    -Parameters @("a","-m5","-s") `
    -LogPath "C:\Logs\arh.log"
```

**Параметры:**
- `-RarPath` (string): Путь к RAR.exe
- `-ArchivePath` (string): Путь к архиву
- `-SourcePath` (string): Источник
- `-Parameters` (string[]): Параметры RAR
- `-LogPath` (string): Путь к логу RAR

**Возвращает:** `[PSObject]` с полями:
- `ExitCode` — код возврата RAR
- `Duration` — время выполнения (минуты)
- `ArchiveSize` — размер архива (МБ)
- `LogContent` — содержимое лога RAR

---

### Test-RarArchive

Проверяет целостность RAR архива.

```powershell
$test = Test-RarArchive -RarPath "c:\work\rar.exe" -ArchivePath "C:\Backup\archive.rar"
if ($test.IsValid) { ... }
```

**Параметры:**
- `-RarPath` (string): Путь к RAR.exe
- `-ArchivePath` (string): Путь к архиву

**Возвращает:** `[PSObject]` с полями:
- `ExitCode` — код возврата
- `IsValid` — `true` если архив целостен

---

### Get-RarExitCodeMeaning

Получает описание кода возврата RAR.

```powershell
$desc = Get-RarExitCodeMeaning -ExitCode 0
# "Успешное выполнение"
```

**Параметры:**
- `-ExitCode` (int): Код возврата RAR

**Возвращает:** `[string]` — описание кода

---

## Верификация

### Get-FileList

Сканирует папку и возвращает список файлов.

```powershell
$files = Get-FileList -Path "C:\Source"
```

**Параметры:**
- `-Path` (string): Путь к папке

**Возвращает:** `[PSObject[]]` с полями:
- `RelativePath` — относительный путь
- `Length` — размер файла
- `LastWriteTime` — дата изменения
- `FullName` — полный путь

---

### Get-FilterFileList

Ищет файлы по маске.

```powershell
$files = Get-FilterFileList -Path "C:\Source" -Filter "*.log"
```

**Параметры:**
- `-Path` (string): Путь к папке
- `-Filter` (string): Маска файла (например, `*.log` или `data/*_2024*`)

**Возвращает:** `[PSObject[]]` — список файлов

---

### Get-FileArhListRar

Читает содержимое RAR архива.

```powershell
$archiveFiles = Get-FileArhListRar -RarPath "c:\work\rar.exe" -ArchivePath "C:\Backup\archive.rar"
```

**Параметры:**
- `-RarPath` (string): Путь к RAR.exe
- `-ArchivePath` (string): Путь к архиву

**Возвращает:** `[PSObject[]]` — список файлов в архиве

---

### Compare-FilesSourceArchive

Сравнивает файлы источника и архива.

```powershell
$result = Compare-FilesSourceArchive -SourceList $sourceFiles -ArchiveList $archiveFiles
if ($result.IsIdentical) { ... }
```

**Параметры:**
- `-SourceList` (object[]): Список файлов источника
- `-ArchiveList` (object[]): Список файлов архива
- `-SourcePath` (string): Корень источника (опц.)

**Возвращает:** `[PSObject]` с полями:
- `IsIdentical` — `true` если совпадают
- `TotalSource` — количество файлов источника
- `TotalArchive` — количество файлов архива
- `MissingInArchive` — отсутствующие в архиве
- `SizeMismatch` — несовпадение размеров
- `Report` — текстовый отчёт

---

## Архивация (Unified Pipeline)

### Prepare-ArchiveItems

Подготавливает элементы для архивации.

```powershell
$items = Prepare-ArchiveItems -Job $jobDef -PCName "HOME-PC"
```

**Параметры:**
- `-Job` (hashtable): Конфигурация задания
- `-PCName` (string): Имя компьютера

**Возвращает:** `[PSObject[]]` — список ArchiveItem

**Типы ArchiveItem:**
- `SourceType='Directory'` — обычный режим
- `SourceType='File'` — индивидуальная файловая
- `SourceType='Folder'` — индивидуальная папочная

---

### Invoke-ArchivePipeline

Выполняет архивацию всех элементов.

```powershell
$result = Invoke-ArchivePipeline `
    -ArchiveItems $items `
    -Job $jobDef `
    -Config $config `
    -LogDir "C:\Logs"
```

**Параметры:**
- `-ArchiveItems` (object[]): Элементы для архивации
- `-Job` (hashtable): Конфигурация задания
- `-Config` (hashtable): Общая конфигурация
- `-LogDir` (string): Папка для логов

**Возвращает:** `[hashtable]` с полями:
- `Results` — массив результатов
- `SuccessCount` — количество успешных
- `ErrorCount` — количество ошибок

---

### Invoke-Verification

Выполняет верификацию архивов.

```powershell
$verifyResult = Invoke-Verification `
    -ArchiveResults $archiveResults `
    -Job $jobDef `
    -Config $config
```

**Параметры:**
- `-ArchiveResults` (object[]): Результаты архивации
- `-Job` (hashtable): Конфигурация задания
- `-Config` (hashtable): Общая конфигурация

**Возвращает:** `[hashtable]` с полями:
- `Verified` — прошедшие верификацию
- `FailedCount` — количество ошибок
- `TotalCount` — общее количество
- `AllPassed` — `true` если все прошли

---

### Invoke-PostOperations

Выполняет пост-операции (копирование, ротация, удаление).

```powershell
Invoke-PostOperations `
    -ArchiveResults $archiveResults `
    -Job $jobDef `
    -Config $config `
    -VerificationResult $verifyResult `
    -PipelineSuccessCount $successCount `
    -PipelineErrorCount $errorCount
```

**Параметры:**
- `-ArchiveResults` (object[]): Результаты архивации
- `-Job` (hashtable): Конфигурация задания
- `-Config` (hashtable): Общая конфигурация
- `-VerificationResult` (hashtable): Результаты верификации
- `-PipelineSuccessCount` (int): Успешные архивы
- `-PipelineErrorCount` (int): Ошибки архивации

---

## Ротация файлов

### Remove-OldFiles

Удаляет старые файлы с гарантией минимального количества.

```powershell
Remove-OldFiles `
    -Path "C:\Backup" `
    -DaysOld 7 `
    -KeepCount 3 `
    -Filter "*.rar"
```

**Параметры:**
- `-Path` (string): Папка для ротации
- `-DaysOld` (int): Дней хранения (0-3650)
- `-KeepCount` (int): Мин. количество файлов (0-100000)
- `-Filter` (string): Маска файлов

**Поддерживает:** `-WhatIf` для предпросмотра

---

## Отчёты

### Save-RemoteReports

Сохраняет XML и CSV отчёты по сетевому пути.

```powershell
Save-RemoteReports `
    -PCName "HOME-PC" `
    -JobName "JOB1" `
    -JobStatus "Success" `
    -Duration "5.2" `
    -SourceFiles 150 `
    -ArchiveSizeMB 245.5 `
    -Verification "Passed" `
    -SourceFileList $fileList `
    -NetPath "\\server\share\NetLogs"
```

**Параметры:**
- `-PCName` (string): Имя компьютера
- `-JobName` (string): Имя задания
- `-JobStatus` (string): `Success`, `Error`, `Warning`
- `-Duration` (string): Время выполнения
- `-SourceFiles` (int): Количество файлов
- `-ArchiveSizeMB` (double): Размер архива (МБ)
- `-Verification` (string): Статус верификации
- `-Errors` (string[]): Список ошибок
- `-Warnings` (string[]): Список предупреждений
- `-LocalLogPath` (string): Путь к локальному логу
- `-SourceFileList` (object[]): Список файлов
- `-NetPath` (string): Сетевой путь (опц.)

**Создаёт файлы:**
- `<PCName>_<JobName>_<timestamp>.xml` — детальный отчёт
- `<PCName>_<JobName>_<timestamp>.csv` — список файлов
- `<PCName>_summary.xml` — сводный статус

---

## Вспомогательные функции

### Get-FileHashCompat

Вычисляет SHA256 хеш файла (совместимость с PS 2.0).

```powershell
$hash = Get-FileHashCompat -Path "c:\work\rar.exe" -Algorithm SHA256
Write-Host $hash.Hash
```

**Параметры:**
- `-Path` (string): Путь к файлу
- `-LiteralPath` (string): Буквальный путь
- `-Algorithm` (string): `SHA1`, `SHA256`, `SHA384`, `SHA512`, `MD5`

**Возвращает:** `[PSObject]` с полями:
- `Hash` — хеш (верхний регистр)
- `Algorithm` — алгоритм
- `Path` — путь к файлу

---

### Test-FileIntegrity

Проверяет целостность файла по хешу.

```powershell
if (Test-FileIntegrity -FilePath "c:\work\rar.exe" -ExpectedHash "ABC123..." -FileType "RAR.exe") {
    Write-Host "Файл безопасен"
}
```

**Параметры:**
- `-FilePath` (string): Путь к файлу
- `-ExpectedHash` (string): Ожидаемый SHA256 хеш
- `-FileType` (string): Тип файла для отчёта

**Возвращает:** `[bool]` — `true` если хеш совпадает

---

### Get-FileInfoDetails

Получает информацию о файлах в папке.

```powershell
$info = Get-FileInfoDetails -Path "C:\Source"
Write-Host "Файлов: $($info.FileCount), Размер: $($info.TotalSizeMB) МБ"
```

**Параметры:**
- `-Path` (string): Путь к папке

**Возвращает:** `[PSObject]` с полями:
- `FileCount` — количество файлов
- `TotalSizeMB` — общий размер (МБ)
- `FileSamples` — первые 5 файлов
- `HasMoreFiles` — есть ли больше 5 файлов
- `MoreFilesCount` — количество дополнительных файлов

---

### Copy-BackupFile

Копирует файл с измерением времени.

```powershell
$result = Copy-BackupFile -SourcePath "C:\Source\file.rar" -DestinationPath "C:\Backup\file.rar"
```

**Параметры:**
- `-SourcePath` (string): Источник
- `-DestinationPath` (string): Назначение

**Возвращает:** `[PSObject]` с полями:
- `Success` — `true` если размеры совпали
- `Duration` — время копирования (секунды)
- `SourceSize` — размер источника
- `DestinationSize` — размер назначения

---

### Format-FileSize

Форматирует размер файла в удобочитаемый вид.

```powershell
$size = Format-FileSize -Path "C:\Backup\archive.rar"
# "245.50 МБ"
```

**Параметры:**
- `-Path` (string): Путь к файлу

**Возвращает:** `[string]` — форматированный размер

---

### Get-DiskSpaceReport

Получает отчёт о свободном месте на дисках.

```powershell
$report = Get-DiskSpaceReport -ComputerName "HOME-PC"
Write-Host $report
# "Диск C: Всего(ГБ)=500.0 Свободно(ГБ)=150.5 Свободно=30.1%"
```

**Параметры:**
- `-ComputerName` (string): Имя компьютера (опц.)

**Возвращает:** `[string]` — сводка по дискам

---

### Send-Email

Отправляет email через CDO.Message.

```powershell
Send-Email `
    -SmtpServer "smtp.localdomain.loc" `
    -From "backup@head.localdomain.loc" `
    -To "admin@head.localdomain.loc" `
    -Subject "Backup Complete" `
    -Body "Backup completed successfully" `
    -Port 25 `
    -UseSSL $false
```

**Параметры:**
- `-SmtpServer` (string): SMTP-сервер
- `-From` (string): Отправитель
- `-To` (string): Получатель
- `-Subject` (string): Тема
- `-Body` (string): Тело письма
- `-Port` (int): Порт (опц., по умолчанию 25)
- `-UseSSL` (bool): Использовать SSL (опц.)
- `-Username` (string): Имя пользователя (опц.)
- `-Password` (string): Пароль (опц.)
- `-IsBodyHtml` (bool): HTML-формат (опц.)

**Возвращает:** `[bool]` — `true` если отправлено

---

### Write-WinEventAppLog

Записывает событие в Windows Event Log.

```powershell
Write-WinEventAppLog -StatusKey "Success" -MessageText "Backup completed" -Source "BackupAllXml"
```

**Параметры:**
- `-StatusKey` (string): `Start`, `Success`, `Warning`, `Error`, `End`
- `-MessageText` (string): Текст сообщения
- `-Source` (string): Источник события (опц.)

**Event IDs:**
- `3000` — Start
- `3001` — Success
- `3002` — Warning
- `3003` — Error
- `3004` — End

---

### Test-Configuration

Проверяет корректность конфигурации.

```powershell
$test = Test-Configuration
if ($test.IsValid) { ... } else { $test.Errors }
```

**Возвращает:** `[hashtable]` с полями:
- `IsValid` — `true` если конфигурация корректна
- `Errors` — список ошибок

---

### Get-BackupConfiguration

Получает конфигурацию из XML.

```powershell
$config = Get-BackupConfiguration
```

**Возвращает:** `[hashtable]` с полями:
- `Settings` — общие настройки
- `Jobs` — задания архивации

---

## Режимы архивации

### Get-ArchiveMode

Определяет режим архивации задания.

```powershell
$mode = Get-ArchiveMode -Job $jobDef
# 'Normal', 'IndividualFiles', 'IndividualFolders'
```

**Параметры:**
- `-Job` (hashtable): Конфигурация задания

**Возвращает:** `[string]` — режим архивации

---

### Resolve-ArchivePattern

Разрешает шаблоны имён архивов.

```powershell
$archiveName = Resolve-ArchivePattern `
    -Pattern "{PCName}_{JobName}_{Date_Time}.rar" `
    -PCName "HOME-PC" `
    -JobName "JOB1" `
    -SourceFileName "data.log" `
    -SourceFolderName "2024-04-12"
# "HOME-PC_JOB1_20260412_205449.rar"
```

**Параметры:**
- `-Pattern` (string): Шаблон имени
- `-PCName` (string): Имя компьютера
- `-JobName` (string): Имя задания
- `-SourceFileName` (string): Имя файла (опц.)
- `-SourceFolderName` (string): Имя папки (опц.)

**Возвращает:** `[string]` — разрешённое имя архива

---

## Примечания

- Все функции совместимы с **PowerShell 2.0**
- Используются только встроенные .NET Framework классы
- Нет зависимостей от сторонних модулей
- Все строки в UTF8 без BOM
- Логи в OEM кодировке (CP866) для кириллицы
