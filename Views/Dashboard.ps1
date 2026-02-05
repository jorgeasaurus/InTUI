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
