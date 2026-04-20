param([string]$Path = ".\Backup-rar-ps2-dp.ps1")

$code = Get-Content -Path $Path -Raw -Encoding Default
$tokens = $null
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($code, [ref]$errors)

if ($errors) {
    Write-Host "Ошибки в скрипте$($Path):" -ForegroundColor Red
    $lines = Get-Content -Path $Path -Encoding Default
    foreach ($err in $errors) {
        $lineNum = $err.Token.StartLine
        $col = $err.Token.StartColumn
        $lineText = $lines[$lineNum - 1]
        Write-Host "Строка $lineNum (столбец $col): $($err.Message)" -ForegroundColor Yellow
        Write-Host ">>> $lineText" -ForegroundColor Cyan
        Write-Host "---" -ForegroundColor Gray
    }
} else {
    Write-Host "Синтаксис OK!" -ForegroundColor Green
}