<# file Send-Mail.ps1
.SYNOPSIS
    ��������� �������� ����� ������ ��������� ������������� ����

.DESCRIPTION
    ������� ��� �������������� �������� ����� � ���������� ��������, HTML-��������������,
    � ���������� �����������. ������������ ������������� ����������� � ��������.

.PARAMETER From
    ����� ����������� (������������ ��������)

.PARAMETER To
    ����� ��� ������ ����������� ����� ������� (������������ ��������)

.PARAMETER Subject
    ���� ������ (������������ ��������)

.PARAMETER Body
    ����� ������ (������������ ��������)

.PARAMETER SmtpServer
    SMTP-������ ��� �������� (������������ ��������)

.PARAMETER AttachPath
    ���� � ����� ��� ����� � ������� ��� �������� � ������

.PARAMETER LogPath
    ���� ��� ���������� ����� (�� ���������: "C:\Logs\mail")

.PARAMETER LogName
    ��� ���� (����� ��������� ������������ {date}, {time}, {datetime})

.PARAMETER MaxLogAge
    ������������ ������� ����� � ���� (����������� ������ �����)

.PARAMETER Credential
    ������� ������ ��� �������������� �� SMTP-�������

.PARAMETER UseSSL
    ������������ SSL-���������� ��� �����������

.PARAMETER Port
    ���� SMTP-������� (�� ���������: 25 ��� ��� SSL, 587 ��� SSL)

.PARAMETER BodyAsHtml
    ������������ HTML-�������������� ���� ������

.PARAMETER Priority
    ��������� ������ (High, Normal, Low)

.PARAMETER Encoding
    ��������� ������ (�� ���������: UTF8)

.EXAMPLE
    # �������� �������� ������
    Send-Mail -From "user1@domain.loc" -To "user2@domain.loc" -Subject "����" -Body "����� ������" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # �������� � ��������� � HTML-���������������
    Send-Mail -From "report@domain.loc" -To "admin@domain.loc" -Subject "�����" -Body "<h1>���������� �����</h1>" -BodyAsHtml -AttachPath "C:\Reports\report.pdf" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # �������� ���������� �����������
    Send-Mail -From "service@domain.loc" -To "user1@domain.loc", "user2@domain.loc" -Subject "�����������" -Body "������ ���������" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # ������ �� ��������� ������
    .\Send-Mail.ps1 -From "alert@domain.loc" -To "admin@domain.loc" -Subject "������" -Body "���������� ������ � �������" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # ������������� � ������������ �������
    Program: powershell.exe
    Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Send-Mail.ps1" -From "daily@domain.loc" -To "report@domain.loc" -Subject "���������� �����" -Body "����� ����������" -AttachPath "C:\Reports\daily.txt" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # ������������� � ������ �������
    . .\Send-Mail.ps1
    Send-Mail -From "noreply@domain.loc" -To "user@domain.loc" -Subject "����� ����������" -Body "����������� ���������" -SmtpServer "smtp.domain.loc"

.EXAMPLE
    # �������� ������� � ������������ ����� PowerShell
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\Scripts\Send-Mail.ps1`" -From `"alert@domain.loc`" -To `"admin@domain.loc`" -Subject `"���������� �����������`" -Body `"������� �������� ���������`" -SmtpServer `"smtp.domain.loc`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DailyMailAlert" -Description "���������� ����������� �� email" -Principal $principal -Settings $settings

.NOTES
    �����: ������
    ������: 2.1 (2025-08-19)
    ���������: PowerShell 3.0 ��� ����
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}")]
    [string]$From,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}")]
    [string[]]$To,

    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [Parameter(Mandatory = $true)]
    [string]$Body,

    [Parameter(Mandatory = $false)]
    [string]$SmtpServer = "SmtpServer.domail.loc",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ($_ -and -not (Test-Path $_)) { throw "���� �� ����������: $_" }
            $true
        })]
    [string[]]$AttachPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\mail",

    [Parameter(Mandatory = $false)]
    [string]$LogName = "MailLog-{datetime}",

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$UseSSL,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port,

    [Parameter(Mandatory = $false)]
    [switch]$BodyAsHtml,

    [Parameter(Mandatory = $false)]
    [ValidateSet("High", "Normal", "Low")]
    [string]$Priority = "Normal",

    [Parameter(Mandatory = $false)]
    [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
)

function Send-Mail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$From,

        [Parameter(Mandatory = $true)]
        [string[]]$To,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [string]$SmtpServer,

        [Parameter(Mandatory = $false)]
        [string[]]$AttachPath,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "C:\Logs\mail",

        [Parameter(Mandatory = $false)]
        [string]$LogName = "MailLog-{datetime}",

        [Parameter(Mandatory = $false)]
        [int]$MaxLogAge = 30,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$UseSSL,

        [Parameter(Mandatory = $false)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [switch]$BodyAsHtml,

        [Parameter(Mandatory = $false)]
        [string]$Priority = "Normal",

        [Parameter(Mandatory = $false)]
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    # ������ ������������� � ����� ����
    $dateString = Get-Date -Format "yyyyMMdd"
    $timeString = Get-Date -Format "HHmmss"
    $dateTimeString = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $finalLogName = $LogName `
        -replace "{date}", $dateString `
        -replace "{time}", $timeString `
        -replace "{datetime}", $dateTimeString

    # �������� ����� ��� �����, ���� �� ����������
    if (-not (Test-Path $LogPath)) {
        Write-Verbose "�������� ����� ��� �����: $LogPath"
        try {
            New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "�� ������� ������� ����� ��� �����: $($_.Exception.Message)"
            return $false
        }
    }

    # ������� ������ �����
    if ($MaxLogAge -gt 0) {
        try {
            $oldLogs = Get-ChildItem -Path $LogPath -Filter "*.log" | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$MaxLogAge)
            }
            
            if ($oldLogs.Count -gt 0) {
                Write-Verbose "�������� ������ ����� ($($oldLogs.Count) ������)"
                $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "�� ������� �������� ������ ����: $($_.Exception.Message)"
        }
    }

    # ������������ ������� ���� � ���-�����
    $logFile = Join-Path $LogPath "$finalLogName.log"

    # ���������� ���������� ��� ��������
    $mailParams = @{
        From        = $From
        To          = $To
        Subject     = $Subject
        Body        = $Body
        SmtpServer  = $SmtpServer
        ErrorAction = "Stop"
        Encoding    = $Encoding
    }

    # ���������� �������������� ����������
    if ($AttachPath) { 
        $mailParams.Attachments = $AttachPath
    }
    if ($Credential) { 
        $mailParams.Credential = $Credential
    }
    else {
        # ������������� ��������� �������������� �� ���������
        $mailParams.Credential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "NT AUTHORITY\ANONYMOUS LOGON", (New-Object System.Security.SecureString))
    }
    if ($UseSSL) { 
        $mailParams.UseSsl = $true
    }
    if ($Port -gt 0) { 
        $mailParams.Port = $Port
    }
    if ($BodyAsHtml) { 
        $mailParams.BodyAsHtml = $true
    }
    if ($Priority -ne "Normal") { 
        $mailParams.Priority = $Priority
    }

    # ����������� ���������� � ��������
    $logMessage = @"
========================================
�������� ������: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
��: $From
����: $($To -join ", ")
����: $Subject
������: $SmtpServer
��������: $(if ($AttachPath) { $AttachPath -join ", " } else { "���" })
========================================
"@

    try {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        Write-Verbose "���������� � �������� ������..."

        # �������� ������
        Send-MailMessage @mailParams

        # ����������� ������
        $successMessage = "������ ������� ����������!`n"
        Add-Content -Path $logFile -Value $successMessage -Encoding UTF8
        Write-Host "������ ������� ����������!" -ForegroundColor Green

        return $true
    }
    catch {
        # ����������� ������
        $errorMessage = "������ ��� �������� ������: $($_.Exception.Message)`n"
        Add-Content -Path $logFile -Value $errorMessage -Encoding UTF8
        Write-Error "������ ��� �������� ������: $($_.Exception.Message)"
        
        return $false
    }
    finally {
        Add-Content -Path $logFile -Value "========================================`n" -Encoding UTF8
    }
}

# ���� ������ ������� �������� (�� ������������ ��� ������)
if ($MyInvocation.InvocationName -ne '.') {
    try {
        # ������ ��������
        $result = Send-Mail @PSBoundParameters
        
        # ���������� � ��������������� ����� ������
        exit $(if ($result) { 0 } else { 1 })
    }
    catch {
        Write-Error "������ ����������: $($_.Exception.Message)"
        exit 1
    }
}
else {
    # ������� ������� ��� ������������� � ������ ��������
    Export-ModuleMember -Function Send-Mail -Alias sendmail
}