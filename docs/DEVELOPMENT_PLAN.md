# План развития проекта PowerShell Backup Toolkit

> **⚠️ Отложено до отдельного спринта.**
> Текущий спринт: обновление конституции и документации (см. docs/constitution.md, docs/specify.md, docs/plan.md).
> Необходимые обновления: таблица модулей (5 типов вместо 2), rename Start-RarArchive → Invoke-Archiving в PIPELINE_TEMPLATE.md.

## Текущее состояние

### Что есть

| Модуль | Платформа | Скрипт | Конфиг | Статус |
|--------|-----------|--------|--------|--------|
| Backup | Windows PS2.0 | `app/ps/backup/Backup-ps2-g-v4.ps1` | `app/ps/backup/Backup-Config.xml` | ✅ Работает |
| Copy   | Windows PS2.0 | `app/ps/copy/copy-ps2-v4.ps1` | `app/ps/copy/Copy-Config.xml` | ✅ Работает |
| Backup | Linux/Solaris | `app/bash/backup-g-v4.sh` | `app/bash/backup.conf` | ✅ Работает |
| Backup | Linux/Solaris | `app/bash/backup-g-v3.sh` | `app/bash/backup.conf` | ⚠️ Устаревший |

### Что нужно сделать

| Приоритет | Задача | Описание |
|-----------|--------|----------|
| **P0** | **[BACKLOG-001]** Унифицировать структуру | Привести Copy к тому же шаблону что Backup (версия, статус) |
| **P0** | **[BACKLOG-002]** Добавить email-уведвления в Copy | Реализовать отправку отчётов по email как в Backup |
| **P0** | **[BACKLOG-003]** Bash-аналог Copy | Создать `app/bash/copy-v4.sh` для Linux/Solaris |
| **P1** | **[BACKLOG-004]** Ротация в Copy | Добавить политики ротации архивов |
| **P1** | **[BACKLOG-005]** Маски файлов | Добавить поддержку масок (*.log, *.xml) в Copy |
| **P1** | **[BACKLOG-006]** Унифицировать конфигурацию | Общий schema для Backup-Config и Copy-Config |
| **P2** | **[BACKLOG-007]** Документация | Создать полные docs/ для обоих модулей |
| **P2** | **[BACKLOG-008]** Тесты | Pester-тесты для Copy |

---

## Этап 1: Унификация модулей (P0)

### Цель: Одинаковая схема и алгоритм работы для Backup и Copy

### 1.1. Единая структура

```
app/
├── ps/
│   ├── backup/
│   │   ├── Backup-ps2-g-v4.ps1          ← основной скрипт
│   │   ├── Backup-ps2-g-v3.ps1          ← предыдущая версия
│   │   ├── Backup-Config.xml            ← конфигурация
│   │   └── README.md                    ← документация модуля
│   │
│   └── copy/
│       ├── copy-ps2-v4.ps1              ← основной скрипт
│       ├── Copy-Config.xml              ← конфигурация
│       ├── Copy-Config-Example.xml      ← пример конфигурации
│       └── README.md                    ← документация модуля (создать)
│
└── bash/
    ├── backup-g-v4.sh                   ← основной скрипт
    ├── backup-g-v3.sh                   ← предыдущая версия
    ├── backup.conf                      ← конфигурация
    ├── copy-v4.sh                       ← будущий (создать)
    └── info.md                          ← документация
```

### 1.2. Единый алгоритм (5 стадий)

Оба модуля должны использовать одинаковую схему:

| Стадия | Backup | Copy |
|--------|--------|------|
| **Preparation** | Сканирование, проверка, маски | Чтение XML, инициализация |
| **Main Operation** | Архивирование RAR | Копирование файлов |
| **Verification** | RAR-тест + проверка файлов | Сравнение размеров |
| **Post-Operations** | Копирование, ротация, удаление | Перемещение в Arhive |
| **Reporting** | XML/CSV + email | XML + email (в процессе) |

### 1.3. Конкретные задачи

**[BACKLOG-001]** Создать `app/ps/copy/README.md` (аналог `app/bash/info.md`)
- [x] Создана: `docs/copy/README.md` (см. docs/copy/README.md)

**[BACKLOG-002]** Добавить email-уведвления в Copy
- [ ] Реализовать функцию `Send-EmailReport`
- [ ] Добавить поддержку `<ReportEmail>` в Copy-Config.xml
- [ ] Протестировать на PS2.0

**[BACKLOG-003]** Создать `app/bash/copy-v4.sh`
- [ ] Аналог `copy-ps2-v4.ps1` для bash
- [ ] Аналог `Copy-Config.xml` для bash (`Copy-Config.conf`)
- [ ] Совместимость с bash 3.0+ (Solaris 10)

---

## Этап 2: Расширение функциональности (P1)

**[BACKLOG-004]** Ротация в Copy
- [ ] Добавить параметр `<ArchiveRetention>` в Copy-Config.xml
- [ ] Логика удаления старых файлов из Arhive по дате/количеству
- [ ] Аналог `Rotate-ArchiveFiles` из Backup

**[BACKLOG-005]** Маски файлов
- [ ] Добавить `<FileMasks>` в Copy-Config.xml
- [ ] Поддержка: `*.log`, `*.xml`, `*`, `*.*`
- [ ] Аналог `Filter-FileMasks` из Backup

**[BACKLOG-006]** Унифицировать конфигурацию
- [ ] Создать общий XSD/XSL schema
- [ ] Общий корневой тег `<FileOperations>`
- [ ] Общий формат `<Job>` элементов
- [ ] Базовый класс конфигурации

---

## Этап 3: Документация и тесты (P2)

**[BACKLOG-007]** Полная документация
- [x] Обновлён `README.md` в корне проекта
- [x] Создана `docs/copy/README.md`
- [ ] Удалить дублирующуюся документацию (docs/README.md, masks.yaml)
- [ ] Создать `CHANGELOG.md`

**[BACKLOG-008]** Тесты
- [ ] Создать `app/tests/copy/`
- [ ] Pester-тесты для Copy-Config.xml
- [ ] Pester-тесты для copy-ps2-v4.ps1
- [ ] Bash-тесты для copy-v4.sh

---

## Этап 4: Оптимизация (P3)

**[BACKLOG-009]** Конкурентность
- [ ] Параллельная обработка Jobs
- [ ] Ограничение потоков (MaxConcurrentJobs)

**[BACKLOG-010]** Сетные пути
- [ ] Поддержка UNC путей с проверкой доступности
- [ ] Retry-логика при сетных ошибках

**[BACKLOG-011]** Мониторинг
- [ ] Интеграция с Zabbix/Prometheus
- [ ] Системный лог (event log)

---

## Приоритизация

```
Немедленно (Sprint 1):
  [BACKLOG-001] ✅ Done — Документация Copy
  [BACKLOG-002] Email в Copy
  [BACKLOG-003] Bash Copy

Следующий спринт:
  [BACKLOG-004] Ротация
  [BACKLOG-005] Маски
  [BACKLOG-006] Унификация конфигурации

Позже:
  [BACKLOG-007] Чистая документация
  [BACKLOG-008] Тесты
  [BACKLOG-009+] Оптимизация
```