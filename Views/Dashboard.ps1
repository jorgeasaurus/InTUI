function New-InTUIDashboardOverviewContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$DashboardData,

        [Parameter(Mandatory)]
        [double]$CompliancePercent,

        [Parameter(Mandatory)]
        [string]$ComplianceBar
    )

    return @(
        '  [bold]Inventory[/]'
        "  [blue]>[/] [white]$($DashboardData.DeviceCount)[/] devices    [green]>[/] [white]$($DashboardData.AppCount)[/] apps    [yellow]>[/] [white]$($DashboardData.UserCount)[/] users    [cyan]>[/] [white]$($DashboardData.GroupCount)[/] groups"
        '  [grey]Managed devices, apps, users, and groups[/]'
        ''
        '  [bold]Compliance Status[/]'
        "  $ComplianceBar [white]$CompliancePercent%[/]"
        ''
        "  [green]+[/] Compliant [white]$($DashboardData.CompliantCount)[/]   [red]x[/] Non-compliant [white]$($DashboardData.NoncompliantCount)[/]   [yellow]![/] Grace Period [white]$($DashboardData.InGracePeriod)[/]   [red]x[/] Error [white]$($DashboardData.ErrorCount)[/]"
    ) -join "`n"
}

function Show-InTUIDashboard {
    <#
    .SYNOPSIS
        Displays the main dashboard with summary counts and status overview.
    #>
    [CmdletBinding()]
    param()

    Write-InTUILog -Message "Loading dashboard data"

    $dashData = Show-InTUILoading -Title "[blue]Loading dashboard data...[/]" -ClearOnComplete -ScriptBlock {
        $countHeaders = @{ ConsistencyLevel = 'eventual' }
        $devices = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
        $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Headers $countHeaders
        $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Headers $countHeaders

        # mobileApps doesn't support $count properly, so fetch all IDs to count
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$select=id' -Beta -All

        $compliance = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta

        @{
            DeviceCount       = $devices.'@odata.count' ?? @($devices.value).Count
            AppCount          = @($apps).Count
            UserCount         = $users.'@odata.count' ?? @($users.value).Count
            GroupCount        = $groups.'@odata.count' ?? @($groups.value).Count
            CompliantCount    = $compliance.compliantDeviceCount ?? 0
            NoncompliantCount = $compliance.nonCompliantDeviceCount ?? 0
            InGracePeriod     = $compliance.inGracePeriodCount ?? 0
            ErrorCount        = $compliance.errorCount ?? 0
        }
    }

    if ($null -eq $dashData) {
        Write-InTUILog -Level 'WARN' -Message "Failed to load dashboard data"
        Show-InTUIWarning "Could not load dashboard data. Check your connection and permissions."
        return
    }

    Write-InTUILog -Message "Dashboard data loaded" -Context @{
        Devices = $dashData.DeviceCount
        Apps = $dashData.AppCount
        Users = $dashData.UserCount
        Groups = $dashData.GroupCount
    }

    # Calculate compliance percentage for progress bar
    $totalDevices = [int]$dashData.CompliantCount + [int]$dashData.NoncompliantCount + [int]$dashData.InGracePeriod + [int]$dashData.ErrorCount
    $compliancePercent = if ($totalDevices -gt 0) { [Math]::Round(([int]$dashData.CompliantCount / $totalDevices) * 100, 1) } else { 0 }
    $complianceBar = Get-InTUIProgressBar -Percentage $compliancePercent -Width 25

    $overviewContent = New-InTUIDashboardOverviewContent -DashboardData $dashData -CompliancePercent $compliancePercent -ComplianceBar $complianceBar
    Show-InTUIPanel -Title "[blue]Overview[/]" -Content $overviewContent -BorderColor Blue
}

function Start-InTUIAutoRefresh {
    <#
    .SYNOPSIS
        Starts an auto-refresh loop for the dashboard.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$IntervalSeconds = 30
    )

    if ($IntervalSeconds -lt 10) { $IntervalSeconds = 10 }
    if ($IntervalSeconds -gt 300) { $IntervalSeconds = 300 }

    Write-InTUILog -Message "Auto-refresh started" -Context @{ Interval = $IntervalSeconds }

    $exitRefresh = $false

    while (-not $exitRefresh) {
        Clear-Host
        Show-InTUIHeader -Subtitle "[grey]Live Dashboard - Auto-refresh every ${IntervalSeconds}s | Press any key to stop[/]"
        Show-InTUIBreadcrumb -Path @('Home', 'Live Dashboard')
        Show-InTUIDashboard

        Write-InTUIText ""
        Write-InTUIText "[grey]Last refresh: $([DateTime]::Now.ToString('HH:mm:ss')) | Next refresh in ${IntervalSeconds}s[/]"
        Write-InTUIText "[yellow]Press any key to stop auto-refresh...[/]"

        # Wait for interval or key press
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while ($stopwatch.Elapsed.TotalSeconds -lt $IntervalSeconds) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                $exitRefresh = $true
                break
            }

            # Update countdown
            $remaining = $IntervalSeconds - [math]::Floor($stopwatch.Elapsed.TotalSeconds)
            Write-Host -NoNewline "`r[grey]Refreshing in ${remaining}s...    [/]"

            Start-Sleep -Milliseconds 500
        }

        $stopwatch.Stop()
    }

    Write-InTUILog -Message "Auto-refresh stopped"
    Show-InTUISuccess "Auto-refresh stopped."
    Read-InTUIKey
}
