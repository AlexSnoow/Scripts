<# file Test-Verification.ps1
.SYNOPSIS
    Скрипт модульного тестирования функций верификации.
.DESCRIPTION
    Проверяет корректность работы функции Compare-FilesSourceArchive на моделях данных.
    Тестирует:
    1. Полное совпадение.
    2. Отсутствие файлов в архиве.
    3. Лишние файлы в архиве.
    4. Несовпадение размеров.
    5. КРИТИЧЕСКИЙ ТЕСТ: Нормализация символов (Тире vs Дефис).
#>

# ===========================================================
#region ФУНКЦИИ (Копия логики из основного скрипта)
# ===========================================================

function Normalize-RelativePath {
    param([string]$FullPath, [string]$RootPath)
    process {
        $normalizedFull = $FullPath -replace '/', '\'
        $normalizedRoot = $RootPath -replace '/', '\'
        $normalizedFull = $normalizedFull.TrimEnd('\')
        $normalizedRoot = $normalizedRoot.TrimEnd('\')
        $lowerFull = $normalizedFull.ToLowerInvariant()
        $lowerRoot = $normalizedRoot.ToLowerInvariant()
        if ($lowerFull.StartsWith($lowerRoot)) {
            $relative = $normalizedFull.Substring($normalizedRoot.Length).TrimStart('\')
        }
        else { $relative = $normalizedFull }
        return $relative.ToLowerInvariant()
    }
}

function Compare-FilesSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$SourceList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ArchiveList,
        [Parameter(Mandatory=$false)][string]$SourcePath
    )
    process {
        Write-Verbose "Начало сравнения: Источник ($($SourceList.Count)) vs Архив ($($ArchiveList.Count))"
        
        # Функция нормализации символов
        $NormalizeChars = {
            param([string]$Text)
            $res = $Text
            $res = $res -replace '[\u2013\u2014\u2015]', '-'   # Тире -> дефис
            $res = $res -replace '[\u201c\u201d\u00ab\u00bb]', '"' 
            $res = $res -replace '\u2026', '...'
            return $res
        }

        # Хеш-таблицы
        $sourceHash = @{}
        foreach ($item in $SourceList) {
            $key = & $NormalizeChars $item.RelativePath.ToLowerInvariant()
            if (-not $sourceHash.ContainsKey($key)) { $sourceHash[$key] = $item }
        }

        $archiveHash = @{}
        foreach ($item in $ArchiveList) {
            $path = $item.RelativePath
            $path = $path -replace '^[A-Z]:\\', '' -replace '^\\\\\?\\', ''
            $path = ($path -replace '/', '\').TrimStart('\').ToLowerInvariant()
            
            $item.RelativePath = $path
            
            $key = & $NormalizeChars $path
            if (-not $archiveHash.ContainsKey($key)) { $archiveHash[$key] = $item }
        }

        $missingInArchive = @()
        $sizeMismatch = @()
        $extraInArchive = @()
        $isIdentical = $true

        # 1. Проверка файлов источника
        foreach ($key in $sourceHash.Keys) {
            $srcItem = $sourceHash[$key]
            
            # ПРЯМОЙ ПОИСК
            if ($archiveHash.ContainsKey($key)) {
                $arhItem = $archiveHash[$key]
                if ($srcItem.Length -ne $arhItem.Length) {
                    $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                    $isIdentical = $false
                }
            }
            else {
                # УМНЫЙ ПОИСК (если прямой не удался)
                # Ищем в архиве путь, который ЗАКАНЧИВАЕТСЯ на наш относительный путь
                # Например: источник "file.txt", архив "folder\file.txt" -> Совпадение
                $foundKey = $archiveHash.Keys | Where-Object { $_.EndsWith("\$key") -or $_ -eq $key } | Select-Object -First 1
                
                if ($foundKey) {
                    $arhItem = $archiveHash[$foundKey]
                    if ($srcItem.Length -ne $arhItem.Length) {
                        $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                        $isIdentical = $false
                    }
                    # Помечаем, что этот файл архива уже обработан (удалять из extra не надо, но для логики это важно)
                    # Мы не удаляем из хеша, просто учитываем, что совпадение есть
                }
                else {
                    $missingInArchive += $srcItem
                    $isIdentical = $false
                }
            }
        }

        # 2. Поиск лишних файлов в архиве
        foreach ($key in $archiveHash.Keys) {
            # Проверяем прямое совпадение
            if ($sourceHash.ContainsKey($key)) { continue }
            
            # Проверяем умное совпадение (является ли этот архивный файл частью какого-то источника)
            $isExtra = $true
            foreach ($srcKey in $sourceHash.Keys) {
                if ($key.EndsWith("\$srcKey") -or $key -eq $srcKey) {
                    $isExtra = $false
                    break
                }
            }
            
            if ($isExtra) {
                $extraInArchive += $archiveHash[$key]
                $isIdentical = $false
            }
        }

        # 3. Генерация отчета
        $reportLines = @()
        if ($isIdentical) {
            $reportLines += "SUCCESS: Полное совпадение файлов ($($SourceList.Count) шт)."
        }
        else {
            if ($missingInArchive.Count -gt 0) {
                $reportLines += "ERROR: Отсутствуют в архиве ($($missingInArchive.Count)):"
                $missingInArchive | Select-Object -First 10 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
                if ($missingInArchive.Count -gt 10) { $reportLines += "  ... и еще $($missingInArchive.Count - 10)" }
            }
            if ($sizeMismatch.Count -gt 0) {
                $reportLines += "ERROR: Не совпадает размер ($($sizeMismatch.Count)):"
                $sizeMismatch | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.Path)" }
            }
            if ($extraInArchive.Count -gt 0) {
                $reportLines += "WARNING: В архиве есть лишние файлы ($($extraInArchive.Count)):"
                $extraInArchive | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
            }
        }

        return [PSCustomObject]@{
            IsIdentical      = $isIdentical
            TotalSource      = $SourceList.Count
            TotalArchive     = $ArchiveList.Count
            MissingInArchive = $missingInArchive
            ExtraInArchive   = $extraInArchive
            SizeMismatch     = $sizeMismatch
            Report           = ($reportLines -join "`r`n")
        }
    }
}

#endregion ФУНКЦИИ

# ===========================================================
#region ТЕСТОВЫЙ ДВИЖОК
# ===========================================================

 $TestResults = @()

function Assert-Test {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Expected,
        [string]$Actual
    )

    if ($Condition) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "         Ожидание: $Expected" -ForegroundColor Yellow
        Write-Host "         Реальность: $Actual" -ForegroundColor Yellow
        return $false
    }
}

# ===========================================================
#region ТЕСТ 1: Полное совпадение (Happy Path)
# ===========================================================
Write-Host "`n=== ТЕСТ 1: Полное совпадение файлов ===" -ForegroundColor Cyan

 $srcList1 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "sub\file2.log"; Length = 200; LastWriteTime = Get-Date }
)
 $arhList1 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "sub\file2.log"; Length = 200; LastWriteTime = Get-Date }
)

 $result1 = Compare-FilesSourceArchive -SourceList $srcList1 -ArchiveList $arhList1
 $TestResults += Assert-Test -TestName "Считает идентичные списки одинаковыми" -Condition ($result1.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result1.IsIdentical)"

# ===========================================================
#region ТЕСТ 2: Отсутствие файлов в архиве
# ===========================================================
Write-Host "`n=== ТЕСТ 2: Файлы отсутствуют в архиве ===" -ForegroundColor Cyan

 $srcList2 = @(
    [PSCustomObject]@{ RelativePath = "file_missing.txt"; Length = 100; LastWriteTime = Get-Date }
)
 $arhList2 = @()

 $result2 = Compare-FilesSourceArchive -SourceList $srcList2 -ArchiveList $arhList2
 $TestResults += Assert-Test -TestName "Обнаружение отсутствия файлов" -Condition ($result2.MissingInArchive.Count -eq 1) -Expected "Missing=1" -Actual "Missing=$($result2.MissingInArchive.Count)"

# ===========================================================
#region ТЕСТ 3: Лишние файлы в архиве
# ===========================================================
Write-Host "`n=== ТЕСТ 3: Лишние файлы в архиве ===" -ForegroundColor Cyan

 $srcList3 = @()
 $arhList3 = @(
    [PSCustomObject]@{ RelativePath = "extra_file.dat"; Length = 500; LastWriteTime = Get-Date }
)

 $result3 = Compare-FilesSourceArchive -SourceList $srcList3 -ArchiveList $arhList3
 $TestResults += Assert-Test -TestName "Обнаружение лишних файлов" -Condition ($result3.ExtraInArchive.Count -eq 1) -Expected "Extra=1" -Actual "Extra=$($result3.ExtraInArchive.Count)"

# ===========================================================
#region ТЕСТ 4: Несовпадение размера
# ===========================================================
Write-Host "`n=== ТЕСТ 4: Несовпадение размера ===" -ForegroundColor Cyan

 $srcList4 = @(
    [PSCustomObject]@{ RelativePath = "size_test.txt"; Length = 100; LastWriteTime = Get-Date }
)
 $arhList4 = @(
    [PSCustomObject]@{ RelativePath = "size_test.txt"; Length = 99; LastWriteTime = Get-Date } # Разный размер
)

 $result4 = Compare-FilesSourceArchive -SourceList $srcList4 -ArchiveList $arhList4
 $TestResults += Assert-Test -TestName "Обнаружение разницы в размерах" -Condition ($result4.SizeMismatch.Count -eq 1) -Expected "Mismatch=1" -Actual "Mismatch=$($result4.SizeMismatch.Count)"

# ===========================================================
#region ТЕСТ 5: Нормализация символов (Тире vs Дефис) - КРИТИЧЕСКИЙ
# ===========================================================
Write-Host "`n=== ТЕСТ 5: Нормализация символов (Кодировка OEM) ===" -ForegroundColor Cyan

# Симуляция реальной проблемы: В источнике файл с длинным тире (U+2014)
# В архиве RAR вывел это как обычный дефис (U+002D) из-за кодировки OEM 866
 $srcList5 = @(
    [PSCustomObject]@{ RelativePath = "docs\отчет — копия.txt"; Length = 100; LastWriteTime = Get-Date } # Символ: — (Em Dash)
)
 $arhList5 = @(
    [PSCustomObject]@{ RelativePath = "docs\отчет - копия.txt"; Length = 100; LastWriteTime = Get-Date } # Символ: - (Hyphen)
)

 $result5 = Compare-FilesSourceArchive -SourceList $srcList5 -ArchiveList $arhList5

 $TestResults += Assert-Test -TestName "Считает файлы с разным написанием тире одинаковыми" -Condition ($result5.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result5.IsIdentical)"

# ===========================================================
#region ТЕСТ 6: Префиксы путей (Корневая папка в архиве)
# ===========================================================
Write-Host "`n=== ТЕСТ 6: Обработка префиксов путей ===" -ForegroundColor Cyan

# Источник: файл в корне сканируемой папки
 $srcList6 = @(
    [PSCustomObject]@{ RelativePath = "data.xml"; Length = 100; LastWriteTime = Get-Date }
)
# Архив: RAR с ключом -ep2 сохранил полный путь (имя папки источника)
 $arhList6 = @(
    [PSCustomObject]@{ RelativePath = "c:\work\backup\source\job1\data.xml"; Length = 100; LastWriteTime = Get-Date }
)

 $result6 = Compare-FilesSourceArchive -SourceList $srcList6 -ArchiveList $arhList6
 $TestResults += Assert-Test -TestName "Игнорирует полный путь в архиве (совпадение по имени файла)" -Condition ($result6.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result6.IsIdentical)"

# ===========================================================
#region ИТОГИ
# ===========================================================
Write-Host "`n============================================" -ForegroundColor Yellow
 $passed = ($TestResults | Where-Object { $_ -eq $true }).Count
 $failed = ($TestResults | Where-Object { $_ -eq $false }).Count
 $total = $TestResults.Count

Write-Host "ИТОГИ ТЕСТИРОВАНИЯ:" -ForegroundColor Yellow
Write-Host "  Пройдено: $passed / $total" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Провалено: $failed" -ForegroundColor Red
    Write-Host "  ВНИМАНИЕ! Функции верификации работают некорректно!" -ForegroundColor Red
}
else {
    Write-Host "  Все тесты пройдены успешно. Функции работают верно." -ForegroundColor Green
}
Write-Host "============================================`n" -ForegroundColor Yellow

if ($failed -gt 0) { exit 1 } else { exit 0 }
