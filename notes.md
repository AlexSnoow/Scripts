# Заметки
@REM mklink /j "vss" "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy11\"
@REM rmdir /v "vss"

REM Копирование данных
@REM echo Копирование данных из !SHADOW_SOURCE! в ...
@REM robocopy "!SHADOW_SOURCE!" "c:\Work\Backups\_Backup_Temp" /MIR /R:3 /W:5 /LOG+:"!Log!" /TEE


@REM if !errorlevel! geq 8 (
@REM     echo %DATE% %TIME%: Ошибка копирования данных. Код ошибки: !errorlevel! >> "!errorsLog!"
@REM     exit /b 1
@REM )

@REM vssadmin delete shadows /all /quiet

@REM echo %DATE% %TIME%: Операция завершена успешно. >> "!Log!"