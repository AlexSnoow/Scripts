@echo off
setlocal enabledelayedexpansion

set ID_FILE="C:\BackupConfigs\last_shadow_id.txt"
if not exist %ID_FILE% (
    echo %DATE% %TIME%: Файл с ID теневой копии не найден. >> "C:\BackupLogs\archive_errors.log"
    exit /b 1
)

set /p SHADOW_ID=<%ID_FILE%

echo Обработка теневой копии !SHADOW_ID!...
for /f "tokens=*" %%j in ('vssadmin list shadows /shadow=!SHADOW_ID! ^| find "Теневой том"') do set SHADOW_VOLUME=%%j
set SHADOW_VOLUME=!SHADOW_VOLUME:*~1024!
set SHADOW_VOLUME=!SHADOW_VOLUME:~17!
set SHADOW_SOURCE=!SHADOW_VOLUME!\soft

echo Копирование данных из !SHADOW_SOURCE! в C:\softbackup...
robocopy "!SHADOW_SOURCE!" "C:\softbackup" /MIR /NJH /NJS /NP /R:3 /W:5

echo Архивирование папки C:\softbackup...
"C:\Program Files\WinRAR\Rar.exe" a -r -m5 -df "D:\Backups\soft_backup_%DATE:~-4%-%DATE:~3,2%-%DATE:~0,2%.rar" "C:\softbackup\*"

echo Удаление теневой копии !SHADOW_ID!...
vssadmin delete shadows /shadow=!SHADOW_ID! /quiet

del /f /q %ID_FILE%
echo Операция завершена успешно.
