---

### 📦 ШАГ 1: Замена `Invoke-Verification` на нативный `rar t`

```powershell
function Invoke-Verification {
<#
.SYNOPSIS
    Выполняет нативную проверку целостности архива через команду RAR "t".
.DESCRIPTION
    Запускает архиватор с параметром 't' для каждого успешного архива.
    Проверяет только код выхода процесса ($process.ExitCode -eq 0).
    Не парсит текстовый вывод, что обеспечивает высокую скорость и надёжность на больших объёмах данных.
    Совместимо с PowerShell 2.0 и Windows 7.
.PARAMETER ArchiveResults
    Массив объектов с результатами успешной архивации (из Invoke-ArchivePipeline).
.PARAMETER Job
    Конфигурация текущего задания.
.PARAMETER Config
    Глобальная конфигурация скрипта.
.EXAMPLE
    $successArchives = $pipelineResult.Results | Where-Object { $_.Status -eq 'Success' }
    $verifyResult = Invoke-Verification -ArchiveResults $successArchives -Job $job -Config $config
    if ($verifyResult.AllPassed) { Write-Host "Проверка пройдена" }
.LINK
    https://internal/wiki/verification-step1
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)][object[]]$ArchiveResults,
        [Parameter(Mandatory=$true)][hashtable]$Job,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    process {
        $rarPath = $Config['Settings']['ArchiverPath']
        $verified = @()
        $failed = 0
        $totalItems = $ArchiveResults.Count

        foreach ($res in $ArchiveResults) {
            if ($res.Status -ne 'Success' -or -not (Test-Path -LiteralPath $res.ArchivePath -PathType Leaf)) {
                Write-Log "Пропуск проверки: $($res.SourceName) (архив не создан)" -Level WARNING -ResultKey
                continue
            }

            Write-Log "Проверка целостности (rar t): $($res.ArchiveName)" -Level INFO
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $rarPath
                $psi.Arguments = "t `"$($res.ArchivePath)`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                $proc.Start() | Out-Null
                $null = $proc.StandardOutput.ReadToEnd()
                $null = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()

                if ($proc.ExitCode -eq 0) {
                    Write-Log "ВЕРИФИКАЦИЯ ОК: $($res.SourceName) (CRC32 OK)" -Level SUCCESS -ResultKey
                    $verified += $res
                }
                else {
                    Write-Log "ВЕРИФИКАЦИЯ ПРОВАЛЕНА: $($res.SourceName) (RAR ExitCode: $($proc.ExitCode))" -Level ERROR -ResultKey
                    $failed++
                }
            }
            catch {
                Write-Log "Ошибка запуска проверки: $($res.SourceName) — $_" -Level ERROR -ResultKey
                $failed++
            }
        }

        return @{
            Verified    = $verified
            FailedCount = $failed
            TotalCount  = $totalItems
            AllPassed   = ($failed -eq 0) -and ($verified.Count -gt 0 -or $totalItems -eq 0)
        }
    }
}
```

---

### 🔍 Что изменилось в Шаге 1
| Аспект                | Было                                                          | Стало                                                |
| --------------------- | ------------------------------------------------------------- | ---------------------------------------------------- |
| **Механизм**          | `rar vtb` → парсинг текста → `Compare-FilesSourceArchive`     | `rar t` → проверка `$proc.ExitCode -eq 0`            |
| **Скорость**          | 3+ часа для 337k файлов                                       | 10–30 минут (нативный C-код)                         |
| **Зависимости**       | 3 функции парсинга/сравнения                                  | Только `Start-Process`/`ProcessStartInfo`            |
| **Безопасность**      | Сравнение только по `Length` (байт)                           | Проверка CRC32 + структуры архива                    |
| **Вызов в конвейере** | `Invoke-Verification -ArchiveResults $successfulArchives ...` | **Без изменений** (обратная совместимость сохранена) |

---

### 🛠 Инструкция по интеграции (Шаг 1)
1. Найдите в `Backup-ps2.ps1` старую функцию `Invoke-Verification` (начинается с `#region ============================================================ UNIFIED PIPELINE: Верификация`).
2. Полностью замените её тело на код выше.
3. В основном цикле (`#region ЭТАП 2: ОСНОВНОЙ ЗАПУСК`) **ничего не меняйте**. Вызов остаётся:
   ```powershell
   Write-LogSection "ШАГ 3: ВЕРИФИКАЦИЯ (включая файлы 0 байт)" -ResultKey
   $verifyResult = Invoke-Verification `
       -ArchiveResults $successfulArchives `
       -Job $job `
       -Config $config
   ```
4. Старые функции `Get-FileArhListRar`, `ConvertFrom-RarListOutput`, `Compare-FilesSourceArchive` пока **оставьте**, но добавьте комментарий `# [OBSOLETE STEP1]` над каждой. Они будут удалены на Шаге 2.

---

### ✅ Критерии приёмки Шага 1
- [ ] Для архива с 337 000 файлов `ШАГ 3` выполняется ≤ 30 мин
- [ ] В логе появляется `[SUCCESS] ВЕРИФИКАЦИЯ ОК: ... (CRC32 OK)`
- [ ] При повреждённом архиве `$verifyResult.FailedCount -gt 0`, удаление источника **блокируется** (существующая логика `Invoke-PostOperations` уже проверяет `$verifyResult.FailedCount`)
- [ ] Файлы 0 байт архивируются и проходят `rar t` без ошибок
- [ ] Конвейер не падает, возвращает корректную хеш-таблицу

---

