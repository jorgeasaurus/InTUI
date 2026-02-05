function Get-InTUIConfigPolicyPlatform {
    <#
    .SYNOPSIS
        Maps a configurationPolicies platforms value to a friendly label.
    #>
    param([string]$Platforms)

    switch -Wildcard ($Platforms) {
        '*windows*' { return 'Windows' }
        '*iOS*'     { return 'iOS' }
        '*macOS*'   { return 'macOS' }
        '*android*' { return 'Android' }
        '*linux*'   { return 'Linux' }
        default     { return $Platforms ?? 'Unknown' }
    }
}

function Get-InTUIConfigPolicyTechnology {
    <#
    .SYNOPSIS
        Maps a configurationPolicies technologies value to a friendly label.
    #>
    param([string]$Technologies)

    switch -Wildcard ($Technologies) {
        '*mdm*'            { return 'MDM' }
        '*configManager*'  { return 'Config Manager' }
        '*microsoftSense*' { return 'Defender' }
        default            { return $Technologies ?? 'Unknown' }
    }
}

function Show-InTUIConfigProfilesView {
    <#
    .SYNOPSIS
        Displays the Configuration Profiles view with platform filtering and search.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Configuration Profiles')

        $choices = @(
            'All Profiles',
            'Windows Profiles',
            'iOS/iPadOS Profiles',
            'macOS Profiles',
            'Android Profiles',
            'Search Profiles',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[cyan]Configuration Profiles[/]" -Choices $choices

        Write-InTUILog -Message "Configuration Profiles view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'All Profiles' {
                Show-InTUIConfigProfileList
            }
            'Windows Profiles' {
                Show-InTUIConfigProfileList -PlatformFilter 'Windows'
            }
            'iOS/iPadOS Profiles' {
                Show-InTUIConfigProfileList -PlatformFilter 'iOS'
            }
            'macOS Profiles' {
                Show-InTUIConfigProfileList -PlatformFilter 'macOS'
            }
            'Android Profiles' {
                Show-InTUIConfigProfileList -PlatformFilter 'Android'
            }
            'Search Profiles' {
                $searchTerm = Read-SpectreText -Prompt "[cyan]Search profiles by name[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching configuration profiles" -Context @{ SearchTerm = $searchTerm }
                    Show-InTUIConfigProfileList -SearchTerm $searchTerm
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

function Show-InTUIConfigProfileList {
    <#
    .SYNOPSIS
        Displays a merged list of legacy device configurations and Settings Catalog policies.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PlatformFilter,

        [Parameter()]
        [string]$SearchTerm
    )

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader

        $breadcrumb = @('Home', 'Configuration Profiles')
        if ($PlatformFilter) { $breadcrumb += "$PlatformFilter Profiles" }
        elseif ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        else { $breadcrumb += 'All Profiles' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        $allProfiles = Show-InTUILoading -Title "[cyan]Loading configuration profiles...[/]" -ScriptBlock {
            $normalized = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Legacy device configurations
            $legacyParams = @{
                Uri      = '/deviceManagement/deviceConfigurations'
                Beta     = $true
                PageSize = 25
            }
            if ($SearchTerm) {
                $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
                $legacyParams['Filter'] = "contains(displayName,'$safe')"
            }
            $legacy = Get-InTUIPagedResults @legacyParams

            if ($legacy -and $legacy.Results) {
                foreach ($p in $legacy.Results) {
                    $typeInfo = Get-InTUIConfigProfileType -ODataType $p.'@odata.type'
                    $normalized.Add([PSCustomObject]@{
                        Id       = $p.id
                        Name     = $p.displayName
                        Platform = $typeInfo.Platform
                        Type     = $typeInfo.FriendlyName
                        Modified = $p.lastModifiedDateTime
                        Source   = 'Legacy'
                    })
                }
            }

            # Settings Catalog policies
            $catalogParams = @{
                Uri      = '/deviceManagement/configurationPolicies'
                Beta     = $true
                PageSize = 25
            }
            if ($SearchTerm) {
                $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
                $catalogParams['Filter'] = "contains(name,'$safe')"
            }
            $catalog = Get-InTUIPagedResults @catalogParams

            if ($catalog -and $catalog.Results) {
                foreach ($p in $catalog.Results) {
                    $normalized.Add([PSCustomObject]@{
                        Id       = $p.id
                        Name     = $p.name
                        Platform = Get-InTUIConfigPolicyPlatform -Platforms $p.platforms
                        Type     = Get-InTUIConfigPolicyTechnology -Technologies $p.technologies
                        Modified = $p.lastModifiedDateTime
                        Source   = 'Catalog'
                    })
                }
            }

            $normalized
        }

        if ($null -eq $allProfiles -or @($allProfiles).Count -eq 0) {
            Show-InTUIWarning "No configuration profiles found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $filteredResults = @($allProfiles)
        if ($PlatformFilter) {
            $filteredResults = @($allProfiles | Where-Object { $_.Platform -eq $PlatformFilter })

            if ($filteredResults.Count -eq 0) {
                Show-InTUIWarning "No $PlatformFilter configuration profiles found."
                Read-InTUIKey
                $exitList = $true
                continue
            }
        }

        $profileChoices = @()
        foreach ($profile in $filteredResults) {
            $modified = Format-InTUIDate -DateString $profile.Modified
            $sourceTag = if ($profile.Source -eq 'Catalog') { '[cyan]SC[/]' } else { '[grey]DC[/]' }

            $displayName = "$sourceTag [white]$($profile.Name)[/] [grey]| $($profile.Platform) | $($profile.Type) | $modified[/]"
            $profileChoices += $displayName
        }

        $profileChoices += '─────────────'
        $profileChoices += 'Back'

        Show-InTUIStatusBar -Total $filteredResults.Count -Showing $filteredResults.Count -FilterText ($PlatformFilter ?? $SearchTerm)

        $selection = Show-InTUIMenu -Title "[cyan]Select a profile[/]" -Choices $profileChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $profileChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $filteredResults.Count) {
                $selected = $filteredResults[$idx]
                if ($selected.Source -eq 'Catalog') {
                    Show-InTUICatalogProfileDetail -ProfileId $selected.Id
                }
                else {
                    Show-InTUILegacyProfileDetail -ProfileId $selected.Id
                }
            }
        }
    }
}

# region Settings Catalog (configurationPolicies)

function Show-InTUICatalogProfileDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a Settings Catalog configuration policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[cyan]Loading profile details...[/]" -ScriptBlock {
            $prof = Invoke-InTUIGraphRequest -Uri "/deviceManagement/configurationPolicies/$ProfileId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/configurationPolicies/$ProfileId/assignments" -Beta

            @{
                Profile     = $prof
                Assignments = $assign
            }
        }

        $profile = $detailData.Profile
        $assignments = $detailData.Assignments

        if ($null -eq $profile) {
            Show-InTUIError "Failed to load profile details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Configuration Profiles', $profile.name)

        $platform = Get-InTUIConfigPolicyPlatform -Platforms $profile.platforms
        $tech = Get-InTUIConfigPolicyTechnology -Technologies $profile.technologies
        $templateName = $profile.templateReference.templateDisplayName

        $propsContent = @"
[bold white]$($profile.name)[/]

[grey]Source:[/]            [cyan]Settings Catalog[/]
[grey]Platform:[/]          $platform
[grey]Technology:[/]        $tech
[grey]Description:[/]       $(if ($profile.description) { $profile.description.Substring(0, [Math]::Min(200, $profile.description.Length)) } else { 'N/A' })
[grey]Template:[/]          $(if ($templateName) { $templateName } else { 'None' })
[grey]Settings Count:[/]    $($profile.settingCount ?? 0)
[grey]Is Assigned:[/]       $($profile.isAssigned ?? $false)
[grey]Created:[/]           $(Format-InTUIDate -DateString $profile.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $profile.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[cyan]Profile Properties[/]" -Content $propsContent -BorderColor Cyan1

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

        Show-InTUIPanel -Title "[cyan]Assignments[/]" -Content $assignContent -BorderColor Cyan1

        $actionChoices = @(
            'View Settings',
            '─────────────',
            'Back to Profiles'
        )

        $action = Show-InTUIMenu -Title "[cyan]Profile Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Config profile detail action" -Context @{ ProfileId = $ProfileId; ProfileName = $profile.name; Action = $action }

        switch ($action) {
            'View Settings' {
                Show-InTUICatalogProfileSettings -ProfileId $ProfileId -ProfileName $profile.name
            }
            'Back to Profiles' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUICatalogProfileSettings {
    <#
    .SYNOPSIS
        Displays configured settings for a Settings Catalog policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId,

        [Parameter()]
        [string]$ProfileName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Configuration Profiles', $ProfileName, 'Settings')

    $settings = Show-InTUILoading -Title "[cyan]Loading settings...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/configurationPolicies/$ProfileId/settings?`$expand=settingDefinitions&`$top=100" -Beta
    }

    if (-not $settings.value) {
        Show-InTUIWarning "No settings data available for this profile."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($setting in $settings.value) {
        $defId = $setting.settingInstance.settingDefinitionId
        $settingName = if ($setting.settingDefinitions -and $setting.settingDefinitions.Count -gt 0) {
            $setting.settingDefinitions[0].displayName
        }
        else {
            $segments = $defId -split '_'
            $segments[-1]
        }

        $instance = $setting.settingInstance
        $value = switch -Wildcard ($instance.'@odata.type') {
            '*ChoiceSettingInstance' {
                $raw = $instance.choiceSettingValue.value
                ($raw -split '_')[-1]
            }
            '*SimpleSettingInstance' {
                "$($instance.simpleSettingValue.value)"
            }
            '*SimpleSettingCollectionInstance' {
                "$(@($instance.simpleSettingCollectionValue).Count) values"
            }
            '*GroupSettingCollectionInstance' {
                "$(@($instance.groupSettingCollectionValue).Count) groups"
            }
            default { 'Complex' }
        }

        $rows += , @($settingName, ($value ?? 'N/A'))
    }

    Show-InTUITable -Title "Profile Settings" -Columns @('Setting', 'Value') -Rows $rows
    Read-InTUIKey
}

# endregion

# region Legacy (deviceConfigurations)

function Show-InTUILegacyProfileDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a legacy device configuration profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[cyan]Loading profile details...[/]" -ScriptBlock {
            $prof = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ProfileId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ProfileId/assignments" -Beta
            $statuses = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ProfileId/deviceStatuses?`$top=200" -Beta

            @{
                Profile     = $prof
                Assignments = $assign
                Statuses    = $statuses
            }
        }

        $profile = $detailData.Profile
        $assignments = $detailData.Assignments
        $statuses = $detailData.Statuses

        if ($null -eq $profile) {
            Show-InTUIError "Failed to load profile details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Configuration Profiles', $profile.displayName)

        $typeInfo = Get-InTUIConfigProfileType -ODataType $profile.'@odata.type'

        $propsContent = @"
[bold white]$($profile.displayName)[/]

[grey]Source:[/]            [grey]Device Configuration[/]
[grey]Type:[/]              $($typeInfo.FriendlyName)
[grey]Platform:[/]          $($typeInfo.Platform)
[grey]Description:[/]       $(if ($profile.description) { $profile.description.Substring(0, [Math]::Min(200, $profile.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $profile.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $profile.lastModifiedDateTime)
[grey]Version:[/]           $($profile.version ?? 'N/A')
"@

        Show-InTUIPanel -Title "[cyan]Profile Properties[/]" -Content $propsContent -BorderColor Cyan1

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

        Show-InTUIPanel -Title "[cyan]Assignments[/]" -Content $assignContent -BorderColor Cyan1

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

        Show-InTUIPanel -Title "[cyan]Device Status Summary[/]" -Content $statusContent -BorderColor Cyan1

        $actionChoices = @(
            'View Device Statuses',
            '─────────────',
            'Back to Profiles'
        )

        $action = Show-InTUIMenu -Title "[cyan]Profile Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Config profile detail action" -Context @{ ProfileId = $ProfileId; ProfileName = $profile.displayName; Action = $action }

        switch ($action) {
            'View Device Statuses' {
                Show-InTUILegacyProfileDeviceStatuses -ProfileId $ProfileId -ProfileName $profile.displayName
            }
            'Back to Profiles' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUILegacyProfileDeviceStatuses {
    <#
    .SYNOPSIS
        Displays device status table for a legacy device configuration profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId,

        [Parameter()]
        [string]$ProfileName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Configuration Profiles', $ProfileName, 'Device Statuses')

    $statuses = Show-InTUILoading -Title "[cyan]Loading device statuses...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ProfileId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No device status data available for this profile."
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

# endregion
