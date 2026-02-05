function Show-InTUICompliancePoliciesView {
    <#
    .SYNOPSIS
        Displays the Compliance Policies view with platform filtering and search.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Compliance Policies')

        $choices = @(
            'All Policies',
            'Windows Policies',
            'iOS/iPadOS Policies',
            'macOS Policies',
            'Android Policies',
            'Search Policies',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[magenta1]Compliance Policies[/]" -Choices $choices

        Write-InTUILog -Message "Compliance Policies view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'All Policies' {
                Show-InTUICompliancePolicyList
            }
            'Windows Policies' {
                Show-InTUICompliancePolicyList -PlatformFilter 'Windows'
            }
            'iOS/iPadOS Policies' {
                Show-InTUICompliancePolicyList -PlatformFilter 'iOS'
            }
            'macOS Policies' {
                Show-InTUICompliancePolicyList -PlatformFilter 'macOS'
            }
            'Android Policies' {
                Show-InTUICompliancePolicyList -PlatformFilter 'Android'
            }
            'Search Policies' {
                $searchTerm = Read-SpectreText -Prompt "[magenta1]Search policies by name[/]"
                if ($searchTerm) {
                    Write-InTUILog -Message "Searching compliance policies" -Context @{ SearchTerm = $searchTerm }
                    Show-InTUICompliancePolicyList -SearchTerm $searchTerm
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

function Show-InTUICompliancePolicyList {
    <#
    .SYNOPSIS
        Displays a list of device compliance policies with optional filtering.
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

        $breadcrumb = @('Home', 'Compliance Policies')
        if ($PlatformFilter) { $breadcrumb += "$PlatformFilter Policies" }
        elseif ($SearchTerm) { $breadcrumb += "Search: $SearchTerm" }
        else { $breadcrumb += 'All Policies' }
        Show-InTUIBreadcrumb -Path $breadcrumb

        $params = @{
            Uri      = '/deviceManagement/deviceCompliancePolicies'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime,version'
        }

        if ($SearchTerm) {
            $safe = ConvertTo-InTUISafeFilterValue -Value $SearchTerm
            $params['Filter'] = "contains(displayName,'$safe')"
        }

        $policies = Show-InTUILoading -Title "[magenta1]Loading compliance policies...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $policies -or $policies.Results.Count -eq 0) {
            Show-InTUIWarning "No compliance policies found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        # Client-side platform filtering (API doesn't support $filter on @odata.type)
        $filteredResults = $policies.Results
        if ($PlatformFilter) {
            $filteredResults = @($policies.Results | Where-Object {
                $typeInfo = Get-InTUICompliancePolicyType -ODataType $_.'@odata.type'
                $typeInfo.Platform -eq $PlatformFilter
            })

            if ($filteredResults.Count -eq 0) {
                Show-InTUIWarning "No $PlatformFilter compliance policies found."
                Read-InTUIKey
                $exitList = $true
                continue
            }
        }

        $policyChoices = @()
        foreach ($policy in $filteredResults) {
            $typeInfo = Get-InTUICompliancePolicyType -ODataType $policy.'@odata.type'
            $modified = Format-InTUIDate -DateString $policy.lastModifiedDateTime

            $displayName = "[white]$($policy.displayName)[/] [grey]| $($typeInfo.FriendlyName) | $($typeInfo.Platform) | $modified[/]"
            $policyChoices += $displayName
        }

        $policyChoices += '─────────────'
        $policyChoices += 'Back'

        Show-InTUIStatusBar -Total $filteredResults.Count -Showing $filteredResults.Count -FilterText ($PlatformFilter ?? $SearchTerm)

        $selection = Show-InTUIMenu -Title "[magenta1]Select a policy[/]" -Choices $policyChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $policyChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $filteredResults.Count) {
                Show-InTUICompliancePolicyDetail -PolicyId $filteredResults[$idx].id
            }
        }
    }
}

function Get-InTUICompliancePolicyType {
    <#
    .SYNOPSIS
        Maps a device compliance @odata.type to a friendly name and platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ODataType
    )

    switch -Wildcard ($ODataType) {
        '*windows10CompliancePolicy*'             { return @{ Platform = 'Windows'; FriendlyName = 'General' } }
        '*windowsPhone81CompliancePolicy*'        { return @{ Platform = 'Windows'; FriendlyName = 'Phone' } }
        '*iosCompliancePolicy*'                   { return @{ Platform = 'iOS'; FriendlyName = 'General' } }
        '*macOSCompliancePolicy*'                 { return @{ Platform = 'macOS'; FriendlyName = 'General' } }
        '*androidCompliancePolicy*'               { return @{ Platform = 'Android'; FriendlyName = 'General' } }
        '*androidWorkProfileCompliancePolicy*'    { return @{ Platform = 'Android'; FriendlyName = 'Work Profile' } }
        '*androidDeviceOwnerCompliancePolicy*'    { return @{ Platform = 'Android'; FriendlyName = 'Device Owner' } }
        default {
            $rawType = $ODataType -replace '#microsoft\.graph\.', ''
            return @{ Platform = 'Unknown'; FriendlyName = $rawType }
        }
    }
}

function Show-InTUICompliancePolicyDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific compliance policy.
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

        $detailData = Show-InTUILoading -Title "[magenta1]Loading policy details...[/]" -ScriptBlock {
            $pol = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId/assignments" -Beta
            $devStatuses = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId/deviceStatuses?`$top=200" -Beta
            $settingSummaries = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId/deviceSettingStateSummaries" -Beta

            @{
                Policy           = $pol
                Assignments      = $assign
                DeviceStatuses   = $devStatuses
                SettingSummaries = $settingSummaries
            }
        }

        $policy = $detailData.Policy
        $assignments = $detailData.Assignments
        $deviceStatuses = $detailData.DeviceStatuses
        $settingSummaries = $detailData.SettingSummaries

        if ($null -eq $policy) {
            Show-InTUIError "Failed to load policy details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Compliance Policies', $policy.displayName)

        $typeInfo = Get-InTUICompliancePolicyType -ODataType $policy.'@odata.type'

        # Panel 1: Policy Properties
        $propsContent = @"
[bold white]$($policy.displayName)[/]

[grey]Type:[/]              $($typeInfo.FriendlyName)
[grey]Platform:[/]          $($typeInfo.Platform)
[grey]Description:[/]       $(if ($policy.description) { $policy.description.Substring(0, [Math]::Min(200, $policy.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $policy.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $policy.lastModifiedDateTime)
[grey]Version:[/]           $($policy.version ?? 'N/A')
"@

        Show-InTUIPanel -Title "[magenta1]Policy Properties[/]" -Content $propsContent -BorderColor Magenta1

        # Panel 2: Assignments
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

        Show-InTUIPanel -Title "[magenta1]Assignments[/]" -Content $assignContent -BorderColor Magenta1

        # Panel 3: Device Status Summary
        $statusList = if ($deviceStatuses.value) { @($deviceStatuses.value) } else { @() }
        $compliant = @($statusList | Where-Object { $_.status -eq 'compliant' }).Count
        $nonCompliant = @($statusList | Where-Object { $_.status -eq 'nonCompliant' }).Count
        $errorCount = @($statusList | Where-Object { $_.status -eq 'error' }).Count
        $notApplicable = @($statusList | Where-Object { $_.status -eq 'notApplicable' }).Count

        $statusContent = @"
[grey]Total Devices:[/]    [white]$($statusList.Count)[/]
[green]Compliant:[/]        $compliant
[red]Non-Compliant:[/]   $nonCompliant
[red]Error:[/]            $errorCount
[grey]Not Applicable:[/]  $notApplicable
"@

        Show-InTUIPanel -Title "[magenta1]Device Status Summary[/]" -Content $statusContent -BorderColor Magenta1

        # Panel 4: Setting Status Summary
        $settingList = if ($settingSummaries.value) { @($settingSummaries.value) } else { @() }
        if ($settingList.Count -gt 0) {
            $settingRows = @()
            foreach ($setting in $settingList) {
                $settingRows += , @(
                    ($setting.settingName ?? $setting.instancePath ?? 'N/A'),
                    "[green]$($setting.compliantDeviceCount ?? 0)[/]",
                    "[red]$($setting.nonCompliantDeviceCount ?? 0)[/]",
                    "[red]$($setting.errorDeviceCount ?? 0)[/]",
                    "[grey]$($setting.notApplicableDeviceCount ?? 0)[/]"
                )
            }

            Show-InTUITable -Title "Setting Status Summary" -Columns @('Setting', 'Compliant', 'NonCompliant', 'Error', 'Not Applicable') -Rows $settingRows -BorderColor Magenta1
        }

        $actionChoices = @(
            'View Device Statuses',
            'View Per-Setting Status',
            '─────────────',
            'Back to Policies'
        )

        $action = Show-InTUIMenu -Title "[magenta1]Policy Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Compliance policy detail action" -Context @{ PolicyId = $PolicyId; PolicyName = $policy.displayName; Action = $action }

        switch ($action) {
            'View Device Statuses' {
                Show-InTUICompliancePolicyDeviceStatuses -PolicyId $PolicyId -PolicyName $policy.displayName
            }
            'View Per-Setting Status' {
                Show-InTUICompliancePolicySettingStatuses -PolicyId $PolicyId -PolicyName $policy.displayName
            }
            'Back to Policies' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUICompliancePolicyDeviceStatuses {
    <#
    .SYNOPSIS
        Displays device status table for a compliance policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter()]
        [string]$PolicyName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Compliance Policies', $PolicyName, 'Device Statuses')

    $statuses = Show-InTUILoading -Title "[magenta1]Loading device statuses...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No device status data available for this policy."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($status in $statuses.value) {
        $stateColor = switch ($status.status) {
            'compliant'     { 'green' }
            'nonCompliant'  { 'red' }
            'error'         { 'red' }
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

    Show-InTUITable -Title "Device Statuses" -Columns @('Device', 'Status', 'User', 'Last Reported') -Rows $rows -BorderColor Magenta1
    Read-InTUIKey
}

function Show-InTUICompliancePolicySettingStatuses {
    <#
    .SYNOPSIS
        Displays per-setting status summary table for a compliance policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId,

        [Parameter()]
        [string]$PolicyName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Compliance Policies', $PolicyName, 'Per-Setting Status')

    $settingSummaries = Show-InTUILoading -Title "[magenta1]Loading setting statuses...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$PolicyId/deviceSettingStateSummaries" -Beta
    }

    if (-not $settingSummaries.value) {
        Show-InTUIWarning "No setting status data available for this policy."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($setting in $settingSummaries.value) {
        $rows += , @(
            ($setting.settingName ?? $setting.instancePath ?? 'N/A'),
            "[green]$($setting.compliantDeviceCount ?? 0)[/]",
            "[red]$($setting.nonCompliantDeviceCount ?? 0)[/]",
            "[red]$($setting.errorDeviceCount ?? 0)[/]",
            "[orange1]$($setting.conflictDeviceCount ?? 0)[/]",
            "[grey]$($setting.notApplicableDeviceCount ?? 0)[/]"
        )
    }

    Show-InTUITable -Title "Per-Setting Status" -Columns @('Setting', 'Compliant', 'NonCompliant', 'Error', 'Conflict', 'Not Applicable') -Rows $rows -BorderColor Magenta1
    Read-InTUIKey
}
