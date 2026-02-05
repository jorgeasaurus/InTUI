function Export-InTUIToCSV {
    <#
    .SYNOPSIS
        Exports an array of objects to a CSV file with user-selected path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Data,

        [Parameter(Mandatory)]
        [string[]]$Properties,

        [Parameter()]
        [string]$DefaultFileName = 'InTUI_Export'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $suggestedName = "${DefaultFileName}_${timestamp}.csv"
    $exportPath = Read-SpectreText -Prompt "[blue]Export path[/]" -DefaultValue "$PWD/$suggestedName"

    if (-not $exportPath) { return }

    Write-InTUILog -Message "Exporting to CSV" -Context @{ Path = $exportPath; Count = $Data.Count }

    try {
        $Data | Select-Object $Properties | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Show-InTUISuccess "Exported $($Data.Count) items to $exportPath"
    }
    catch {
        Show-InTUIError "Failed to export: $($_.Exception.Message)"
        Write-InTUILog -Level 'ERROR' -Message "CSV export failed: $($_.Exception.Message)"
    }

    Read-InTUIKey
}

function Invoke-InTUIBulkDeviceAction {
    <#
    .SYNOPSIS
        Performs a bulk action on multiple devices via multi-select.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Devices', 'Bulk Actions')

    $devices = Show-InTUILoading -Title "[blue]Loading devices...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceManagement/managedDevices' -Beta -PageSize 100 -Select 'id,deviceName,operatingSystem,userPrincipalName,complianceState'
    }

    if ($null -eq $devices -or $devices.Results.Count -eq 0) {
        Show-InTUIWarning "No devices found."
        Read-InTUIKey
        return
    }

    $deviceNames = $devices.Results | ForEach-Object {
        $icon = Get-InTUIDeviceIcon -OperatingSystem $_.operatingSystem
        "$icon $($_.deviceName) [grey]($($_.userPrincipalName ?? 'Unassigned'))[/]"
    }

    Write-SpectreHost "[blue]Select devices for bulk action (space to select, enter to confirm):[/]"
    $selected = Read-SpectreMultiSelection -Title "[blue]Select devices[/]" -Choices $deviceNames -PageSize 20

    if (-not $selected -or $selected.Count -eq 0) {
        Show-InTUIWarning "No devices selected."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Bulk action: devices selected" -Context @{ Count = $selected.Count }

    $actionChoices = @(
        'Sync Devices',
        'Restart Devices',
        'Retire Devices',
        'Export Selected to CSV',
        'Cancel'
    )

    $action = Show-InTUIMenu -Title "[blue]Bulk action for $($selected.Count) device(s)[/]" -Choices $actionChoices

    if ($action -eq 'Cancel') { return }

    # Map selected display names back to device objects
    $selectedDevices = @()
    foreach ($sel in $selected) {
        $idx = $deviceNames.IndexOf($sel)
        if ($idx -ge 0) {
            $selectedDevices += $devices.Results[$idx]
        }
    }

    Write-InTUILog -Message "Bulk action executing" -Context @{ Action = $action; Count = $selectedDevices.Count }

    switch ($action) {
        'Sync Devices' {
            $confirm = Show-InTUIConfirm -Message "[yellow]Sync $($selectedDevices.Count) device(s)?[/]"
            if ($confirm) {
                Show-InTUILoading -Title "[blue]Syncing $($selectedDevices.Count) devices...[/]" -ScriptBlock {
                    foreach ($device in $selectedDevices) {
                        Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$($device.id)/syncDevice" -Method POST -Beta
                    }
                }
                Show-InTUISuccess "Sync initiated for $($selectedDevices.Count) device(s)."
                Read-InTUIKey
            }
        }
        'Restart Devices' {
            $confirm = Show-InTUIConfirm -Message "[yellow]Restart $($selectedDevices.Count) device(s)?[/]"
            if ($confirm) {
                Show-InTUILoading -Title "[blue]Restarting $($selectedDevices.Count) devices...[/]" -ScriptBlock {
                    foreach ($device in $selectedDevices) {
                        Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$($device.id)/rebootNow" -Method POST -Beta
                    }
                }
                Show-InTUISuccess "Restart initiated for $($selectedDevices.Count) device(s)."
                Read-InTUIKey
            }
        }
        'Retire Devices' {
            $confirm = Show-InTUIConfirm -Message "[red]RETIRE $($selectedDevices.Count) device(s)? This removes company data.[/]"
            if ($confirm) {
                $confirm2 = Show-InTUIConfirm -Message "[red]Final confirmation: Retire $($selectedDevices.Count) device(s)?[/]"
                if ($confirm2) {
                    Show-InTUILoading -Title "[red]Retiring $($selectedDevices.Count) devices...[/]" -ScriptBlock {
                        foreach ($device in $selectedDevices) {
                            Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$($device.id)/retire" -Method POST -Beta
                        }
                    }
                    Show-InTUISuccess "Retire initiated for $($selectedDevices.Count) device(s)."
                    Read-InTUIKey
                }
            }
        }
        'Export Selected to CSV' {
            Export-InTUIToCSV -Data $selectedDevices -Properties @('deviceName', 'operatingSystem', 'userPrincipalName', 'complianceState') -DefaultFileName 'InTUI_Devices'
        }
    }
}
