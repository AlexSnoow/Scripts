@startuml
title Unified Pipeline: Процесс выполнения задания

start
:ЭТАП 0: Проверка XML конфигурации;
if (SHA256 хеш XML совпадает?) then (No)
    :Критическая ошибка - остановка;
    stop
else (Yes)
    :ЭТАП 1: Проверка RAR.exe;
    if (SHA256 хеш RAR совпадает?) then (No)
        :Критическая ошибка - остановка;
        stop
    else (Yes)
        :Инициализация логирования;
        :Загрузка конфигурации заданий;
        
        repeat для каждого задания (Job)
            :ШАГ 1: Подготовка элементов архивации;
            if (Режим IndividualFiles?) then (Yes)
                :Сканирование файлов по маске;
                :Создание списка ArchiveItem (по файлу);
            else (No)
                if (Режим IndividualFolders?) then (Yes)
                    :Сканирование подпапок;
                    :Создание списка ArchiveItem (по папке);
                else (No)
                    :Обычный режим (весь источник);
                    :Один ArchiveItem на задание;
                endif
            endif
            
            :ШАГ 2: Архивация через RAR;
            repeat для каждого ArchiveItem
                :Вызов Start-RarArchive;
                if (RAR ExitCode = 0?) then (Yes)
                    :Архив создан успешно;
                else (No)
                    :Запись ошибки в лог;
                endif
            repeat end
            
            :ШАГ 3: Верификация архивов;
            repeat для каждого успешного архива
                :Get-FileList (источник);
                :Get-FileArhListRar (архив);
                :Compare-FilesSourceArchive;
                if (Все файлы совпали?) then (Yes)
                    :Верификация OK;
                else (No)
                    :Запись ошибки верификации;
                endif
            repeat end
            
            :ШАГ 4: Пост-операции;
            if (RemoteDest указан?) then (Yes)
                :Копирование архивов в сетевое хранилище;
                if (RemoveRemoteDestFlag=true?) then (Yes)
                    :Ротация удалённого хранилища;
                endif
            endif
            
            if (RemoveSourceFlag=true?) then (Yes)
                if (Верификация прошла успешно?) then (Yes)
                    :Удаление источников;
                else (No)
                    :Удаление ОТМЕНЕНО (ошибки верификации);
                endif
            endif
            
            :Ротация локального хранилища;
            :Сохранение сетевых отчётов (XML/CSV);
        repeat end
        
        :Запись в Windows Event Log;
        :Отправка SMTP уведомлений;
    endif
endif

stop
@enduml

---

@startuml
title Структура данных ArchiveItem

class ArchiveItem {
    +SourcePath: string      # Путь к файлу/папке
    +SourceName: string      # Отображаемое имя
    +ArchiveName: string     # Имя выходного .rar
    +SourceType: string      # 'File' | 'Folder' | 'Directory'
    +SourceRoot: string      # Корень для верификации
    +SourceFilter: string    # Фильтр файлов (опционально)
}

note right of ArchiveItem
  Единая структура для всех режимов:
  - Normal: SourceType='Directory'
  - IndividualFiles: SourceType='File'
  - IndividualFolders: SourceType='Folder'
end note
@enduml

---

@startuml
title Формат сетевого отчёта (XML)

title BackupReport.xml

class BackupReport {
    +Host: string
    +Job: string
    +Timestamp: datetime
    +Status: string
    +Duration: string
    +SourceFiles: int
    +ArchiveSizeMB: double
    +Verification: string
    +LocalLogPath: string
    +Errors: Error[]
    +Warnings: Warning[]
}

class Error {
    +Message: string
}

class Warning {
    +Message: string
}

BackupReport *-- Error
BackupReport *-- Warning
@enduml

---

@startuml
title Формат сводного отчёта (summary.xml)

title HostSummary.xml

class HostSummary {
    +Host: string
    +LastRun: datetime
    +LastDuration: string
    +Job: Job[]
}

class Job {
    +name: string
    +status: string
    +error: string (опционально)
}

HostSummary *-- Job
@enduml