# Получить текущие настройки аудита
$auditSettings = auditpol /get /category:*

# Путь для сохранения списка команд
$outputFile = "C:auditpol_commands.txt"

# Инициализировать файл (очистить если существует)
Set-Content -Path $outputFile -Value "# Список команд auditpol для настройки аудита`r`n" -Encoding UTF8

# Обрабатывать каждую строку вывода
foreach ($line in $auditSettings) {
    if ($line -match "^(?<category>.+?)s+(?<success>Success|No Auditing)s+(?<failure>Failure|No Auditing)$") {
        $category = $matches['category'].Trim()
        $success = if ($matches['success'] -eq "Success") { "enable" } else { "disable" }
        $failure = if ($matches['failure'] -eq "Failure") { "enable" } else { "disable" }
        $cmd = "auditpol /set /category:`"$category`" /success:$success /failure:$failure"
        Add-Content -Path $outputFile -Value $cmd
    }
}

Write-Output "Список команд сохранён в файл: $outputFile"
