function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [string]$LogPath,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )

    if (-not $LogPath) {
        Write-Error "LogPath must be specified."
        return
    }

    # Ensure directory exists
    $dir = Split-Path -Path $LogPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$Level] -> $Message"

    try {
        Add-Content -Path $LogPath -Value $line -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to write to log: $($_.Exception.Message)"
    }
}