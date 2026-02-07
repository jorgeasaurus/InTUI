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
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
        $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Headers $countHeaders
        $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Headers $countHeaders

        $compliance = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta

        @{
            DeviceCount       = $devices.'@odata.count' ?? @($devices.value).Count
            AppCount          = $apps.'@odata.count' ?? @($apps.value).Count
            UserCount         = $users.'@odata.count' ?? @($users.value).Count
            GroupCount        = $groups.'@odata.count' ?? @($groups.value).Count
            CompliantCount    = $compliance.compliantDeviceCount ?? '?'
            NoncompliantCount = $compliance.nonCompliantDeviceCount ?? '?'
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

    $devicePanel = Format-SpectrePanel -Data @"
[white bold]$($dashData.DeviceCount)[/] managed devices
[green]$($dashData.CompliantCount)[/] compliant
[red]$($dashData.NoncompliantCount)[/] non-compliant
"@ -Title "[blue]Devices[/]" -Color Blue

    $appPanel = Format-SpectrePanel -Data @"
[white bold]$($dashData.AppCount)[/] applications
"@ -Title "[green]Apps[/]" -Color Green

    $userPanel = Format-SpectrePanel -Data @"
[white bold]$($dashData.UserCount)[/] users
"@ -Title "[yellow]Users[/]" -Color Yellow

    $groupPanel = Format-SpectrePanel -Data @"
[white bold]$($dashData.GroupCount)[/] groups
"@ -Title "[magenta]Groups[/]" -Color Magenta1

    $devicePanel | Out-SpectreHost
    $appPanel | Out-SpectreHost
    $userPanel | Out-SpectreHost
    $groupPanel | Out-SpectreHost
    Write-SpectreHost ""
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

        Write-SpectreHost ""
        Write-SpectreHost "[grey]Last refresh: $([DateTime]::Now.ToString('HH:mm:ss')) | Next refresh in ${IntervalSeconds}s[/]"
        Write-SpectreHost "[yellow]Press any key to stop auto-refresh...[/]"

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
