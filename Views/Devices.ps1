function Show-InTUIDevicesView {
    <#
    .SYNOPSIS
        Displays the Devices management view mimicking the Intune Devices blade.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Devices')

        $deviceChoices = @(
            'All Devices',
            'Windows Devices',
            'iOS/iPadOS Devices',
            'macOS Devices',
            'Android Devices',
            'Compliance Overview',
            'Search Device',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[blue]Devices[/]" -Choices $deviceChoices

        switch ($selection) {
            'All Devices' {
                Show-InTUIDeviceList
            }
            'Windows Devices' {
                Show-InTUIDeviceList -OSFilter 'Windows'
            }
            'iOS/iPadOS Devices' {
                Show-InTUIDeviceList -OSFilter 'iOS'
            }
            'macOS Devices' {
                Show-InTUIDeviceList -OSFilter 'macOS'
            }
            'Android Devices' {
                Show-InTUIDeviceList -OSFilter 'Android'
            }
            'Compliance Overview' {
                Show-InTUIComplianceOverview
            }
            'Search Device' {
                $searchTerm = Read-SpectreText -Prompt "[blue]Search devices by name[/]"
                if ($searchTerm) {
                    Show-InTUIDeviceList -SearchTerm $searchTerm
                }
            }
            'Back to Home' {
                $exitView = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIDeviceList {
    <#
    .SYNOPSIS
        Displays a paginated list of managed devices.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OSFilter,

        [Parameter()]
        [string]$SearchTerm,

        [Parameter()]
        [string]$ComplianceFilter
    )

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader

        $breadcrumb = @('Home', 'Devices')
        if ($OSFilter) { $breadcrumb += "$OSFilter Devices" }
        elseif ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        else { $breadcrumb += 'All Devices' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        # Build filter
        $filter = @()
        if ($OSFilter) {
            switch ($OSFilter) {
                'Windows' { $filter += "contains(operatingSystem,'Windows')" }
                'iOS'     { $filter += "(operatingSystem eq 'iOS' or operatingSystem eq 'iPadOS')" }
                'macOS'   { $filter += "operatingSystem eq 'macOS'" }
                'Android' { $filter += "contains(operatingSystem,'Android')" }
            }
        }
        if ($ComplianceFilter) {
            $filter += "complianceState eq '$ComplianceFilter'"
        }

        $uri = '/deviceManagement/managedDevices'
        $selectFields = 'id,deviceName,operatingSystem,osVersion,complianceState,managedDeviceOwnerType,enrolledDateTime,lastSyncDateTime,userPrincipalName,model,manufacturer,serialNumber,managementAgent'

        $params = @{
            Uri      = $uri
            Beta     = $true
            PageSize = 25
            Select   = $selectFields
        }

        if ($filter.Count -gt 0) {
            $params['Filter'] = $filter -join ' and '
        }
        if ($SearchTerm) {
            $params['Filter'] = "contains(deviceName,'$SearchTerm')"
        }

        $devices = Show-InTUILoading -Title "[blue]Loading devices...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $devices -or $devices.Results.Count -eq 0) {
            Show-InTUIWarning "No devices found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        # Build display choices
        $deviceChoices = @()
        foreach ($device in $devices.Results) {
            $icon = Get-InTUIDeviceIcon -OperatingSystem $device.operatingSystem
            $compliance = $device.complianceState
            $compColor = Get-InTUIComplianceColor -State $compliance
            $lastSync = Format-InTUIDate -DateString $device.lastSyncDateTime
            $owner = if ($device.userPrincipalName) { $device.userPrincipalName.Split('@')[0] } else { 'Unassigned' }

            $displayName = "$icon $($device.deviceName) [$compColor]($compliance)[/] [grey]| $owner | $lastSync[/]"
            $deviceChoices += $displayName
        }

        $deviceChoices += '─────────────'
        $deviceChoices += 'Back'

        Show-InTUIStatusBar -Total ($devices.Count ?? $devices.Results.Count) -Showing $devices.Results.Count -FilterText ($OSFilter ?? $SearchTerm)

        $selection = Show-InTUIMenu -Title "[blue]Select a device[/]" -Choices $deviceChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            # Find the selected device by matching index
            $idx = $deviceChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $devices.Results.Count) {
                Show-InTUIDeviceDetail -DeviceId $devices.Results[$idx].id
            }
        }
    }
}

function Show-InTUIDeviceDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific device, mimicking the Intune device detail blade.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $device = Show-InTUILoading -Title "[blue]Loading device details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId" -Beta
        }

        if ($null -eq $device) {
            Show-InTUIError "Failed to load device details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Devices', $device.deviceName)

        # Device Properties Panel
        $compColor = Get-InTUIComplianceColor -State $device.complianceState
        $icon = Get-InTUIDeviceIcon -OperatingSystem $device.operatingSystem

        $propertiesContent = @"
$icon [bold]$($device.deviceName)[/]

[grey]Compliance State:[/]  [$compColor]$($device.complianceState)[/]
[grey]OS:[/]               $($device.operatingSystem) $($device.osVersion)
[grey]Model:[/]            $($device.manufacturer) $($device.model)
[grey]Serial Number:[/]    $($device.serialNumber ?? 'N/A')
[grey]Owner Type:[/]       $($device.managedDeviceOwnerType)
[grey]Management:[/]       $($device.managementAgent)
[grey]Enrolled:[/]         $(Format-InTUIDate -DateString $device.enrolledDateTime)
[grey]Last Sync:[/]        $(Format-InTUIDate -DateString $device.lastSyncDateTime)
[grey]User:[/]             $($device.userPrincipalName ?? 'None')
[grey]User Display Name:[/] $($device.userDisplayName ?? 'N/A')
"@

        Show-InTUIPanel -Title "[blue]Device Properties[/]" -Content $propertiesContent -BorderColor Blue

        # Hardware info
        $hwContent = @"
[grey]Storage (Total):[/]     $([math]::Round(($device.totalStorageSpaceInBytes / 1GB), 1)) GB
[grey]Storage (Free):[/]      $([math]::Round(($device.freeStorageSpaceInBytes / 1GB), 1)) GB
[grey]Physical Memory:[/]     $([math]::Round(($device.physicalMemoryInBytes / 1GB), 1)) GB
[grey]IMEI:[/]                $($device.imei ?? 'N/A')
[grey]Wi-Fi MAC:[/]           $($device.wiFiMacAddress ?? 'N/A')
[grey]EAS Device ID:[/]       $($device.easDeviceId ?? 'N/A')
[grey]Azure AD Device ID:[/]  $($device.azureADDeviceId ?? 'N/A')
"@

        Show-InTUIPanel -Title "[cyan]Hardware Information[/]" -Content $hwContent -BorderColor Cyan

        # Action menu
        $actionChoices = @(
            'Sync Device',
            'Restart Device',
            'Device Configuration Status',
            'App Install Status',
            'Rename Device',
            'Retire Device',
            'Wipe Device',
            '─────────────',
            'Back to Devices'
        )

        $action = Show-InTUIMenu -Title "[blue]Device Actions[/]" -Choices $actionChoices

        switch ($action) {
            'Sync Device' {
                Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'syncDevice'
            }
            'Restart Device' {
                $confirm = Show-InTUIConfirm -Message "[yellow]Are you sure you want to restart [bold]$($device.deviceName)[/]?[/]"
                if ($confirm) {
                    Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'rebootNow'
                }
            }
            'Device Configuration Status' {
                Show-InTUIDeviceConfigStatus -DeviceId $DeviceId -DeviceName $device.deviceName
            }
            'App Install Status' {
                Show-InTUIDeviceAppStatus -DeviceId $DeviceId -DeviceName $device.deviceName
            }
            'Rename Device' {
                $newName = Read-SpectreText -Prompt "[blue]Enter new device name[/]"
                if ($newName) {
                    $body = @{ deviceName = $newName }
                    $result = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId" -Method PATCH -Body $body -Beta
                    if ($null -ne $result) {
                        Show-InTUISuccess "Device renamed to '$newName'. Change will apply on next sync."
                    }
                    Read-InTUIKey
                }
            }
            'Retire Device' {
                $confirm = Show-InTUIConfirm -Message "[red]⚠ Are you sure you want to RETIRE [bold]$($device.deviceName)[/]? This will remove company data.[/]"
                if ($confirm) {
                    Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'retire'
                }
            }
            'Wipe Device' {
                $confirm = Show-InTUIConfirm -Message "[red]⚠ DANGEROUS: Are you sure you want to WIPE [bold]$($device.deviceName)[/]? This will factory reset the device![/]"
                if ($confirm) {
                    $confirm2 = Show-InTUIConfirm -Message "[red]⚠ FINAL CONFIRMATION: This action CANNOT be undone. Proceed with wipe?[/]"
                    if ($confirm2) {
                        Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'wipe'
                    }
                }
            }
            'Back to Devices' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Invoke-InTUIDeviceAction {
    <#
    .SYNOPSIS
        Executes a remote action on a managed device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter(Mandatory)]
        [ValidateSet('syncDevice', 'rebootNow', 'retire', 'wipe', 'resetPasscode', 'remoteLock', 'shutDown')]
        [string]$Action,

        [Parameter()]
        [hashtable]$Body
    )

    $result = Show-InTUILoading -Title "[blue]Executing $Action...[/]" -ScriptBlock {
        $params = @{
            Uri    = "/deviceManagement/managedDevices/$DeviceId/$Action"
            Method = 'POST'
            Beta   = $true
        }
        if ($Body) { $params['Body'] = $Body }
        Invoke-InTUIGraphRequest @params
    }

    Show-InTUISuccess "Action '$Action' has been initiated."
    Read-InTUIKey
}

function Show-InTUIDeviceConfigStatus {
    <#
    .SYNOPSIS
        Shows device configuration profile status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter()]
        [string]$DeviceName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Devices', $DeviceName, 'Configuration Status')

    $configs = Show-InTUILoading -Title "[blue]Loading configuration status...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId/deviceConfigurationStates" -Beta
    }

    if ($null -eq $configs -or ($configs.value | Measure-Object).Count -eq 0) {
        Show-InTUIWarning "No configuration profiles assigned to this device."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($config in $configs.value) {
        $stateColor = switch ($config.state) {
            'compliant'    { 'green' }
            'notCompliant' { 'red' }
            'error'        { 'red' }
            'notApplicable' { 'grey' }
            default        { 'yellow' }
        }

        $rows += , @(
            $config.displayName,
            "[$stateColor]$($config.state)[/]",
            ($config.platformType ?? 'N/A'),
            ($config.settingCount ?? '0')
        )
    }

    Show-InTUITable -Title "Configuration Profiles" -Columns @('Profile Name', 'State', 'Platform', 'Settings') -Rows $rows

    Read-InTUIKey
}

function Show-InTUIDeviceAppStatus {
    <#
    .SYNOPSIS
        Shows app installation status for a device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter()]
        [string]$DeviceName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Devices', $DeviceName, 'App Install Status')

    $appStatuses = Show-InTUILoading -Title "[blue]Loading app install status...[/]" -ScriptBlock {
        $detected = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId/detectedApps" -Beta
        return $detected
    }

    if ($null -eq $appStatuses -or ($appStatuses.value | Measure-Object).Count -eq 0) {
        Show-InTUIWarning "No app install data available for this device."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($app in $appStatuses.value) {
        $rows += , @(
            $app.displayName,
            ($app.version ?? 'N/A'),
            ($app.sizeInByte ? "$([math]::Round($app.sizeInByte / 1MB, 1)) MB" : 'N/A')
        )
    }

    Show-InTUITable -Title "Detected Apps" -Columns @('App Name', 'Version', 'Size') -Rows $rows

    Read-InTUIKey
}

function Show-InTUIComplianceOverview {
    <#
    .SYNOPSIS
        Shows compliance overview with statistics.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Devices', 'Compliance Overview')

    $complianceData = Show-InTUILoading -Title "[blue]Loading compliance data...[/]" -ScriptBlock {
        $overview = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDeviceOverview' -Beta
        return $overview
    }

    if ($null -eq $complianceData) {
        Show-InTUIWarning "Could not load compliance data."
        Read-InTUIKey
        return
    }

    $content = @"
[bold white]Device Compliance Overview[/]

[grey]Total Enrolled:[/]              $($complianceData.enrolledDeviceCount ?? 'N/A')
[grey]MDM Enrolled:[/]                $($complianceData.mdmEnrolledCount ?? 'N/A')
[grey]Dual Enrolled:[/]               $($complianceData.dualEnrolledDeviceCount ?? 'N/A')

[bold]Compliance Status:[/]
[green]  Compliant:[/]                 $($complianceData.deviceCompliancePolicyDeviceStateSummary.compliantDeviceCount ?? 'N/A')
[red]  Non-compliant:[/]             $($complianceData.deviceCompliancePolicyDeviceStateSummary.nonCompliantDeviceCount ?? 'N/A')
[yellow]  In Grace Period:[/]           $($complianceData.deviceCompliancePolicyDeviceStateSummary.inGracePeriodCount ?? 'N/A')
[grey]  Not Evaluated:[/]             $($complianceData.deviceCompliancePolicyDeviceStateSummary.notEvaluatedDeviceCount ?? 'N/A')
[red]  Error:[/]                     $($complianceData.deviceCompliancePolicyDeviceStateSummary.errorCount ?? 'N/A')
[orange1]  Conflict:[/]                  $($complianceData.deviceCompliancePolicyDeviceStateSummary.conflictDeviceCount ?? 'N/A')

[bold]OS Distribution:[/]
[blue]  Windows:[/]                   $($complianceData.deviceOperatingSystemSummary.windowsCount ?? 'N/A')
[grey]  iOS:[/]                       $($complianceData.deviceOperatingSystemSummary.iosCount ?? 'N/A')
[grey]  macOS:[/]                     $($complianceData.deviceOperatingSystemSummary.macOSCount ?? 'N/A')
[green]  Android:[/]                   $($complianceData.deviceOperatingSystemSummary.androidCount ?? 'N/A')
[yellow]  Linux:[/]                     $($complianceData.deviceOperatingSystemSummary.linuxCount ?? 'N/A')
"@

    Show-InTUIPanel -Title "[blue]Compliance Overview[/]" -Content $content -BorderColor Blue

    $exitOverview = $false
    while (-not $exitOverview) {
        $choices = @(
            'View Compliant Devices',
            'View Non-Compliant Devices',
            'Back'
        )

        $selection = Show-InTUIMenu -Title "[blue]Filter by compliance[/]" -Choices $choices

        switch ($selection) {
            'View Compliant Devices' {
                Show-InTUIDeviceList -ComplianceFilter 'compliant'
            }
            'View Non-Compliant Devices' {
                Show-InTUIDeviceList -ComplianceFilter 'noncompliant'
            }
            'Back' {
                $exitOverview = $true
            }
        }
    }
}
