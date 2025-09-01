@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Путь к папке источнику
set "PATH_SRC=test"

REM Создаем директории для логов если их нет
set "PATH_LOGS=c:\Work\Backups\Logs"
if not exist "!PATH_LOGS!" mkdir "!PATH_LOGS!"

set "errorsLog=!PATH_LOGS!\archive_errors.log"
set "Log=!PATH_LOGS!\archive_log.log"
set ID_FILE="!PATH_LOGS!\last_shadow_id.txt"

echo %DATE% %TIME%: Запуск скрипта архивации >> "!Log!"

if not exist !ID_FILE! (
    echo %DATE% %TIME%: Файл с ID теневой копии не найден. >> "!errorsLog!"
    exit /b 1
)

set /p SHADOW_ID=<!ID_FILE!
echo %DATE% %TIME%: Обработка теневой копии !SHADOW_ID!... >> "!Log!"

echo Получен !SHADOW_ID!

REM Сохраняем вывод vssadmin во временный файл для анализа
set "TEMP_OUTPUT=%TEMP%\vssadmin_output.txt"
vssadmin list shadows /shadow=!SHADOW_ID! > "!TEMP_OUTPUT!" 2>&1

REM Ищем строку с путем к теневой копии и извлекаем только путь
set SHADOW_PATH=
for /f "tokens=*" %%j in ('type "!TEMP_OUTPUT!" ^| find "Shadow Copy Volume"') do (
    set "line=%%j"
    for /f "tokens=2 delims=:" %%k in ("!line!") do (
        for /f "tokens=* delims= " %%l in ("%%k") do set "SHADOW_PATH=%%l"
    )
)

if "!SHADOW_PATH!"=="" (
    for /f "tokens=3" %%j in ('type "!TEMP_OUTPUT!" ^| find "Том теневой копии"') do (
        set "SHADOW_PATH=%%j"
    )
)

del "!TEMP_OUTPUT!"

if "!SHADOW_PATH!"=="" (
    echo %DATE% %TIME%: Не удалось найти путь к теневой копии !SHADOW_ID! >> "!errorsLog!"
    echo %DATE% %TIME%: Вывод команды vssadmin: >> "!errorsLog!"
    vssadmin list shadows /shadow=!SHADOW_ID! >> "!errorsLog!" 2>&1
    exit /b 1
)

echo получен путь: !SHADOW_PATH! >> "!Log!"
echo получен путь: !SHADOW_PATH!

set "SHADOW_SOURCE=!SHADOW_PATH!\!PATH_SRC!"
echo %DATE% %TIME%: Источник данных: !SHADOW_SOURCE! >> "!Log!"

echo получен источник: !SHADOW_SOURCE!

endlocal