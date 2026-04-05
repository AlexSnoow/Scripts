# PowerShell Backup Toolkit

Набор PowerShell-скриптов для автоматизации резервного копирования файлов и папок под Windows.

## Возможности

- **Архивирование** — создание локальных архивов с использованием RAR, 7-Zip или ZIP
- **Копирование** — доставка архивов в сетевое хранилище
- **Ротация** — управляемое удаление старых резервных копий
- **Уведомления** — отправка email-отчётов о результатах бэкапа
- **Логирование** — подробные логи всех операций
- **Верификация** — проверка целостности созданных архивов

## Совместимость

- Windows PowerShell 5.1
- Windows 10/11, Windows Server 2016+

## Структура проекта

```
├── src/                          # Исходный код
│   ├── Backup-Main-All.ps1       # Монолитный orchestrator (v2.5) — основной скрипт
│   ├── Backup-Main-Folders.ps1   # Folder-level orchestrator
│   ├── Backup-Main-Files.ps1     # File-level orchestrator
│   ├── modules/                  # PowerShell модули
│   │   ├── Backup-Logger.psm1    # Логирование
│   │   ├── Backup-RAR.psm1       # RAR архивирование
│   │   ├── Backup-7z.psm1        # 7-Zip архивирование
│   │   ├── Backup-Zip.psm1       # ZIP архивирование
│   │   ├── Backup-Copy.psm1      # Копирование в сетевое хранилище
│   │   ├── Remove-OldFiles.psm1  # Ротация старых бэкапов
│   │   └── Mail-Email-Send.psm1  # Email-уведомления
│   └── tests/                    # Тесты
├── config/                       # Конфигурации
│   ├── Backup-Config-All-rar.json
│   └── Backup-Config-All-rar_json_TEMPLATE.txt
├── docs/                         # Документация
│   ├── constitution.md           # Конституция проекта
│   ├── Backup_info.md            # Техническая спецификация
│   └── Backup_shema.md           # Схема процесса (PlantUML)
├── .gitignore
└── LICENSE
```

## Быстрый старт

### 1. Настройка конфигурации

Скопируйте шаблон конфигурации и отредактируйте пути:

```powershell
Copy-Item config/Backup-Config-All-rar_json_TEMPLATE.txt config/my-backup-config.json
```

Откройте `config/my-backup-config.json` и укажите:
- `SourcePath` — путь к источнику бэкапа
- `LocalBackupPath` — путь для локальных архивов
- `RemoteBackupPath` — путь к сетевому хранилищу (опционально)
- `ArchiverType` — тип архиватора: `RAR`, `7z` или `ZIP`

### 2. Запуск монолитного скрипта

```powershell
.\src\Backup-Main-All.ps1 -ConfigPath "config/my-backup-config.json"
```

### 3. Запуск модульного варианта

```powershell
# Folder-level (архивирование папок целиком)
.\src\Backup-Main-Folders.ps1

# File-level (архивирование отдельных файлов по маске)
.\src\Backup-Main-Files.ps1
```

## Режимы архиваторов

| Архиватор | Модуль | Описание |
|-----------|--------|----------|
| RAR | `Backup-RAR.psm1` | WinRAR, максимальное сжатие |
| 7-Zip | `Backup-7z.psm1` | Открытый формат, хорошее сжатие |
| ZIP | `Backup-Zip.psm1` | Встроенный в PowerShell, базовое сжатие |

## Документация

- [constitution.md](docs/constitution.md) — архитектурные правила и принципы проекта
- [Backup_info.md](docs/Backup_info.md) — техническая спецификация
- [Backup_shema.md](docs/Backup_shema.md) — схема процесса бэкапа (PlantUML)

## Лицензия

Apache License 2.0 — см. [LICENSE](LICENSE)
