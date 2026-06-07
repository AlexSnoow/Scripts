Финальный план: docs/PIPELINE_TEMPLATE.md (10/10)
Цель
Документ-шаблон для создания скриптов с 5-этапным пайплайном на PowerShell и Bash. Содержит: теорию паттерна, эталонный пример из Backup, два готовых скрипта (sync), скелеты для Cleanup и Monitor, шаблоны конфигов, чек-лист.
Итоговые решения
Вопрос	Решение
Типы скриптов	Backup, Copy, Sync, Cleanup, Monitor
Платформы	PS (Windows), Bash (Linux/Solaris)
Конфигурация	XML для PS, Shell conf для Bash
Структура PS	app/ps/{type}/ (существующие + новые)
Структура Bash	app/bash/{type}/ (подкаталоги)
Именование	{type}-ps-v4.ps1 / {type}-bash-v4.sh
Утилиты	Копии в каждом скрипте (монолит)
Детализация скелетов	Рабочий код с базовой логикой
Эталонные примеры	sync-ps-v4.ps1 + sync-bash-v4.sh (полностью готовые)
Миграция	Не нужна (только новые скрипты)
Язык	Русский
Тесты	Pester для PS, Bash unit для Bash
Структура документа PIPELINE_TEMPLATE.md
# Шаблон 5-Stage Pipeline

## 1. Паттерн "5-Stage Pipeline"
   1.1. Обзор паттерна (абстрактно)
   1.2. Этап 1: Подготовка (Preparation)
   1.3. Этап 2: Главная операция (Main Operation)
   1.4. Этап 3: Верификация (Verification)
   1.5. Этап 4: Пост-операции (Post-Operations)
   1.6. Этап 5: Отчётность (Reporting)
   1.7. Mermaid-диаграмма пайплайна
   1.8. Обязательные правила (из constitution.md)

## 2. Реализация в Backup-ps2-g-v4.ps1 (эталон)
   2.1. Точка входа (line 766-901)
   2.2. Загрузка конфига (line 768-794)
   2.3. Preparation > Invoke-Job (line 684-762)
   2.4. Main Operation > Invoke-Archiving (line 628-679)
   2.5. Verification > ExitCode + Test-FileIntegrity (line 667-676, 241-293)
   2.6. Post-Operations > Remove-OldFiles + Copy-Remote (line 354-422, 329-348)
   2.7. Reporting > Send-Email + сводка (line 24-81, 846-900)
   2.8. Связи между этапами (таблица)

## 3. PowerShell Skeleton (рабочий код)
   3.1. Скелет sync-ps-v4.ps1 (полностью готовый)
   3.2. Скелет cleanup-ps-v4.ps1 (с TODO-маркерами для логики)
   3.3. Скелет monitor-ps-v4.ps1 (с TODO-маркерами для логики)

## 4. Bash Skeleton (рабочий код)
   4.1. Скелет sync-bash-v4.sh (полностью готовый)
   4.2. Скелет cleanup-bash-v4.sh (с TODO-маркерами)
   4.3. Скелет monitor-bash-v4.sh (с TODO-маркерами)

## 5. Шаблоны конфигурации
   5.1. XML-шаблон (Sync)
   5.2. XML-шаблон (Cleanup)
   5.3. XML-шаблон (Monitor)
   5.4. Shell conf-шаблон (Sync)
   5.5. Shell conf-шаблон (Cleanup)
   5.6. Shell conf-шаблон (Monitor)

## 6. Справочник: что делает каждый тип скрипта
   6.1. Backup — назначение, этапы, особенности PS vs Bash
   6.2. Copy — назначение, этапы, особенности PS vs Bash
   6.3. Sync — назначение, этапы, режимы (полная/инкрементальная)
   6.4. Cleanup — назначение, этапы, политики очистки
   6.5. Monitor — назначение, этапы, что проверяется

## 7. Чек-лист создания нового скрипта
   7.1. Выбор типа и платформы
   7.2. Создание каталогов
   7.3. Копирование скелета
   7.4. Заполнение логики
   7.5. Создание конфига
   7.6. Тестирование
   7.7. Документация
Детали по разделам
Раздел 1: Паттерн
Абстрактное описание без привязки к конкретному скрипту. Каждый этап:
- Назначение (1-2 предложения)
- Входные данные (что нужно на входе)
- Выходные данные (что выдаёт)
- Обязательные проверки (что нельзя пропустить)
Mermaid-диаграмма:
[Preparation] > [Main Operation] > [Verification] > [Post-Operations] > [Reporting]
Правила из constitution.md:
- Порядок этапов запрещено нарушать
- Верификация до удаления источников
- Ротация после создания новых файлов
Раздел 2: Эталон Backup
Конкретные ссылки на Backup-ps2-g-v4.ps1:
Этап	Функция
Preparation	Invoke-Job, $ctx, Prepare-*
Main Operation	Invoke-Archiving, Get-RarParams
Verification	ExitCode check, Test-FileIntegrity
Post-Operations	Remove-OldFiles, Copy-Remote
Reporting	Send-Email, сводка
Раздел 3: PowerShell Skeleton
sync-ps-v4.ps1 — полностью готовый скрипт:
- Параметры: -ConfigurationPath, -testmode
- Утилиты: Write-Log, Send-Email, Get-FileHashCompat, Test-FileIntegrity, Remove-OldFiles, Get-DiskSpaceReport
- Пайплайн: Preparation (сканирование source/dest) > Main Operation (rsync-логика через Compare-Object) > Verification (сравнение размеров) > Post-Operations (ротация) > Reporting (XML + email)
cleanup-ps-v4.ps1 — скелет с TODO:
- Параметры: -ConfigurationPath, -testmode
- Утилиты: общие
- Пайплайн: Preparation (сканирование по маскам) > Main Operation (удаление по политикам) > Verification (проверка удаления) > Post-Operations (очистка temp) > Reporting
monitor-ps-v4.ps1 — скелет с TODO:
- Параметры: -ConfigurationPath
- Утилиты: общие
- Пайплайн: Preparation (список путей для проверки) > Main Operation (проверка доступности, размеров, free space) > Verification (сравнение с порогами) > Post-Operations (нет) > Reporting (XML + email)
Раздел 4: Bash Skeleton
Аналогичные три скрипта на Bash:
- sync-bash-v4.sh — полностью готовый
- cleanup-bash-v4.sh — с TODO
- monitor-bash-v4.sh — с TODO
Утилиты Bash: log(), resolve_name(), copy_remote(), rotate_files(), send_email() (curl/netcat).
Раздел 5: Конфигурации
Sync XML (минимальный):
<SyncConfig>
  <General>
    <ParentJobName>SyncAll</ParentJobName>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\SyncAll\logs</LogPathRoot>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Jobs>
    <Job Name="JOB1">
      <Source>C:\Source\</Source>
      <Dest>C:\Dest\</Dest>
      <Mode>incremental</Mode> <!-- full | incremental -->
      <ExcludeToday>true</ExcludeToday>
      <SourceFilter>*</SourceFilter>
    </Job>
  </Jobs>
</SyncConfig>
Cleanup XML (минимальный):
<CleanupConfig>
  <General>
    <ParentJobName>CleanupAll</ParentJobName>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\CleanupAll\logs</LogPathRoot>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Jobs>
    <Job Name="JOB1">
      <TargetPath>C:\Temp\</TargetPath>
      <FileMasks>*.tmp,*.log,*.bak</FileMasks>
      <DaysOld>30</DaysOld>
      <KeepCount>10</KeepCount>
      <Recurse>true</Recurse>
    </Job>
  </Jobs>
</CleanupConfig>
Monitor XML (минимальный):
<MonitorConfig>
  <General>
    <ParentJobName>MonitorAll</ParentJobName>
    <SmtpServer>smtp.localdomain.loc</SmtpServer>
  </General>
  <Paths>
    <LogPathRoot>C:\Work\MonitorAll\logs</LogPathRoot>
  </Paths>
  <Recipients>
    <AdminMail>admin@localdomain.loc</AdminMail>
  </Recipients>
  <Checks>
    <Check Name="DISK_C">
      <Type>FreeSpace</Type>
      <Path>C:\</Path>
      <MinFreeGB>10</MinFreeGB>
    </Check>
    <Check Name="BACKUP_DIR">
      <Type>PathExists</Type>
      <Path>C:\Backup\</Path>
    </Check>
    <Check Name="LOG_SIZE">
      <Type>MaxSize</Type>
      <Path>C:\Work\logs\</Path>
      <MaxSizeMB>500</MaxSizeMB>
    </Check>
  </Checks>
</MonitorConfig>
Shell conf — аналогичные файлы для Bash (key=value).
Раздел 6: Справочник
Таблица для каждого типа:
Тип	Назначение	Этапы	Backup PS
Backup	Архивация RAR/tar.gz	5/5	RAR
Copy	Копирование без архивации	5/5	Copy-Item
Sync	Синхронизация директорий	5/5	Compare-Object
Cleanup	Очистка по политикам	3-5/5	Remove-Item
Monitor	Проверка ресурсов	3-5/5	.NET classes
Раздел 7: Чек-лист
Пошаговый:
1. Выбрать тип (Backup/Copy/Sync/Cleanup/Monitor)
2. Выбрать платформу (PS/Bash/обе)
3. Создать каталог app/ps/{type}/ или app/bash/{type}/
4. Скопировать соответствующий скелет
5. Заполнить TODO-маркеты логикой
6. Создать XML/conf конфигурацию
7. Протестировать через -testmode
8. Написать документацию в docs/{type}/README.md
9. Добавить в AGENTS.md команды запуска
Файлы
Файл	Действие	Описание
docs/PIPELINE_TEMPLATE.md	Создать	Основной документ (~800-1000 строк)
Изменения в существующих файлах не предполагаются.