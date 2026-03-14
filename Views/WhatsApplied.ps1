function Show-InTUIWhatsAppliedView {
    <#
    .SYNOPSIS
        Unified view showing all policies, profiles, and apps applied to a device or user.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', "What's Applied?")

        $choices = @('By Device', 'By User', '─────────────', 'Back to Home')
        $selection = Show-InTUIMenu -Title "[blue]What's Applied?[/]" -Choices $choices

        switch ($selection) {
            'By Device' {
                $searchTerm = Read-InTUITextInput -Message "[blue]Enter device name to search[/]"
                if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }

                $safeTerm = ConvertTo-InTUISafeFilterValue -Value $searchTerm
                $devices = Show-InTUILoading -Title "[blue]Searching devices...[/]" -ScriptBlock {
                    Get-InTUIPagedResults -Uri '/deviceManagement/managedDevices' -Beta -PageSize 20 `
                        -Filter "contains(deviceName,'$safeTerm')" `
                        -Select 'id,deviceName,operatingSystem,userPrincipalName'
                }

                if ($null -eq $devices -or $devices.Results.Count -eq 0) {
                    Show-InTUIWarning "No devices found matching '$searchTerm'."
                    Read-InTUIKey
                    continue
                }

                $deviceChoices = @()
                foreach ($d in $devices.Results) {
                    $deviceChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $d.deviceName)[/] [grey]| $($d.operatingSystem) | $($d.userPrincipalName ?? 'Unassigned')[/]"
                }
                $choiceMap = Get-InTUIChoiceMap -Choices $deviceChoices
                $menuChoices = @($choiceMap.Choices + '─────────────' + 'Cancel')

                $deviceSelection = Show-InTUIMenu -Title "[blue]Select a device[/]" -Choices $menuChoices

                if ($deviceSelection -ne 'Cancel' -and $deviceSelection -ne '─────────────') {
                    $idx = $choiceMap.IndexMap[$deviceSelection]
                    if ($null -ne $idx -and $idx -lt $devices.Results.Count) {
                        $selectedDevice = $devices.Results[$idx]
                        Show-InTUIDeviceWhatsApplied -DeviceId $selectedDevice.id -DeviceName $selectedDevice.deviceName
                    }
                }
            }
            'By User' {
                $searchTerm = Read-InTUITextInput -Message "[blue]Enter user name or UPN to search[/]"
                if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }

                $safeTerm = ConvertTo-InTUISafeFilterValue -Value $searchTerm
                $users = Show-InTUILoading -Title "[blue]Searching users...[/]" -ScriptBlock {
                    Get-InTUIPagedResults -Uri '/users' -PageSize 20 `
                        -Filter "startsWith(displayName,'$safeTerm') or startsWith(userPrincipalName,'$safeTerm')" `
                        -Select 'id,displayName,userPrincipalName'
                }

                if ($null -eq $users -or $users.Results.Count -eq 0) {
                    Show-InTUIWarning "No users found matching '$searchTerm'."
                    Read-InTUIKey
                    continue
                }

                $userChoices = @()
                foreach ($u in $users.Results) {
                    $userChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $u.displayName)[/] [grey]| $($u.userPrincipalName)[/]"
                }
                $choiceMap = Get-InTUIChoiceMap -Choices $userChoices
                $menuChoices = @($choiceMap.Choices + '─────────────' + 'Cancel')

                $userSelection = Show-InTUIMenu -Title "[blue]Select a user[/]" -Choices $menuChoices

                if ($userSelection -ne 'Cancel' -and $userSelection -ne '─────────────') {
                    $idx = $choiceMap.IndexMap[$userSelection]
                    if ($null -ne $idx -and $idx -lt $users.Results.Count) {
                        $selectedUser = $users.Results[$idx]
                        Show-InTUIUserWhatsApplied -UserId $selectedUser.id -UserName $selectedUser.displayName
                    }
                }
            }
            'Back to Home' {
                $exitView = $true
            }
            default { continue }
        }
    }
}

function Show-InTUIDeviceWhatsApplied {
    <#
    .SYNOPSIS
        Shows all configuration, compliance, and app assignments applied to a specific device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter()]
        [string]$DeviceName = 'Device'
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', "What's Applied?", $DeviceName)

    Write-InTUILog -Message "Loading What's Applied for device" -Context @{ DeviceId = $DeviceId; DeviceName = $DeviceName }

    $data = Show-InTUILoading -Title "[blue]Loading applied policies and apps...[/]" -ScriptBlock {
        $configStates = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId/deviceConfigurationStates" -Beta
        $complianceStates = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/$DeviceId/deviceCompliancePolicyStates" -Beta
        $deviceInfo = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices/${DeviceId}?`$select=userId" -Beta

        $appIntents = $null
        if ($deviceInfo.userId) {
            $appIntents = Invoke-InTUIGraphRequest -Uri "/users/$($deviceInfo.userId)/mobileAppIntentAndStates" -Beta
        }

        @{
            ConfigStates    = $configStates
            ComplianceStates = $complianceStates
            AppIntents      = $appIntents
        }
    }

    # Configuration Profiles
    $configItems = if ($data.ConfigStates.value) { @($data.ConfigStates.value) } else { @() }
    if ($configItems.Count -gt 0) {
        $configRows = @()
        foreach ($state in $configItems) {
            $stateColor = switch ($state.state) {
                'compliant'    { 'green' }
                'notApplicable' { 'grey' }
                default        { 'yellow' }
            }
            $configRows += , @(
                ($state.displayName ?? 'N/A'),
                "[$stateColor]$($state.state ?? 'N/A')[/]",
                ($state.platformType ?? 'N/A')
            )
        }
        Render-InTUITable -Title "Configuration Profiles ($($configItems.Count))" -Columns @('Profile Name', 'State', 'Platform') -Rows $configRows -BorderColor Blue
    }
    else {
        Show-InTUIPanel -Title "[blue]Configuration Profiles[/]" -Content "[grey]No configuration profile states found.[/]" -BorderColor Blue
    }

    # Compliance Policies
    $complianceItems = if ($data.ComplianceStates.value) { @($data.ComplianceStates.value) } else { @() }
    if ($complianceItems.Count -gt 0) {
        $compRows = @()
        foreach ($state in $complianceItems) {
            $stateColor = Get-InTUIComplianceColor -State $state.state
            $compRows += , @(
                ($state.displayName ?? 'N/A'),
                "[$stateColor]$($state.state ?? 'N/A')[/]"
            )
        }
        Render-InTUITable -Title "Compliance Policies ($($complianceItems.Count))" -Columns @('Policy Name', 'State') -Rows $compRows -BorderColor Green
    }
    else {
        Show-InTUIPanel -Title "[green]Compliance Policies[/]" -Content "[grey]No compliance policy states found.[/]" -BorderColor Green
    }

    # App Assignments
    if ($data.AppIntents -and $data.AppIntents.value) {
        $allApps = @()
        foreach ($intentState in $data.AppIntents.value) {
            if ($intentState.mobileAppList) {
                $allApps += @($intentState.mobileAppList)
            }
        }

        if ($allApps.Count -gt 0) {
            $appRows = @()
            foreach ($app in $allApps) {
                $installColor = Get-InTUIInstallStateColor -State $app.installState
                $appRows += , @(
                    ($app.displayName ?? 'N/A'),
                    "[$installColor]$($app.installState ?? 'N/A')[/]",
                    ($app.mobileAppIntent ?? 'N/A')
                )
            }
            Render-InTUITable -Title "App Assignments ($($allApps.Count))" -Columns @('App Name', 'Install State', 'Intent') -Rows $appRows -BorderColor Cyan
        }
        else {
            Show-InTUIPanel -Title "[cyan]App Assignments[/]" -Content "[grey]No app assignment data found.[/]" -BorderColor Cyan
        }
    }
    else {
        Show-InTUIPanel -Title "[cyan]App Assignments[/]" -Content "[grey]No app intent data available (no user association).[/]" -BorderColor Cyan
    }

    Read-InTUIKey
}

function Show-InTUIUserWhatsApplied {
    <#
    .SYNOPSIS
        Shows all configuration, compliance, and app assignments targeting a user via group membership.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [string]$UserName = 'User'
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', "What's Applied?", $UserName)

    Write-InTUILog -Message "Loading What's Applied for user" -Context @{ UserId = $UserId; UserName = $UserName }

    $data = Show-InTUILoading -Title "[blue]Loading user assignments...[/]" -ScriptBlock {
        # Get user's group memberships
        $groups = Invoke-InTUIGraphRequest -Uri "/users/$UserId/memberOf?`$select=id,displayName" -All

        # Get configuration policies with assignments
        $catalogPolicies = Invoke-InTUIGraphRequest -Uri '/deviceManagement/configurationPolicies?$expand=assignments&$top=100' -Beta
        $legacyPolicies = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceConfigurations?$expand=assignments&$top=100' -Beta

        # Get compliance policies with assignments
        $compliancePolicies = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$top=100' -Beta

        # Get apps with assignments
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$expand=assignments&$top=100' -Beta

        @{
            Groups             = $groups
            CatalogPolicies    = $catalogPolicies
            LegacyPolicies     = $legacyPolicies
            CompliancePolicies = $compliancePolicies
            Apps               = $apps
        }
    }

    $groupIds = @()
    $groupList = if ($data.Groups -is [array]) { $data.Groups } elseif ($data.Groups.value) { @($data.Groups.value) } else { @() }
    foreach ($g in $groupList) {
        $groupIds += $g.id
    }

    # Well-known group IDs for All Users / All Devices
    $allUsersId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
    $allDevicesId = 'adadadad-808e-44e2-905a-0b7873a8a531'

    # Helper: check if any assignment targets this user's groups
    $matchAssignments = {
        param($assignments)
        foreach ($assignment in $assignments) {
            $target = $assignment.target
            $type = $target.'@odata.type'
            if ($type -eq '#microsoft.graph.allLicensedUsersAssignmentTarget' -or $type -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                return $true
            }
            if ($target.groupId -and ($groupIds -contains $target.groupId -or $target.groupId -eq $allUsersId -or $target.groupId -eq $allDevicesId)) {
                return $true
            }
        }
        return $false
    }

    # Match configuration profiles
    $matchedConfigs = @()
    foreach ($source in @($data.CatalogPolicies, $data.LegacyPolicies)) {
        $items = if ($source.value) { @($source.value) } else { @() }
        foreach ($policy in $items) {
            $assignments = if ($policy.assignments) { @($policy.assignments) } else { @() }
            if ($assignments.Count -gt 0 -and (& $matchAssignments $assignments)) {
                $matchedConfigs += $policy
            }
        }
    }

    if ($matchedConfigs.Count -gt 0) {
        $configRows = @()
        foreach ($policy in $matchedConfigs) {
            $name = $policy.displayName ?? $policy.name ?? 'N/A'
            $configRows += , @(
                (ConvertTo-InTUISafeMarkup -Text $name),
                "$(@($policy.assignments).Count) groups"
            )
        }
        Render-InTUITable -Title "Configuration Profiles ($($matchedConfigs.Count))" -Columns @('Profile Name', 'Assignments') -Rows $configRows -BorderColor Blue
    }
    else {
        Show-InTUIPanel -Title "[blue]Configuration Profiles[/]" -Content "[grey]No matching configuration profiles found.[/]" -BorderColor Blue
    }

    # Match compliance policies
    $matchedCompliance = @()
    $compItems = if ($data.CompliancePolicies.value) { @($data.CompliancePolicies.value) } else { @() }
    foreach ($policy in $compItems) {
        $assignments = if ($policy.assignments) { @($policy.assignments) } else { @() }
        if ($assignments.Count -gt 0 -and (& $matchAssignments $assignments)) {
            $matchedCompliance += $policy
        }
    }

    if ($matchedCompliance.Count -gt 0) {
        $compRows = @()
        foreach ($policy in $matchedCompliance) {
            $compRows += , @(
                (ConvertTo-InTUISafeMarkup -Text ($policy.displayName ?? 'N/A')),
                "$(@($policy.assignments).Count) groups"
            )
        }
        Render-InTUITable -Title "Compliance Policies ($($matchedCompliance.Count))" -Columns @('Policy Name', 'Assignments') -Rows $compRows -BorderColor Green
    }
    else {
        Show-InTUIPanel -Title "[green]Compliance Policies[/]" -Content "[grey]No matching compliance policies found.[/]" -BorderColor Green
    }

    # Match apps
    $matchedApps = @()
    $appItems = if ($data.Apps.value) { @($data.Apps.value) } else { @() }
    foreach ($app in $appItems) {
        $assignments = if ($app.assignments) { @($app.assignments) } else { @() }
        if ($assignments.Count -gt 0 -and (& $matchAssignments $assignments)) {
            $matchedApps += $app
        }
    }

    if ($matchedApps.Count -gt 0) {
        $appRows = @()
        foreach ($app in $matchedApps) {
            $appRows += , @(
                (ConvertTo-InTUISafeMarkup -Text ($app.displayName ?? 'N/A')),
                "$(@($app.assignments).Count) assignments"
            )
        }
        Render-InTUITable -Title "App Assignments ($($matchedApps.Count))" -Columns @('App Name', 'Assignments') -Rows $appRows -BorderColor Cyan
    }
    else {
        Show-InTUIPanel -Title "[cyan]App Assignments[/]" -Content "[grey]No matching app assignments found.[/]" -BorderColor Cyan
    }

    Write-InTUIText ""
    Write-InTUIText "[grey]Groups evaluated: $($groupIds.Count) | Profiles: $($matchedConfigs.Count) | Compliance: $($matchedCompliance.Count) | Apps: $($matchedApps.Count)[/]"

    Read-InTUIKey
}
