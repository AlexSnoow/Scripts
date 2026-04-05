<#
.SYNOPSIS
    Генератор продакшен-скриптов из XML-конфигурации.

.DESCRIPTION
    Читает Backup-Config.xml, сериализует в $Script:EmbeddedConfig,
    встраивает в шаблоны (заменяя CONFIG_BLOCK), удаляет CONFIG_LOADER,
    запускает тесты, при успехе сохраняет в dist/.

    Процесс:
    1. Чтение XML-конфига
    2. Генерация $EmbeddedConfig
    3. Замена CONFIG_BLOCK + удаление CONFIG_LOADER в шаблонах
    4. Тест 1: Проверка синтаксиса сгенерированных файлов
    5. Если всё прошло — сохранение в dist/

.PARAMETER ConfigPath
    Путь к XML конфигурации. По умолчанию: .\common\Backup-Config.xml

.PARAMETER SkipTests
    Пропустить тесты и сразу сгенерировать файлы.

.EXAMPLE
    .\build.ps1
    Полный цикл: генерация + тесты + dist/

.EXAMPLE
    .\build.ps1 -SkipTests
    Только генерация без тестов.
#>

param(
    [string]$ConfigPath = ".\common\Backup-Config-All.xml",
    [switch]$SkipTests
)

$Script:ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$Msg) Write-Host "`n>>> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info  { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Gray }

# ===========================================================
# 1. Чтение XML
# ===========================================================
Write-Step "Чтение конфигурации: $ConfigPath"
if (-not (Test-Path $ConfigPath)) {
    Write-Fail "Файл не найден: $ConfigPath"
    exit 1
}

try {
    [xml]$xmlDoc = Get-Content $ConfigPath -Encoding UTF8
    Write-Ok "XML загружен"
}
catch {
    Write-Fail "Ошибка парсинга XML: $_"
    exit 1
}

$b = $xmlDoc.BackupConfig

# ===========================================================
# 2. Сериализация в PS
# ===========================================================
Write-Step "Сериализация в PowerShell-хеш"

function Escape-PS {
    param([string]$s)
    return $s -replace "'", "''"
}

function Serialize-Array {
    param([System.Xml.XmlElement]$Node, [string]$Tag)
    $items = @()
    foreach ($p in $Node.$Tag) {
        $items += "'$(Escape-PS $p.InnerText)'"
    }
    return "@($($items -join ', '))"
}

$jobsCode = "@{"
foreach ($jn in $b.Jobs.Job) {
    $n = Escape-PS $jn.Name
    $jobsCode += "`n    '$n' = @{"
    $jobsCode += "`n        'Name' = '$n'"
    $jobsCode += "`n        'Source' = '$(Escape-PS $jn.Source)'"
    if ($jn.SourceFilter) { $jobsCode += "`n        'SourceFilter' = '$(Escape-PS $jn.SourceFilter)'" }
    $jobsCode += "`n        'RemoveSourceFlag' = `$$($jn.RemoveSourceFlag -eq 'true')"
    $jobsCode += "`n        'SourceDaysOld' = $([int]$jn.SourceDaysOld)"
    $jobsCode += "`n        'SourceKeepCount' = $([int]$jn.SourceKeepCount)"
    $jobsCode += "`n        'ArchivePattern' = '$(Escape-PS $jn.ArchivePattern)'"
    $jobsCode += "`n        'LocalDest' = '$(Escape-PS $jn.LocalDest)'"
    $jobsCode += "`n        'LocalDestDaysOld' = $([int]$jn.LocalDestDaysOld)"
    $jobsCode += "`n        'LocalDestKeepCount' = $([int]$jn.LocalDestKeepCount)"
    $jobsCode += "`n        'RemoteDest' = '$(Escape-PS $jn.RemoteDest)'"
    $jobsCode += "`n        'RemoveRemoteDestFlag' = `$$($jn.RemoveRemoteDestFlag -eq 'true')"
    $jobsCode += "`n        'RemoteDestDaysOld' = $([int]$jn.RemoteDestDaysOld)"
    $jobsCode += "`n        'RemoteDestKeepCount' = $([int]$jn.RemoteDestKeepCount)"
    $jobsCode += "`n        'ArhLog' = `$$($jn.ArhLog -eq 'true')"
    $jobsCode += "`n        'ArchiveIndividualFolders' = `$$($jn.ArchiveIndividualFolders -eq 'true')"
    if ($jn.IndividualArchivePattern) { $jobsCode += "`n        'IndividualArchivePattern' = '$(Escape-PS $jn.IndividualArchivePattern)'" }
    if ($jn.ExcludeFolderPattern) { $jobsCode += "`n        'ExcludeFolderPattern' = '$(Escape-PS $jn.ExcludeFolderPattern)'" }
    if ($jn.ArhParameters) { $jobsCode += "`n        'ArhParameters' = $(Serialize-Array $jn.ArhParameters 'Param')" }
    if ($jn.SourceCheckMasks) { $jobsCode += "`n        'SourceCheckMasks' = $(Serialize-Array $jn.SourceCheckMasks 'Mask')" }
    $jobsCode += "`n    }"
}
$jobsCode += "`n}"

$embeddedBlock = @"
`$Script:EmbeddedConfig = @{
    General = @{
        JobName      = '$(Escape-PS $b.General.JobName)'
        Domain       = '$(Escape-PS $b.General.Domain)'
        SmtpServer   = '$(Escape-PS $b.General.SmtpServer)'
        LogDaysOld   = $([int]$b.General.LogDaysOld)
        LogKeepCount = $([int]$b.General.LogKeepCount)
        ArchiverType = '$(Escape-PS $b.General.ArchiverType)'
        DefaultRarParameters = $(Serialize-Array $b.General.DefaultRarParameters 'Param')
        Default7zParameters = $(Serialize-Array $b.General.Default7zParameters 'Param')
    }
    Paths = @{
        LogPathRoot  = '$(Escape-PS $b.Paths.LogPathRoot)'
        NetLogPath   = '$(Escape-PS $b.Paths.NetLogPath)'
        RarPath      = '$(Escape-PS $b.Paths.RarPath)'
        SevenZipPath = '$(Escape-PS $b.Paths.SevenZipPath)'
    }
    Recipients = @{
        AdminIS   = '$(Escape-PS $b.Recipients.AdminIS)'
        AdminOS   = '$(Escape-PS $b.Recipients.AdminOS)'
        AdminMail = '$(Escape-PS $b.Recipients.AdminMail)'
    }
    Integrity = @{
        RarExeHash      = '$(Escape-PS $b.Integrity.RarExeHash)'
        SevenZipExeHash = '$(Escape-PS $b.Integrity.SevenZipExeHash)'
    }
    Jobs = $jobsCode
}
`$BackupConfig = `$Script:EmbeddedConfig
"@

Write-Ok "Сериализовано ($($b.Jobs.Job.Count) заданий)"

# ===========================================================
# 3. Генерация Prod-скриптов
# ===========================================================
function Build-Prod {
    param([string]$Template, [string]$Output, [string]$Label)

    Write-Step "Генерация $Label"
    Write-Info "  Шаблон: $Template"
    Write-Info "  Вывод:  $Output"

    if (-not (Test-Path $Template)) {
        Write-Fail "Не найден: $Template"; return $false
    }

    $content = Get-Content $Template -Raw -Encoding UTF8

    # 1) Заменяем CONFIG_BLOCK на встроенный конфиг
    $pattern = '(?s)#region CONFIG_BLOCK.*?#endregion CONFIG_BLOCK'
    $content = $content -replace $pattern, $embeddedBlock

    # 2) Удаляем CONFIG_LOADER (закомментируем) — оборачиваем в <# #>
    $loaderPattern = '(?s)#region CONFIG_LOADER.*?#endregion CONFIG_LOADER'
    $content = $content -replace $loaderPattern, "<# CONFIG_LOADER отключён (конфигурация встроена)`r`n#>"

    $outDir = Split-Path $Output -Parent
    if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }

    $bom = New-Object System.Text.UTF8Encoding $true
    $fullOut = (Resolve-Path $outDir).Path + "\" + (Split-Path $Output -Leaf)
    [System.IO.File]::WriteAllText($fullOut, $content, $bom)

    Write-Ok "$Label создан: $(Split-Path $Output -Leaf)"
    return $true
}

$distDir = Join-Path $Script:ScriptDir "dist"
if (-not (Test-Path $distDir)) { New-Item -Path $distDir -ItemType Directory -Force | Out-Null }

$ok51 = Build-Prod `
    -Template (Join-Path $Script:ScriptDir "common\Backup-Main-All.ps1") `
    -Output   (Join-Path $distDir "Backup-Prod-PS51.ps1") `
    -Label    "Backup-Prod-PS51.ps1"

$ok2 = Build-Prod `
    -Template (Join-Path $Script:ScriptDir "ps2\Backup-Run.ps1") `
    -Output   (Join-Path $distDir "Backup-Prod-PS2.ps1") `
    -Label    "Backup-Prod-PS2.ps1"

if (-not $ok51 -or -not $ok2) {
    Write-Fail "Ошибка генерации"
    exit 1
}

# ===========================================================
# 4. Тесты
# ===========================================================
if ($SkipTests) {
    Write-Host "`nТесты пропущены." -ForegroundColor Yellow
    Write-Host "Файлы: $distDir" -ForegroundColor Green
    exit 0
}

$allOk = $true

Write-Step "ТЕСТ 1: Проверка синтаксиса"

foreach ($pair in @(
    @{ File = (Join-Path $distDir "Backup-Prod-PS51.ps1"); Label = "PS51" },
    @{ File = (Join-Path $distDir "Backup-Prod-PS2.ps1");  Label = "PS2"  }
)) {
    Write-Info "Проверка $($pair.Label)..."
    $errors = $null; $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($pair.File, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Fail "$($pair.Label): $($errors.Count) ошибок"
        $errors | Select-Object -First 5 | ForEach-Object {
            Write-Fail "  Строка $($_.Extent.StartLineNumber): $($_.Message)"
        }
        $allOk = $false
    }
    else {
        Write-Ok "$($pair.Label): синтаксис валиден"
    }
}

if (-not $allOk) {
    Write-Fail "Тесты провалены"
    exit 1
}

# ===========================================================
# Итоги
# ===========================================================
Write-Step "РЕЗУЛЬТАТЫ"
Write-Ok "Все тесты пройдены!"
Write-Host "`nПродакшен-скрипты:" -ForegroundColor Green
Write-Host "  $distDir\Backup-Prod-PS51.ps1" -ForegroundColor White
Write-Host "  $distDir\Backup-Prod-PS2.ps1" -ForegroundColor White
Write-Host "`nСледующий шаг: Authenticode подпись" -ForegroundColor Yellow
