# PowerShell 2.0. Backup Toolkit

Набор PowerShell-скриптов для автоматизации резервного копирования файлов и папок под Windows.

## Возможности

- **Архивирование** — создание локальных архивов с использованием RAR
- **Копирование** — доставка архивов в сетевое хранилище
- **Ротация** — управляемое удаление старых резервных копий
- **Уведомления** — отправка email-отчётов о результатах бэкапа
- **Логирование** — подробные логи всех операций
- **Верификация** — проверка целостности созданных архивов

## Совместимость

- Windows PowerShell 2.0
- Windows 7

## Структура проекта

```

```

## Быстрый старт

### 1. Настройка конфигурации

Файл конфигурации

### 2. Запуск скрипта

```powershell
powershell.exe -executionpolicy RemoteSigned -file .\Backup-ps2.ps1
```

### 3. Запуск теста

```powershell
powershell.exe -executionpolicy RemoteSigned -file .\Backup-ps2.ps1 -testmode
```

## Варианты конфигурации


## Документация

- [constitution.md](docs/constitution.md) — архитектурные правила и принципы проекта
- [Backup_info.md](docs/Backup_info.md) — техническая спецификация
- [Backup_shema.md](docs/Backup_shema.md) — схема процесса бэкапа (PlantUML)

## Лицензия

Apache License 2.0 — см. [LICENSE](LICENSE)
