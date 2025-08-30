@echo off
chcp 65001
setlocal enabledelayedexpansion

REM переменные
SET "errorsLog=C:\Work\Backups\Logs\shadow_errors.log"
SET "Log=C:\Work\Backups\Logs\shadow_log.log"
SET "shadowIdFile=C:\Work\Backups\Logs\last_shadow_id.txt"

REM Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo %DATE% %TIME%: Скрипт требует запуска от имени Администратора. >> "%errorsLog%"
    exit /b 1
)

echo %DATE% %TIME%: Попытка создания теневой копии тома C:... >> "%Log%"

REM Создание теневой копии и универсальный парсинг ID
set SHADOW_ID=
for /f "tokens=2" %%i in ('vssadmin Create Shadows /Quiet /for=C: ^| findstr /i /c:"ID"') do set SHADOW_ID=%%i

if "!SHADOW_ID!"=="" (
    echo %DATE% %TIME%: Ошибка: Не удалось создать теневую копию. Проверьте состояние VSS-писателей (vssadmin list writers). >> "%errorsLog%"
    exit /b 1
)

echo %DATE% %TIME%: Теневая копия создана: !SHADOW_ID! >> "%Log%"
echo !SHADOW_ID! > "%shadowIdFile%"

endlocal
