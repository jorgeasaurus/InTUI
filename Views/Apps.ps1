function Show-InTUIAppsView {
    <#
    .SYNOPSIS
        Displays the Apps management view mimicking the Intune Apps blade.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Apps')

        $appChoices = @(
            'All Apps',
            'Windows Apps',
            'iOS/iPadOS Apps',
            'macOS Apps',
            'Android Apps',
            'Web Apps',
            'Microsoft 365 Apps',
            'App Install Status Monitor',
            'Bulk Assign Apps',
            'Search Apps',
            '-------------',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[green]Apps[/]" -Choices $appChoices

        Write-InTUILog -Message "Apps view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'All Apps' {
                Show-InTUIAppList
            }
            'Windows Apps' {
                Show-InTUIAppList -PlatformFilter 'windows'
            }
            'iOS/iPadOS Apps' {
                Show-InTUIAppList -PlatformFilter 'ios'
            }
            'macOS Apps' {
                Show-InTUIAppList -PlatformFilter 'macos'
            }
            'Android Apps' {
                Show-InTUIAppList -PlatformFilter 'android'
            }
            'Web Apps' {
                Show-InTUIAppList -TypeFilter 'webApp'
            }
            'Microsoft 365 Apps' {
                Show-InTUIAppList -TypeFilter 'officeSuite'
            }
            'App Install Status Monitor' {
                Show-InTUIAppInstallStatusMonitor
            }
            'Bulk Assign Apps' {
                Invoke-InTUIBulkAppAssignment
            }
            'Search Apps' {
                $searchTerm = Read-InTUITextInput -Message "[green]Search apps by name[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching apps" -Context @{ SearchTerm = $searchTerm }
                    Show-InTUIAppList -SearchTerm $searchTerm
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

function Show-InTUIAppList {
    <#
    .SYNOPSIS
        Displays a list of managed apps with filtering.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PlatformFilter,

        [Parameter()]
        [string]$TypeFilter,

        [Parameter()]
        [string]$SearchTerm
    )

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader

        $breadcrumb = @('Home', 'Apps')
        if ($PlatformFilter) { $breadcrumb += "$PlatformFilter Apps" }
        elseif ($TypeFilter) { $breadcrumb += "$TypeFilter" }
        elseif ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        else { $breadcrumb += 'All Apps' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        $filter = @()
        if ($SearchTerm) {
            $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
            $filter += "contains(displayName,'$safe')"
        }
        elseif ($PlatformFilter) {
            switch ($PlatformFilter) {
                'windows' {
                    $filter += "(isof('microsoft.graph.win32LobApp') or isof('microsoft.graph.windowsMobileMSI') or isof('microsoft.graph.windowsUniversalAppX') or isof('microsoft.graph.windowsMicrosoftEdgeApp') or isof('microsoft.graph.windowsStoreApp'))"
                }
                'ios' {
                    $filter += "(isof('microsoft.graph.iosVppApp') or isof('microsoft.graph.iosStoreApp') or isof('microsoft.graph.iosLobApp') or isof('microsoft.graph.managedIOSStoreApp'))"
                }
                'macos' {
                    $filter += "(isof('microsoft.graph.macOSLobApp') or isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSMicrosoftEdgeApp'))"
                }
                'android' {
                    $filter += "(isof('microsoft.graph.androidStoreApp') or isof('microsoft.graph.androidLobApp') or isof('microsoft.graph.managedAndroidStoreApp') or isof('microsoft.graph.androidManagedStoreApp'))"
                }
            }
        }
        elseif ($TypeFilter -eq 'webApp') {
            $filter += "isof('microsoft.graph.webApp')"
        }
        elseif ($TypeFilter -eq 'officeSuite') {
            $filter += "isof('microsoft.graph.officeSuiteApp')"
        }

        $params = @{
            Uri      = '/deviceAppManagement/mobileApps'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,publisher,createdDateTime,lastModifiedDateTime'
        }

        if ($filter.Count -gt 0) {
            $params['Filter'] = $filter -join ' and '
        }

        $apps = Show-InTUILoading -Title "[green]Loading apps...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $apps -or $apps.Results.Count -eq 0) {
            Show-InTUIWarning "No apps found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $appChoices = @()
        foreach ($app in $apps.Results) {
            $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
            $modified = Format-InTUIDate -DateString $app.lastModifiedDateTime
            $publisher = if ($app.publisher) { $app.publisher } else { 'Unknown' }

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $app.displayName)[/] [grey]| $appType | $publisher | $modified[/]"
            $appChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $appChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $apps.TotalCount -Showing $apps.Results.Count

        $selection = Show-InTUIMenu -Title "[green]Select an app[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $apps.Results.Count) {
                Show-InTUIAppDetail -AppId $apps.Results[$idx].id
            }
        }
    }
}

function Get-InTUIAppTypeFriendlyName {
    <#
    .SYNOPSIS
        Converts OData type to friendly app type name.
    #>
    param([string]$ODataType)

    switch -Wildcard ($ODataType) {
        '*win32LobApp'            { return 'Win32' }
        '*windowsMobileMSI'       { return 'MSI' }
        '*windowsUniversalAppX'   { return 'APPX/MSIX' }
        '*windowsMicrosoftEdgeApp' { return 'Edge' }
        '*windowsStoreApp'        { return 'Store (Win)' }
        '*officeSuiteApp'         { return 'M365 Apps' }
        '*iosVppApp'              { return 'iOS VPP' }
        '*managedIOSStoreApp'     { return 'iOS Managed' }
        '*iosStoreApp'            { return 'iOS Store' }
        '*iosLobApp'              { return 'iOS LOB' }
        '*macOSLobApp'            { return 'macOS LOB' }
        '*macOSDmgApp'            { return 'macOS DMG' }
        '*macOSMicrosoftEdgeApp'  { return 'macOS Edge' }
        '*managedAndroidStoreApp' { return 'Android Managed' }
        '*androidManagedStoreApp' { return 'Managed Google Play' }
        '*androidStoreApp'        { return 'Android Store' }
        '*androidLobApp'          { return 'Android LOB' }
        '*webApp'                 { return 'Web App' }
        '*microsoftStoreForBusinessApp' { return 'Store for Business' }
        default                   { return ($ODataType -replace '#microsoft\.graph\.', '') }
    }
}

function Show-InTUIAppDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $app = Show-InTUILoading -Title "[green]Loading app details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId" -Beta
        }

        if ($null -eq $app) {
            Show-InTUIError "Failed to load app details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Apps', $app.displayName)

        Add-InTUIHistoryEntry -ViewType 'App' -ViewId $AppId -DisplayName $app.displayName

        $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $app.displayName)[/]

[grey]Type:[/]              $appType
[grey]Publisher:[/]         $($app.publisher ?? 'N/A')
[grey]Description:[/]       $(if ($app.description) { $app.description.Substring(0, [Math]::Min(200, $app.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $app.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $app.lastModifiedDateTime)
[grey]Is Featured:[/]       $($app.isFeatured ?? $false)
[grey]Privacy URL:[/]       $($app.privacyInformationUrl ?? 'N/A')
[grey]Info URL:[/]          $($app.informationUrl ?? 'N/A')
[grey]Owner:[/]             $($app.owner ?? 'N/A')
[grey]Developer:[/]         $($app.developer ?? 'N/A')
[grey]Notes:[/]             $($app.notes ?? 'N/A')
"@

        Show-InTUIPanel -Title "[green]App Properties[/]" -Content $propsContent -BorderColor Green

        if ($app.'@odata.type' -match 'win32LobApp') {
            $win32Content = @"
[grey]File Name:[/]         $($app.fileName ?? 'N/A')
[grey]Install Command:[/]   $($app.installCommandLine ?? 'N/A')
[grey]Uninstall Command:[/] $($app.uninstallCommandLine ?? 'N/A')
[grey]Setup File Path:[/]   $($app.setupFilePath ?? 'N/A')
[grey]Min OS Version:[/]    $($app.minimumSupportedOperatingSystem ?? 'N/A')
"@
            Show-InTUIPanel -Title "[cyan]Win32 App Details[/]" -Content $win32Content -BorderColor Cyan1
        }

        $actionChoices = @(
            'View Assignments',
            'Create Assignment',
            'View Device Install Status',
            'View User Install Status',
            '─────────────',
            'Back to Apps'
        )

        $action = Show-InTUIMenu -Title "[green]App Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "App detail action" -Context @{ AppId = $AppId; AppName = $app.displayName; Action = $action }

        switch ($action) {
            'View Assignments' {
                Show-InTUIAppAssignments -AppId $AppId -AppName $app.displayName
            }
            'Create Assignment' {
                New-InTUIAppAssignment -AppId $AppId -AppName $app.displayName
            }
            'View Device Install Status' {
                Show-InTUIAppDeviceStatus -AppId $AppId -AppName $app.displayName
            }
            'View User Install Status' {
                Show-InTUIAppUserStatus -AppId $AppId -AppName $app.displayName
            }
            'Back to Apps' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Select-InTUIGroup {
    <#
    .SYNOPSIS
        Displays a group picker and returns the selected group.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Title = "Select a group"
    )

    $groups = Show-InTUILoading -Title "[green]Loading groups...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/groups' -PageSize 50 -Select 'id,displayName,description'
    }

    if ($null -eq $groups -or $groups.Results.Count -eq 0) {
        Show-InTUIWarning "No groups found."
        return $null
    }

    $groupChoices = @()
    foreach ($group in $groups.Results) {
        $desc = if ($group.description) { $group.description.Substring(0, [Math]::Min(50, $group.description.Length)) } else { 'No description' }
        $groupChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $group.displayName)[/] [grey]| $desc[/]"
    }

    $choiceMap = Get-InTUIChoiceMap -Choices $groupChoices
    $menuChoices = @($choiceMap.Choices + '─────────────' + 'Cancel')

    $selection = Show-InTUIMenu -Title "[green]$Title[/]" -Choices $menuChoices

    if ($selection -eq 'Cancel' -or $selection -eq '─────────────') {
        return $null
    }

    $idx = $choiceMap.IndexMap[$selection]
    if ($null -ne $idx -and $idx -lt $groups.Results.Count) {
        return $groups.Results[$idx]
    }

    return $null
}

function New-InTUIAppAssignment {
    <#
    .SYNOPSIS
        Creates a new app assignment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter()]
        [string]$AppName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', $AppName, 'Create Assignment')

    # Select intent
    $intentChoices = @(
        'Required (auto-install)',
        'Available (user choice)',
        'Uninstall',
        '─────────────',
        'Cancel'
    )

    $intentSelection = Show-InTUIMenu -Title "[green]Select Assignment Intent[/]" -Choices $intentChoices

    if ($intentSelection -eq 'Cancel' -or $intentSelection -eq '─────────────') {
        return
    }

    $intent = switch ($intentSelection) {
        'Required (auto-install)' { 'required' }
        'Available (user choice)' { 'available' }
        'Uninstall'               { 'uninstall' }
    }

    # Select target type
    $targetChoices = @(
        'All Users',
        'All Devices',
        'Select Group',
        '─────────────',
        'Cancel'
    )

    $targetSelection = Show-InTUIMenu -Title "[green]Select Target[/]" -Choices $targetChoices

    if ($targetSelection -eq 'Cancel' -or $targetSelection -eq '─────────────') {
        return
    }

    $group = $null
    $target = $null
    $targetDisplay = $null

    switch ($targetSelection) {
        'All Users' {
            $target = @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
            $targetDisplay = 'All Users'
        }
        'All Devices' {
            $target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
            $targetDisplay = 'All Devices'
        }
        'Select Group' {
            $group = Select-InTUIGroup -Title "Select target group"
            if (-not $group) { return }
            $target = @{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                groupId = $group.id
            }
            $targetDisplay = "Group: $(ConvertTo-InTUISafeMarkup -Text $group.displayName)"
        }
    }

    $confirm = Show-InTUIConfirm -Message "[yellow]Create $intent assignment for $AppName to $targetDisplay?[/]"

    if (-not $confirm) {
        return
    }

    # Create assignment
    $body = @{
        mobileAppAssignments = @(
            @{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                intent = $intent
                target = $target
                settings = $null
            }
        )
    }

    Write-InTUILog -Message "Creating app assignment" -Context @{
        AppId = $AppId
        AppName = $AppName
        Intent = $intent
        Target = $targetDisplay
    }

    $result = Show-InTUILoading -Title "[green]Creating assignment...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/assign" -Method POST -Body $body -Beta
    }

    if ($null -ne $result) {
        Show-InTUISuccess "Assignment created successfully."
    }
    else {
        Show-InTUIError "Failed to create assignment."
    }

    Read-InTUIKey
}

function Show-InTUIAppAssignments {
    <#
    .SYNOPSIS
        Displays app assignments.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter()]
        [string]$AppName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', $AppName, 'Assignments')

    $assignments = Show-InTUILoading -Title "[green]Loading assignments...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/assignments" -Beta
    }

    if (-not $assignments.value) {
        Show-InTUIWarning "No assignments found for this app."
        Read-InTUIKey
        return
    }

    $rows = @()
    $groupAssignments = @()
    foreach ($assignment in $assignments.value) {
        $intent = switch ($assignment.intent) {
            'required'         { '[green]Required[/]' }
            'available'        { '[blue]Available[/]' }
            'uninstall'        { '[red]Uninstall[/]' }
            'availableWithoutEnrollment' { '[yellow]Available (No Enrollment)[/]' }
            default            { $assignment.intent }
        }

        $targetType = switch ($assignment.target.'@odata.type') {
            '#microsoft.graph.allLicensedUsersAssignmentTarget' { 'All Users' }
            '#microsoft.graph.allDevicesAssignmentTarget'       { 'All Devices' }
            '#microsoft.graph.groupAssignmentTarget'            { "Group: $($assignment.target.groupId)" }
            '#microsoft.graph.exclusionGroupAssignmentTarget'   { "[red]Exclude:[/] $($assignment.target.groupId)" }
            default { $assignment.target.'@odata.type' -replace '#microsoft\.graph\.', '' }
        }

        $rows += , @($intent, $targetType)

        # Track group assignments for cross-reference
        if ($assignment.target.groupId) {
            $groupAssignments += $assignment.target.groupId
        }
    }

    Render-InTUITable -Title "App Assignments" -Columns @('Intent', 'Target') -Rows $rows

    if ($groupAssignments.Count -gt 0) {
        $groupChoices = @()
        foreach ($gId in ($groupAssignments | Sort-Object -Unique)) {
            $groupChoices += $gId
        }
        $groupChoices += 'Back'

        $selection = Show-InTUIMenu -Title "[green]View group detail[/]" -Choices $groupChoices
        if ($selection -ne 'Back') {
            Show-InTUIGroupDetail -GroupId $selection
        }
    }
    else {
        Read-InTUIKey
    }
}

function Show-InTUIAppDeviceStatus {
    <#
    .SYNOPSIS
        Shows app device install statuses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter()]
        [string]$AppName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', $AppName, 'Device Install Status')

    $statuses = Show-InTUILoading -Title "[green]Loading device install status...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No device install status data available."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($status in $statuses.value) {
        $installColor = Get-InTUIInstallStateColor -State $status.installState

        $rows += , @(
            ($status.deviceName ?? 'N/A'),
            "[$installColor]$($status.installState)[/]",
            ($status.userPrincipalName ?? 'N/A'),
            ($status.osVersion ?? 'N/A'),
            (Format-InTUIDate -DateString $status.lastSyncDateTime)
        )
    }

    Show-InTUITable -Title "Device Install Status" -Columns @('Device', 'Status', 'User', 'OS Version', 'Last Sync') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIAppUserStatus {
    <#
    .SYNOPSIS
        Shows app user install statuses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter()]
        [string]$AppName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', $AppName, 'User Install Status')

    $statuses = Show-InTUILoading -Title "[green]Loading user install status...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/userStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No user install status data available."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($status in $statuses.value) {
        $rows += , @(
            ($status.userPrincipalName ?? $status.userName ?? 'N/A'),
            ($status.installedDeviceCount ?? 0),
            ($status.failedDeviceCount ?? 0),
            ($status.notInstalledDeviceCount ?? 0)
        )
    }

    Show-InTUITable -Title "User Install Status" -Columns @('User', 'Installed', 'Failed', 'Not Installed') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIAppInstallStatusMonitor {
    <#
    .SYNOPSIS
        Shows overview of app install status across all apps.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'Install Status Monitor')

    $apps = Show-InTUILoading -Title "[green]Loading app status overview...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceAppManagement/mobileApps' -Beta -PageSize 25 -Select 'id,displayName'
    }

    if ($null -eq $apps -or $apps.Results.Count -eq 0) {
        Show-InTUIWarning "No apps found."
        Read-InTUIKey
        return
    }

    Write-InTUIText "[bold]App Install Status Summary[/]"
    Write-InTUIText "[grey]Select an app to view detailed install status[/]"
    Write-Host ""

    $choices = @()
    foreach ($app in $apps.Results) {
        $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
        $choices += "$(ConvertTo-InTUISafeMarkup -Text $app.displayName) [grey]($appType)[/]"
    }
    $choiceMap = Get-InTUIChoiceMap -Choices $choices
    $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

    $selection = Show-InTUIMenu -Title "[green]Select app for status[/]" -Choices $menuChoices

    if ($selection -eq 'Back' -or $selection -eq '─────────────') {
        return
    }

    $idx = $choiceMap.IndexMap[$selection]
    if ($null -ne $idx -and $idx -lt $apps.Results.Count) {
        Show-InTUIAppDeviceStatus -AppId $apps.Results[$idx].id -AppName $apps.Results[$idx].displayName
    }
}

function Invoke-InTUIBulkAppAssignment {
    <#
    .SYNOPSIS
        Assigns multiple apps to a group in bulk.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'Bulk Assign Apps')

    # Load apps
    $apps = Show-InTUILoading -Title "[green]Loading apps...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceAppManagement/mobileApps' -Beta -PageSize 50 -Select 'id,displayName'
    }

    if ($null -eq $apps -or $apps.Results.Count -eq 0) {
        Show-InTUIWarning "No apps found."
        Read-InTUIKey
        return
    }

    Write-InTUIText "[bold]Bulk App Assignment[/]"
    Write-InTUIText "[grey]Select multiple apps to assign to a group[/]"
    Write-Host ""

    # Multi-select apps
    $appChoices = @()
    foreach ($app in $apps.Results) {
        $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
        $appChoices += "$(ConvertTo-InTUISafeMarkup -Text $app.displayName) [grey]($appType)[/]"
    }

    $selectedApps = Show-InTUIMultiSelect -Title "[green]Select apps (Space to select, Enter to confirm)[/]" -Choices $appChoices -PageSize 15

    if (-not $selectedApps -or $selectedApps.Count -eq 0) {
        Show-InTUIWarning "No apps selected."
        Read-InTUIKey
        return
    }

    # Map selections back to app objects
    $selectedAppObjects = @()
    foreach ($selection in $selectedApps) {
        for ($i = 0; $i -lt $appChoices.Count; $i++) {
            if ($appChoices[$i] -eq $selection) {
                $selectedAppObjects += $apps.Results[$i]
                break
            }
        }
    }

    Write-Host ""
    Write-InTUIText "[white]Selected $($selectedAppObjects.Count) app(s)[/]"

    # Select intent
    $intentChoices = @(
        'Required (auto-install)',
        'Available (user choice)',
        'Uninstall',
        '─────────────',
        'Cancel'
    )

    $intentSelection = Show-InTUIMenu -Title "[green]Select Assignment Intent[/]" -Choices $intentChoices

    if ($intentSelection -eq 'Cancel' -or $intentSelection -eq '─────────────') {
        return
    }

    $intent = switch ($intentSelection) {
        'Required (auto-install)' { 'required' }
        'Available (user choice)' { 'available' }
        'Uninstall'               { 'uninstall' }
    }

    # Select target
    $targetChoices = @(
        'All Users',
        'All Devices',
        'Select Group',
        '─────────────',
        'Cancel'
    )

    $targetSelection = Show-InTUIMenu -Title "[green]Select Target[/]" -Choices $targetChoices

    if ($targetSelection -eq 'Cancel' -or $targetSelection -eq '─────────────') {
        return
    }

    $group = $null
    $target = $null
    $targetDisplay = $null

    switch ($targetSelection) {
        'All Users' {
            $target = @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
            $targetDisplay = 'All Users'
        }
        'All Devices' {
            $target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
            $targetDisplay = 'All Devices'
        }
        'Select Group' {
            $group = Select-InTUIGroup -Title "Select target group"
            if (-not $group) { return }
            $target = @{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                groupId = $group.id
            }
            $targetDisplay = "Group: $(ConvertTo-InTUISafeMarkup -Text $group.displayName)"
        }
    }

    # Confirm
    $appNames = ($selectedAppObjects | ForEach-Object { $_.displayName }) -join ", "
    if ($appNames.Length -gt 100) {
        $appNames = $appNames.Substring(0, 100) + "..."
    }

    $confirm = Show-InTUIConfirm -Message "[yellow]Create $intent assignments for $($selectedAppObjects.Count) apps to $targetDisplay?[/]"

    if (-not $confirm) {
        return
    }

    # Execute bulk assignment
    Write-InTUILog -Message "Starting bulk app assignment" -Context @{
        AppCount = $selectedAppObjects.Count
        Intent = $intent
        Target = $targetDisplay
    }

    $successCount = 0
    $failCount = 0

    $body = @{
        mobileAppAssignments = @(
            @{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                intent = $intent
                target = $target
                settings = $null
            }
        )
    }

    foreach ($app in $selectedAppObjects) {
        $result = Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$($app.id)/assign" -Method POST -Body $body -Beta

        if ($null -ne $result) {
            $successCount++
        }
        else {
            $failCount++
            Write-InTUILog -Level 'WARN' -Message "Failed to assign app" -Context @{ AppName = $app.displayName }
        }
    }

    Write-InTUILog -Message "Bulk assignment completed" -Context @{
        Success = $successCount
        Failed = $failCount
    }

    if ($failCount -eq 0) {
        Show-InTUISuccess "Successfully assigned $successCount app(s) to $targetDisplay."
    }
    else {
        Show-InTUIWarning "Assigned $successCount app(s), $failCount failed."
    }

    Read-InTUIKey
}
