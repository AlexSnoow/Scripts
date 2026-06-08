# PowerShell 2.0 Compatibility

Скрипты проекта разработаны для PowerShell 2.0 (Windows 7). Запуск: `powershell.exe -Version 2.0 -ExecutionPolicy RemoteSigned -file .\script.ps1`

## Недоступные возможности и альтернативы
| PS 5.1+ | PS 2.0 | Альтернатива |
|---------|--------|-------------|
| `Get-FileHash` | ❌ | `Get-FileHashCompat` (через .NET Crypto) |
| `[string]::IsNullOrWhiteSpace()` | ❌ | `Test-StringIsNullOrWhiteSpace` |
| `ConvertFrom-Json` | ❌ | Использовать XML |
| `PSCustomObject` | ❌ | `New-Object PSObject -Property @{}` |
| `Export-Csv -Encoding` | ❌ | Явное указание UTF8 |

## Паттерны

### Хеширование (Get-FileHashCompat)
```powershell
$hashAlgo = [System.Security.Cryptography.SHA256]::Create()
$fileStream = [System.IO.File]::OpenRead($Path)
$hashBytes = $hashAlgo.ComputeHash($fileStream)
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '')
```
Поддерживает: SHA1, SHA256, SHA384, SHA512, MD5.

### Проверка пустой строки
```powershell
function Test-StringIsNullOrWhiteSpace {
    param([string]$Value)
    if ($Value -eq $null -or $Value -eq '' -or $Value -match '^\s*$') { return $true }
    return $false
}
```

### Создание объектов
```powershell
$obj = New-Object PSObject -Property @{ Name = "Value" }
```

## Кодировки
- **Логи:** OEM (CP866) — `[System.Text.Encoding]::GetEncoding(866)`
- **Отчёты:** UTF8 без BOM — `New-Object System.Text.UTF8Encoding $false`

## Работа с XML
```powershell
[xml]$xmlDoc = Get-Content $xmlPath -Encoding UTF8
$b = $xmlDoc.BackupConfig
foreach ($jobNode in $b.Jobs.Job) { $name = $jobNode.Name }
```

## Запуск внешних процессов
```powershell
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $RarPath; $psi.Arguments = $argsList -join ' '
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi; $process.Start() | Out-Null; $process.WaitForExit()
```

## SMTP (CDO.Message)
```powershell
$msg = New-Object -ComObject CDO.Message
$cfg = $msg.Configuration
$cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpserver") = "smtp.domain.loc"
$cfg.Fields.Item("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
$cfg.Fields.Update(); $msg.Send()
```
