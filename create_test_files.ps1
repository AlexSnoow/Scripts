# Скрипт для создания тестовых файлов
$testPath = "C:\Test\backup3"

# Создаем директорию для тестов (если не существует)
if (-not (Test-Path -Path $testPath)) {
    New-Item -ItemType Directory -Path $testPath -Force | Out-Null
}

# Создаем 10 файлов с разными датами
for ($i = 0; $i -lt 10; $i++) {
    $fileName = "$testPath\File_$i.txt"
    $fileDate = (Get-Date).AddDays(-$i)
    
    # Создаем файл с содержимым
    "Тестовый файл создан $($fileDate.ToString('dd.MM.yyyy'))" | Out-File -FilePath $fileName
    
    # Устанавливаем дату изменения
    Set-ItemProperty -Path $fileName -Name LastWriteTime -Value $fileDate
    
    Write-Host "Создан файл: $fileName с датой $($fileDate.ToString('dd.MM.yyyy'))"
}

Write-Host "`nТестовые файлы успешно созданы в: $testPath"
Write-Host "Список файлов:"
Get-ChildItem $testPath | Format-Table Name, LastWriteTime