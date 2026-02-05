function Show-InTUIDashboard {
    <#
    .SYNOPSIS
        Displays the main dashboard with summary counts and status overview.
    #>
    [CmdletBinding()]
    param()

    Write-InTUILog -Message "Loading dashboard data"

    $dashData = Show-InTUILoading -Title "[blue]Loading dashboard data...[/]" -ScriptBlock {
        $devices = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices?$top=1&$select=id' -Beta
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$top=1&$select=id' -Beta
        $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Method GET
        $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Method GET

        $compliant = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=complianceState eq 'compliant'&`$top=1&`$count=true&`$select=id" -Beta
        $noncompliant = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=complianceState eq 'noncompliant'&`$top=1&`$count=true&`$select=id" -Beta

        @{
            DeviceCount      = $devices.'@odata.count' ?? @($devices.value).Count
            AppCount         = $apps.'@odata.count' ?? @($apps.value).Count
            UserCount        = $users.'@odata.count' ?? @($users.value).Count
            GroupCount       = $groups.'@odata.count' ?? @($groups.value).Count
            CompliantCount   = if ($compliant.'@odata.count') { $compliant.'@odata.count' } else { '?' }
            NoncompliantCount = if ($noncompliant.'@odata.count') { $noncompliant.'@odata.count' } else { '?' }
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

    $devicePanel = Format-SpectrePanel -Title "[blue]Devices[/]" -Content @"
[white bold]$($dashData.DeviceCount)[/] managed devices
[green]$($dashData.CompliantCount)[/] compliant
[red]$($dashData.NoncompliantCount)[/] non-compliant
"@ -Color Blue

    $appPanel = Format-SpectrePanel -Title "[green]Apps[/]" -Content @"
[white bold]$($dashData.AppCount)[/] applications
"@ -Color Green

    $userPanel = Format-SpectrePanel -Title "[yellow]Users[/]" -Content @"
[white bold]$($dashData.UserCount)[/] users
"@ -Color Yellow

    $groupPanel = Format-SpectrePanel -Title "[magenta]Groups[/]" -Content @"
[white bold]$($dashData.GroupCount)[/] groups
"@ -Color Magenta

    Write-SpectreHost $devicePanel
    Write-SpectreHost $appPanel
    Write-SpectreHost $userPanel
    Write-SpectreHost $groupPanel
    Write-SpectreHost ""
}
