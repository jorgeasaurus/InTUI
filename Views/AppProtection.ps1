function Show-InTUIAppProtectionView {
    <#
    .SYNOPSIS
        Displays the App Protection management view for MAM policies, VPP tokens, and Win32 dependencies.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'App Protection')

        $choices = @(
            'iOS App Protection Policies',
            'Android App Protection Policies',
            'Windows App Protection Policies',
            'VPP Tokens',
            '─────────────',
            'Back to Apps'
        )

        $selection = Show-InTUIMenu -Title "[green]App Protection[/]" -Choices $choices

        Write-InTUILog -Message "App Protection view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'iOS App Protection Policies' {
                Show-InTUIAppProtectionPolicyList -Platform 'ios'
            }
            'Android App Protection Policies' {
                Show-InTUIAppProtectionPolicyList -Platform 'android'
            }
            'Windows App Protection Policies' {
                Show-InTUIAppProtectionPolicyList -Platform 'windows'
            }
            'VPP Tokens' {
                Show-InTUIVppTokenList
            }
            'Back to Apps' {
                $exitView = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIAppProtectionPolicyList {
    <#
    .SYNOPSIS
        Displays a list of app protection policies for a given platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ios', 'android', 'windows')]
        [string]$Platform
    )

    $exitList = $false

    $platformUri = switch ($Platform) {
        'ios'     { '/deviceAppManagement/iosManagedAppProtections' }
        'android' { '/deviceAppManagement/androidManagedAppProtections' }
        'windows' { '/deviceAppManagement/windowsInformationProtectionPolicies' }
    }

    $platformLabel = switch ($Platform) {
        'ios'     { 'iOS' }
        'android' { 'Android' }
        'windows' { 'Windows' }
    }

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'App Protection', "$platformLabel Policies")

        $params = @{
            Uri      = $platformUri
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime'
        }

        $policies = Show-InTUILoading -Title "[green]Loading $platformLabel app protection policies...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $policies -or $policies.Results.Count -eq 0) {
            Show-InTUIWarning "No $platformLabel app protection policies found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $policyChoices = @()
        foreach ($policy in $policies.Results) {
            $modified = Format-InTUIDate -DateString $policy.lastModifiedDateTime
            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $policy.displayName)[/] [grey]| $modified[/]"
            $policyChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $policyChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $policies.TotalCount -Showing $policies.Results.Count

        $selection = Show-InTUIMenu -Title "[green]Select a policy[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $policies.Results.Count) {
                Show-InTUIAppProtectionPolicyDetail -PolicyId $policies.Results[$idx].id -Platform $Platform
            }
        }
    }
}

function Show-InTUIAppProtectionPolicyDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific app protection policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter(Mandatory)]
        [ValidateSet('ios', 'android', 'windows')]
        [string]$Platform
    )

    $exitDetail = $false

    $platformUri = switch ($Platform) {
        'ios'     { '/deviceAppManagement/iosManagedAppProtections' }
        'android' { '/deviceAppManagement/androidManagedAppProtections' }
        'windows' { '/deviceAppManagement/windowsInformationProtectionPolicies' }
    }

    $platformLabel = switch ($Platform) {
        'ios'     { 'iOS' }
        'android' { 'Android' }
        'windows' { 'Windows' }
    }

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[green]Loading policy details...[/]" -ScriptBlock {
            $pol = Invoke-InTUIGraphRequest -Uri "$platformUri/$PolicyId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "$platformUri/$PolicyId/assignments" -Beta

            @{
                Policy      = $pol
                Assignments = $assign
            }
        }

        $policy = $detailData.Policy
        $assignments = $detailData.Assignments

        if ($null -eq $policy) {
            Show-InTUIError "Failed to load policy details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'App Protection', "$platformLabel Policies", $policy.displayName)

        Write-InTUILog -Message "Viewing app protection policy detail" -Context @{ PolicyId = $PolicyId; Platform = $Platform; PolicyName = $policy.displayName }

        # Panel 1: Properties
        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $policy.displayName)[/]

[grey]Platform:[/]          $platformLabel
[grey]Description:[/]       $(if ($policy.description) { $policy.description.Substring(0, [Math]::Min(200, $policy.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $policy.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $policy.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[green]Policy Properties[/]" -Content $propsContent -BorderColor Green

        # Panel 2: Key policy settings (platform-specific)
        if ($Platform -eq 'ios' -or $Platform -eq 'android') {
            $storageLocations = if ($policy.allowedDataStorageLocations) {
                ($policy.allowedDataStorageLocations -join ', ')
            } else { 'N/A' }

            $settingsContent = @"
[grey]Allowed Data Storage:[/]           $storageLocations
[grey]Org Credentials Required:[/]       $($policy.organizationalCredentialsRequired ?? 'N/A')
[grey]PIN Required:[/]                   $($policy.pinRequired ?? 'N/A')
[grey]Managed Browser:[/]                $($policy.managedBrowser ?? 'N/A')
[grey]Minimum OS Version:[/]             $($policy.minimumRequiredOsVersion ?? $policy.minimumOsVersion ?? 'N/A')
[grey]Maximum OS Version:[/]             $($policy.maximumRequiredOsVersion ?? $policy.maximumOsVersion ?? 'N/A')
[grey]Contact Sync Blocked:[/]           $($policy.contactSyncBlocked ?? 'N/A')
"@
        }
        else {
            # Windows
            $settingsContent = @"
[grey]Enforcement Level:[/]              $($policy.enforcementLevel ?? 'N/A')
[grey]RMS Template ID:[/]                $($policy.rightsManagementServicesTemplateId ?? 'N/A')
"@
        }

        Show-InTUIPanel -Title "[green]Policy Settings[/]" -Content $settingsContent -BorderColor Green

        # Panel 3: Assignments
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

        Show-InTUIPanel -Title "[green]Assignments[/]" -Content $assignContent -BorderColor Green

        $actionChoices = @(
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[green]Policy Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "App protection policy detail action" -Context @{ PolicyId = $PolicyId; PolicyName = $policy.displayName; Action = $action }

        switch ($action) {
            'Back' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIVppTokenList {
    <#
    .SYNOPSIS
        Displays a list of Apple VPP tokens.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'App Protection', 'VPP Tokens')

        $params = @{
            Uri      = '/deviceAppManagement/vppTokens'
            Beta     = $true
            PageSize = 25
            Select   = 'id,organizationName,appleId,state,tokenActionStatus,lastSyncDateTime,expirationDateTime,lastModifiedDateTime'
        }

        $tokens = Show-InTUILoading -Title "[green]Loading VPP tokens...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $tokens -or $tokens.Results.Count -eq 0) {
            Show-InTUIWarning "No VPP tokens found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $tokenChoices = @()
        foreach ($token in $tokens.Results) {
            $stateColor = switch ($token.state) {
                'valid'   { 'green' }
                'expired' { 'red' }
                default   { 'yellow' }
            }

            $expiresDisplay = Format-InTUIDate -DateString $token.expirationDateTime
            $expiresColor = 'grey'
            if ($token.expirationDateTime) {
                try {
                    $expDate = [DateTime]::Parse($token.expirationDateTime)
                    $daysUntilExpiry = ($expDate - [DateTime]::UtcNow).TotalDays
                    if ($daysUntilExpiry -le 30) {
                        $expiresColor = 'red'
                    }
                }
                catch { $null = $_ }
            }

            $orgName = $token.organizationName ?? 'Unknown'
            $displayName = "[white]$orgName[/] [grey]| $($token.appleId) |[/] [$stateColor]$($token.state)[/] [grey]| Expires:[/] [$expiresColor]$expiresDisplay[/]"
            $tokenChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $tokenChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $tokens.TotalCount -Showing $tokens.Results.Count

        $selection = Show-InTUIMenu -Title "[green]Select a VPP token[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $tokens.Results.Count) {
                Show-InTUIVppTokenDetail -TokenId $tokens.Results[$idx].id
            }
        }
    }
}

function Show-InTUIVppTokenDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific VPP token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TokenId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $token = Show-InTUILoading -Title "[green]Loading VPP token details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/vppTokens/$TokenId" -Beta
        }

        if ($null -eq $token) {
            Show-InTUIError "Failed to load VPP token details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Apps', 'App Protection', 'VPP Tokens', ($token.organizationName ?? 'Unknown'))

        Write-InTUILog -Message "Viewing VPP token detail" -Context @{ TokenId = $TokenId; OrgName = $token.organizationName }

        $stateColor = switch ($token.state) {
            'valid'   { 'green' }
            'expired' { 'red' }
            default   { 'yellow' }
        }

        # Check expiration warning
        $expirationWarning = ''
        if ($token.expirationDateTime) {
            try {
                $expDate = [DateTime]::Parse($token.expirationDateTime)
                $daysUntilExpiry = ($expDate - [DateTime]::UtcNow).TotalDays
                if ($daysUntilExpiry -le 30 -and $daysUntilExpiry -gt 0) {
                    $expirationWarning = "`n[red]WARNING: Token expires in $([math]::Floor($daysUntilExpiry)) days![/]"
                }
                elseif ($daysUntilExpiry -le 0) {
                    $expirationWarning = "`n[red]WARNING: Token has expired![/]"
                }
            }
            catch { $null = $_ }
        }

        $propsContent = @"
[bold white]$($token.organizationName ?? 'Unknown')[/]

[grey]Apple ID:[/]                    $($token.appleId ?? 'N/A')
[grey]State:[/]                       [$stateColor]$($token.state)[/]
[grey]Token Action Status:[/]         $($token.tokenActionStatus ?? 'N/A')
[grey]Country/Region:[/]              $($token.countryOrRegion ?? 'N/A')
[grey]Auto Update Apps:[/]            $($token.automaticallyUpdateApps ?? 'N/A')
[grey]Last Sync:[/]                   $(Format-InTUIDate -DateString $token.lastSyncDateTime)
[grey]Last Sync Status:[/]            $($token.lastSyncStatus ?? 'N/A')
[grey]Expiration:[/]                  $(Format-InTUIDate -DateString $token.expirationDateTime)
[grey]Last Modified:[/]               $(Format-InTUIDate -DateString $token.lastModifiedDateTime)$expirationWarning
"@

        Show-InTUIPanel -Title "[green]VPP Token Properties[/]" -Content $propsContent -BorderColor Green

        $actionChoices = @(
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[green]Token Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "VPP token detail action" -Context @{ TokenId = $TokenId; OrgName = $token.organizationName; Action = $action }

        switch ($action) {
            'Back' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIWin32AppDependencies {
    <#
    .SYNOPSIS
        Displays Win32 app dependency and supersedence relationships.
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
    Show-InTUIBreadcrumb -Path @('Home', 'Apps', ($AppName ?? 'App'), 'Dependencies')

    Write-InTUILog -Message "Loading Win32 app dependencies" -Context @{ AppId = $AppId; AppName = $AppName }

    $relationships = Show-InTUILoading -Title "[green]Loading app relationships...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/relationships" -Beta
    }

    if (-not $relationships.value -or @($relationships.value).Count -eq 0) {
        Show-InTUIWarning "No dependencies or supersedence configured for this app."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($rel in $relationships.value) {
        $targetAppName = $rel.targetDisplayName ?? $rel.targetId ?? 'N/A'

        $relType = switch ($rel.targetType) {
            'child'  { 'Dependency' }
            'parent' { 'Supersedence' }
            default  { $rel.targetType ?? 'N/A' }
        }

        $depType = switch ($rel.dependencyType) {
            'autoInstall' { 'Auto Install' }
            'detect'      { 'Detect' }
            default       { $rel.dependencyType ?? 'N/A' }
        }

        $rows += , @($targetAppName, $relType, $depType)
    }

    Show-InTUITable -Title "App Relationships" -Columns @('Target App', 'Relationship Type', 'Dependency Type') -Rows $rows

    Write-InTUILog -Message "Displayed Win32 app dependencies" -Context @{ AppId = $AppId; RelationshipCount = @($relationships.value).Count }

    Read-InTUIKey
}
