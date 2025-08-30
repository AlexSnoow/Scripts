@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Создаем директории для логов если их нет
if not exist "C:\Work\Backups\Logs" mkdir "C:\Work\Backups\Logs"

set "errorsLog=C:\Work\Backups\Logs\archive_errors.log"
set "Log=C:\Work\Backups\Logs\archive_log.log"
set ID_FILE="C:\Work\Backups\Logs\last_shadow_id.txt"

echo %DATE% %TIME%: Запуск скрипта архивации >> "!Log!"

if not exist !ID_FILE! (
    echo %DATE% %TIME%: Файл с ID теневой копии не найден. >> "!errorsLog!"
    exit /b 1
)

set /p SHADOW_ID=<!ID_FILE!
echo %DATE% %TIME%: Обработка теневой копии !SHADOW_ID!... >> "!Log!"

REM Универсальный метод поиска пути к теневой копии
set SHADOW_PATH=
for /f "tokens=*" %%j in ('vssadmin list shadows /shadow=!SHADOW_ID! ^| find "Volume"') do (
    set "SHADOW_VOLUME=%%j"
    REM Извлекаем путь из строки
    for /f "tokens=2 delims=: " %%k in ("!SHADOW_VOLUME!") do set "SHADOW_PATH=%%k"
)

if "!SHADOW_PATH!"=="" (
    echo %DATE% %TIME%: Не удалось найти путь к теневой копии !SHADOW_ID! >> "!errorsLog!"
    exit /b 1
)

set "SHADOW_SOURCE=!SHADOW_PATH!\soft"
echo %DATE% %TIME%: Источник данных: !SHADOW_SOURCE! >> "!Log!"

REM Копирование данных
echo Копирование данных из !SHADOW_SOURCE! в C:\softbackup...
robocopy "!SHADOW_SOURCE!" "C:\softbackup" /MIR /NJH /NJS /NP /R:3 /W:5 >> "!Log!" 2>&1

REM Архивирование
echo Архивирование папки C:\softbackup...
"C:\Program Files\WinRAR\Rar.exe" a -r -m5 -df "D:\Backups\soft_backup_%DATE:~-4%-%DATE:~3,2%-%DATE:~0,2%.rar" "C:\softbackup\*" >> "!Log!" 2>&1

REM Удаление теневой копии
echo Удаление теневой копии !SHADOW_ID!...
vssadmin delete shadows /shadow=!SHADOW_ID! /quiet >> "!Log!" 2>&1

del /f /q !ID_FILE! >> "!Log!" 2>&1
echo %DATE% %TIME%: Операция завершена успешно. >> "!Log!"

endlocal