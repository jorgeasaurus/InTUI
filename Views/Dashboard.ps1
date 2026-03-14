function Show-InTUIDashboard {
    <#
    .SYNOPSIS
        Displays the main dashboard with summary counts and status overview.
    #>
    [CmdletBinding()]
    param()

    Write-InTUILog -Message "Loading dashboard data"

    $dashData = Show-InTUILoading -Title "[blue]Loading dashboard data...[/]" -ScriptBlock {
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

    # Device panel with enhanced visuals
    $deviceContent = @"
  [white]$($dashData.DeviceCount)[/] [grey]managed devices[/]

  [bold]Compliance Status[/]
  $complianceBar [white]$compliancePercent%[/]

  [green]+[/] Compliant       [white]$($dashData.CompliantCount)[/]
  [red]x[/] Non-compliant   [white]$($dashData.NoncompliantCount)[/]
  [yellow]![/] Grace Period    [white]$($dashData.InGracePeriod)[/]
  [red]x[/] Error           [white]$($dashData.ErrorCount)[/]
"@
    Show-InTUIPanel -Title "[blue]Devices[/]" -Content $deviceContent -BorderColor Blue

    # App panel
    $appContent = @"
  [white]$($dashData.AppCount)[/] [grey]applications[/]

  [grey]Managed apps across all platforms[/]
"@
    Show-InTUIPanel -Title "[green]Apps[/]" -Content $appContent -BorderColor Green

    # User panel
    $userContent = @"
  [white]$($dashData.UserCount)[/] [grey]users[/]

  [grey]Azure AD directory users[/]
"@
    Show-InTUIPanel -Title "[yellow]Users[/]" -Content $userContent -BorderColor Yellow

    # Group panel
    $groupContent = @"
  [white]$($dashData.GroupCount)[/] [grey]groups[/]

  [grey]Security and distribution groups[/]
"@
    Show-InTUIPanel -Title "[cyan]Groups[/]" -Content $groupContent -BorderColor Cyan

    # Quick stats footer
    Write-InTUIText ""
    Write-InTUIText "[grey]$(([string][char]0x2500) * 60)[/]"
    Write-InTUIText "[grey]Quick Stats:[/] [blue]>[/] [white]$($dashData.DeviceCount)[/] devices  [green]>[/] [white]$($dashData.AppCount)[/] apps  [yellow]>[/] [white]$($dashData.UserCount)[/] users  [cyan]>[/] [white]$($dashData.GroupCount)[/] groups"
    Write-InTUIText ""
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
