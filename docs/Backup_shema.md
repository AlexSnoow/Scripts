@startuml
title Процесс выполнения задания

start
:Начало работы;
:Загрузка конфигурации;
if (Проверка флага Enabled\nЗапускать задание?) then (Yes)
    if (Проверка флага Create_Backup_Rar\nСоздавать архив?) then (Yes)
        :Запуск Create_Backup_Rar.ps1;
        if (Проверка статуса архивации?) then (Success)
        else (Error)
            :Фиксирование ошибки;
            -> Завершение работы;
        endif
    else (No)
    endif

    if (Проверка флага Copy-Robocopy\nСоздавать копию?) then (Yes)
        :Запуск Copy-Robocopy.ps1;
        if (Проверка статуса копирования?) then (Success)
        else (Error)
            :Фиксирование ошибки;
            -> Завершение работы;
        endif
    else (No)
    endif

    if (Проверка флага Remove-OldFiles\nУдалять старые файлы?) then (Yes)
        :Запуск Remove-OldFiles.ps1;
        if (Проверка статуса очистки?) then (Success)
        else (Error)
            :Фиксирование ошибки;
            -> Завершение работы;
        endif
    else (No)
    endif

    if (Проверка флага Send-Mail\nОтправлять сообщения?) then (Yes)
        :Запуск Send-Mail.ps1;
    else (No)
    endif
else (No)
endif

:Завершение работы;
stop
@enduml