# Project Structure

Актуальная структура проекта. Обновляется при изменениях.

```
Scripts/
├── app/
│   ├── ps/
│   │   ├── backup/               # PowerShell — Backup (архивация RAR/7zip/zip)
│   │   │   ├── <FileName>-<PSVersion>-<VersionScript>.ps1
│   │   │   ├── <FileName>-Config.xml
│   │   │   └── <FileName>-StatusView.ps1
│   │   ├── copy/                 # PowerShell — Copy (копирование без архиватора)
│   │   │   ├── <FileName>-<PSVersion>-<VersionScript>.ps1
│   │   │   ├── <FileName>-Config.xml
│   │   │   └── <FileName>-Files.ps1
│   │   ├── sync/                 # PowerShell — Sync (планируется)
│   │   ├── cleanup/              # PowerShell — Cleanup (планируется)
│   │   └── monitor/              # PowerShell — Monitor (планируется)
│   ├── bash/
│   │   ├── backup/               # Linux/Solaris — Backup (архивация tar.gz)
│   │   │   ├── <FileName>-<OS Linux/Solaris>-<VersionScript>.sh
│   │   │   └── <FileName>.conf
│   │   └── copy/                 # Linux/Solaris — Copy (планируется)
│   ├── lib/                      # Общие библиотеки
│   ├── sandbox/                  # Экспериментальный код
│   ├── tests/                    # Pester/Bash unit тесты
│   ├── PS_linter.ps1             # Линтер PowerShell
│   ├── Create-Test-Files-FromList.ps1
│   └── Test-Verification.ps1
├── tests/                        # Тестовые данные (src, dest, logs)
├── docs/
│   ├── wiki/                     # База знаний (Zettelkasten)
│   │   ├── index.md              # Карта знаний
│   │   ├── log.md                # Журнал изменений
│   │   ├── structure.md          # Структура проекта (этот файл)
│   │   ├── archive-modes.md
│   │   ├── common-functions.md
│   │   ├── copy-module.md
│   │   ├── pipeline-template.md
│   │   └── ps2-compatibility.md
│   ├── raw/                      # Черновики и заметки (только чтение)
│   ├── patterns/                 # Паттерны кода
│   ├── diagrams/                 # Диаграммы процессов
│   ├── constitution.md           # Конституция проекта
│   ├── specify.md                # Спецификация (доменные инварианты)
│   ├── plan.md                   # Архитектура и технологический стек
│   └── roadmap.md                # План развития
├── README.md                     # Главный файл документации
├── AGENTS.md                     # Инструкция для AI-агентов
└── LICENSE                       # Лицензия
```

## Шаблоны имён

| Шаблон | Пример | Назначение |
|--------|--------|------------|
| `<FileName>-<PSVersion>-<VersionScript>.ps1` | `backup-ps2-v6.ps1` | Основной скрипт (PowerShell) |
| `<FileName>-Config.xml` | `Backup-Config.xml` | Конфигурация (XML) |
| `<FileName>-<OS Linux/Solaris>-<VersionScript>.sh` | `backup-g-v4.sh` | Основной скрипт (Bash) |
| `<FileName>.conf` | `backup.conf` | Конфигурация (Bash, key=value) |

## Текущий охват

Реализованы модули **Backup** (PS + Bash) и **Copy** (PS). Остальные модули (Sync, Cleanup, Monitor) — в планах.
