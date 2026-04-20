<#
.SYNOPSIS
    Скрипт для создания тестовых файлов и папок.
.DESCRIPTION
    Генерирует набор файлов с разными датами модификации и папки для проверки сценариев резервного копирования.
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

Write-Host "--- Запуск генератора тестовых данных ---" -ForegroundColor Yellow

# --- Настройка путей ---
$baseTestPath = "C:\testBackups"
$job1Path = Join-Path -Path $baseTestPath -ChildPath "JOB1_folder"
$job2Path = Join-Path -Path $baseTestPath -ChildPath "JOB2_File_in_Arh"
$job3Path = Join-Path -Path $baseTestPath -ChildPath "JOB3_folder_exect"
$job3Exclude1 = Join-Path -Path $job3Path -ChildPath "test1"
$job3Exclude2 = Join-Path -Path $job3Path -ChildPath "test2"

$pathsToCreate = @(
    $job1Path,
    $job2Path,
    $job3Path,
    $job3Exclude1,
    $job3Exclude2
)

# --- Создание директорий ---
$pathsToCreate | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Host "Создана директория: $_"
    }
}

# --- Создание файлов для Job1 и Job3 ---
1..5 | ForEach-Object {
    "Содержимое файла $_" | Out-File -FilePath (Join-Path -Path $job1Path -ChildPath "file$_.txt")
    "Содержимое файла $_" | Out-File -FilePath (Join-Path -Path $job3Path -ChildPath "file$_.txt")
}
"Содержимое для исключения 1" | Out-File -FilePath (Join-Path -Path $job3Exclude1 -ChildPath "excluded1.txt")
"Содержимое для исключения 2" | Out-File -FilePath (Join-Path -Path $job3Exclude2 -ChildPath "excluded2.txt")


# --- Создание файлов для Job2 (файлы .msg с разными датами) ---
Write-Host "`nСоздание файлов для Job2 с разными датами..."
for ($i = 0; $i -lt 12; $i++) {
    $fileName = Join-Path -Path $job2Path -ChildPath "File_$i.msg"
    $fileDate = (Get-Date).AddDays(-$i * 3) # Создаем файлы с разницей в 3 дня
    
    "Тестовый файл .msg создан $($fileDate.ToString('dd.MM.yyyy'))" | Out-File -FilePath $fileName
    
    Set-ItemProperty -Path $fileName -Name LastWriteTime -Value $fileDate
    
    Write-Host "Создан файл: $fileName с датой $($fileDate.ToString('dd.MM.yyyy'))"
}

Write-Host "---------------"
Write-Host "`nТестовые данные успешно созданы в: $baseTestPath" -ForegroundColor Green
Write-Host "Список содержимого:"
Get-ChildItem $baseTestPath -Recurse | Format-Table FullName, LastWriteTime