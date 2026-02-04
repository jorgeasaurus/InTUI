function Show-InTUIDashboard {
    <#
    .SYNOPSIS
        Displays the main dashboard with summary counts and status overview.
    #>
    [CmdletBinding()]
    param()

    $dashData = Show-InTUILoading -Title "[blue]Loading dashboard data...[/]" -ScriptBlock {
        $devices = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices?$top=1&$select=id' -Beta
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$top=1&$select=id' -Beta
        $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Method GET
        $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Method GET

        # Get compliance summary
        $compliant = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=complianceState eq 'compliant'&`$top=1&`$count=true&`$select=id" -Beta
        $noncompliant = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=complianceState eq 'noncompliant'&`$top=1&`$count=true&`$select=id" -Beta

        @{
            DeviceCount      = if ($devices.'@odata.count') { $devices.'@odata.count' } else { ($devices.value | Measure-Object).Count }
            AppCount         = if ($apps.'@odata.count') { $apps.'@odata.count' } else { ($apps.value | Measure-Object).Count }
            UserCount        = if ($users.'@odata.count') { $users.'@odata.count' } else { ($users.value | Measure-Object).Count }
            GroupCount       = if ($groups.'@odata.count') { $groups.'@odata.count' } else { ($groups.value | Measure-Object).Count }
            CompliantCount   = if ($compliant.'@odata.count') { $compliant.'@odata.count' } else { '?' }
            NoncompliantCount = if ($noncompliant.'@odata.count') { $noncompliant.'@odata.count' } else { '?' }
        }
    }

    if ($null -eq $dashData) {
        Show-InTUIWarning "Could not load dashboard data. Check your connection and permissions."
        return
    }

    # Build dashboard panels
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
