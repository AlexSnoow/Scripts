# Roadmap — План развития проекта

> **Version**: 2.0 | **Date**: 2026-06-08
>
> Единый файл плана развития. Обновляется по мере выполнения задач.
> Техническая архитектура — `docs/plan.md`, конституция — `docs/constitution.md`.

---

## Цель проекта

Создание надёжного мультиплатформенного инструментария для автоматизации файловых операций:
Backup, Copy, Sync, Cleanup, Monitor — на PowerShell 2.0 (Windows 7+) и Bash 3.0+ (Linux/Solaris 10+).

---

## Текущее состояние

| Модуль | Платформа | Скрипт | Статус |
|--------|-----------|--------|--------|
| Backup | PS 2.0 | `app/ps/backup/backup-ps2-v6.ps1` | ✅ Работает |
| Copy | PS 2.0 | `app/ps/copy/copy-ps2-v4.ps1` | ⚠️ Базовый, нужны доработки |
| Backup | Bash 3.0+ | `app/bash/backup/backup-g-v4.sh` | ✅ Работает |
| Sync | PS 2.0 | Skeleton (см. [[pipeline-template]]) | ⏳ Требует реализации |
| Cleanup | PS 2.0 | Skeleton (см. [[pipeline-template]]) | ⏳ Требует реализации |
| Monitor | PS 2.0 | Skeleton (см. [[pipeline-template]]) | ⏳ Требует реализации |

---

## Этап 1: Доработка Copy (P0 — ближайший спринт)

### Задачи

| ID | Задача | Описание | Статус |
|----|--------|----------|--------|
| COPY-001 | Email-уведомления | Реализовать `Send-EmailReport` в copy-ps2-v4.ps1, добавить `<ReportEmail>` в Copy-Config.xml | ⏳ |
| COPY-002 | Bash-аналог Copy | Создать `app/bash/copy/copy-v4.sh` + `copy.conf` (bash 3.0+) | ⏳ |
| COPY-003 | Маски файлов | Добавить `<FileMasks>` в Copy-Config.xml, аналог `Filter-FileMasks` из Backup | ⏳ |
| COPY-004 | Ротация | Добавить `<ArchiveRetention>` (DaysOld/KeepCount), аналог `Remove-OldFiles` | ⏳ |
| COPY-005 | Документация | Обновить `docs/copy/README.md` после каждой доработки | ⏳ |

### Критерии завершения этапа
- copy-ps2-v4.ps1 отправляет email после каждого Job
- copy-v4.sh работает на bash 3.0+ (проверено на Solaris 10)
- Маски файлов работают в режимах ByDate, IndividualFiles, IndividualFolders
- Ротация удаляет старые файлы из Arhive по DaysOld/KeepCount

---

## Этап 2: Реализация Sync (P1)

### Задачи

| ID | Задача | Описание | Статус |
|----|--------|----------|--------|
| SYNC-001 | Sync PS | Реализовать `app/ps/sync/sync-ps2-v4.ps1` по skeleton из PIPELINE_TEMPLATE.md | ⏳ |
| SYNC-002 | Sync Config PS | Создать `app/ps/sync/Sync-Config.xml` | ⏳ |
| SYNC-003 | Sync Bash | Создать `app/bash/sync/sync-v4.sh` + `sync.conf` | ⏳ |
| SYNC-004 | Режимы sync | Реализовать incremental, mirror, full | ⏳ |
| SYNC-005 | Тесты | Pester для Sync, bash unit для sync-v4.sh | ⏳ |

### Критерии завершения этапа
- Все три режима (incremental, mirror, full) работают корректно
- Верификация файлов после синхронизации
- Тесты пройдены

---

## Этап 3: Реализация Cleanup (P1)

### Задачи

| ID | Задача | Описание | Статус |
|----|--------|----------|--------|
| CLEANUP-001 | Cleanup PS | Реализовать `app/ps/cleanup/cleanup-ps2-v4.ps1` по skeleton | ⏳ |
| CLEANUP-002 | Cleanup Config PS | Создать `app/ps/cleanup/Cleanup-Config.xml` | ⏳ |
| CLEANUP-003 | Cleanup Bash | Создать `app/bash/cleanup/cleanup-v4.sh` + `cleanup.conf` | ⏳ |
| CLEANUP-004 | Безопасность | Белый список опасных путей, ExcludePatterns | ⏳ |
| CLEANUP-005 | Тесты | Pester для Cleanup, bash unit | ⏳ |

### Критерии завершения этапа
- Очистка работает по DaysOld и KeepCount
- Защита от удаления системных директорий
- Логирование всех удалений

---

## Этап 4: Реализация Monitor (P2)

### Задачи

| ID | Задача | Описание | Статус |
|----|--------|----------|--------|
| MONITOR-001 | Monitor PS | Реализовать `app/ps/monitor/monitor-ps2-v4.ps1` по skeleton | ⏳ |
| MONITOR-002 | Monitor Config PS | Создать `app/ps/monitor/Monitor-Config.xml` | ⏳ |
| MONITOR-003 | Monitor Bash | Создать `app/bash/monitor/monitor-v4.sh` + `monitor.conf` | ⏳ |
| MONITOR-004 | Типы проверок | FreeSpace, PathExists, MaxSize + новые | ⏳ |
| MONITOR-005 | Тесты | Pester для Monitor, bash unit | ⏳ |

### Критерии завершения этапа
- Проверки дисков, путей, размеров работают
- Email отправляется только при ошибках/предупреждениях
- XML-отчёт формируется

---

## Этап 5: Унификация и документация (P2)

### Задачи

| ID | Задача | Описание | Статус |
|----|--------|----------|--------|
| UNIFY-001 | Общий schema | Создать общий XSD для всех Config.xml | ⏳ |
| UNIFY-002 | Документация | Полные README для всех модулей | ⏳ |
| UNIFY-003 | CHANGELOG | Создать CHANGELOG.md | ⏳ |
| UNIFY-004 | Удаление дублей | Очистить docs/ от устаревших файлов | ⏳ |

---

## Архив

### Выполненные задачи

| ID | Задача | Дата | Результат |
|----|--------|------|-----------|
| BACKLOG-001 | Документация Copy | 2026-06 | Создан [[copy-module]] |

---

## Зависимости между задачами

```
COPY-001 (Email) ──────────────────────┐
COPY-002 (Bash Copy) ─────────────────┤
COPY-003 (Маски) ─────────────────────┤
COPY-004 (Ротация) ───────────────────┘
                                      │
                                      ▼
                          ┌─────────────────────┐
                          │   Этап 2: Sync      │
                          └─────────────────────┘
                                      │
                                      ▼
                          ┌─────────────────────┐
                          │   Этап 3: Cleanup   │
                          └─────────────────────┘
                                      │
                                      ▼
                          ┌─────────────────────┐
                          │   Этап 4: Monitor   │
                          └─────────────────────┘
                                      │
                                      ▼
                          ┌─────────────────────┐
                          │   Этап 5: Унификация│
                          └─────────────────────┘
```

---

## Правила обновления roadmap

1. Статус задачи обновляется при начале/завершении работы
2. Новые задачи добавляются в соответствующий этап
3. Выполненные задачи переносятся в секцию "Архив"
4. Критерии завершения этапа проверяются перед переходом к следующему

---

*Последнее обновление: 2026-06-08*
