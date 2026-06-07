# Загружаем функцию из файла
. ".\Write-Log.ps1"

$testLog = "C:\Users\user\Documents\ProgramProjects\Scripts\app\sandbox\test_log.txt"
if (Test-Path $testLog) { Remove-Item $testLog -Force }

Write-Host "Starting tests for Write-Log..." -ForegroundColor Cyan

# Тест 1: Базовая запись
Write-Log -Message "Test 1: Basic Write" -LogPath $testLog -Level "INFO"
if (Test-Path $testLog) {
    Write-Host "[PASS] Test 1: File created" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Test 1: File not created" -ForegroundColor Red
}

# Тест 2: Запись нескольких строк
Write-Log -Message "Test 2: Second Line" -LogPath $testLog -Level "WARN"
$content = Get-Content $testLog
if ($content.Count -eq 2) {
    Write-Host "[PASS] Test 2: Two lines written" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Test 2: Expected 2 lines, got $($content.Count)" -ForegroundColor Red
}

# Тест 3: Проверка уровня (Level)
Write-Log -Message "Test 3: Level Check" -LogPath $testLog -Level "ERROR"
if ($content[-1] -match "\[ERROR\]") {
    Write-Host "[PASS] Test 3: Level ERROR correctly logged" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Test 3: Level ERROR not found in last line" -ForegroundColor Red
}

# Очистка
if (Test-Path $testLog) { Remove-Item $testLog -Force }
Write-Host "Tests completed." -ForegroundColor Cyan
