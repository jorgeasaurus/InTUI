function Get-InTUIGroupType {
    <#
    .SYNOPSIS
        Determines the friendly group type name.
    #>
    param($Group)

    if ($Group.groupTypes -contains 'DynamicMembership') {
        if ($Group.securityEnabled) { return '[cyan]Dynamic Security[/]' }
        else { return '[cyan]Dynamic M365[/]' }
    }
    elseif ($Group.securityEnabled -and -not $Group.mailEnabled) {
        return '[blue]Security[/]'
    }
    elseif ($Group.mailEnabled -and $Group.securityEnabled) {
        return '[green]Mail-enabled Security[/]'
    }
    elseif ($Group.groupTypes -contains 'Unified') {
        return '[magenta]Microsoft 365[/]'
    }
    elseif ($Group.mailEnabled) {
        return '[yellow]Distribution[/]'
    }
    else {
        return '[grey]Assigned Security[/]'
    }
}

function Show-InTUIGroupsView {
    <#
    .SYNOPSIS
        Displays the Groups management view mimicking the Intune Groups blade.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Groups')

        $groupChoices = @(
            'All Groups',
            'Security Groups',
            'Microsoft 365 Groups',
            'Dynamic Groups',
            'Search Groups',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[magenta]Groups[/]" -Choices $groupChoices

        Write-InTUILog -Message "Groups view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'All Groups' {
                Show-InTUIGroupList
            }
            'Security Groups' {
                Show-InTUIGroupList -TypeFilter 'Security'
            }
            'Microsoft 365 Groups' {
                Show-InTUIGroupList -TypeFilter 'Microsoft365'
            }
            'Dynamic Groups' {
                Show-InTUIGroupList -TypeFilter 'Dynamic'
            }
            'Search Groups' {
                $searchTerm = Read-SpectreText -Prompt "[magenta]Search groups by name[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching groups" -Context @{ SearchTerm = $searchTerm }
                    Show-InTUIGroupList -SearchTerm $searchTerm
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

function Show-InTUIGroupList {
    <#
    .SYNOPSIS
        Displays a paginated list of groups.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TypeFilter,

        [Parameter()]
        [string]$SearchTerm
    )

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader

        $breadcrumb = @('Home', 'Groups')
        if ($TypeFilter) { $breadcrumb += "$TypeFilter Groups" }
        elseif ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        else { $breadcrumb += 'All Groups' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        $params = @{
            Uri      = '/groups'
            PageSize = 25
            Select   = 'id,displayName,description,groupTypes,mailEnabled,securityEnabled,membershipRule,createdDateTime'
            OrderBy  = 'displayName'
        }

        $filter = @()
        if ($TypeFilter) {
            switch ($TypeFilter) {
                'Security' {
                    $filter += "securityEnabled eq true and mailEnabled eq false"
                }
                'Microsoft365' {
                    $filter += "groupTypes/any(g:g eq 'Unified')"
                }
                'Dynamic' {
                    $filter += "groupTypes/any(g:g eq 'DynamicMembership')"
                }
            }
        }
        if ($SearchTerm) {
            $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
            $filter += "startswith(displayName,'$safe')"
        }

        if ($filter.Count -gt 0) {
            $params['Filter'] = $filter -join ' and '
        }

        $groups = Show-InTUILoading -Title "[magenta]Loading groups...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $groups -or $groups.Results.Count -eq 0) {
            Show-InTUIWarning "No groups found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $groupChoices = @()
        foreach ($group in $groups.Results) {
            $groupType = Get-InTUIGroupType -Group $group
            $desc = if ($group.description) {
                $truncated = $group.description
                if ($truncated.Length -gt 40) { $truncated = $truncated.Substring(0, 40) + '...' }
                $truncated
            }
            else { 'No description' }

            $displayName = "$groupType [white]$($group.displayName)[/] [grey]| $desc[/]"
            $groupChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $groupChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($groups.Count ?? $groups.Results.Count) -Showing $groups.Results.Count -FilterText ($TypeFilter ?? $SearchTerm)

        $selection = Show-InTUIMenu -Title "[magenta]Select a group[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $groups.Results.Count) {
                Show-InTUIGroupDetail -GroupId $groups.Results[$idx].id
            }
        }
    }
}

function Show-InTUIGroupDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $group = Show-InTUILoading -Title "[magenta]Loading group details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/groups/$GroupId`?`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,mailNickname,membershipRule,membershipRuleProcessingState,createdDateTime,renewedDateTime,visibility,isAssignableToRole"
        }

        if ($null -eq $group) {
            Show-InTUIError "Failed to load group details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Groups', $group.displayName)

        $groupType = Get-InTUIGroupType -Group $group
        $isDynamic = $group.groupTypes -contains 'DynamicMembership'

        $propsContent = @"
[bold white]$($group.displayName)[/]

[grey]Type:[/]                      $groupType
[grey]Description:[/]               $($group.description ?? 'N/A')
[grey]Mail Nickname:[/]             $($group.mailNickname ?? 'N/A')
[grey]Mail Enabled:[/]              $($group.mailEnabled)
[grey]Security Enabled:[/]          $($group.securityEnabled)
[grey]Visibility:[/]                $($group.visibility ?? 'N/A')
[grey]Role Assignable:[/]           $($group.isAssignableToRole ?? $false)
[grey]Created:[/]                   $(Format-InTUIDate -DateString $group.createdDateTime)
[grey]Renewed:[/]                   $(Format-InTUIDate -DateString $group.renewedDateTime)
"@

        if ($isDynamic) {
            $propsContent += @"

[grey]Membership Rule:[/]           $($group.membershipRule ?? 'N/A')
[grey]Rule Processing State:[/]     $($group.membershipRuleProcessingState ?? 'N/A')
"@
        }

        Show-InTUIPanel -Title "[magenta]Group Properties[/]" -Content $propsContent -BorderColor Magenta

        $memberCountData = Show-InTUILoading -Title "[magenta]Loading member count...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/groups/$GroupId/members?`$top=1&`$select=id"
        }

        if ($null -ne $memberCountData) {
            $count = $memberCountData.'@odata.count' ?? @($memberCountData.value).Count
            Write-SpectreHost "[grey]Members:[/] [white]$count[/]"
            Write-SpectreHost ""
        }

        $actionChoices = @(
            'View Members',
            'View Owners',
            'View Device Members'
        )

        if ($isDynamic) {
            $actionChoices += 'View Membership Rule'
        }

        $actionChoices += '─────────────'
        $actionChoices += 'Back to Groups'

        $action = Show-InTUIMenu -Title "[magenta]Group Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Group detail action" -Context @{ GroupId = $GroupId; GroupName = $group.displayName; Action = $action }

        switch ($action) {
            'View Members' {
                Show-InTUIGroupMembers -GroupId $GroupId -GroupName $group.displayName
            }
            'View Owners' {
                Show-InTUIGroupOwners -GroupId $GroupId -GroupName $group.displayName
            }
            'View Device Members' {
                Show-InTUIGroupDeviceMembers -GroupId $GroupId -GroupName $group.displayName
            }
            'View Membership Rule' {
                Clear-Host
                Show-InTUIHeader
                Show-InTUIBreadcrumb -Path @('Home', 'Groups', $group.displayName, 'Membership Rule')
                Show-InTUIPanel -Title "Dynamic Membership Rule" -Content "[cyan]$($group.membershipRule ?? 'No rule defined')[/]" -BorderColor Cyan1
                Write-SpectreHost "[grey]Processing State:[/] $($group.membershipRuleProcessingState ?? 'N/A')"
                Read-InTUIKey
            }
            'Back to Groups' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIGroupMembers {
    <#
    .SYNOPSIS
        Shows group members.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter()]
        [string]$GroupName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Groups', $GroupName, 'Members')

    $members = Show-InTUILoading -Title "[magenta]Loading members...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri "/groups/$GroupId/members" -PageSize 50 -Select 'id,displayName,userPrincipalName,mail,jobTitle'
    }

    if ($null -eq $members -or $members.Results.Count -eq 0) {
        Show-InTUIWarning "No members found in this group."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($member in $members.Results) {
        $memberType = switch ($member.'@odata.type') {
            '#microsoft.graph.user'            { '[blue]User[/]' }
            '#microsoft.graph.device'          { '[green]Device[/]' }
            '#microsoft.graph.group'           { '[magenta]Group[/]' }
            '#microsoft.graph.servicePrincipal' { '[yellow]Service Principal[/]' }
            default { ($member.'@odata.type' -replace '#microsoft\.graph\.', '') }
        }

        $rows += , @(
            $member.displayName,
            $memberType,
            ($member.userPrincipalName ?? ($member.mail ?? 'N/A')),
            ($member.jobTitle ?? 'N/A')
        )
    }

    Show-InTUITable -Title "Members of $GroupName" -Columns @('Name', 'Type', 'UPN/Email', 'Title') -Rows $rows

    $userMembers = $members.Results | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' }
    if ($userMembers.Count -gt 0) {
        $choices = @($userMembers | ForEach-Object { $_.displayName })
        $choices += 'Back'

        $selection = Show-InTUIMenu -Title "[magenta]View user details[/]" -Choices $choices
        if ($selection -ne 'Back') {
            $selectedUser = $userMembers | Where-Object { $_.displayName -eq $selection }
            if ($selectedUser) {
                Show-InTUIUserDetail -UserId $selectedUser.id
            }
        }
    }
    else {
        Read-InTUIKey
    }
}

function Show-InTUIGroupOwners {
    <#
    .SYNOPSIS
        Shows group owners.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter()]
        [string]$GroupName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Groups', $GroupName, 'Owners')

    $owners = Show-InTUILoading -Title "[magenta]Loading owners...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/groups/$GroupId/owners?`$select=id,displayName,userPrincipalName,mail"
    }

    if (-not $owners.value) {
        Show-InTUIWarning "No owners found for this group."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($owner in $owners.value) {
        $rows += , @(
            $owner.displayName,
            ($owner.userPrincipalName ?? 'N/A'),
            ($owner.mail ?? 'N/A')
        )
    }

    Show-InTUITable -Title "Owners of $GroupName" -Columns @('Name', 'UPN', 'Email') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIGroupDeviceMembers {
    <#
    .SYNOPSIS
        Shows device members of a group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter()]
        [string]$GroupName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Groups', $GroupName, 'Device Members')

    $members = Show-InTUILoading -Title "[magenta]Loading device members...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri "/groups/$GroupId/members/microsoft.graph.device" -PageSize 50 -Select 'id,displayName,operatingSystem,operatingSystemVersion,trustType,isManaged'
    }

    if ($null -eq $members -or $members.Results.Count -eq 0) {
        Show-InTUIWarning "No device members found in this group."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($device in $members.Results) {
        $managed = if ($device.isManaged) { '[green]Yes[/]' } else { '[grey]No[/]' }
        $icon = Get-InTUIDeviceIcon -OperatingSystem $device.operatingSystem

        $rows += , @(
            "$icon $($device.displayName)",
            ($device.operatingSystem ?? 'N/A'),
            ($device.operatingSystemVersion ?? 'N/A'),
            ($device.trustType ?? 'N/A'),
            $managed
        )
    }

    Show-InTUITable -Title "Device Members of $GroupName" -Columns @('Device', 'OS', 'Version', 'Trust Type', 'Managed') -Rows $rows
    Read-InTUIKey
}
