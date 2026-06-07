# Загружаем функцию (используем абсолютный путь для надежности в песочнице)
$funcPath = "C:\Users\user\Documents\ProgramProjects\Scripts\app\sandbox\ps\function Write-Log\Write-Log.ps1"
if (Test-Path $funcPath) { . $funcPath } else { Write-Error "Function file not found at $funcPath" }

# Загружаем конфигурацию (абсолютный путь)
$configPath = "C:\Users\user\Documents\ProgramProjects\Scripts\app\sandbox\config\Backup-Config_Write-Log.xml"
if (Test-Path $configPath) {
    [xml]$config = Get-Content $configPath
    $logPath = $config.BackupConfig.Paths.LogPathRoot
    Write-Host "Configured Log Path: $logPath" -ForegroundColor Cyan

    # Проверяем работу функции с реальным конфигом
    Write-Log -Message "Verification: Config loaded successfully" -LogPath $logPath -Level "SUCCESS"

    # Проверка результата
    if (Test-Path $logPath) {
        $content = Get-Content $logPath
        if ($content -match "Verification: Config loaded successfully") {
            Write-Host "[PASS] Verification successful using XML config" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Verification failed: Content mismatch" -ForegroundColor Red
        }
    } else {
        Write-Host "[FAIL] Verification failed: Log path not found" -ForegroundColor Red
    }
} else {
    Write-Host "[FAIL] Config file not found at $configPath" -ForegroundColor Red
}
