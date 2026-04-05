<#
.SYNOPSIS
    Модуль для создания и проверки RAR архивов.
.DESCRIPTION
    Предоставляет функции для работы с архиватором WinRAR из командной строки.
.EXAMPLE
    New-RarArchive -SourcePath "C:\data" -DestinationPath "D:\backup.rar" -RarPath "C:\Program Files\WinRAR\rar.exe" -Parameters @("a", "-m5")
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function New-RarArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$RarPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Parameters,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePaths
    )

    try {
        if (-not (Test-Path -Path $RarPath)) {
            throw "Архиватор WinRAR не найден по пути: $RarPath"
        }
        
        $arguments = $Parameters + "`"$DestinationPath`"" + "`"$SourcePath`""
        
        if ($ExcludePaths) {
            $excludeSwitches = $ExcludePaths | ForEach-Object { "-x`"$_`"" }
            $arguments += $excludeSwitches
        }

        Write-Host "Запуск WinRAR со следующими аргументами: $RarPath $arguments"
        
        $process = Start-Process -FilePath $RarPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            throw "WinRAR завершился с кодом ошибки $($process.ExitCode)."
        }

        Write-Host "Архив '$DestinationPath' успешно создан." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Ошибка при создании RAR архива: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function New-RarArchive