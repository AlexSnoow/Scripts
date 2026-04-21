Вот готовое решение, полностью соответствующее архитектуре вашего скрипта, требованиям PowerShell 2.0/Windows 7 и принципам Clean Code/KISS. Решение добавляет новый режим `ByDate` в Unified Pipeline, использует временные списки файлов (`@listfile`) для архиватора RAR и корректно обрабатывает верификацию без повторного сканирования диска.

### 1. Изменения в `Backup-Config-All.xml`
Добавьте новые элементы в нужное `<Job>`:
```xml
<!-- Пример: JOB22 -->
<Job Name="JOB22">
    <Source>C:\Work\BackupAllXml\src\JOB22\</Source>
    <ArchiveByDate>true</ArchiveByDate>
    <ArchiveByDatePattern>{PCName}_{JobName}_{LastWriteTime}.rar</ArchiveByDatePattern>
    <ExcludeTodayFiles>true</ExcludeTodayFiles>
    <FileFilter>*.*</FileFilter>
    <ExcludeFilePattern></ExcludeFilePattern>
    <RemoveSourceFlag>false</RemoveSourceFlag>
    <LocalDest>C:\Work\BackupAllXml\dst\Local\JOB22\</LocalDest>
    <LocalDestDaysOld>7</LocalDestDaysOld>
    <LocalDestKeepCount>7</LocalDestKeepCount>
    <RemoteDest>C:\Work\BackupAllXml\dst\Remote\</RemoteDest>
    <RemoveRemoteDestFlag>false</RemoveRemoteDestFlag>
    <ArhLog>true</ArhLog>
</Job>
```

### 2. Обновление блока `#region UNIFIED PIPELINE: Формирование элементов архивации`
Замените или добавьте следующие функции в указанный регион:

```powershell
# ==============================================================================
# Функция разрешения шаблонов архива (обновлённая версия)
# ==============================================================================
function Resolve-ArchivePattern {
    <#
    .SYNOPSIS
    Подставляет переменные в шаблон имени архива.
    .DESCRIPTION
    Заменяет макеты {PCName}, {JobName}, {LastWriteTime}, {Date}, {Time}, {Date_Time}, 
    {SourceFileName}, {SourceFolderName} на фактические значения.
    .PARAMETER Pattern
    Шаблон имени файла архива.
    .PARAMETER PCName
    Имя компьютера.
    .PARAMETER JobName
    Имя задания.
    .PARAMETER SourceFileName
    Имя исходного файла (или дата для режима ByDate).
    .PARAMETER SourceFolderName
    Имя исходной папки.
    .PARAMETER LastWriteTime
    Дата последнего изменения (формат YYYYMMDD).
    .EXAMPLE
    Resolve-ArchivePattern -Pattern "{PCName}_{JobName}_{LastWriteTime}.rar" -PCName "SRV01" -JobName "JOB22" -LastWriteTime "20260420"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$PCName,
        [Parameter(Mandatory=$true)][string]$JobName,
        [string]$SourceFileName = '',
        [string]$SourceFolderName = '',
        [string]$LastWriteTime = ''
    )
    $name = $Pattern
    $name = $name -replace '\{PCName\}', $PCName
    $name = $name -replace '\{JobName\}', $JobName
    $name = $name -replace '\{SourceFileName\}', $SourceFileName
    $name = $name -replace '\{SourceFolderName\}', $SourceFolderName
    $name = $name -replace '\{LastWriteTime\}', $LastWriteTime
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $currentTime = Get-Date -Format 'HHmmss'
    $name = $name -replace '\{Date\}', $currentDate
    $name = $name -replace '\{Time\}', $currentTime
    $name = $name -replace '\{Date_Time\}', "${currentDate}_${currentTime}"
    $name = $name -replace '[\\/:*?"<>|]', '_'
    if ($name -notmatch '\.rar$') { $name = $name + '.rar' }
    return $name
}

# ==============================================================================
# Новый режим: Группировка файлов по дате LastWriteTime
# ==============================================================================
function Get-ArchiveItems_ByDate {
    <#
    .SYNOPSIS
    Группирует файлы по дате LastWriteTime и формирует элементы архивации по дням.
    .DESCRIPTION
    Сканирует источник, группирует файлы по дате модификации (YYYYMMDD), исключает файлы за текущую дату,
    создает временные list-файлы для RAR и возвращает коллекцию ArchiveItem с типом 'DateGroup'.
    .PARAMETER Job
    Конфигурация задания.
    .PARAMETER PCName
    Имя компьютера.
    .PARAMETER JobName
    Имя задания.
    .EXAMPLE
    Get-ArchiveItems_ByDate -Job $Job -PCName 'PC01' -JobName 'JOB22'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)][hashtable]$Job,
        [Parameter(Mandatory=$true)][string]$PCName,
        [Parameter(Mandatory=$true)][string]$JobName
    )
    process {
        $todayStr = (Get-Date).ToString('yyyyMMdd')
        $excludeToday = $true
        if ($Job.ContainsKey('ExcludeTodayFiles')) { $excludeToday = [System.Convert]::ToBoolean($Job['ExcludeTodayFiles']) }

        $filter = if ($Job.ContainsKey('FileFilter') -and -not (Test-StringIsNullOrWhiteSpace($Job['FileFilter']))) { $Job['FileFilter'] }
                  elseif ($Job.ContainsKey('SourceFilter') -and -not (Test-StringIsNullOrWhiteSpace($Job['SourceFilter']))) { $Job['SourceFilter'] }
                  else { '*.*' }

        Write-Log "Сканирование файлов по маске '$filter'..." -Level INFO
        $allFiles = Get-FilterFileList -Path $Job['Source'] -Filter $filter
        
        # Исключение по паттерну (например, fxserver.log)
        if ($Job.ContainsKey('ExcludeFilePattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['ExcludeFilePattern']))) {
            $exc = $Job['ExcludeFilePattern']
            $allFiles = $allFiles | Where-Object {
                $nm = Split-Path $_.RelativePath -Leaf
                ($_.RelativePath -notlike $exc) -and ($nm -notlike $exc)
            }
        }

        if ($allFiles.Count -eq 0) {
            Write-Log "Файлы для архивации по дате не найдены" -Level WARNING
            return @()
        }

        Write-Log "Найдено файлов: $($allFiles.Count). Группировка по LastWriteTime..." -Level INFO

        # Группировка через hashtable (быстро и совместимо с PS 2.0)
        $groups = @{}
        foreach ($f in $allFiles) {
            $dateStr = $f.LastWriteTime.ToString('yyyyMMdd')
            if ($excludeToday -and $dateStr -eq $todayStr) { continue }
            if (-not $groups.ContainsKey($dateStr)) { $groups[$dateStr] = New-Object System.Collections.ArrayList }
            $null = $groups[$dateStr].Add($f)
        }

        $pattern = "{PCName}_{JobName}_{LastWriteTime}.rar"
        if ($Job.ContainsKey('ArchiveByDatePattern') -and -not (Test-StringIsNullOrWhiteSpace($Job['ArchiveByDatePattern']))) {
            $pattern = $Job['ArchiveByDatePattern']
        }

        $tempListDir = Join-Path $env:TEMP "BackupByDateLists_$PID"
        if (-not (Test-Path $tempListDir)) { New-Item -Path $tempListDir -ItemType Directory -Force | Out-Null }

        $items = @()
        foreach ($dateKey in $groups.Keys) {
            $fileGroup = @($groups[$dateKey])
            $archiveName = Resolve-ArchivePattern -Pattern $pattern -PCName $PCName -JobName $JobName -LastWriteTime $dateKey

            # Создаём listfile для RAR (OEM кодировка для корректных путей в Windows)
            $listFilePath = Join-Path $tempListDir "files_${dateKey}.txt"
            $filePaths = $fileGroup | ForEach-Object { $_.FullName }
            [System.IO.File]::WriteAllLines($listFilePath, $filePaths, $Script:EncodingOEM)

            $items += (New-Object PSObject -Property @{
                SourcePath   = $Job['Source']
                SourceName   = "Дата: $dateKey ($($fileGroup.Count) файлов)"
                ArchiveName  = $archiveName
                SourceType   = 'DateGroup'
                SourceRoot   = $Job['Source']
                SourceFilter = $null
                FileListPath = $listFilePath
                SourceFileList = $fileGroup # Для верификации без повторного сканирования
                FileCount    = $fileGroup.Count
            })
        }
        Write-Log "Подготовлено архивов по дате: $($items.Count)" -Level INFO
        return $items
    }
}

# ==============================================================================
# Обновлённый определитель режима
# ==============================================================================
function Get-ArchiveMode {
    [CmdletBinding()]
    param([hashtable]$Job)
    $indFiles = $false; $indFolders = $false; $byDate = $false
    if ($Job.ContainsKey('ArchiveIndividualFiles'))   { $indFiles   = [System.Convert]::ToBoolean($Job['ArchiveIndividualFiles']) }
    if ($Job.ContainsKey('ArchiveIndividualFolders')) { $indFolders = [System.Convert]::ToBoolean($Job['ArchiveIndividualFolders']) }
    if ($Job.ContainsKey('ArchiveByDate'))            { $byDate     = [System.Convert]::ToBoolean($Job['ArchiveByDate']) }
    
    if ($indFiles)   { return 'IndividualFiles' }
    if ($indFolders) { return 'IndividualFolders' }
    if ($byDate)     { return 'ByDate' }
    return 'Normal'
}

# ==============================================================================
# Обновлённый диспетчер подготовки
# ==============================================================================
function Prepare-ArchiveItems {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)][hashtable]$Job,
        [Parameter(Mandatory=$true)][string]$PCName
    )
    $mode = Get-ArchiveMode -Job $Job
    switch ($mode) {
        'IndividualFiles'   { return Get-ArchiveItems_IndividualFiles   -Job $Job -PCName $PCName -JobName $Job['Name'] }
        'IndividualFolders' { return Get-ArchiveItems_IndividualFolders -Job $Job -PCName $PCName -JobName $Job['Name'] }
        'ByDate'            { return Get-ArchiveItems_ByDate            -Job $Job -PCName $PCName -JobName $Job['Name'] }
        default             { return Get-ArchiveItems_Normal            -Job $Job -PCName $PCName }
    }
}
```

### 3. Обновление `Start-RarArchive` (Поддержка `@listfile`)
Найдите функцию `Start-RarArchive` и обновите её сигнатуру и блок формирования аргументов:

```powershell
function Start-RarArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RarPath,
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$false)][string]$SourcePath = '',
        [Parameter(Mandatory=$false)][string]$FileList = '', # Новый параметр
        [Parameter(Mandatory=$false)][string[]]$Parameters = @('a', '-m3', '-s', '-ep1', '-rr1p', '-r', '-dh', '-t'),
        [Parameter(Mandatory=$false)][string]$LogPath,
        [Parameter(Mandatory=$false)][string]$SourceFilter
    )
    begin {
        $actualLogPath = $null
        if ($PSBoundParameters.ContainsKey('LogPath') -and -not ([string]::IsNullOrEmpty($LogPath))) {
            $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
            if ([string]::IsNullOrEmpty($logDir)) { $logDir = '.' }
            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
                try { $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop } catch {}
            }
            if (Test-Path -LiteralPath $logDir -PathType Container) { $actualLogPath = $LogPath }
        }
        
        $argsList = @($Parameters)
        if ($actualLogPath) { $argsList += '-ilog "' + $actualLogPath + '"' }
        $safeArchivePath = '"' + ($ArchivePath -replace '"', '""') + '"'

        # Приоритет: FileList -> SourceFilter -> SourcePath
        if (-not (Test-StringIsNullOrWhiteSpace($FileList)) -and (Test-Path $FileList)) {
            $argsList += @($safeArchivePath, '@"' + $FileList + '"')
        }
        elseif (-not (Test-StringIsNullOrWhiteSpace($SourceFilter))) {
            $filteredPath = Join-Path -Path $SourcePath -ChildPath $SourceFilter
            $argsList += @($safeArchivePath, '"' + ($filteredPath -replace '"', '""') + '"')
        }
        else {
            $argsList += @($safeArchivePath, '"' + ($SourcePath -replace '"', '""') + '"')
        }
    }
    process {
        # ... (оставьте остальной код process без изменений) ...
        # Убедитесь, что внутри process используется $argsList
    }
}
```

### 4. Обновление `Invoke-ArchivePipeline`
Найдите строку вызова `Start-RarArchive` и добавьте передачу `FileList`:

```powershell
    $arhResult = Start-RarArchive `
        -RarPath $rarPath `
        -ArchivePath $archivePath `
        -SourcePath $item.SourcePath `
        -FileList (if ($item.PSObject.Properties.Match('FileListPath').Count -gt 0) { $item.FileListPath } else { '' }) `
        -Parameters $rarParams `
        -LogPath $arhLogPath `
        -SourceFilter $srcFilter
```

### 5. Обновление `Invoke-Verification`
Добавьте обработку типа `DateGroup` в блок выбора типа источника:

```powershell
        # === Получаем список файлов источника ===
        $sourceFiles = @()
        if ($res.SourceType -eq 'File') {
            # ... существующий код ...
        }
        elseif ($res.SourceType -eq 'DateGroup') {
            $sourceFiles = @($res.SourceFileList)
            Write-Log "Верификация группы по дате $($res.SourceName) ($($sourceFiles.Count) файлов)..." -Level INFO
        }
        elseif ($res.SourceType -eq 'Folder') {
            # ... существующий код ...
        }
```

### 6. Очистка временных файлов (в `Invoke-PostOperations`)
Добавьте в начало функции `Invoke-PostOperations` блок очистки `listfile`, чтобы не засорять `%TEMP%`:

```powershell
function Invoke-PostOperations {
    param(...)
    # Очистка временных списков файлов после архивации
    foreach ($res in $ArchiveResults) {
        if ($res.SourceType -eq 'DateGroup' -and (Test-Path $res.FileListPath)) {
            Remove-Item -LiteralPath $res.FileListPath -Force -ErrorAction SilentlyContinue
        }
    }
    # ... остальной код ...
}
```

### 7. Парсинг новых узлов в конфигурации (блок `foreach ($jobNode in $b.Jobs.Job)`)
Добавьте эти строки в цикл загрузки XML, чтобы новые параметры попали в `$Script:EmbeddedConfig`:

```powershell
    if ($jobNode.ArchiveByDate) { $Script:EmbeddedConfig['Jobs'][$jn]['ArchiveByDate'] = $jobNode.ArchiveByDate }
    if ($jobNode.ArchiveByDatePattern) { $Script:EmbeddedConfig['Jobs'][$jn]['ArchiveByDatePattern'] = $jobNode.ArchiveByDatePattern }
    if ($jobNode.ExcludeTodayFiles) { $Script:EmbeddedConfig['Jobs'][$jn]['ExcludeTodayFiles'] = $jobNode.ExcludeTodayFiles }
    if ($jobNode.FileFilter) { $Script:EmbeddedConfig['Jobs'][$jn]['FileFilter'] = $jobNode.FileFilter }
```

### Почему это решение соответствует правилам:
1. **Безопасность > Производительность**: Используется `[System.IO.File]::WriteAllLines` с явной OEM-кодировкой для корректной передачи путей RAR. Верификация использует сохранённый список файлов, исключая риск рассинхронизации при повторном чтении диска.
2. **Простота > Функциональность**: Режим интегрирован в существующий Unified Pipeline без дублирования логики архивации/верификации. `ArchiveItem` расширяется только необходимыми свойствами.
3. **Принцип Глагол-Существительное**: `Get-ArchiveItems_ByDate`, `Resolve-ArchivePattern`, `Prepare-ArchiveItems`.
4. **KISS/DRY**: Логика группировки вынесена в одну функцию, использует hashtable для скорости в PS 2.0. Временные файлы удаляются сразу после использования.
5. **Совместимость с PS 2.0/Win7**: Нет `Group-Object` (используется явный цикл+hashtable), нет `[ordered]`, используются `[System.Convert]::ToBoolean()`, `[System.IO.File]` методы.
6. **RAR команды**: Используется синтаксис `@listfile` согласно `rar_help_eng.txt` (`<@listfiles...>`).

Вставьте блоки в указанные места, и скрипт будет корректно архивировать большие наборы файлов по датам, исключая текущий день, с полной поддержкой верификации и ротации.