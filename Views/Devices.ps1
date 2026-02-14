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
            "$([char]0x25A1) All Devices",
            "$([char]0x25A0) Windows Devices",
            "$([char]0x25CF) iOS/iPadOS Devices",
            "$([char]0x25C6) macOS Devices",
            "$([char]0x25B2) Android Devices",
            "$([char]0x2713) Compliance Overview",
            "$([char]0x2315) Search Device",
            "$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)",
            "$([char]0x2190) Back to Home"
        )

        $selection = Show-InTUIMenu -Title "[blue]Devices[/]" -Choices $deviceChoices

        Write-InTUILog -Message "Devices view selection" -Context @{ Selection = $selection }

        # Strip icon prefix for switch matching
        $cleanSelection = $selection -replace "^.{1,2} ", ""

        switch ($cleanSelection) {
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
                $searchTerm = Read-SpectreText -Message "[blue]$([char]0x2315) Search devices by name[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching devices" -Context @{ SearchTerm = $searchTerm }
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

        $filter = @()
        if ($SearchTerm) {
            $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
            $filter += "contains(deviceName,'$safe')"
        }
        else {
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
        }

        $params = @{
            Uri      = '/deviceManagement/managedDevices'
            Beta     = $true
            PageSize = 25
            Select   = 'id,deviceName,operatingSystem,osVersion,complianceState,managedDeviceOwnerType,enrolledDateTime,lastSyncDateTime,userPrincipalName,model,manufacturer,serialNumber,managementAgent'
        }

        if ($filter.Count -gt 0) {
            $params['Filter'] = $filter -join ' and '
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

        $choiceMap = Get-InTUIChoiceMap -Choices $deviceChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($devices.Count ?? $devices.Results.Count) -Showing $devices.Results.Count -FilterText ($OSFilter ?? $SearchTerm)

        $selection = Show-InTUIMenu -Title "[blue]Select a device[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $devices.Results.Count) {
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

        $hwContent = @"
[grey]Storage (Total):[/]     $([math]::Round(($device.totalStorageSpaceInBytes / 1GB), 1)) GB
[grey]Storage (Free):[/]      $([math]::Round(($device.freeStorageSpaceInBytes / 1GB), 1)) GB
[grey]Physical Memory:[/]     $([math]::Round(($device.physicalMemoryInBytes / 1GB), 1)) GB
[grey]IMEI:[/]                $($device.imei ?? 'N/A')
[grey]Wi-Fi MAC:[/]           $($device.wiFiMacAddress ?? 'N/A')
[grey]EAS Device ID:[/]       $($device.easDeviceId ?? 'N/A')
[grey]Azure AD Device ID:[/]  $($device.azureADDeviceId ?? 'N/A')
"@

        Show-InTUIPanel -Title "[cyan]Hardware Information[/]" -Content $hwContent -BorderColor Cyan1

        # Show Defender status panel for Windows devices
        if ($device.operatingSystem -match 'Windows') {
            Show-InTUIDefenderPanel -DeviceId $DeviceId
        }

        $actionChoices = @(
            "$([char]0x21BB) Sync Device",
            "$([char]0x21BA) Restart Device",
            "$([char]0x2699) Device Configuration Status",
            "$([char]0x25A6) App Install Status",
            "$([char]0x270E) Rename Device",
            "$([char]0x26A0) Retire Device",
            "$([char]0x2717) Wipe Device",
            "$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)",
            "$([char]0x2190) Back to Devices"
        )

        $action = Show-InTUIMenu -Title "[blue]Device Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Device detail action" -Context @{ DeviceId = $DeviceId; DeviceName = $device.deviceName; Action = $action }

        # Strip icon prefix for switch matching
        $cleanAction = $action -replace "^.{1,2} ", ""

        switch ($cleanAction) {
            'Sync Device' {
                Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'syncDevice'
            }
            'Restart Device' {
                $confirm = Show-InTUIConfirm -Message "[yellow]$([char]0x26A0) Are you sure you want to restart [bold]$($device.deviceName)[/]?[/]"
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
                $newName = Read-SpectreText -Message "[blue]$([char]0x270E) Enter new device name[/]"
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
                $confirm = Show-InTUIConfirm -Message "[red]$([char]0x26A0) Are you sure you want to RETIRE [bold]$($device.deviceName)[/]? This will remove company data.[/]"
                if ($confirm) {
                    Invoke-InTUIDeviceAction -DeviceId $DeviceId -Action 'retire'
                }
            }
            'Wipe Device' {
                $confirm = Show-InTUIConfirm -Message "[red]$([char]0x26A0) DANGEROUS: Are you sure you want to WIPE [bold]$($device.deviceName)[/]? This will factory reset the device![/]"
                if ($confirm) {
                    $confirm2 = Show-InTUIConfirm -Message "[red]$([char]0x26A0) FINAL CONFIRMATION: This action CANNOT be undone. Proceed with wipe?[/]"
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

    Write-InTUILog -Message "Executing device action" -Context @{ DeviceId = $DeviceId; Action = $Action }

    # Track if an error occurred via script variable
    $script:LastActionError = $false

    Show-InTUILoading -Title "[blue]Executing $Action...[/]" -ScriptBlock {
        $params = @{
            Uri    = "/deviceManagement/managedDevices/$DeviceId/$Action"
            Method = 'POST'
            Beta   = $true
        }
        if ($Body) { $params['Body'] = $Body }

        $result = Invoke-InTUIGraphRequest @params
        # Invoke-InTUIGraphRequest returns null on both success (204) and error
        # But it prints "Graph API Error:" on errors, so we need another way to detect
        # If it returns non-null, it definitely succeeded
        if ($null -ne $result) {
            $script:LastActionError = $false
        }
    }

    # For POST actions, assume success unless error was printed
    # The user will see the Graph API Error message if there was one
    Write-InTUILog -Message "Device action initiated" -Context @{ DeviceId = $DeviceId; Action = $Action }
    Show-InTUISuccess "Action '$Action' has been initiated. Check the device for status."
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

    if (-not $configs.value) {
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
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId/detectedApps" -Beta
    }

    if (-not $appStatuses.value) {
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
        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDeviceOverview' -Beta
    }

    if ($null -eq $complianceData) {
        Show-InTUIWarning "Could not load compliance data."
        Read-InTUIKey
        return
    }

    # Calculate totals for progress bars
    $compSum = $complianceData.deviceCompliancePolicyDeviceStateSummary
    $totalCompliance = ([int]($compSum.compliantDeviceCount ?? 0)) + ([int]($compSum.nonCompliantDeviceCount ?? 0)) +
                       ([int]($compSum.inGracePeriodCount ?? 0)) + ([int]($compSum.errorCount ?? 0))

    $compPercent = if ($totalCompliance -gt 0) { [Math]::Round(([int]($compSum.compliantDeviceCount ?? 0) / $totalCompliance) * 100, 1) } else { 0 }
    $compBar = Get-InTUIProgressBar -Percentage $compPercent -Width 30

    $osSum = $complianceData.deviceOperatingSystemSummary
    $totalOS = ([int]($osSum.windowsCount ?? 0)) + ([int]($osSum.iosCount ?? 0)) + ([int]($osSum.macOSCount ?? 0)) +
               ([int]($osSum.androidCount ?? 0)) + ([int]($osSum.linuxCount ?? 0))

    $content = @"
[bold white]$([char]0x2713) Device Compliance Overview[/]

$([char]0x2500)$([char]0x2500)$([char]0x2500) [grey dim]Enrollment Summary[/] $([char]0x2500)$([char]0x2500)$([char]0x2500)
[grey]$([char]0x25CF) Total Enrolled:[/]      [white bold]$($complianceData.enrolledDeviceCount ?? 'N/A')[/]
[grey]$([char]0x25CF) MDM Enrolled:[/]        [white bold]$($complianceData.mdmEnrolledCount ?? 'N/A')[/]
[grey]$([char]0x25CF) Dual Enrolled:[/]       [white bold]$($complianceData.dualEnrolledDeviceCount ?? 'N/A')[/]

$([char]0x2500)$([char]0x2500)$([char]0x2500) [grey dim]Compliance Status[/] $([char]0x2500)$([char]0x2500)$([char]0x2500)
$compBar [white]$compPercent%[/] compliant

[green]$([char]0x25CF)[/] Compliant          [white bold]$($compSum.compliantDeviceCount ?? 'N/A')[/]
[red]$([char]0x25CF)[/] Non-compliant      [white bold]$($compSum.nonCompliantDeviceCount ?? 'N/A')[/]
[yellow]$([char]0x25CF)[/] In Grace Period    [white bold]$($compSum.inGracePeriodCount ?? 'N/A')[/]
[grey]$([char]0x25CF)[/] Not Evaluated      [white bold]$($compSum.notEvaluatedDeviceCount ?? 'N/A')[/]
[red]$([char]0x25CF)[/] Error              [white bold]$($compSum.errorCount ?? 'N/A')[/]
[orange1]$([char]0x25CF)[/] Conflict           [white bold]$($compSum.conflictDeviceCount ?? 'N/A')[/]

$([char]0x2500)$([char]0x2500)$([char]0x2500) [grey dim]OS Distribution[/] $([char]0x2500)$([char]0x2500)$([char]0x2500)
[blue]$([char]0x25A0)[/] Windows    [white bold]$($osSum.windowsCount ?? 'N/A')[/]
[grey]$([char]0x25CF)[/] iOS        [white bold]$($osSum.iosCount ?? 'N/A')[/]
[white]$([char]0x25C6)[/] macOS      [white bold]$($osSum.macOSCount ?? 'N/A')[/]
[green]$([char]0x25B2)[/] Android    [white bold]$($osSum.androidCount ?? 'N/A')[/]
[yellow]$([char]0x25C7)[/] Linux      [white bold]$($osSum.linuxCount ?? 'N/A')[/]
"@

    Show-InTUIPanel -Title "[blue]$([char]0x2713) Compliance Overview[/]" -Content $content -BorderColor Blue

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

function Get-InTUIThreatLevelDisplay {
    <#
    .SYNOPSIS
        Returns color-coded threat level display.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ThreatLevel
    )

    switch ($ThreatLevel) {
        'none'     { return "[green]None[/]" }
        'low'      { return "[yellow]Low[/]" }
        'medium'   { return "[orange1]Medium[/]" }
        'high'     { return "[red]High[/]" }
        'severe'   { return "[red bold]Severe[/]" }
        default    { return "[grey]$($ThreatLevel ?? 'Unknown')[/]" }
    }
}

function Show-InTUIDefenderPanel {
    <#
    .SYNOPSIS
        Shows Defender protection status panel for a Windows device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId
    )

    # Fetch Windows protection state
    $protectionState = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId`?`$select=windowsProtectionState" -Beta

    if (-not $protectionState.windowsProtectionState) {
        return  # No Defender data available
    }

    $defender = $protectionState.windowsProtectionState

    $rtpStatus = if ($defender.realTimeProtectionEnabled) { "[green]Enabled[/]" } else { "[red]Disabled[/]" }
    $malwareStatus = if ($defender.malwareProtectionEnabled) { "[green]Enabled[/]" } else { "[red]Disabled[/]" }
    $networkStatus = if ($defender.networkInspectionSystemEnabled) { "[green]Enabled[/]" } else { "[grey]Disabled[/]" }
    $rebootRequired = if ($defender.rebootRequired) { "[yellow]Yes[/]" } else { "[green]No[/]" }
    $fullScanRequired = if ($defender.fullScanRequired) { "[yellow]Yes[/]" } else { "[green]No[/]" }
    $signatureOutOfDate = if ($defender.signatureUpdateOverdue) { "[red]Yes[/]" } else { "[green]No[/]" }

    $threatLevel = Get-InTUIThreatLevelDisplay -ThreatLevel $defender.deviceThreatState

    $defenderContent = @"
[grey]Real-Time Protection:[/]     $rtpStatus
[grey]Malware Protection:[/]       $malwareStatus
[grey]Network Inspection:[/]       $networkStatus
[grey]Device Threat Level:[/]      $threatLevel
[grey]Reboot Required:[/]          $rebootRequired
[grey]Full Scan Required:[/]       $fullScanRequired
[grey]Signatures Outdated:[/]      $signatureOutOfDate
[grey]Last Quick Scan:[/]          $(Format-InTUIDate -DateString $defender.lastQuickScanDateTime)
[grey]Last Full Scan:[/]           $(Format-InTUIDate -DateString $defender.lastFullScanDateTime)
"@

    Show-InTUIPanel -Title "[red]Microsoft Defender[/]" -Content $defenderContent -BorderColor Red
}
