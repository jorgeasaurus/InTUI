function Show-InTUIUsersView {
    <#
    .SYNOPSIS
        Displays the Users management view mimicking the Intune Users blade.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Users')

        $userChoices = @(
            'All Users',
            'Licensed Users',
            'Search Users',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[yellow]Users[/]" -Choices $userChoices

        Write-InTUILog -Message "Users view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'All Users' {
                Show-InTUIUserList
            }
            'Licensed Users' {
                Show-InTUIUserList -LicensedOnly
            }
            'Search Users' {
                $searchTerm = Read-SpectreText -Message "[yellow]Search users by name or email[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching users" -Context @{ SearchTerm = $searchTerm }
                    Show-InTUIUserList -SearchTerm $searchTerm
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

function Show-InTUIUserList {
    <#
    .SYNOPSIS
        Displays a paginated list of users.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SearchTerm,

        [Parameter()]
        [switch]$LicensedOnly
    )

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader

        $breadcrumb = @('Home', 'Users')
        if ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        elseif ($LicensedOnly) { $breadcrumb += 'Licensed Users' }
        else { $breadcrumb += 'All Users' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        $params = @{
            Uri      = '/users'
            PageSize = 25
            Select   = 'id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled,createdDateTime,assignedLicenses'
            OrderBy  = 'displayName'
        }

        $filters = @()
        if ($SearchTerm) {
            $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
            $filters += "(startswith(displayName,'$safe') or startswith(userPrincipalName,'$safe') or startswith(mail,'$safe'))"
        }
        if ($LicensedOnly) {
            $filters += 'assignedLicenses/$count ne 0'
            $params['Headers'] = @{ ConsistencyLevel = 'eventual' }
            $params['IncludeCount'] = $true
        }
        if ($filters.Count -gt 0) {
            $params['Filter'] = $filters -join ' and '
        }

        $users = Show-InTUILoading -Title "[yellow]Loading users...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $users -or $users.Results.Count -eq 0) {
            Show-InTUIWarning "No users found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $filteredUsers = $users.Results

        $userChoices = @()
        foreach ($user in $filteredUsers) {
            $enabled = if ($user.accountEnabled) { '[green]●[/]' } else { '[red]●[/]' }
            $dept = if ($user.department) { $user.department } else { 'N/A' }
            $licenses = @($user.assignedLicenses).Count

            $displayName = "$enabled [white]$(ConvertTo-InTUISafeMarkup -Text $user.displayName)[/] [grey]| $($user.userPrincipalName) | $dept | $licenses license(s)[/]"
            $userChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $userChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($users.Count ?? $filteredUsers.Count) -Showing $filteredUsers.Count -FilterText $SearchTerm

        $selection = Show-InTUIMenu -Title "[yellow]Select a user[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $filteredUsers.Count) {
                Show-InTUIUserDetail -UserId $filteredUsers[$idx].id
            }
        }
    }
}

function Show-InTUIUserDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $user = Show-InTUILoading -Title "[yellow]Loading user details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/users/$UserId`?`$select=id,displayName,userPrincipalName,mail,givenName,surname,jobTitle,department,officeLocation,mobilePhone,businessPhones,city,state,country,postalCode,accountEnabled,createdDateTime,lastSignInDateTime,assignedLicenses,assignedPlans"
        }

        if ($null -eq $user) {
            Show-InTUIError "Failed to load user details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Users', $user.displayName)

        $enabled = if ($user.accountEnabled) { '[green]Enabled[/]' } else { '[red]Disabled[/]' }

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $user.displayName)[/] $enabled

[grey]UPN:[/]               $($user.userPrincipalName)
[grey]Email:[/]             $($user.mail ?? 'N/A')
[grey]First Name:[/]        $($user.givenName ?? 'N/A')
[grey]Last Name:[/]         $($user.surname ?? 'N/A')
[grey]Job Title:[/]         $($user.jobTitle ?? 'N/A')
[grey]Department:[/]        $($user.department ?? 'N/A')
[grey]Office:[/]            $($user.officeLocation ?? 'N/A')
[grey]Mobile Phone:[/]      $($user.mobilePhone ?? 'N/A')
[grey]Business Phone:[/]    $(if ($user.businessPhones) { $user.businessPhones -join ', ' } else { 'N/A' })
[grey]City:[/]              $($user.city ?? 'N/A')
[grey]State:[/]             $($user.state ?? 'N/A')
[grey]Country:[/]           $($user.country ?? 'N/A')
[grey]Created:[/]           $(Format-InTUIDate -DateString $user.createdDateTime)
[grey]Licenses:[/]          $(@($user.assignedLicenses).Count) assigned
"@

        Show-InTUIPanel -Title "[yellow]User Properties[/]" -Content $propsContent -BorderColor Yellow

        $actionChoices = @(
            'View Managed Devices',
            'View App Installations',
            'View Group Memberships',
            'View Licenses',
            '─────────────',
            'Back to Users'
        )

        $action = Show-InTUIMenu -Title "[yellow]User Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "User detail action" -Context @{ UserId = $UserId; UserName = $user.displayName; Action = $action }

        switch ($action) {
            'View Managed Devices' {
                Show-InTUIUserDevices -UserId $UserId -UserName $user.displayName
            }
            'View App Installations' {
                Show-InTUIUserApps -UserId $UserId -UserName $user.displayName
            }
            'View Group Memberships' {
                Show-InTUIUserGroups -UserId $UserId -UserName $user.displayName
            }
            'View Licenses' {
                Show-InTUIUserLicenses -UserId $UserId -UserName $user.displayName -Licenses $user.assignedLicenses
            }
            'Back to Users' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIUserDevices {
    <#
    .SYNOPSIS
        Shows devices registered/managed for a user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [string]$UserName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Users', $UserName, 'Managed Devices')

    $devices = Show-InTUILoading -Title "[yellow]Loading user devices...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/users/$UserId/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,complianceState,lastSyncDateTime,model,manufacturer" -Beta
    }

    if (-not $devices.value) {
        Show-InTUIWarning "No managed devices found for this user."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($device in $devices.value) {
        $compColor = Get-InTUIComplianceColor -State $device.complianceState
        $icon = Get-InTUIDeviceIcon -OperatingSystem $device.operatingSystem

        $rows += , @(
            "$icon $($device.deviceName)",
            "$($device.operatingSystem) $($device.osVersion)",
            "[$compColor]$($device.complianceState)[/]",
            "$($device.manufacturer) $($device.model)",
            (Format-InTUIDate -DateString $device.lastSyncDateTime)
        )
    }

    Show-InTUITable -Title "Managed Devices for $UserName" -Columns @('Device', 'OS', 'Compliance', 'Model', 'Last Sync') -Rows $rows

    $deviceChoices = ($devices.value | ForEach-Object { $_.deviceName })
    $deviceChoices += 'Back'

    $selection = Show-InTUIMenu -Title "[yellow]View device details[/]" -Choices $deviceChoices

    if ($selection -ne 'Back') {
        $selectedDevice = $devices.value | Where-Object { $_.deviceName -eq $selection }
        if ($selectedDevice) {
            Show-InTUIDeviceDetail -DeviceId $selectedDevice.id
        }
    }
}

function Show-InTUIUserApps {
    <#
    .SYNOPSIS
        Shows app installations for a user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [string]$UserName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Users', $UserName, 'App Installations')

    $apps = Show-InTUILoading -Title "[yellow]Loading user app installations...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/users/$UserId/mobileAppIntentAndStates" -Beta
    }

    if (-not $apps.value) {
        Show-InTUIWarning "No app installation data available for this user."
        Read-InTUIKey
        return
    }

    foreach ($appState in $apps.value) {
        if ($appState.mobileAppList) {
            $rows = @()
            foreach ($app in $appState.mobileAppList) {
                $installColor = Get-InTUIInstallStateColor -State $app.installState

                $rows += , @(
                    $app.displayName,
                    "[$installColor]$($app.installState)[/]",
                    ($app.displayVersion ?? 'N/A'),
                    ($app.mobileAppIntent ?? 'N/A')
                )
            }

            Show-InTUITable -Title "App Installations" -Columns @('App Name', 'Install State', 'Version', 'Intent') -Rows $rows
        }
    }

    Read-InTUIKey
}

function Show-InTUIUserGroups {
    <#
    .SYNOPSIS
        Shows group memberships for a user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [string]$UserName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Users', $UserName, 'Group Memberships')

    $groups = Show-InTUILoading -Title "[yellow]Loading group memberships...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/users/$UserId/memberOf?`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,membershipRule" -All
    }

    if (-not $groups -or @($groups).Count -eq 0) {
        Show-InTUIWarning "No group memberships found for this user."
        Read-InTUIKey
        return
    }

    # Filter to only groups (not roles, etc.)
    $groupsOnly = $groups | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }

    if ($groupsOnly.Count -eq 0) {
        Show-InTUIWarning "No group memberships found."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($group in $groupsOnly) {
        $groupType = Get-InTUIGroupType -Group $group
        $rows += , @(
            $group.displayName,
            $groupType,
            ($group.description ?? 'N/A')
        )
    }

    Show-InTUITable -Title "Group Memberships for $UserName" -Columns @('Group Name', 'Type', 'Description') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIUserLicenses {
    <#
    .SYNOPSIS
        Shows license assignments for a user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [string]$UserName,

        [Parameter()]
        [array]$Licenses
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Users', $UserName, 'Licenses')

    $licenseDetails = Show-InTUILoading -Title "[yellow]Loading license details...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/users/$UserId/licenseDetails"
    }

    if (-not $licenseDetails.value) {
        Show-InTUIWarning "No licenses assigned to this user."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($license in $licenseDetails.value) {
        $enabledPlans = @($license.servicePlans | Where-Object { $_.provisioningStatus -eq 'Success' }).Count
        $totalPlans = @($license.servicePlans).Count

        $rows += , @(
            $license.skuPartNumber,
            $license.skuId,
            "$enabledPlans / $totalPlans plans enabled"
        )
    }

    Show-InTUITable -Title "Licenses for $UserName" -Columns @('License', 'SKU ID', 'Service Plans') -Rows $rows
    Read-InTUIKey
}
