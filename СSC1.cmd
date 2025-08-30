@echo off
setlocal enabledelayedexpansion

REM Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo %DATE% %TIME%: Скрипт требует запуска от имени Администратора. >> "C:\BackupLogs\shadow_errors.log"
    exit /b 1
)

REM Создание необходимых папок
if not exist "C:\BackupLogs" mkdir "C:\BackupLogs"
if not exist "C:\BackupConfigs" mkdir "C:\BackupConfigs"

echo %DATE% %TIME%: Попытка создания теневой копии тома C:... >> "C:\BackupLogs\shadow_log.log"

REM Создание теневой копии и универсальный парсинг ID
set SHADOW_ID=
for /f "tokens=2" %%i in ('vssadmin create shadow /for=C: ^| findstr /i /c:"ID"') do set SHADOW_ID=%%i

if "!SHADOW_ID!"=="" (
    echo %DATE% %TIME%: Ошибка: Не удалось создать теневую копию. Проверьте состояние VSS-писателей (vssadmin list writers). >> "C:\BackupLogs\shadow_errors.log"
    exit /b 1
)

echo %DATE% %TIME%: Теневая копия создана: !SHADOW_ID! >> "C:\BackupLogs\shadow_log.log"
echo !SHADOW_ID! > "C:\BackupConfigs\last_shadow_id.txt"

endlocal
