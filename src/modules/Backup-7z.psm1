<#
.SYNOPSIS
    Модуль для создания и проверки 7-Zip архивов.
.DESCRIPTION
    Предоставляет функции для работы с архиватором 7-Zip из командной строки.
.EXAMPLE
    New-7zArchive -SourcePath "C:\data" -DestinationPath "D:\backup.7z" -SevenZipPath "C:\Program Files\7-Zip\7z.exe" -Parameters @("a", "-mx=9")
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function New-7zArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$SevenZipPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Parameters,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePaths
    )

    try {
        if (-not (Test-Path -Path $SevenZipPath)) {
            throw "Архиватор 7-Zip не найден по пути: $SevenZipPath"
        }
        
        $arguments = $Parameters + "`"$DestinationPath`"" + "`"$SourcePath`""
        
        if ($ExcludePaths) {
            $excludeSwitches = $ExcludePaths | ForEach-Object { "-x!`"$_`"" } # 7-Zip использует -x! для исключения
            $arguments += $excludeSwitches
        }

        Write-Host "Запуск 7-Zip со следующими аргументами: $SevenZipPath $arguments"
        
        $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            throw "7-Zip завершился с кодом ошибки $($process.ExitCode)."
        }

        Write-Host "Архив '$DestinationPath' успешно создан." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Ошибка при создании 7-Zip архива: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function New-7zArchive