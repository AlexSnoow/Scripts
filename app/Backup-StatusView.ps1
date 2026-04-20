# Backup-StatusView.ps1 — GUI мониторинг с изменяемой высотой лога
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Backup Monitor" Height="550" Width="950"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="200"/>
        </Grid.RowDefinitions>

        <!-- Таблица заданий -->
        <DataGrid x:Name="dgServers" Grid.Row="0" AutoGenerateColumns="False" IsReadOnly="True"
                  SelectionMode="Single" CanUserSortColumns="True">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Host" Binding="{Binding server}" Width="100"/>
                <DataGridTextColumn Header="Job" Binding="{Binding job}" Width="80"/>
                <DataGridTextColumn Header="Status" Binding="{Binding statusText}" Width="100"/>
                <DataGridTextColumn Header="Last Run" Binding="{Binding lastRun}" Width="150"/>
                <DataGridTextColumn Header="Duration" Binding="{Binding duration}" Width="80"/>
                <DataGridTextColumn Header="Files" Binding="{Binding sourceFiles}" Width="60"/>
                <DataGridTextColumn Header="Size (MB)" Binding="{Binding archiveSize}" Width="90"/>
                <DataGridTextColumn Header="Verification" Binding="{Binding verification}" Width="100"/>
                <DataGridTextColumn Header="Error" Binding="{Binding error}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>

        <!-- Разделитель, позволяющий изменять высоту лога -->
        <GridSplitter Grid.Row="1" Height="5" HorizontalAlignment="Stretch" Background="Gray" ResizeDirection="Rows"/>

        <!-- Блок лога -->
        <GroupBox Grid.Row="2" Header="Job Log">
            <TextBox x:Name="txtLog" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                     IsReadOnly="True" FontFamily="Consolas" FontSize="11" Padding="5"/>
        </GroupBox>
    </Grid>
</Window>
"@

# Загрузка XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$dgServers = $Window.FindName("dgServers")
$txtLog = $Window.FindName("txtLog")

# === Конфигурация ===
$LogRoot = "C:\Work\BackupAllJson\logs"
$HostsXml = "C:\Work\BackupAllJson\hosts.xml"   # опционально

function Load-Inventory {
    $data = @()
    if (Test-Path $HostsXml) {
        [xml]$inv = Get-Content $HostsXml -Encoding UTF8
        $logRoot = $inv.BackupInventory.LogPathRoot
        foreach ($server in $inv.BackupInventory.Server) {
            foreach ($task in $server.Task) {
                $summaryFile = Join-Path $logRoot "$($server.name)_summary.xml"
                $item = @{
                    server       = $server.name
                    job          = $task.id
                    statusText   = "Unknown"
                    lastRun      = "-"
                    duration     = "-"
                    sourceFiles  = "-"
                    archiveSize  = "-"
                    verification = "-"
                    error        = ""
                    logPath      = ""
                }
                if (Test-Path $summaryFile) {
                    [xml]$summary = Get-Content $summaryFile -Encoding UTF8
                    $jobNode = $summary.HostSummary.Job | Where-Object { $_.name -eq $task.id }
                    if ($jobNode) {
                        $status = $jobNode.status
                        $item.lastRun = $summary.HostSummary.LastRun
                        $item.duration = $summary.HostSummary.TotalDuration
                        if ($jobNode.error) { $item.error = $jobNode.error }
                        $item.statusText = switch ($status) {
                            'Success' { "Success" }
                            'Error'   { "Error" }
                            'Warning' { "Warning" }
                            default   { "Unknown" }
                        }
                    }
                }
                $jobPattern = "$($server.name)_$($task.id)_*.xml"
                $latestJob = Get-ChildItem (Join-Path $logRoot $jobPattern) -ErrorAction SilentlyContinue |
                             Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestJob) {
                    try {
                        [xml]$report = Get-Content $latestJob.FullName -Encoding UTF8
                        $r = $report.BackupReport
                        if ($r.Status) { $item.statusText = $r.Status }
                        $item.sourceFiles = $r.SourceFiles
                        $item.archiveSize = $r.ArchiveSizeMB
                        $item.verification = $r.Verification
                        $item.duration = $r.Duration
                        $item.lastRun = $r.Timestamp -replace 'T', ' '
                        $item.logPath = $latestJob.FullName
                    } catch {}
                }
                $data += [PSCustomObject]$item
            }
        }
    } else {
        $reports = Get-ChildItem (Join-Path $LogRoot "*.xml") -File | Where-Object { $_.Name -notmatch "_summary\.xml$" }
        foreach ($report in $reports) {
            try {
                [xml]$r = Get-Content $report.FullName -Encoding UTF8
                $item = [PSCustomObject]@{
                    server       = $r.BackupReport.Host
                    job          = $r.BackupReport.Job
                    statusText   = $r.BackupReport.Status
                    lastRun      = $r.BackupReport.Timestamp -replace 'T', ' '
                    duration     = $r.BackupReport.Duration
                    sourceFiles  = $r.BackupReport.SourceFiles
                    archiveSize  = $r.BackupReport.ArchiveSizeMB
                    verification = $r.BackupReport.Verification
                    error        = if ($r.BackupReport.Errors.Error) { ($r.BackupReport.Errors.Error -join "; ") } else { "" }
                    logPath      = $report.FullName
                }
                $data += $item
            } catch {}
        }
    }
    return $data
}

function Refresh-Grid {
    $data = Load-Inventory
    $dgServers.ItemsSource = @($data)
}

# Двойной клик — показать лог
$dgServers.Add_MouseDoubleClick({
    $selected = $dgServers.SelectedItem
    if (-not $selected) { return }
    if ($selected.logPath -and (Test-Path $selected.logPath)) {
        try {
            [xml]$report = Get-Content $selected.logPath -Encoding UTF8
            $logFile = $report.BackupReport.LogPath
            if ($logFile -and (Test-Path $logFile)) {
                $txtLog.Text = Get-Content $logFile -Tail 100 -Encoding UTF8 | Out-String
            } else {
                $txtLog.Text = "Log file not found: $logFile"
            }
        } catch {
            $txtLog.Text = "Error reading report: $_"
        }
    } else {
        $txtLog.Text = "No data for $($selected.server)\$($selected.job)"
    }
})

Refresh-Grid
$Window.ShowDialog() | Out-Null