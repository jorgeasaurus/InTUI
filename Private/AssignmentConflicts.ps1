function Show-InTUIAssignmentConflictView {
    <#
    .SYNOPSIS
        Detects groups targeted by multiple configuration or compliance policies (potential conflicts).
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Assignment Conflicts')

        $choices = @('Configuration Profiles', 'Compliance Policies', '─────────────', 'Back to Home')
        $selection = Show-InTUIMenu -Title "[yellow]Assignment Conflict Check[/]" -Choices $choices

        switch ($selection) {
            'Configuration Profiles' {
                Show-InTUIConfigConflicts
            }
            'Compliance Policies' {
                Show-InTUIComplianceConflicts
            }
            'Back to Home' {
                $exitView = $true
            }
            default { continue }
        }
    }
}

function Show-InTUIConfigConflicts {
    <#
    .SYNOPSIS
        Finds groups targeted by multiple configuration profiles.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Assignment Conflicts', 'Configuration Profiles')

    $data = Show-InTUILoading -Title "[yellow]Loading configuration profiles...[/]" -ScriptBlock {
        $catalog = Invoke-InTUIGraphRequest -Uri '/deviceManagement/configurationPolicies?$expand=assignments&$top=200' -Beta
        $legacy = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceConfigurations?$expand=assignments&$top=200' -Beta
        @{
            Catalog = $catalog
            Legacy  = $legacy
        }
    }

    $allPolicies = @()
    foreach ($source in @($data.Catalog, $data.Legacy)) {
        $items = if ($source.value) { @($source.value) } else { @() }
        foreach ($policy in $items) {
            $allPolicies += $policy
        }
    }

    $conflicts = Find-InTUIAssignmentOverlaps -Policies $allPolicies

    if ($conflicts.Count -eq 0) {
        Show-InTUISuccess "No assignment conflicts detected among $($allPolicies.Count) configuration profiles."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($conflict in $conflicts) {
        $rows += , @(
            $conflict.GroupName,
            (ConvertTo-InTUISafeMarkup -Text $conflict.PolicyA),
            (ConvertTo-InTUISafeMarkup -Text $conflict.PolicyB),
            ($conflict.Platform ?? 'N/A')
        )
    }

    Show-InTUIWarning "Found $($conflicts.Count) potential conflict(s)."
    Write-InTUIText ""

    Render-InTUITable -Title "Configuration Profile Conflicts" -Columns @('Group', 'Policy A', 'Policy B', 'Platform') -Rows $rows -BorderColor Yellow

    Read-InTUIKey
}

function Show-InTUIComplianceConflicts {
    <#
    .SYNOPSIS
        Finds groups targeted by multiple compliance policies.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Assignment Conflicts', 'Compliance Policies')

    $data = Show-InTUILoading -Title "[yellow]Loading compliance policies...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$top=200' -Beta
    }

    $allPolicies = if ($data.value) { @($data.value) } else { @() }

    $conflicts = Find-InTUIAssignmentOverlaps -Policies $allPolicies

    if ($conflicts.Count -eq 0) {
        Show-InTUISuccess "No assignment conflicts detected among $($allPolicies.Count) compliance policies."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($conflict in $conflicts) {
        $rows += , @(
            $conflict.GroupName,
            (ConvertTo-InTUISafeMarkup -Text $conflict.PolicyA),
            (ConvertTo-InTUISafeMarkup -Text $conflict.PolicyB),
            ($conflict.Platform ?? 'N/A')
        )
    }

    Show-InTUIWarning "Found $($conflicts.Count) potential conflict(s)."
    Write-InTUIText ""

    Render-InTUITable -Title "Compliance Policy Conflicts" -Columns @('Group', 'Policy A', 'Policy B', 'Platform') -Rows $rows -BorderColor Yellow

    Read-InTUIKey
}

function Find-InTUIAssignmentOverlaps {
    <#
    .SYNOPSIS
        Finds groups targeted by 2+ policies. Returns conflict entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Policies
    )

    # Build map: GroupId -> list of policy names
    $groupPolicyMap = @{}
    $groupNameCache = @{}

    foreach ($policy in $Policies) {
        $policyName = $policy.displayName ?? $policy.name ?? 'Unknown'
        $platform = $policy.'@odata.type' -replace '#microsoft\.graph\.', '' -replace 'Configuration$', ''

        $assignments = if ($policy.assignments) { @($policy.assignments) } else { @() }
        foreach ($assignment in $assignments) {
            $target = $assignment.target
            $groupId = $target.groupId
            if (-not $groupId) { continue }

            if (-not $groupPolicyMap.ContainsKey($groupId)) {
                $groupPolicyMap[$groupId] = @()
            }
            $groupPolicyMap[$groupId] += @{ Name = $policyName; Platform = $platform }
        }
    }

    # Find groups with 2+ policies
    $conflicts = @()
    foreach ($groupId in $groupPolicyMap.Keys) {
        $policies = $groupPolicyMap[$groupId]
        if ($policies.Count -lt 2) { continue }

        # Resolve group name (batch-cached)
        if (-not $groupNameCache.ContainsKey($groupId)) {
            $group = Invoke-InTUIGraphRequest -Uri "/groups/${groupId}?`$select=displayName"
            $groupNameCache[$groupId] = if ($group.displayName) { $group.displayName } else { $groupId }
        }
        $groupName = $groupNameCache[$groupId]

        # Report pairs
        for ($i = 0; $i -lt $policies.Count; $i++) {
            for ($j = $i + 1; $j -lt $policies.Count; $j++) {
                $conflicts += [PSCustomObject]@{
                    GroupName = $groupName
                    PolicyA   = $policies[$i].Name
                    PolicyB   = $policies[$j].Name
                    Platform  = $policies[$i].Platform
                }
            }
        }
    }

    return $conflicts
}
