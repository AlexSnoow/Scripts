# Create_Backup_Rar.ps1

## Назначение

Скрипт PowerShell для автоматической архивации файлов и папок с помощью RAR (WinRAR). Позволяет создавать архивы с динамическим именем (дата/время), вести логи, проверять свободное место и использовать различные ключи архивации.

## Основная функция

- **Backup-WithRAR** — функция для архивации, принимает параметры:
  - `RarPath` — путь к RAR.exe (по умолчанию: стандартный путь WinRAR)
  - `SRC` — исходный файл или папка для архивации
  - `DST` — папка назначения для архива
  - `ArchiveName` — имя архива (поддерживает плейсхолдеры `{date}`, `{time}`, `{datetime}`)
  - `Keys` — дополнительные ключи для RAR (по умолчанию: `a -r -m3 -dh -ep1`)
  - `ArchiveExtension` — расширение архива (`rar`, `zip`, `7z`)

## Возможности

- Автоматическое создание папки назначения
- Логирование stdout и ошибок в отдельные файлы
- Вывод размера созданного архива
- Экспорт функции для использования в модулях

## Дополнения что можно еще реализовать
- Проверка свободного места на диске
Самый быстрый и правильный способ в PowerShell — использовать встроенный Get-PSDrive или Get-CimInstance.

Вот минимальные команды:

1. Через Get-PSDrive (самый простой вариант)
1.1. (Get-PSDrive C).Free/1GB
2. Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}
2.1. (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace/1GB



## Примеры использования

```powershell
# Простой запуск
Backup-WithRAR -SRC "C:\test\backup1" -DST "C:\test\rar" -ArchiveName "DataBackup-{datetime}"

# С выбором формата ZIP
Backup-WithRAR -SRC "C:\Logs" -DST "E:\Archives" -ArchiveName "Logs-{date}" -ArchiveExtension "zip" -Verbose
```

## Требования

- Установленный WinRAR/RAR.exe
- PowerShell 5.0+

## Автор

- Иванов, версия 2.0 (2025-08-19)

---
