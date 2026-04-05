<#
.SYNOPSIS
    Backup Manager — GUI мониторинга резервного копирования.
.DESCRIPTION
    Отображает статус всех заданий на всех хостах.
    Читает XML-отчёты из сетевого хранилища логов.

    Функции:
    - DataGrid с цветовой индикацией статуса
    - Автообновление каждые 5 минут
    - Фильтр: показать только ошибки
    - Двойной клик → просмотр полного лога
    - Экспорт статуса в CSV

    Запуск:
        powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Backup-Manager.ps1

    Для разработки (с консолью):
        $DEVELOP = $true
        powershell.exe -ExecutionPolicy Bypass -File .\Backup-Manager.ps1
#>

# === Флаг разработки ===
$DEVELOP = $false

# Скрыть консоль
if (-not $DEVELOP) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    $hwnd = [ConsoleHelper]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) { [ConsoleHelper]::ShowWindow($hwnd, 0) }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===========================================================
# XAML
# ===========================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Менеджер резервного копирования" Height="600" Width="1000"
        WindowStartupLocation="CenterScreen" MinWidth="700" MinHeight="400">
    <Window.Resources>
        <Style x:Key="StatusCell" TargetType="DataGridCell">
            <Style.Triggers>
                <DataTrigger Binding="{Binding statusColor}" Value="Green">
                    <Setter Property="Background" Value="#C8E6C9"/>
                    <Setter Property="Foreground" Value="#1B5E20"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding statusColor}" Value="Red">
                    <Setter Property="Background" Value="#FFCDD2"/>
                    <Setter Property="Foreground" Value="#B71C1C"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding statusColor}" Value="Yellow">
                    <Setter Property="Background" Value="#FFF9C4"/>
                    <Setter Property="Foreground" Value="#F57F17"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding statusColor}" Value="Gray">
                    <Setter Property="Background" Value="#F5F5F5"/>
                    <Setter Property="Foreground" Value="#9E9E9E"/>
                </DataTrigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="150"/>
        </Grid.RowDefinitions>

        <!-- Панель управления -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="btnRefresh" Content="🔄 Обновить" Width="120" Margin="0,0,10,0"/>
            <CheckBox x:Name="chkErrorsOnly" Content="⚠ Только ошибки" Margin="0,0,20,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="lblLastUpdate" Text="Последнее обновление: —" VerticalAlignment="Center" Foreground="Gray"/>
            <TextBlock x:Name="lblAutoRefresh" Text="Автообновление: 5 мин" VerticalAlignment="Center" Foreground="Gray" Margin="20,0,0,0"/>
            <Button x:Name="btnExport" Content="📊 Экспорт CSV" Width="120" Margin="20,0,0,0"/>
        </StackPanel>

        <!-- Таблица заданий -->
        <DataGrid x:Name="dgServers" Grid.Row="1" AutoGenerateColumns="False"
                  IsReadOnly="True" SelectionMode="Single" CanUserSortColumns="True"
                  HeadersVisibility="Column" GridLinesVisibility="Horizontal"
                  RowBackground="White" AlternatingRowBackground="#FAFAFA">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Сервер" Binding="{Binding server}" Width="100"/>
                <DataGridTextColumn Header="Задание" Binding="{Binding job}" Width="80"/>
                <DataGridTextColumn Header="Версия" Binding="{Binding version}" Width="70"/>
                <DataGridTextColumn Header="Статус" Binding="{Binding statusText}" Width="100">
                    <DataGridTextColumn.CellStyle>
                        <StaticResource ResourceKey="StatusCell"/>
                    </DataGridTextColumn.CellStyle>
                </DataGridTextColumn>
                <DataGridTextColumn Header="Последний запуск" Binding="{Binding lastRun}" Width="150"/>
                <DataGridTextColumn Header="Длительность" Binding="{Binding duration}" Width="100"/>
                <DataGridTextColumn Header="Файлов" Binding="{Binding sourceFiles}" Width="70"/>
                <DataGridTextColumn Header="Размер (МБ)" Binding="{Binding archiveSize}" Width="100"/>
                <DataGridTextColumn Header="Верификация" Binding="{Binding verification}" Width="100"/>
                <DataGridTextColumn Header="Ошибка" Binding="{Binding error}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>

        <!-- Статистика -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,5,0,5">
            <TextBlock x:Name="lblStats" Text="Всего: 0 | ✅ 0 | ❌ 0 | ⚠️ 0" FontSize="12" Foreground="Gray"/>
        </StackPanel>

        <!-- Просмотр логов -->
        <GroupBox Grid.Row="3" Header="Лог задания" Margin="0,5,0,0">
            <TextBox x:Name="txtLog" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                     IsReadOnly="True" FontFamily="Consolas" FontSize="11" Padding="5"
                     Text="Двойной клик по заданию для просмотра лога..."/>
        </GroupBox>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

$dgServers     = $Window.FindName("dgServers")
$btnRefresh    = $Window.FindName("btnRefresh")
$btnExport     = $Window.FindName("btnExport")
$chkErrorsOnly = $Window.FindName("chkErrorsOnly")
$lblLastUpdate = $Window.FindName("lblLastUpdate")
$lblAutoRefresh = $Window.FindName("lblAutoRefresh")
$lblStats      = $Window.FindName("lblStats")
$txtLog        = $Window.FindName("txtLog")

# ===========================================================
# Конфигурация
# ===========================================================
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$HostsXml  = Join-Path $ScriptDir "hosts.xml"
$Global:AllData = @()

# ===========================================================
# Загрузка инвентаря
# ===========================================================
function Load-Inventory {
    if (-not (Test-Path $HostsXml)) {
        return @()
    }

    [xml]$inv = Get-Content $HostsXml -Encoding UTF8
    $logRoot = $inv.BackupInventory.LogPathRoot
    $data = @()

    foreach ($server in $inv.BackupInventory.Server) {
        foreach ($task in $server.Task) {
            # Ищем последний XML-отчёт для этого задания
            $summaryFile = Join-Path $logRoot "$($server.name)_summary.xml"
            $serverStatus = 'Unknown'
            $lastRun = '—'
            $duration = '—'
            $sourceFiles = '—'
            $archiveSize = '—'
            $verification = '—'
            $errorText = ''
            $statusColor = 'Gray'

            # Читаем сводный файл хоста
            if (Test-Path $summaryFile) {
                [xml]$summary = Get-Content $summaryFile -Encoding UTF8
                $jobNode = $summary.HostSummary.Job | Where-Object { $_.name -eq $task.id }

                if ($jobNode) {
                    $serverStatus = $jobNode.status
                    $lastRun = $summary.HostSummary.LastRun
                    $duration = $summary.HostSummary.TotalDuration
                    if ($jobNode.error) { $errorText = $jobNode.error }

                    switch ($serverStatus) {
                        'Success' { $statusColor = 'Green' }
                        'Error'   { $statusColor = 'Red' }
                        'Warning' { $statusColor = 'Yellow' }
                        default   { $statusColor = 'Gray' }
                    }
                }
            }

            # Ищем детальный отчёт задания
            $jobPattern = "$($server.name)_$($task.id)_*.xml"
            $latestJob = Get-ChildItem (Join-Path $logRoot $jobPattern) -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if ($latestJob) {
                try {
                    [xml]$report = Get-Content $latestJob.FullName -Encoding UTF8
                    $r = $report.BackupReport
                    if ($r.Status) { $serverStatus = $r.Status }
                    $sourceFiles = $r.SourceFiles
                    $archiveSize = $r.ArchiveSizeMB
                    $verification = $r.Verification
                    $duration = $r.Duration

                    switch ($serverStatus) {
                        'Success' { $statusColor = 'Green' }
                        'Error'   { $statusColor = 'Red' }
                        'Warning' { $statusColor = 'Yellow' }
                        default   { $statusColor = 'Gray' }
                    }
                }
                catch {}
            }

            $statusText = switch ($serverStatus) {
                'Success' { '✅ Успех' }
                'Error'   { '❌ Ошибка' }
                'Warning' { '⚠️ Внимание' }
                default   { '⏳ Неизвестно' }
            }

            $verificationText = switch ($verification) {
                'Passed'  { '✅ Passed' }
                'Failed'  { '❌ Failed' }
                default   { '—' }
            }

            $data += @{
                server       = $server.name
                job          = $task.id
                version      = $task.version
                statusText   = $statusText
                statusColor  = $statusColor
                lastRun      = $lastRun
                duration     = $duration
                sourceFiles  = $sourceFiles
                archiveSize  = $archiveSize
                verification = $verificationText
                error        = $errorText
                logPath      = if ($latestJob) { $latestJob.FullName } else { '' }
                summaryFile  = $summaryFile
            }
        }
    }
    return $data
}

# ===========================================================
# Обновление DataGrid
# ===========================================================
function Refresh-Grid {
    $data = Load-Inventory
    $Global:AllData = $data

    if ($chkErrorsOnly.IsChecked) {
        $data = $data | Where-Object { $_.statusColor -eq 'Red' -or $_.statusColor -eq 'Yellow' }
    }

    $dgServers.ItemsSource = @($data)

    $now = Get-Date -Format 'HH:mm:ss'
    $lblLastUpdate.Text = "Последнее обновление: $now"

    # Статистика
    $total = $Global:AllData.Count
    $ok = ($Global:AllData | Where-Object { $_.statusColor -eq 'Green' }).Count
    $err = ($Global:AllData | Where-Object { $_.statusColor -eq 'Red' }).Count
    $warn = ($Global:AllData | Where-Object { $_.statusColor -eq 'Yellow' }).Count
    $lblStats.Text = "Всего: $total | ✅ $ok | ❌ $err | ⚠️ $warn"
}

# ===========================================================
# Обработчики
# ===========================================================
$btnRefresh.Add_Click({ Refresh-Grid })

$chkErrorsOnly.Add_Checked({ Refresh-Grid })
$chkErrorsOnly.Add_Unchecked({ Refresh-Grid })

$btnExport.Add_Click({
    if ($Global:AllData.Count -eq 0) { return }
    $saveDlg = New-Object Microsoft.Win32.SaveFileDialog
    $saveDlg.FileName = "backup_status_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $saveDlg.Filter = "CSV files|*.csv"
    if ($saveDlg.ShowDialog()) {
        $Global:AllData | ForEach-Object {
            [PSCustomObject]@{
                Server = $_.server
                Job = $_.job
                Status = $_.statusText
                LastRun = $_.lastRun
                Duration = $_.duration
                SourceFiles = $_.sourceFiles
                ArchiveSizeMB = $_.archiveSize
                Verification = $_.verification
                Error = $_.error
            }
        } | Export-Csv -Path $saveDlg.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
})

$dgServers.Add_MouseDoubleClick({
    $selected = $dgServers.SelectedItem
    if (-not $selected) { return }

    $logContent = ""

    # 1. Пробуем прочитать детальный XML-отчёт
    if ($selected.logPath -and (Test-Path $selected.logPath)) {
        try {
            [xml]$r = Get-Content $selected.logPath -Encoding UTF8
            $logContent += "=== XML Отчёт ===`n"
            $logContent += "Host: $($r.BackupReport.Host)`n"
            $logContent += "Job: $($r.BackupReport.Job)`n"
            $logContent += "Timestamp: $($r.BackupReport.Timestamp)`n"
            $logContent += "Status: $($r.BackupReport.Status)`n"
            $logContent += "Duration: $($r.BackupReport.Duration)`n"
            $logContent += "SourceFiles: $($r.BackupReport.SourceFiles)`n"
            $logContent += "ArchiveSize: $($r.BackupReport.ArchiveSizeMB) MB`n"
            $logContent += "Verification: $($r.BackupReport.Verification)`n"
            if ($r.BackupReport.Errors.Error) {
                $logContent += "`nErrors:`n"
                foreach ($e in $r.BackupReport.Errors.Error) { $logContent += "  - $e`n" }
            }
            if ($r.BackupReport.LogPath) {
                $logContent += "`nLog: $($r.BackupReport.LogPath)`n"
            }
        }
        catch { $logContent = "Ошибка чтения отчёта: $_" }
    }

    # 2. Если есть путь к лог-файлу — читаем его
    if ($selected.logPath -and (Test-Path $selected.logPath)) {
        try {
            [xml]$r = Get-Content $selected.logPath -Encoding UTF8
            if ($r.BackupReport.LogPath -and (Test-Path $r.BackupReport.LogPath)) {
                $logContent += "`n=== Лог-файл (последние 100 строк) ===`n"
                $logContent += Get-Content $r.BackupReport.LogPath -Tail 100 -Encoding UTF8 | Out-String
            }
        }
        catch {}
    }

    if (-not $logContent) {
        $logContent = "Логи не найдены для $($selected.server)\$($selected.job)"
    }

    $txtLog.Text = $logContent
})

# Автообновление каждые 5 минут
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(5)
$timer.Add_Tick({ Refresh-Grid })
$timer.Start()

# Первичная загрузка
Refresh-Grid

# Показ окна
$Window.ShowDialog() | Out-Null
