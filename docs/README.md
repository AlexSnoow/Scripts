# Документация проекта PowerShell Backup Toolkit

## Структура документации

### Обзор и архитектура
| Файл | Описание |
|------|----------|
| `Backup_info.md` | Обзор пайплайна резервного копирования |
| `BACKUP_PIPELINE_OVERVIEW.md` | Диаграммы 5-этапного пайплайна (PlantUML) |
| `Backup_shema.md` | Диаграммы процесса (PlantUML) |
| `Backup_Shema.mermaid` | Диаграммы в формате Mermaid |
| `Backup_Shema_Corrected.mermaid` | Исправленная версия Mermaid-диаграмм |

### Конфигурация
| Файл | Описание |
|------|----------|
| `Backup_Config_Reference.md` | Справочник XML-конфигурации |

### API и функции
| Файл | Описание |
|------|----------|
| `Backup_API_Reference.md` | Справочник функций PowerShell (рус.) |
| `FUNCTIONS_REFERENCE.md` | English function reference |

### Совместимость
| Файл | Описание |
|------|----------|
| `PowerShell_info.md` | Совместимость с PowerShell 2.0 |

### Рефакторинг
| Файл | Описание |
|------|----------|
| `REFactoring-NOTES.md` | Примечания по рефакторингу |

### Модуль Copy
| Файл | Описание |
|------|----------|
| `copy/README.md` | Документация модуля копирования |

### Планы и развитие
| Файл | Описание |
|------|----------|
| `DEVELOPMENT_PLAN.md` | План развития проекта |

### Команда
| Файл | Описание |
|------|----------|
| `constitution.md` | Team constitution |

---

## Структура проекта (кратко)

```
Scripts/
├── app/
│   ├── ps/
│   │   ├── backup/  ← резервное копирование с RAR
│   │   └── copy/    ← обычное копирование
│   └── bash/        ← Linux/Solaris аналоги
├── docs/
│   ├── copy/        ← документация модуля Copy
│   └── ...          ← эта документация
├── README.md        ← главный README
└── AGENTS.md        ← инструкция для AI-агентов
```
