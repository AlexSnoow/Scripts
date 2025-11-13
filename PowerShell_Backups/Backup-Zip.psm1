<#
.SYNOPSIS
    Модуль для создания ZIP архивов средствами PowerShell.
.DESCRIPTION
    Предоставляет функцию-обертку над стандартным командлетом `Compress-Archive`.
.EXAMPLE
    New-ZipArchive -SourcePath "C:\data" -DestinationPath "D:\backup.zip" -Parameters @{ CompressionLevel = "Optimal" }
.NOTES
    Автор: Kilo Code
    Версия: 1.0
    Дата: 2025-11-12
#>

function New-ZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{ CompressionLevel = "Optimal" }
    )

    try {
        $compressParams = @{
            Path            = $SourcePath
            DestinationPath = $DestinationPath
            ErrorAction     = 'Stop'
        }

        # Добавляем параметры из хэш-таблицы, если они есть
        if ($Parameters) {
            foreach ($key in $Parameters.Keys) {
                $compressParams[$key] = $Parameters[$key]
            }
        }

        Write-Host "Создание ZIP архива '$DestinationPath'..."
        Compress-Archive @compressParams
        
        Write-Host "Архив '$DestinationPath' успешно создан." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Ошибка при создании ZIP архива: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function New-ZipArchive