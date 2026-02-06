function Show-InTUIConditionalAccessView {
    <#
    .SYNOPSIS
        Displays the Conditional Access view with policies, named locations, and sign-in logs.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access')

        $choices = @(
            'Policies',
            'Named Locations',
            'Sign-in Logs',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[DeepSkyBlue1]Conditional Access[/]" -Choices $choices

        Write-InTUILog -Message "Conditional Access view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Policies' {
                Show-InTUIConditionalAccessPolicyList
            }
            'Named Locations' {
                Show-InTUINamedLocationList
            }
            'Sign-in Logs' {
                Show-InTUISignInLogs
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

function Show-InTUIConditionalAccessPolicyList {
    <#
    .SYNOPSIS
        Displays a list of Conditional Access policies.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Policies')

        $params = @{
            Uri      = '/identity/conditionalAccess/policies'
            Beta     = $false
            PageSize = 25
            Select   = 'id,displayName,state,createdDateTime,modifiedDateTime'
        }

        $policies = Show-InTUILoading -Title "[DeepSkyBlue1]Loading Conditional Access policies...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $policies -or $policies.Results.Count -eq 0) {
            Show-InTUIWarning "No Conditional Access policies found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $policyChoices = @()
        foreach ($policy in $policies.Results) {
            $modified = Format-InTUIDate -DateString $policy.modifiedDateTime
            $stateDisplay = switch ($policy.state) {
                'enabled'                              { '[green]enabled[/]' }
                'disabled'                             { '[grey]disabled[/]' }
                'enabledForReportingButNotEnforced'     { '[yellow]report-only[/]' }
                default                                { "[grey]$($policy.state)[/]" }
            }

            $displayName = "[white]$($policy.displayName)[/] [grey]| $stateDisplay | $modified[/]"
            $policyChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $policyChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($policies.Count ?? $policies.Results.Count) -Showing $policies.Results.Count

        $selection = Show-InTUIMenu -Title "[DeepSkyBlue1]Select a policy[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $policies.Results.Count) {
                Show-InTUIConditionalAccessPolicyDetail -PolicyId $policies.Results[$idx].id
            }
        }
    }
}

function Show-InTUIConditionalAccessPolicyDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific Conditional Access policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $policy = Show-InTUILoading -Title "[DeepSkyBlue1]Loading policy details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/identity/conditionalAccess/policies/$PolicyId"
        }

        if ($null -eq $policy) {
            Show-InTUIError "Failed to load policy details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Policies', $policy.displayName)

        # Panel 1: Properties
        $stateDisplay = switch ($policy.state) {
            'enabled'                              { '[green]enabled[/]' }
            'disabled'                             { '[grey]disabled[/]' }
            'enabledForReportingButNotEnforced'     { '[yellow]report-only[/]' }
            default                                { $policy.state }
        }

        $propsContent = @"
[bold white]$($policy.displayName)[/]

[grey]State:[/]             $stateDisplay
[grey]Created:[/]           $(Format-InTUIDate -DateString $policy.createdDateTime)
[grey]Modified:[/]          $(Format-InTUIDate -DateString $policy.modifiedDateTime)
"@

        Show-InTUIPanel -Title "[DeepSkyBlue1]Properties[/]" -Content $propsContent -BorderColor DeepSkyBlue1

        # Panel 2: Conditions summary
        $conditions = $policy.conditions
        $condContent = ""

        # Users
        $includeUsers = $conditions.users.includeUsers
        $excludeUsers = $conditions.users.excludeUsers
        $includeGroups = $conditions.users.includeGroups
        $excludeGroups = $conditions.users.excludeGroups

        $usersInclude = if ($includeUsers -contains 'All') { 'All users' }
                        elseif ($includeUsers) { "$(@($includeUsers).Count) user(s)" }
                        else { 'None' }
        if ($includeGroups -and @($includeGroups).Count -gt 0) {
            $usersInclude += ", $(@($includeGroups).Count) group(s)"
        }

        $usersExclude = if ($excludeUsers -and @($excludeUsers).Count -gt 0) { "$(@($excludeUsers).Count) user(s)" } else { '' }
        if ($excludeGroups -and @($excludeGroups).Count -gt 0) {
            $groupExcl = "$(@($excludeGroups).Count) group(s)"
            $usersExclude = if ($usersExclude) { "$usersExclude, $groupExcl" } else { $groupExcl }
        }
        if (-not $usersExclude) { $usersExclude = 'None' }

        $condContent += "[grey]Users Include:[/]     $usersInclude"
        $condContent += "`n[grey]Users Exclude:[/]     $usersExclude"

        # Applications
        $includeApps = $conditions.applications.includeApplications
        $excludeApps = $conditions.applications.excludeApplications

        $appsInclude = if ($includeApps -contains 'All') { 'All cloud apps' }
                       elseif ($includeApps) { "$(@($includeApps).Count) app(s)" }
                       else { 'None' }

        $appsExclude = if ($excludeApps -and @($excludeApps).Count -gt 0) { "$(@($excludeApps).Count) app(s)" } else { 'None' }

        $condContent += "`n[grey]Apps Include:[/]      $appsInclude"
        $condContent += "`n[grey]Apps Exclude:[/]      $appsExclude"

        # Platforms
        if ($conditions.platforms) {
            $platInclude = if ($conditions.platforms.includePlatforms) {
                ($conditions.platforms.includePlatforms -join ', ')
            } else { 'None' }
            $condContent += "`n[grey]Platforms:[/]         $platInclude"
        }

        # Locations
        if ($conditions.locations) {
            $locInclude = if ($conditions.locations.includeLocations) {
                ($conditions.locations.includeLocations -join ', ')
            } else { 'None' }
            $locExclude = if ($conditions.locations.excludeLocations) {
                ($conditions.locations.excludeLocations -join ', ')
            } else { 'None' }
            $condContent += "`n[grey]Locations Include:[/] $locInclude"
            $condContent += "`n[grey]Locations Exclude:[/] $locExclude"
        }

        # Client app types
        if ($conditions.clientAppTypes) {
            $condContent += "`n[grey]Client App Types:[/]  $($conditions.clientAppTypes -join ', ')"
        }

        # Sign-in risk levels
        if ($conditions.signInRiskLevels -and @($conditions.signInRiskLevels).Count -gt 0) {
            $condContent += "`n[grey]Sign-in Risk:[/]      $($conditions.signInRiskLevels -join ', ')"
        }

        Show-InTUIPanel -Title "[DeepSkyBlue1]Conditions[/]" -Content $condContent -BorderColor DeepSkyBlue1

        # Panel 3: Grant Controls
        $grantControls = $policy.grantControls
        if ($grantControls) {
            $builtIn = if ($grantControls.builtInControls) {
                $grantControls.builtInControls -join ', '
            } else { 'None' }
            $operator = $grantControls.operator ?? 'N/A'

            $grantContent = @"
[grey]Built-in Controls:[/] $builtIn
[grey]Operator:[/]          $operator
"@
            Show-InTUIPanel -Title "[DeepSkyBlue1]Grant Controls[/]" -Content $grantContent -BorderColor DeepSkyBlue1
        }

        # Panel 4: Session Controls
        $sessionControls = $policy.sessionControls
        if ($sessionControls) {
            $sessionContent = ""
            $hasSession = $false

            if ($sessionControls.signInFrequency) {
                $sif = $sessionControls.signInFrequency
                $sessionContent += "[grey]Sign-in Frequency:[/] $($sif.value) $($sif.type) (enabled: $($sif.isEnabled))"
                $hasSession = $true
            }
            if ($sessionControls.persistentBrowser) {
                $pb = $sessionControls.persistentBrowser
                if ($hasSession) { $sessionContent += "`n" }
                $sessionContent += "[grey]Persistent Browser:[/] $($pb.mode) (enabled: $($pb.isEnabled))"
                $hasSession = $true
            }
            if ($sessionControls.cloudAppSecurity) {
                $cas = $sessionControls.cloudAppSecurity
                if ($hasSession) { $sessionContent += "`n" }
                $sessionContent += "[grey]Cloud App Security:[/] $($cas.cloudAppSecurityType) (enabled: $($cas.isEnabled))"
                $hasSession = $true
            }
            if ($sessionControls.applicationEnforcedRestrictions) {
                $aer = $sessionControls.applicationEnforcedRestrictions
                if ($hasSession) { $sessionContent += "`n" }
                $sessionContent += "[grey]App Enforced Restrictions:[/] enabled: $($aer.isEnabled)"
                $hasSession = $true
            }

            if ($hasSession) {
                Show-InTUIPanel -Title "[DeepSkyBlue1]Session Controls[/]" -Content $sessionContent -BorderColor DeepSkyBlue1
            }
        }

        $actionChoices = @(
            '─────────────',
            'Back to Policies'
        )

        $action = Show-InTUIMenu -Title "[DeepSkyBlue1]Policy Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "CA policy detail action" -Context @{ PolicyId = $PolicyId; PolicyName = $policy.displayName; Action = $action }

        switch ($action) {
            'Back to Policies' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUINamedLocationList {
    <#
    .SYNOPSIS
        Displays a list of Named Locations.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Named Locations')

        $params = @{
            Uri      = '/identity/conditionalAccess/namedLocations'
            Beta     = $false
            PageSize = 25
            Select   = 'id,displayName,createdDateTime,modifiedDateTime'
        }

        $locations = Show-InTUILoading -Title "[DeepSkyBlue1]Loading named locations...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $locations -or $locations.Results.Count -eq 0) {
            Show-InTUIWarning "No named locations found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $locationChoices = @()
        foreach ($location in $locations.Results) {
            $modified = Format-InTUIDate -DateString $location.modifiedDateTime
            $locType = switch -Wildcard ($location.'@odata.type') {
                '*ipNamedLocation'      { 'IP Ranges' }
                '*countryNamedLocation'  { 'Countries' }
                default                  { 'Unknown' }
            }

            $displayName = "[white]$($location.displayName)[/] [grey]| $locType | $modified[/]"
            $locationChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $locationChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total ($locations.Count ?? $locations.Results.Count) -Showing $locations.Results.Count

        $selection = Show-InTUIMenu -Title "[DeepSkyBlue1]Select a named location[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $locations.Results.Count) {
                Show-InTUINamedLocationDetail -LocationId $locations.Results[$idx].id
            }
        }
    }
}

function Show-InTUINamedLocationDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific Named Location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocationId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $location = Show-InTUILoading -Title "[DeepSkyBlue1]Loading named location details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/identity/conditionalAccess/namedLocations/$LocationId"
        }

        if ($null -eq $location) {
            Show-InTUIError "Failed to load named location details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Named Locations', $location.displayName)

        $locType = switch -Wildcard ($location.'@odata.type') {
            '*ipNamedLocation'      { 'IP Ranges' }
            '*countryNamedLocation'  { 'Countries' }
            default                  { 'Unknown' }
        }

        $propsContent = @"
[bold white]$($location.displayName)[/]

[grey]Type:[/]             $locType
[grey]Created:[/]          $(Format-InTUIDate -DateString $location.createdDateTime)
[grey]Modified:[/]         $(Format-InTUIDate -DateString $location.modifiedDateTime)
"@

        # IP Named Location details
        if ($location.'@odata.type' -like '*ipNamedLocation') {
            $propsContent += "`n[grey]Is Trusted:[/]       $($location.isTrusted ?? $false)"

            if ($location.ipRanges -and @($location.ipRanges).Count -gt 0) {
                $propsContent += "`n`n[bold white]IP Ranges:[/]"
                foreach ($range in $location.ipRanges) {
                    $propsContent += "`n  $($range.cidrAddress)"
                }
            }
        }

        # Country Named Location details
        if ($location.'@odata.type' -like '*countryNamedLocation') {
            $propsContent += "`n[grey]Include Unknown:[/]  $($location.includeUnknownCountriesAndRegions ?? $false)"

            if ($location.countriesAndRegions -and @($location.countriesAndRegions).Count -gt 0) {
                $propsContent += "`n`n[bold white]Countries and Regions:[/]"
                $propsContent += "`n  $($location.countriesAndRegions -join ', ')"
            }
        }

        Show-InTUIPanel -Title "[DeepSkyBlue1]Named Location Properties[/]" -Content $propsContent -BorderColor DeepSkyBlue1

        $actionChoices = @(
            '─────────────',
            'Back to Named Locations'
        )

        $action = Show-InTUIMenu -Title "[DeepSkyBlue1]Location Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Named location detail action" -Context @{ LocationId = $LocationId; LocationName = $location.displayName; Action = $action }

        switch ($action) {
            'Back to Named Locations' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUISignInLogs {
    <#
    .SYNOPSIS
        Displays sign-in logs with filtering for Conditional Access analysis.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Sign-in Logs')

    $filterChoices = @(
        'All Recent',
        'Failures Only',
        'Specific User',
        '─────────────',
        'Back'
    )

    $filterSelection = Show-InTUIMenu -Title "[DeepSkyBlue1]Sign-in Log Filter[/]" -Choices $filterChoices

    Write-InTUILog -Message "Sign-in logs filter selection" -Context @{ Filter = $filterSelection }

    if ($filterSelection -eq 'Back' -or $filterSelection -eq '─────────────') {
        return
    }

    $filter = $null

    switch ($filterSelection) {
        'Failures Only' {
            $filter = 'status/errorCode ne 0'
        }
        'Specific User' {
            $upn = Read-SpectreText -Prompt "[DeepSkyBlue1]Enter user principal name (UPN)[/]"
            if (-not $upn) { return }
            $safeUpn = ConvertTo-InTUISafeFilterValue -Value $upn
            $filter = "userPrincipalName eq '$safeUpn'"
            Write-InTUILog -Message "Sign-in logs filtering by user" -Context @{ UPN = $upn }
        }
    }

    $params = @{
        Uri      = '/auditLogs/signIns'
        Beta     = $false
        PageSize = 25
        Select   = 'id,userDisplayName,userPrincipalName,appDisplayName,ipAddress,status,createdDateTime,conditionalAccessStatus'
    }

    if ($filter) {
        $params['Filter'] = $filter
    }

    $signIns = Show-InTUILoading -Title "[DeepSkyBlue1]Loading sign-in logs...[/]" -ScriptBlock {
        Get-InTUIPagedResults @params
    }

    if ($null -eq $signIns -or $signIns.Results.Count -eq 0) {
        Show-InTUIWarning "No sign-in logs found."
        Read-InTUIKey
        return
    }

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Conditional Access', 'Sign-in Logs', $filterSelection)

    $rows = @()
    foreach ($signIn in $signIns.Results) {
        $statusDisplay = if ($signIn.status.errorCode -eq 0) {
            '[green]Success[/]'
        } else {
            "[red]Failed: $($signIn.status.errorCode)[/]"
        }

        $caStatus = switch ($signIn.conditionalAccessStatus) {
            'success'    { '[green]success[/]' }
            'failure'    { '[red]failure[/]' }
            'notApplied' { '[grey]notApplied[/]' }
            default      { "[grey]$($signIn.conditionalAccessStatus)[/]" }
        }

        $time = Format-InTUIDate -DateString $signIn.createdDateTime

        $rows += , @(
            ($signIn.userDisplayName ?? 'N/A'),
            ($signIn.appDisplayName ?? 'N/A'),
            ($signIn.ipAddress ?? 'N/A'),
            $statusDisplay,
            $caStatus,
            $time
        )
    }

    Show-InTUITable -Title "Sign-in Logs ($filterSelection)" -Columns @('User', 'App', 'IP', 'Status', 'CA Status', 'Time') -Rows $rows

    Read-InTUIKey
}
