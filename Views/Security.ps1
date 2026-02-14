function Show-InTUISecurityView {
    <#
    .SYNOPSIS
        Displays the Security view with security baselines, endpoint protection, and BitLocker keys.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security')

        $choices = @(
            "$([char]0x26E8) Security Baselines",
            "$([char]0x2699) Endpoint Protection Policies",
            "$([char]0x26A0) Microsoft Defender Overview",
            "$([char]0x2318) BitLocker Recovery Keys",
            "$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)$([char]0x2550)",
            "$([char]0x2190) Back to Home"
        )

        $selection = Show-InTUIMenu -Title "[red]$([char]0x26E8) Security[/]" -Choices $choices

        Write-InTUILog -Message "Security view selection" -Context @{ Selection = $selection }

        # Strip icon prefix for switch matching
        $cleanSelection = $selection -replace "^.{1,2} ", ""

        switch ($cleanSelection) {
            'Security Baselines' {
                Show-InTUISecurityBaselineList
            }
            'Endpoint Protection Policies' {
                Show-InTUIEndpointProtectionList
            }
            'Microsoft Defender Overview' {
                Show-InTUIDefenderOverview
            }
            'BitLocker Recovery Keys' {
                Show-InTUIBitLockerKeys
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

function Show-InTUISecurityBaselineList {
    <#
    .SYNOPSIS
        Displays a list of security baseline intents.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines')

        $params = @{
            Uri      = '/deviceManagement/intents'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,isAssigned'
        }

        $intents = Show-InTUILoading -Title "[red]Loading security baselines...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $intents -or $intents.Results.Count -eq 0) {
            Show-InTUIWarning "No security baselines found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $intentChoices = @()
        foreach ($intent in $intents.Results) {
            $assigned = if ($intent.isAssigned) { 'Yes' } else { 'No' }
            $modified = Format-InTUIDate -DateString $intent.lastModifiedDateTime

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $intent.displayName)[/] [grey]| Assigned: $assigned | $modified[/]"
            $intentChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $intentChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($intents.Count ?? $intents.Results.Count) -Showing $intents.Results.Count

        $selection = Show-InTUIMenu -Title "[red]Select a baseline[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $intents.Results.Count) {
                Show-InTUISecurityBaselineDetail -IntentId $intents.Results[$idx].id
            }
        }
    }
}

function Show-InTUISecurityBaselineDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific security baseline intent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IntentId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[red]Loading baseline details...[/]" -ScriptBlock {
            $intent = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/assignments" -Beta
            $states = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/deviceStates?`$top=200" -Beta

            @{
                Intent      = $intent
                Assignments = $assign
                DeviceStates = $states
            }
        }

        $intent = $detailData.Intent
        $assignments = $detailData.Assignments
        $deviceStates = $detailData.DeviceStates

        if ($null -eq $intent) {
            Show-InTUIError "Failed to load baseline details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines', $intent.displayName)

        $assigned = if ($intent.isAssigned) { '[green]Yes[/]' } else { '[grey]No[/]' }

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $intent.displayName)[/]

[grey]Description:[/]       $(if ($intent.description) { $intent.description.Substring(0, [Math]::Min(200, $intent.description.Length)) } else { 'N/A' })
[grey]Assigned:[/]          $assigned
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $intent.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[red]Baseline Properties[/]" -Content $propsContent -BorderColor Red

        # Assignments panel
        $assignmentCount = if ($assignments.value) { @($assignments.value).Count } else { 0 }
        $assignContent = "[grey]Total Assignments:[/] [white]$assignmentCount[/]"

        if ($assignments.value) {
            $assignContent += "`n"
            foreach ($assignment in $assignments.value) {
                $targetType = switch ($assignment.target.'@odata.type') {
                    '#microsoft.graph.allLicensedUsersAssignmentTarget' { '[blue]All Users[/]' }
                    '#microsoft.graph.allDevicesAssignmentTarget'       { '[blue]All Devices[/]' }
                    '#microsoft.graph.groupAssignmentTarget'            { "Group: $($assignment.target.groupId)" }
                    '#microsoft.graph.exclusionGroupAssignmentTarget'   { "[red]Exclude:[/] $($assignment.target.groupId)" }
                    default { $assignment.target.'@odata.type' -replace '#microsoft\.graph\.', '' }
                }
                $assignContent += "`n  $targetType"
            }
        }

        Show-InTUIPanel -Title "[red]Assignments[/]" -Content $assignContent -BorderColor Red

        # Device state summary panel
        $stateList = if ($deviceStates.value) { @($deviceStates.value) } else { @() }
        $succeeded = @($stateList | Where-Object { $_.state -eq 'succeeded' -or $_.state -eq 'compliant' }).Count
        $errorCount = @($stateList | Where-Object { $_.state -eq 'error' }).Count
        $conflict = @($stateList | Where-Object { $_.state -eq 'conflict' }).Count
        $notApplicable = @($stateList | Where-Object { $_.state -eq 'notApplicable' }).Count

        $stateContent = @"
[grey]Total Devices:[/]    [white]$($stateList.Count)[/]
[green]Succeeded:[/]        $succeeded
[red]Error:[/]            $errorCount
[orange1]Conflict:[/]          $conflict
[grey]Not Applicable:[/]   $notApplicable
"@

        Show-InTUIPanel -Title "[red]Device State Summary[/]" -Content $stateContent -BorderColor Red

        $actionChoices = @(
            'View Device States',
            '─────────────',
            'Back to Baselines'
        )

        $action = Show-InTUIMenu -Title "[red]Baseline Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Security baseline detail action" -Context @{ IntentId = $IntentId; BaselineName = $intent.displayName; Action = $action }

        switch ($action) {
            'View Device States' {
                Show-InTUISecurityBaselineDeviceStates -IntentId $IntentId -BaselineName $intent.displayName
            }
            'Back to Baselines' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUISecurityBaselineDeviceStates {
    <#
    .SYNOPSIS
        Displays device state table for a security baseline intent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IntentId,

        [Parameter()]
        [string]$BaselineName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines', $BaselineName, 'Device States')

    $states = Show-InTUILoading -Title "[red]Loading device states...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/deviceStates?`$top=50" -Beta
    }

    if (-not $states.value) {
        Show-InTUIWarning "No device state data available for this baseline."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($state in $states.value) {
        $stateColor = switch ($state.state) {
            'succeeded'     { 'green' }
            'compliant'     { 'green' }
            'error'         { 'red' }
            'conflict'      { 'orange1' }
            'notApplicable' { 'grey' }
            default         { 'yellow' }
        }

        $rows += , @(
            ($state.deviceDisplayName ?? 'N/A'),
            "[$stateColor]$($state.state)[/]",
            ($state.userName ?? 'N/A'),
            (Format-InTUIDate -DateString $state.lastReportedDateTime)
        )
    }

    Show-InTUITable -Title "Device States" -Columns @('Device', 'State', 'User', 'Last Reported') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIEndpointProtectionList {
    <#
    .SYNOPSIS
        Displays a list of endpoint protection device configurations.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection')

        $params = @{
            Uri      = '/deviceManagement/deviceConfigurations'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime'
        }

        $configs = Show-InTUILoading -Title "[red]Loading endpoint protection policies...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $configs -or $configs.Results.Count -eq 0) {
            Show-InTUIWarning "No device configurations found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        # Client-side filter for endpoint protection types
        $filteredResults = @($configs.Results | Where-Object {
            $odataType = $_.'@odata.type'
            $odataType -match 'endpointProtection' -or $odataType -match 'windowsDefender' -or $odataType -match 'firewallRules'
        })

        if ($filteredResults.Count -eq 0) {
            Show-InTUIWarning "No endpoint protection policies found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $configChoices = @()
        foreach ($config in $filteredResults) {
            $typeName = ($config.'@odata.type' -replace '#microsoft\.graph\.', '')
            $modified = Format-InTUIDate -DateString $config.lastModifiedDateTime

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/] [grey]| $typeName | $modified[/]"
            $configChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $configChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $filteredResults.Count -Showing $filteredResults.Count

        $selection = Show-InTUIMenu -Title "[red]Select a policy[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $filteredResults.Count) {
                Show-InTUIEndpointProtectionDetail -ConfigId $filteredResults[$idx].id
            }
        }
    }
}

function Show-InTUIEndpointProtectionDetail {
    <#
    .SYNOPSIS
        Displays detailed information about an endpoint protection configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[red]Loading policy details...[/]" -ScriptBlock {
            $config = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/assignments" -Beta
            $statuses = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/deviceStatuses?`$top=200" -Beta

            @{
                Config      = $config
                Assignments = $assign
                Statuses    = $statuses
            }
        }

        $config = $detailData.Config
        $assignments = $detailData.Assignments
        $statuses = $detailData.Statuses

        if ($null -eq $config) {
            Show-InTUIError "Failed to load policy details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection', $config.displayName)

        $typeName = ($config.'@odata.type' -replace '#microsoft\.graph\.', '')

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/]

[grey]Type:[/]              $typeName
[grey]Description:[/]       $(if ($config.description) { $config.description.Substring(0, [Math]::Min(200, $config.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $config.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $config.lastModifiedDateTime)
[grey]Version:[/]           $($config.version ?? 'N/A')
"@

        Show-InTUIPanel -Title "[red]Policy Properties[/]" -Content $propsContent -BorderColor Red

        # Assignments panel
        $assignmentCount = if ($assignments.value) { @($assignments.value).Count } else { 0 }
        $assignContent = "[grey]Total Assignments:[/] [white]$assignmentCount[/]"

        if ($assignments.value) {
            $assignContent += "`n"
            foreach ($assignment in $assignments.value) {
                $targetType = switch ($assignment.target.'@odata.type') {
                    '#microsoft.graph.allLicensedUsersAssignmentTarget' { '[blue]All Users[/]' }
                    '#microsoft.graph.allDevicesAssignmentTarget'       { '[blue]All Devices[/]' }
                    '#microsoft.graph.groupAssignmentTarget'            { "Group: $($assignment.target.groupId)" }
                    '#microsoft.graph.exclusionGroupAssignmentTarget'   { "[red]Exclude:[/] $($assignment.target.groupId)" }
                    default { $assignment.target.'@odata.type' -replace '#microsoft\.graph\.', '' }
                }
                $assignContent += "`n  $targetType"
            }
        }

        Show-InTUIPanel -Title "[red]Assignments[/]" -Content $assignContent -BorderColor Red

        # Device status summary panel
        $statusList = if ($statuses.value) { @($statuses.value) } else { @() }
        $succeeded = @($statusList | Where-Object { $_.status -eq 'succeeded' }).Count
        $failed = @($statusList | Where-Object { $_.status -eq 'failed' }).Count
        $pending = @($statusList | Where-Object { $_.status -eq 'pending' -or $_.status -eq 'notApplicable' }).Count
        $other = $statusList.Count - $succeeded - $failed - $pending

        $statusContent = @"
[grey]Total Devices:[/]  [white]$($statusList.Count)[/]
[green]Succeeded:[/]      $succeeded
[red]Failed:[/]         $failed
[yellow]Pending:[/]        $pending
"@
        if ($other -gt 0) {
            $statusContent += "`n[grey]Other:[/]          $other"
        }

        Show-InTUIPanel -Title "[red]Device Status Summary[/]" -Content $statusContent -BorderColor Red

        $actionChoices = @(
            'View Device Statuses',
            '─────────────',
            'Back to Endpoint Protection'
        )

        $action = Show-InTUIMenu -Title "[red]Policy Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Endpoint protection detail action" -Context @{ ConfigId = $ConfigId; ConfigName = $config.displayName; Action = $action }

        switch ($action) {
            'View Device Statuses' {
                Show-InTUIEndpointProtectionDeviceStatuses -ConfigId $ConfigId -ConfigName $config.displayName
            }
            'Back to Endpoint Protection' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIEndpointProtectionDeviceStatuses {
    <#
    .SYNOPSIS
        Displays device status table for an endpoint protection configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigId,

        [Parameter()]
        [string]$ConfigName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection', $ConfigName, 'Device Statuses')

    $statuses = Show-InTUILoading -Title "[red]Loading device statuses...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No device status data available for this policy."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($status in $statuses.value) {
        $stateColor = switch ($status.status) {
            'succeeded'     { 'green' }
            'failed'        { 'red' }
            'error'         { 'red' }
            'pending'       { 'yellow' }
            'notApplicable' { 'grey' }
            default         { 'yellow' }
        }

        $rows += , @(
            ($status.deviceDisplayName ?? 'N/A'),
            "[$stateColor]$($status.status)[/]",
            ($status.userName ?? 'N/A'),
            (Format-InTUIDate -DateString $status.lastReportedDateTime)
        )
    }

    Show-InTUITable -Title "Device Statuses" -Columns @('Device', 'Status', 'User', 'Last Reported') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIBitLockerKeys {
    <#
    .SYNOPSIS
        Search for a device and display its BitLocker recovery keys.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'BitLocker Recovery Keys')

        $searchTerm = Read-SpectreText -Message "[red]Enter device name or device ID to search[/]"

        if (-not $searchTerm) {
            $exitView = $true
            continue
        }

        Write-InTUILog -Message "BitLocker key search" -Context @{ SearchTerm = $searchTerm }

        # Search for matching devices
        $devices = Show-InTUILoading -Title "[red]Searching for devices...[/]" -ScriptBlock {
            $safe = ConvertTo-InTUISafeFilterValue -Value $searchTerm
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=contains(deviceName,'$safe')&`$select=id,deviceName,azureADDeviceId" -Beta
        }

        if (-not $devices.value) {
            Show-InTUIWarning "No devices found matching '$searchTerm'."
            Read-InTUIKey
            continue
        }

        $deviceChoices = @()
        foreach ($device in $devices.value) {
            $deviceChoices += "[white]$($device.deviceName)[/] [grey]| $($device.azureADDeviceId ?? 'No Azure AD ID')[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $deviceChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        $selection = Show-InTUIMenu -Title "[red]Select a device[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            continue
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt @($devices.value).Count) {
                $selectedDevice = @($devices.value)[$idx]

                if (-not $selectedDevice.azureADDeviceId) {
                    Show-InTUIWarning "Selected device does not have an Azure AD Device ID. Cannot retrieve BitLocker keys."
                    Read-InTUIKey
                    continue
                }

                Write-InTUILog -Message "Retrieving BitLocker keys for device" -Context @{
                    DeviceName = $selectedDevice.deviceName
                    AzureADDeviceId = $selectedDevice.azureADDeviceId
                }

                Show-InTUIBitLockerKeysForDevice -DeviceName $selectedDevice.deviceName -AzureADDeviceId $selectedDevice.azureADDeviceId
            }
        }
    }
}

function Show-InTUIBitLockerKeysForDevice {
    <#
    .SYNOPSIS
        Displays BitLocker recovery keys for a specific device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName,

        [Parameter(Mandatory)]
        [string]$AzureADDeviceId
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'BitLocker Recovery Keys', $DeviceName)

    # Get BitLocker recovery keys (v1.0, not beta)
    $keys = Show-InTUILoading -Title "[red]Loading BitLocker recovery keys...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$AzureADDeviceId'"
    }

    if (-not $keys.value) {
        Show-InTUIWarning "No BitLocker recovery keys found for '$DeviceName'."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "BitLocker keys found" -Context @{ DeviceName = $DeviceName; KeyCount = @($keys.value).Count }

    $rows = @()
    foreach ($key in $keys.value) {
        $rows += , @(
            ($key.id ?? 'N/A'),
            (Format-InTUIDate -DateString $key.createdDateTime),
            ($key.volumeType ?? 'N/A'),
            '[grey]********-****-****-****-************[/]'
        )
    }

    Show-InTUITable -Title "BitLocker Recovery Keys for $DeviceName" -Columns @('Key ID', 'Created', 'Volume Type', 'Recovery Key') -Rows $rows

    # Offer to reveal individual keys
    $revealChoices = @()
    foreach ($key in $keys.value) {
        $revealChoices += "Reveal key: $($key.id)"
    }
    $choiceMap = Get-InTUIChoiceMap -Choices $revealChoices
    $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

    $revealSelection = Show-InTUIMenu -Title "[red]Reveal a recovery key?[/]" -Choices $menuChoices

    if ($revealSelection -ne 'Back' -and $revealSelection -ne '─────────────') {
        $revealIdx = $choiceMap.IndexMap[$revealSelection]
        if ($null -ne $revealIdx -and $revealIdx -lt @($keys.value).Count) {
            $selectedKey = @($keys.value)[$revealIdx]

            Write-InTUILog -Message "Revealing BitLocker recovery key" -Context @{ KeyId = $selectedKey.id; DeviceName = $DeviceName }

            $fullKey = Show-InTUILoading -Title "[red]Retrieving recovery key...[/]" -ScriptBlock {
                Invoke-InTUIGraphRequest -Uri "/informationProtection/bitlocker/recoveryKeys/$($selectedKey.id)?`$select=key"
            }

            if ($fullKey.key) {
                $keyContent = @"
[bold white]BitLocker Recovery Key[/]

[grey]Key ID:[/]        $($selectedKey.id)
[grey]Device:[/]        $DeviceName
[grey]Volume Type:[/]   $($selectedKey.volumeType ?? 'N/A')
[grey]Created:[/]       $(Format-InTUIDate -DateString $selectedKey.createdDateTime)

[bold red]Recovery Key:[/]  [white]$($fullKey.key)[/]
"@
                Show-InTUIPanel -Title "[red]Recovery Key[/]" -Content $keyContent -BorderColor Red
            }
            else {
                Show-InTUIWarning "Could not retrieve the recovery key. Check permissions."
            }

            Read-InTUIKey
        }
    }
}

function Show-InTUIDefenderOverview {
    <#
    .SYNOPSIS
        Displays Microsoft Defender aggregate status across all Windows devices.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Microsoft Defender Overview')

    Write-InTUILog -Message "Loading Defender overview"

    $data = Show-InTUILoading -Title "[red]Loading Defender status...[/]" -ScriptBlock {
        # Get Windows devices with protection state
        $devices = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=contains(operatingSystem,'Windows')&`$select=id,deviceName,windowsProtectionState&`$top=200" -Beta

        if (-not $devices.value) {
            return $null
        }

        $stats = @{
            Total = 0
            RTPEnabled = 0
            RTPDisabled = 0
            MalwareProtectionEnabled = 0
            SignaturesUpToDate = 0
            SignaturesOutdated = 0
            RebootRequired = 0
            FullScanRequired = 0
            ThreatLevels = @{
                None = 0
                Low = 0
                Medium = 0
                High = 0
                Severe = 0
                Unknown = 0
            }
            DevicesWithThreats = @()
        }

        foreach ($device in $devices.value) {
            if (-not $device.windowsProtectionState) { continue }

            $stats.Total++
            $defender = $device.windowsProtectionState

            if ($defender.realTimeProtectionEnabled) { $stats.RTPEnabled++ } else { $stats.RTPDisabled++ }
            if ($defender.malwareProtectionEnabled) { $stats.MalwareProtectionEnabled++ }
            if ($defender.signatureUpdateOverdue) { $stats.SignaturesOutdated++ } else { $stats.SignaturesUpToDate++ }
            if ($defender.rebootRequired) { $stats.RebootRequired++ }
            if ($defender.fullScanRequired) { $stats.FullScanRequired++ }

            $threatState = $defender.deviceThreatState ?? 'unknown'
            switch ($threatState) {
                'none'   { $stats.ThreatLevels.None++ }
                'low'    { $stats.ThreatLevels.Low++ }
                'medium' { $stats.ThreatLevels.Medium++ }
                'high'   { $stats.ThreatLevels.High++; $stats.DevicesWithThreats += $device }
                'severe' { $stats.ThreatLevels.Severe++; $stats.DevicesWithThreats += $device }
                default  { $stats.ThreatLevels.Unknown++ }
            }
        }

        $stats
    }

    if ($null -eq $data -or $data.Total -eq 0) {
        Show-InTUIWarning "No Windows devices with Defender data found."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Defender overview loaded" -Context @{
        TotalDevices = $data.Total
        RTPEnabled = $data.RTPEnabled
        ThreatCount = $data.ThreatLevels.High + $data.ThreatLevels.Severe
    }

    # Protection Status Panel
    $rtpPercent = if ($data.Total -gt 0) { [math]::Round(($data.RTPEnabled / $data.Total) * 100) } else { 0 }

    $protectionContent = @"
[bold]Real-Time Protection[/]
[green]Enabled:[/]           $($data.RTPEnabled) devices ($rtpPercent%)
[red]Disabled:[/]          $($data.RTPDisabled) devices

[bold]Malware Protection[/]
[green]Enabled:[/]           $($data.MalwareProtectionEnabled) devices

[bold]Signature Status[/]
[green]Up to Date:[/]        $($data.SignaturesUpToDate) devices
[red]Outdated:[/]          $($data.SignaturesOutdated) devices

[bold]Actions Required[/]
[yellow]Reboot Required:[/]   $($data.RebootRequired) devices
[yellow]Full Scan Required:[/] $($data.FullScanRequired) devices
"@

    Show-InTUIPanel -Title "[red]Protection Status ($($data.Total) Windows Devices)[/]" -Content $protectionContent -BorderColor Red

    # Threat Levels Panel
    $threatContent = @"
[green]None:[/]      $($data.ThreatLevels.None) devices
[yellow]Low:[/]       $($data.ThreatLevels.Low) devices
[orange1]Medium:[/]    $($data.ThreatLevels.Medium) devices
[red]High:[/]      $($data.ThreatLevels.High) devices
[red bold]Severe:[/]    $($data.ThreatLevels.Severe) devices
"@

    Show-InTUIPanel -Title "[red]Threat Levels[/]" -Content $threatContent -BorderColor Red

    # Show devices with high/severe threats
    if ($data.DevicesWithThreats.Count -gt 0) {
        Write-SpectreHost "[red bold]Devices with High/Severe Threats:[/]"
        Write-SpectreHost ""

        $rows = @()
        foreach ($device in $data.DevicesWithThreats) {
            $threatLevel = Get-InTUIThreatLevelDisplay -ThreatLevel $device.windowsProtectionState.deviceThreatState
            $rows += , @(
                ($device.deviceName ?? 'N/A'),
                $threatLevel
            )
        }

        Show-InTUITable -Title "Devices Requiring Attention" -Columns @('Device', 'Threat Level') -Rows $rows -BorderColor Red
    }

    Read-InTUIKey
}
