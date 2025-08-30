@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Создаем директории для логов если их нет
if not exist "C:\Work\Backups\Logs" mkdir "C:\Work\Backups\Logs"

REM переменные
SET "errorsLog=C:\Work\Backups\Logs\shadow_errors.log"
SET "Log=C:\Work\Backups\Logs\shadow_log.log"
SET "shadowIdFile=C:\Work\Backups\Logs\last_shadow_id.txt"

echo [DEBUG] Запуск скрипта: !DATE! !TIME! > "!Log!"
echo [DEBUG] Запуск скрипта: !DATE! !TIME!

REM Проверка прав администратора
net session >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Скрипт требует запуска от имени Администратора. >> "!errorsLog!"
    echo [ERROR] Скрипт требует запуска от имени Администратора.
    exit /b 1
)
echo [DEBUG] Права администратора подтверждены >> "!Log!"
echo [DEBUG] Права администратора подтверждены

REM Создание теневой копии через WMIC с подробным логированием
echo [DEBUG] Выполнение команды: wmic shadowcopy call create Volume=C:\ >> "!Log!"
echo [DEBUG] Выполнение команды: wmic shadowcopy call create Volume=C:\

set "TEMP_OUTPUT=%TEMP%\wmic_output.txt"
wmic shadowcopy call create Volume=C:\ > "!TEMP_OUTPUT!" 2>&1
set WMIC_EXITCODE=!errorlevel!

echo [DEBUG] Код возврата WMIC: !WMIC_EXITCODE! >> "!Log!"
echo [DEBUG] Код возврата WMIC: !WMIC_EXITCODE!

echo [DEBUG] Вывод команды WMIC: >> "!Log!"
type "!TEMP_OUTPUT!" >> "!Log!"
echo [DEBUG] Вывод команды WMIC:
type "!TEMP_OUTPUT!"

REM Парсинг вывода WMIC
set SHADOW_ID=
for /f "usebackq tokens=2 delims={}" %%i in (`type "!TEMP_OUTPUT!" ^| find "ShadowID"`) do (
    set "SHADOW_ID=%%i"
    set "SHADOW_ID=!SHADOW_ID:~0,-1!"
    set "SHADOW_ID={!SHADOW_ID!}"
)

if "!SHADOW_ID!"=="" (
    echo [ERROR] Не удалось извлечь ShadowID из вывода WMIC >> "!errorsLog!"
    echo [ERROR] Не удалось извлечь ShadowID из вывода WMIC
    goto :cleanup
)

echo [DEBUG] Извлеченный ShadowID: !SHADOW_ID! >> "!Log!"
echo [DEBUG] Извлеченный ShadowID: !SHADOW_ID!

echo !SHADOW_ID! > "!shadowIdFile!"
echo [SUCCESS] Теневая копия создана: !SHADOW_ID! >> "!Log!"
echo [SUCCESS] Теневая копия создана: !SHADOW_ID!

:cleanup
del "!TEMP_OUTPUT!" >nul 2>&1

REM Проверка существования теневой копии через vssadmin
echo [DEBUG] Проверка существования теневой копии через vssadmin list shadows >> "!Log!"
vssadmin list shadows >> "!Log!" 2>&1
echo [DEBUG] Проверка завершена >> "!Log!"

endlocal