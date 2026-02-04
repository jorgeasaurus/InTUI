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
            'Search Apps',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[green]Apps[/]" -Choices $appChoices

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
            'Search Apps' {
                $searchTerm = Read-SpectreText -Prompt "[green]Search apps by name[/]"
                if ($searchTerm) {
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

        # Build filter
        $filter = @()
        if ($PlatformFilter) {
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
        if ($TypeFilter -eq 'webApp') {
            $filter += "isof('microsoft.graph.webApp')"
        }
        if ($TypeFilter -eq 'officeSuite') {
            $filter += "isof('microsoft.graph.officeSuiteApp')"
        }

        $uri = '/deviceAppManagement/mobileApps'
        $selectFields = 'id,displayName,description,publisher,createdDateTime,lastModifiedDateTime,@odata.type'

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
            $params['Filter'] = "contains(displayName,'$SearchTerm')"
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

        # Build display choices
        $appChoices = @()
        foreach ($app in $apps.Results) {
            $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
            $modified = Format-InTUIDate -DateString $app.lastModifiedDateTime
            $publisher = if ($app.publisher) { $app.publisher } else { 'Unknown' }

            $displayName = "[white]$($app.displayName)[/] [grey]| $appType | $publisher | $modified[/]"
            $appChoices += $displayName
        }

        $appChoices += '─────────────'
        $appChoices += 'Back'

        Show-InTUIStatusBar -Total ($apps.Count ?? $apps.Results.Count) -Showing $apps.Results.Count

        $selection = Show-InTUIMenu -Title "[green]Select an app[/]" -Choices $appChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $appChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $apps.Results.Count) {
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
        '*iosStoreApp'            { return 'iOS Store' }
        '*iosLobApp'              { return 'iOS LOB' }
        '*managedIOSStoreApp'     { return 'iOS Managed' }
        '*macOSLobApp'            { return 'macOS LOB' }
        '*macOSDmgApp'            { return 'macOS DMG' }
        '*macOSMicrosoftEdgeApp'  { return 'macOS Edge' }
        '*androidStoreApp'        { return 'Android Store' }
        '*androidLobApp'          { return 'Android LOB' }
        '*managedAndroidStoreApp' { return 'Android Managed' }
        '*androidManagedStoreApp' { return 'Managed Google Play' }
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

        $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'

        # App Properties
        $propsContent = @"
[bold white]$($app.displayName)[/]

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

        # Show type-specific info for Win32 apps
        if ($app.'@odata.type' -match 'win32LobApp') {
            $win32Content = @"
[grey]File Name:[/]         $($app.fileName ?? 'N/A')
[grey]Install Command:[/]   $($app.installCommandLine ?? 'N/A')
[grey]Uninstall Command:[/] $($app.uninstallCommandLine ?? 'N/A')
[grey]Setup File Path:[/]   $($app.setupFilePath ?? 'N/A')
[grey]Min OS Version:[/]    $($app.minimumSupportedOperatingSystem ?? 'N/A')
"@
            Show-InTUIPanel -Title "[cyan]Win32 App Details[/]" -Content $win32Content -BorderColor Cyan
        }

        # Action menu
        $actionChoices = @(
            'View Assignments',
            'View Device Install Status',
            'View User Install Status',
            '─────────────',
            'Back to Apps'
        )

        $action = Show-InTUIMenu -Title "[green]App Actions[/]" -Choices $actionChoices

        switch ($action) {
            'View Assignments' {
                Show-InTUIAppAssignments -AppId $AppId -AppName $app.displayName
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

    if ($null -eq $assignments -or ($assignments.value | Measure-Object).Count -eq 0) {
        Show-InTUIWarning "No assignments found for this app."
        Read-InTUIKey
        return
    }

    $rows = @()
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
    }

    Show-InTUITable -Title "App Assignments" -Columns @('Intent', 'Target') -Rows $rows
    Read-InTUIKey
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

    if ($null -eq $statuses -or ($statuses.value | Measure-Object).Count -eq 0) {
        Show-InTUIWarning "No device install status data available."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($status in $statuses.value) {
        $installColor = switch ($status.installState) {
            'installed'   { 'green' }
            'failed'      { 'red' }
            'notInstalled' { 'grey' }
            'uninstallFailed' { 'red' }
            default       { 'yellow' }
        }

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

    if ($null -eq $statuses -or ($statuses.value | Measure-Object).Count -eq 0) {
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
        $response = Get-InTUIPagedResults -Uri '/deviceAppManagement/mobileApps' -Beta -PageSize 25 -Select 'id,displayName,@odata.type'
        return $response
    }

    if ($null -eq $apps -or $apps.Results.Count -eq 0) {
        Show-InTUIWarning "No apps found."
        Read-InTUIKey
        return
    }

    Write-SpectreHost "[bold]App Install Status Summary[/]"
    Write-SpectreHost "[grey]Select an app to view detailed install status[/]"
    Write-SpectreHost ""

    $choices = @()
    foreach ($app in $apps.Results) {
        $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
        $choices += "$($app.displayName) [grey]($appType)[/]"
    }
    $choices += '─────────────'
    $choices += 'Back'

    $selection = Show-InTUIMenu -Title "[green]Select app for status[/]" -Choices $choices

    if ($selection -eq 'Back' -or $selection -eq '─────────────') {
        return
    }

    $idx = $choices.IndexOf($selection)
    if ($idx -ge 0 -and $idx -lt $apps.Results.Count) {
        Show-InTUIAppDeviceStatus -AppId $apps.Results[$idx].id -AppName $apps.Results[$idx].displayName
    }
}
