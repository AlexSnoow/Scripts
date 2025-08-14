@echo off
setlocal enabledelayedexpansion

:: Параметры конфигурации
set "target_dir=%~1"
if "%target_dir%"=="" set "target_dir=C:\Logs"
set /a days_old=30
set /a keep_min=5

:: Проверка директории
if not exist "%target_dir%" (
    echo Ошибка: Директория "%target_dir%" не существует
    exit /b 1
)

:: Получение количества файлов в директории
set /a file_count=0
for /f %%a in ('dir /b /a-d "%target_dir%\*" 2^>nul ^| find /c /v ""') do set /a file_count=%%a

:: Если файлов меньше минимального - выход
if %file_count% leq %keep_min% (
    echo Файлов в директории: %file_count% (меньше/равно %keep_min%). Удаление не требуется.
    exit /b 0
)

:: Удаление файлов старше N дней с сохранением минимального количества
set /a counter=0
for /f "delims=" %%f in ('dir /b /a-d /o-d "%target_dir%\*"') do (
    set /a counter+=1
    if !counter! gtr %keep_min% (
        forfiles /p "%target_dir%" /m "%%f" /d -%days_old% /c "cmd /c if @isdir==FALSE del /q @path"
    )
)

echo Операция завершена. Сохранено файлов: %keep_min%
exit /b 0
