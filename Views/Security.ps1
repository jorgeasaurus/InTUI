function Show-InTUISecurityView {
    <#
    .SYNOPSIS
        Displays the Security view with security baselines, endpoint protection, and BitLocker keys.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security')

        $choices = @(
            'Security Baselines',
            'Endpoint Protection Policies',
            'Microsoft Defender Overview',
            'BitLocker Recovery Keys',
            'Activate PIM Role(s)',
            'Deactivate PIM Role(s)',
            '-------------',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[red]Security[/]" -Choices $choices

        Write-InTUILog -Message "Security view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Security Baselines' {
                Show-InTUISecurityBaselineList
            }
            'Endpoint Protection Policies' {
                Show-InTUIEndpointProtectionList
            }
            'Microsoft Defender Overview' {
                Show-InTUIDefenderOverview
            }
            'BitLocker Recovery Keys' {
                Show-InTUIBitLockerKeys
            }
            'Activate PIM Role(s)' {
                Show-InTUIPimRoleActivation
            }
            'Deactivate PIM Role(s)' {
                Show-InTUIPimRoleDeactivation
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

function Show-InTUIPimRoleActivation {
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Entra ID PIM Role Activation')

    if (-not $script:Connected) {
        Show-InTUIWarning "Connect to Microsoft Graph before activating PIM roles."
        Read-InTUIKey
        return
    }

    if (-not (Test-InTUIPimDelegatedContext)) {
        Show-InTUIError "PIM role activation requires an interactive delegated user connection. Service principal connections are not supported."
        Read-InTUIKey
        return
    }

    $data = Get-InTUIPimRoleActivationDataWithReconnect

    if ($null -eq $data -or $data.PermissionError) {
        Show-InTUIPimPermissionWarning
        Read-InTUIKey
        return
    }

    $eligibleRoles = @($data.Eligible)
    $activeRoles = @($data.Active)
    $availableRoles = @($eligibleRoles)

    if ($activeRoles.Count -gt 0) {
        Show-InTUIInfo "$($activeRoles.Count) active role assignment(s) found. Eligible roles are still shown for activation."
    }

    if ($availableRoles.Count -eq 0) {
        Show-InTUIWarning "No eligible Entra ID directory roles found for this account."
        Write-InTUIText "[grey]- You may not have direct eligible PIM assignments.[/]"
        Write-InTUIText "[grey]- Group-based PIM eligibility is not included in this view.[/]"
        Write-InTUIText "[grey]- The current connection may lack PIM permissions.[/]"
        Read-InTUIKey
        return
    }

    $roleChoices = @()
    foreach ($role in $availableRoles) {
        $scope = Get-InTUIPimScopeLabel -DirectoryScopeId $role.DirectoryScopeId
        $roleChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $role.DisplayName)[/] [grey]| Scope: $scope[/]"
    }

    $choiceMap = Get-InTUIChoiceMap -Choices $roleChoices
    $selectedChoices = @(Show-InTUIMultiSelect -Title "[red]Select PIM roles to activate[/]" -Choices $choiceMap.Choices -PageSize 15)
    if ($selectedChoices.Count -eq 0) {
        return
    }

    $selectedRoles = @(Resolve-InTUIPimSelectedRole -SelectedChoices $selectedChoices -ChoiceMap $choiceMap -AvailableRoles $availableRoles)

    if ($selectedRoles.Count -eq 0) {
        return
    }

    $hours = Read-InTUIPimDurationInput -MaximumHours 8
    if ($null -eq $hours) {
        return
    }

    $reason = Read-InTUIPimReasonInput
    if (-not (Test-InTUIPimReason -Reason $reason)) {
        return
    }

    if (-not (Confirm-InTUIPimActivation -Roles $selectedRoles -Hours $hours -Reason $reason)) {
        return
    }

    $results = Show-InTUILoading -Title "[red]Submitting PIM activation request(s)...[/]" -ScriptBlock {
        Invoke-InTUIPimRoleActivation -Roles $selectedRoles -Hours $hours -Reason $reason
    }

    Start-Sleep -Seconds 2
    $refreshedActive = Show-InTUILoading -Title "[red]Refreshing activation status...[/]" -ScriptBlock {
        @(Get-InTUIPimActiveDirectoryRole)
    }
    Update-InTUIPimActivationResultsFromActiveRoles -Results $results -ActiveRoles $refreshedActive

    Show-InTUIPimActivationResults -Results $results
    Read-InTUIKey
}

function Show-InTUIPimRoleDeactivation {
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Entra ID PIM Role Deactivation')

    if (-not $script:Connected) {
        Show-InTUIWarning "Connect to Microsoft Graph before deactivating PIM roles."
        Read-InTUIKey
        return
    }

    if (-not (Test-InTUIPimDelegatedContext)) {
        Show-InTUIError "PIM role deactivation requires an interactive delegated user connection. Service principal connections are not supported."
        Read-InTUIKey
        return
    }

    $data = Get-InTUIPimActiveRoleDataWithReconnect

    if ($null -eq $data -or $data.PermissionError) {
        Show-InTUIPimPermissionWarning
        Read-InTUIKey
        return
    }

    $activeRoles = @($data.Active)
    if ($activeRoles.Count -eq 0) {
        Show-InTUIWarning "No active Entra ID PIM directory roles found for this account."
        Write-InTUIText "[grey]- Activate a role first, or wait for Graph to reflect the active assignment.[/]"
        Write-InTUIText "[grey]- Group-based PIM activation is not included in this view.[/]"
        Read-InTUIKey
        return
    }

    $roleChoices = @()
    foreach ($role in $activeRoles) {
        $scope = Get-InTUIPimScopeLabel -DirectoryScopeId $role.DirectoryScopeId
        $roleChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $role.DisplayName)[/] [grey]| Scope: $scope[/]"
    }

    $choiceMap = Get-InTUIChoiceMap -Choices $roleChoices
    $selectedChoices = @(Show-InTUIMultiSelect -Title "[red]Select active PIM roles to deactivate[/]" -Choices $choiceMap.Choices -PageSize 15)
    if ($selectedChoices.Count -eq 0) {
        return
    }

    $selectedRoles = @(Resolve-InTUIPimSelectedRole -SelectedChoices $selectedChoices -ChoiceMap $choiceMap -AvailableRoles $activeRoles)
    if ($selectedRoles.Count -eq 0) {
        return
    }

    $reason = Read-InTUIPimOptionalReasonInput
    if (-not (Confirm-InTUIPimDeactivation -Roles $selectedRoles -Reason $reason)) {
        return
    }

    $results = Show-InTUILoading -Title "[red]Submitting PIM deactivation request(s)...[/]" -ScriptBlock {
        Invoke-InTUIPimRoleDeactivation -Roles $selectedRoles -Reason $reason
    }

    Start-Sleep -Seconds 2
    $refreshedActive = Show-InTUILoading -Title "[red]Refreshing active role status...[/]" -ScriptBlock {
        @(Get-InTUIPimActiveDirectoryRole)
    }
    Update-InTUIPimDeactivationResultsFromActiveRoles -Results $results -ActiveRoles $refreshedActive

    Show-InTUIPimActivationResults -Title "PIM Deactivation Results" -Results $results
    Read-InTUIKey
}

function Get-InTUIPimRoleActivationDataWithReconnect {
    [CmdletBinding()]
    param()

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $data = Get-InTUIPimRoleActivationData
        if (-not $data.PermissionError) {
            return $data
        }

        Show-InTUIPimPermissionWarning
        if (-not (Show-InTUIConfirm -Message "[yellow]Reconnect with PIM permissions now?[/]")) {
            Read-InTUIKey
            return $null
        }

        if (-not (Connect-InTUIPimPermissions)) {
            Show-InTUIError "Reconnect with PIM permissions failed."
            Read-InTUIKey
            return $null
        }

        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Entra ID PIM Role Activation')
    }

    return $data
}

function Get-InTUIPimActiveRoleDataWithReconnect {
    [CmdletBinding()]
    param()

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $data = Get-InTUIPimActiveRoleData
        if (-not $data.PermissionError) {
            return $data
        }

        Show-InTUIPimPermissionWarning
        if (-not (Show-InTUIConfirm -Message "[yellow]Reconnect with PIM permissions now?[/]")) {
            Read-InTUIKey
            return $null
        }

        if (-not (Connect-InTUIPimPermissions)) {
            Show-InTUIError "Reconnect with PIM permissions failed."
            Read-InTUIKey
            return $null
        }

        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Entra ID PIM Role Deactivation')
    }

    return $data
}

function Get-InTUIPimRoleActivationData {
    [CmdletBinding()]
    param()

    Show-InTUILoading -Title "[red]Loading eligible PIM roles...[/]" -ScriptBlock {
        $script:LastGraphError = $null
        $eligible = @(Get-InTUIPimEligibleDirectoryRole)
        if (Test-InTUIPimPermissionError -ErrorInfo $script:LastGraphError) {
            return @{ PermissionError = $true; Eligible = @(); Active = @() }
        }

        $active = @(Get-InTUIPimActiveDirectoryRole)
        if (Test-InTUIPimPermissionError -ErrorInfo $script:LastGraphError) {
            return @{ PermissionError = $true; Eligible = @(); Active = @() }
        }

        @{
            PermissionError = $false
            Eligible        = $eligible
            Active          = $active
        }
    }
}

function Get-InTUIPimActiveRoleData {
    [CmdletBinding()]
    param()

    Show-InTUILoading -Title "[red]Loading active PIM roles...[/]" -ScriptBlock {
        $script:LastGraphError = $null
        $active = @(Get-InTUIPimActiveDirectoryRole)
        if (Test-InTUIPimPermissionError -ErrorInfo $script:LastGraphError) {
            return @{ PermissionError = $true; Active = @() }
        }

        @{
            PermissionError = $false
            Active          = $active
        }
    }
}

function Connect-InTUIPimPermissions {
    [CmdletBinding()]
    param()

    $tenantId = $script:TenantId
    $environment = if ($script:CloudEnvironment) { $script:CloudEnvironment } else { 'Global' }

    Connect-InTUI -TenantId $tenantId -Environment $environment -Scopes (Get-InTUIPimConnectionScopes)
}

function Resolve-InTUIPimSelectedRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SelectedChoices,

        [Parameter(Mandatory)]
        [hashtable]$ChoiceMap,

        [Parameter(Mandatory)]
        [object[]]$AvailableRoles
    )

    $selectedRoles = @()
    foreach ($choice in $SelectedChoices) {
        $idx = $ChoiceMap.IndexMap[$choice]
        if ($null -ne $idx -and $idx -lt $AvailableRoles.Count) {
            $selectedRoles += $AvailableRoles[$idx]
        }
    }

    return $selectedRoles
}

function Read-InTUIPimDurationInput {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$MaximumHours = 8
    )

    while ($true) {
        $value = Read-InTUITextInput -Message "[red]Duration in hours[/]" -DefaultAnswer '1'
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }

        $hours = 0
        if ([int]::TryParse($value, [ref]$hours) -and $hours -ge 1 -and $hours -le $MaximumHours) {
            return $hours
        }

        Show-InTUIWarning "Enter a whole number from 1 to $MaximumHours."
    }
}

function Read-InTUIPimReasonInput {
    [CmdletBinding()]
    param()

    while ($true) {
        $reason = Read-InTUITextInput -Message "[red]Reason for activation[/]"
        if (Test-InTUIPimReason -Reason $reason) {
            return $reason.Trim()
        }

        Show-InTUIWarning "Activation reason is required."
    }
}

function Read-InTUIPimOptionalReasonInput {
    [CmdletBinding()]
    param()

    $reason = Read-InTUITextInput -Message "[red]Reason for deactivation[/] [grey](optional, press Enter to skip)[/]"
    if ([string]::IsNullOrWhiteSpace($reason)) {
        return ''
    }

    return $reason.Trim()
}

function Confirm-InTUIPimActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Roles,

        [Parameter(Mandatory)]
        [int]$Hours,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    $roleLines = @($Roles | ForEach-Object {
        $scope = Get-InTUIPimScopeLabel -DirectoryScopeId $_.DirectoryScopeId
        "- $($_.DisplayName) ($scope)"
    })
    $content = @"
[bold white]Selected roles:[/]
$($roleLines -join "`n")

[grey]Duration:[/] $Hours hour(s)
[grey]Reason:[/] $Reason
"@

    Show-InTUIPanel -Title "[red]Review PIM Activation[/]" -Content $content -BorderColor Red
    return (Show-InTUIConfirm -Message "[yellow]Submit activation request(s)?[/]")
}

function Confirm-InTUIPimDeactivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Roles,

        [Parameter()]
        [string]$Reason
    )

    $roleLines = @($Roles | ForEach-Object {
        $scope = Get-InTUIPimScopeLabel -DirectoryScopeId $_.DirectoryScopeId
        "- $($_.DisplayName) ($scope)"
    })
    $reasonLine = if ([string]::IsNullOrWhiteSpace($Reason)) { 'N/A' } else { $Reason }
    $content = @"
[bold white]Selected active roles:[/]
$($roleLines -join "`n")

[grey]Reason:[/] $reasonLine
"@

    Show-InTUIPanel -Title "[red]Review PIM Deactivation[/]" -Content $content -BorderColor Red
    return (Show-InTUIConfirm -Message "[yellow]Submit deactivation request(s)?[/]")
}

function Update-InTUIPimActivationResultsFromActiveRoles {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Results = @(),

        [Parameter()]
        [object[]]$ActiveRoles = @()
    )

    $activeKeys = @{}
    foreach ($role in @($ActiveRoles)) {
        $activeKeys[(Get-InTUIPimRoleKey -Role $role)] = $true
    }

    foreach ($result in @($Results)) {
        if ($result.Status -eq 'Failed' -or $null -eq $result.Role) {
            continue
        }

        if ($activeKeys.ContainsKey((Get-InTUIPimRoleKey -Role $result.Role))) {
            $result.Status = 'Activated'
        }
    }
}

function Update-InTUIPimDeactivationResultsFromActiveRoles {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Results = @(),

        [Parameter()]
        [object[]]$ActiveRoles = @()
    )

    $activeKeys = @{}
    foreach ($role in @($ActiveRoles)) {
        $activeKeys[(Get-InTUIPimRoleKey -Role $role)] = $true
    }

    foreach ($result in @($Results)) {
        if ($result.Status -eq 'Failed' -or $null -eq $result.Role) {
            continue
        }

        if (-not $activeKeys.ContainsKey((Get-InTUIPimRoleKey -Role $result.Role))) {
            $result.Status = 'Deactivated'
        }
    }
}

function Show-InTUIPimActivationResults {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Title = 'PIM Activation Results',

        [Parameter()]
        [object[]]$Results = @()
    )

    $rows = @()
    foreach ($result in @($Results)) {
        $statusColor = switch -Regex ($result.Status) {
            'Activated|Granted|Provisioned' { 'green' }
            'Pending|Approval'             { 'yellow' }
            'Failed|Denied'                { 'red' }
            default                        { 'blue' }
        }
        $detail = if ($result.Error) { $result.Error } elseif ($result.RequestId) { $result.RequestId } else { 'N/A' }
        $rows += , @(
            ($result.RoleName ?? 'Unknown role'),
            "[$statusColor]$($result.Status)[/]",
            $detail
        )
    }

    Show-InTUITable -Title $Title -Columns @('Role', 'Status', 'Request/Error') -Rows $rows -BorderColor Red
}

function Show-InTUIPimPermissionWarning {
    [CmdletBinding()]
    param()

    $scopes = (Get-InTUIPimRequiredScopes) -join ', '
    Show-InTUIWarning "PIM role activation requires delegated Graph permissions: $scopes."
}

function Show-InTUISecurityBaselineList {
    <#
    .SYNOPSIS
        Displays a list of security baseline intents.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines')

        $params = @{
            Uri      = '/deviceManagement/intents'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,isAssigned'
        }

        $intents = Show-InTUILoading -Title "[red]Loading security baselines...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $intents -or $intents.Results.Count -eq 0) {
            Show-InTUIWarning "No security baselines found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $intentChoices = @()
        foreach ($intent in $intents.Results) {
            $assigned = if ($intent.isAssigned) { 'Yes' } else { 'No' }
            $modified = Format-InTUIDate -DateString $intent.lastModifiedDateTime

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $intent.displayName)[/] [grey]| Assigned: $assigned | $modified[/]"
            $intentChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $intentChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $intents.TotalCount -Showing $intents.Results.Count

        $selection = Show-InTUIMenu -Title "[red]Select a baseline[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $intents.Results.Count) {
                Show-InTUISecurityBaselineDetail -IntentId $intents.Results[$idx].id
            }
        }
    }
}

function Show-InTUISecurityBaselineDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific security baseline intent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IntentId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[red]Loading baseline details...[/]" -ScriptBlock {
            $intent = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/assignments" -Beta
            $states = Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/deviceStates?`$top=200" -Beta

            @{
                Intent      = $intent
                Assignments = $assign
                DeviceStates = $states
            }
        }

        $intent = $detailData.Intent
        $assignments = $detailData.Assignments
        $deviceStates = $detailData.DeviceStates

        if ($null -eq $intent) {
            Show-InTUIError "Failed to load baseline details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines', $intent.displayName)

        $assigned = if ($intent.isAssigned) { '[green]Yes[/]' } else { '[grey]No[/]' }

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $intent.displayName)[/]

[grey]Description:[/]       $(if ($intent.description) { $intent.description.Substring(0, [Math]::Min(200, $intent.description.Length)) } else { 'N/A' })
[grey]Assigned:[/]          $assigned
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $intent.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[red]Baseline Properties[/]" -Content $propsContent -BorderColor Red

        # Assignments panel
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

        Show-InTUIPanel -Title "[red]Assignments[/]" -Content $assignContent -BorderColor Red

        # Device state summary panel
        $stateList = if ($deviceStates.value) { @($deviceStates.value) } else { @() }
        $succeeded = @($stateList | Where-Object { $_.state -eq 'succeeded' -or $_.state -eq 'compliant' }).Count
        $errorCount = @($stateList | Where-Object { $_.state -eq 'error' }).Count
        $conflict = @($stateList | Where-Object { $_.state -eq 'conflict' }).Count
        $notApplicable = @($stateList | Where-Object { $_.state -eq 'notApplicable' }).Count

        $stateContent = @"
[grey]Total Devices:[/]    [white]$($stateList.Count)[/]
[green]Succeeded:[/]        $succeeded
[red]Error:[/]            $errorCount
[orange1]Conflict:[/]          $conflict
[grey]Not Applicable:[/]   $notApplicable
"@

        Show-InTUIPanel -Title "[red]Device State Summary[/]" -Content $stateContent -BorderColor Red

        $actionChoices = @(
            'View Device States',
            '─────────────',
            'Back to Baselines'
        )

        $action = Show-InTUIMenu -Title "[red]Baseline Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Security baseline detail action" -Context @{ IntentId = $IntentId; BaselineName = $intent.displayName; Action = $action }

        switch ($action) {
            'View Device States' {
                Show-InTUISecurityBaselineDeviceStates -IntentId $IntentId -BaselineName $intent.displayName
            }
            'Back to Baselines' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUISecurityBaselineDeviceStates {
    <#
    .SYNOPSIS
        Displays device state table for a security baseline intent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IntentId,

        [Parameter()]
        [string]$BaselineName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Security Baselines', $BaselineName, 'Device States')

    $states = Show-InTUILoading -Title "[red]Loading device states...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/intents/$IntentId/deviceStates?`$top=50" -Beta
    }

    if (-not $states.value) {
        Show-InTUIWarning "No device state data available for this baseline."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($state in $states.value) {
        $stateColor = switch ($state.state) {
            'succeeded'     { 'green' }
            'compliant'     { 'green' }
            'error'         { 'red' }
            'conflict'      { 'orange1' }
            'notApplicable' { 'grey' }
            default         { 'yellow' }
        }

        $rows += , @(
            ($state.deviceDisplayName ?? 'N/A'),
            "[$stateColor]$($state.state)[/]",
            ($state.userName ?? 'N/A'),
            (Format-InTUIDate -DateString $state.lastReportedDateTime)
        )
    }

    Show-InTUITable -Title "Device States" -Columns @('Device', 'State', 'User', 'Last Reported') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIEndpointProtectionList {
    <#
    .SYNOPSIS
        Displays a list of endpoint protection device configurations.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection')

        $params = @{
            Uri      = '/deviceManagement/deviceConfigurations'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime'
        }

        $configs = Show-InTUILoading -Title "[red]Loading endpoint protection policies...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $configs -or $configs.Results.Count -eq 0) {
            Show-InTUIWarning "No device configurations found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        # Client-side filter for endpoint protection types
        $filteredResults = @($configs.Results | Where-Object {
            $odataType = $_.'@odata.type'
            $odataType -match 'endpointProtection' -or $odataType -match 'windowsDefender' -or $odataType -match 'firewallRules'
        })

        if ($filteredResults.Count -eq 0) {
            Show-InTUIWarning "No endpoint protection policies found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $configChoices = @()
        foreach ($config in $filteredResults) {
            $typeName = ($config.'@odata.type' -replace '#microsoft\.graph\.', '')
            $modified = Format-InTUIDate -DateString $config.lastModifiedDateTime

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/] [grey]| $typeName | $modified[/]"
            $configChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $configChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $filteredResults.Count -Showing $filteredResults.Count

        $selection = Show-InTUIMenu -Title "[red]Select a policy[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $filteredResults.Count) {
                Show-InTUIEndpointProtectionDetail -ConfigId $filteredResults[$idx].id
            }
        }
    }
}

function Show-InTUIEndpointProtectionDetail {
    <#
    .SYNOPSIS
        Displays detailed information about an endpoint protection configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[red]Loading policy details...[/]" -ScriptBlock {
            $config = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/assignments" -Beta
            $statuses = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/deviceStatuses?`$top=200" -Beta

            @{
                Config      = $config
                Assignments = $assign
                Statuses    = $statuses
            }
        }

        $config = $detailData.Config
        $assignments = $detailData.Assignments
        $statuses = $detailData.Statuses

        if ($null -eq $config) {
            Show-InTUIError "Failed to load policy details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection', $config.displayName)

        $typeName = ($config.'@odata.type' -replace '#microsoft\.graph\.', '')

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/]

[grey]Type:[/]              $typeName
[grey]Description:[/]       $(if ($config.description) { $config.description.Substring(0, [Math]::Min(200, $config.description.Length)) } else { 'N/A' })
[grey]Created:[/]           $(Format-InTUIDate -DateString $config.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $config.lastModifiedDateTime)
[grey]Version:[/]           $($config.version ?? 'N/A')
"@

        Show-InTUIPanel -Title "[red]Policy Properties[/]" -Content $propsContent -BorderColor Red

        # Assignments panel
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

        Show-InTUIPanel -Title "[red]Assignments[/]" -Content $assignContent -BorderColor Red

        # Device status summary panel
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

        Show-InTUIPanel -Title "[red]Device Status Summary[/]" -Content $statusContent -BorderColor Red

        $actionChoices = @(
            'View Device Statuses',
            '─────────────',
            'Back to Endpoint Protection'
        )

        $action = Show-InTUIMenu -Title "[red]Policy Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Endpoint protection detail action" -Context @{ ConfigId = $ConfigId; ConfigName = $config.displayName; Action = $action }

        switch ($action) {
            'View Device Statuses' {
                Show-InTUIEndpointProtectionDeviceStatuses -ConfigId $ConfigId -ConfigName $config.displayName
            }
            'Back to Endpoint Protection' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIEndpointProtectionDeviceStatuses {
    <#
    .SYNOPSIS
        Displays device status table for an endpoint protection configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigId,

        [Parameter()]
        [string]$ConfigName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Endpoint Protection', $ConfigName, 'Device Statuses')

    $statuses = Show-InTUILoading -Title "[red]Loading device statuses...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$ConfigId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUIWarning "No device status data available for this policy."
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

function Show-InTUIBitLockerKeys {
    <#
    .SYNOPSIS
        Search for a device and display its BitLocker recovery keys.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Security', 'BitLocker Recovery Keys')

        $searchTerm = Read-InTUITextInput -Message "[red]Enter device name or device ID to search[/]"

        if (-not $searchTerm) {
            $exitView = $true
            continue
        }

        Write-InTUILog -Message "BitLocker key search" -Context @{ SearchTerm = $searchTerm }

        # Search for matching devices
        $devices = Show-InTUILoading -Title "[red]Searching for devices...[/]" -ScriptBlock {
            $safe = ConvertTo-InTUISafeFilterValue -Value $searchTerm
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=contains(deviceName,'$safe')&`$select=id,deviceName,azureADDeviceId" -Beta
        }

        if (-not $devices.value) {
            Show-InTUIWarning "No devices found matching '$searchTerm'."
            Read-InTUIKey
            continue
        }

        $deviceChoices = @()
        foreach ($device in $devices.value) {
            $deviceChoices += "[white]$($device.deviceName)[/] [grey]| $($device.azureADDeviceId ?? 'No Azure AD ID')[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $deviceChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        $selection = Show-InTUIMenu -Title "[red]Select a device[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            continue
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt @($devices.value).Count) {
                $selectedDevice = @($devices.value)[$idx]

                if (-not $selectedDevice.azureADDeviceId) {
                    Show-InTUIWarning "Selected device does not have an Azure AD Device ID. Cannot retrieve BitLocker keys."
                    Read-InTUIKey
                    continue
                }

                Write-InTUILog -Message "Retrieving BitLocker keys for device" -Context @{
                    DeviceName = $selectedDevice.deviceName
                    AzureADDeviceId = $selectedDevice.azureADDeviceId
                }

                Show-InTUIBitLockerKeysForDevice -DeviceName $selectedDevice.deviceName -AzureADDeviceId $selectedDevice.azureADDeviceId
            }
        }
    }
}

function Show-InTUIBitLockerKeysForDevice {
    <#
    .SYNOPSIS
        Displays BitLocker recovery keys for a specific device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName,

        [Parameter(Mandatory)]
        [string]$AzureADDeviceId
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'BitLocker Recovery Keys', $DeviceName)

    # Get BitLocker recovery keys (v1.0, not beta)
    $keys = Show-InTUILoading -Title "[red]Loading BitLocker recovery keys...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$AzureADDeviceId'"
    }

    if ($null -eq $keys -and (Test-InTUIBitLockerPermissionError -ErrorInfo $script:LastGraphError)) {
        Show-InTUIBitLockerPermissionWarning
        Read-InTUIKey
        return
    }

    if (-not $keys.value) {
        Show-InTUIWarning "No BitLocker recovery keys found for '$DeviceName'."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "BitLocker keys found" -Context @{ DeviceName = $DeviceName; KeyCount = @($keys.value).Count }

    $rows = @()
    foreach ($key in $keys.value) {
        $rows += , @(
            ($key.id ?? 'N/A'),
            (Format-InTUIDate -DateString $key.createdDateTime),
            ($key.volumeType ?? 'N/A'),
            '[grey]********-****-****-****-************[/]'
        )
    }

    Show-InTUITable -Title "BitLocker Recovery Keys for $DeviceName" -Columns @('Key ID', 'Created', 'Volume Type', 'Recovery Key') -Rows $rows

    # Offer to reveal individual keys
    $revealChoices = @()
    foreach ($key in $keys.value) {
        $revealChoices += "Reveal key: $($key.id)"
    }
    $choiceMap = Get-InTUIChoiceMap -Choices $revealChoices
    $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

    $revealSelection = Show-InTUIMenu -Title "[red]Reveal a recovery key?[/]" -Choices $menuChoices

    if ($revealSelection -ne 'Back' -and $revealSelection -ne '─────────────') {
        $revealIdx = $choiceMap.IndexMap[$revealSelection]
        if ($null -ne $revealIdx -and $revealIdx -lt @($keys.value).Count) {
            $selectedKey = @($keys.value)[$revealIdx]

            Write-InTUILog -Message "Revealing BitLocker recovery key" -Context @{ KeyId = $selectedKey.id; DeviceName = $DeviceName }

            $fullKey = Show-InTUILoading -Title "[red]Retrieving recovery key...[/]" -ScriptBlock {
                Invoke-InTUIGraphRequest -Uri "/informationProtection/bitlocker/recoveryKeys/$($selectedKey.id)?`$select=key"
            }

            $recoveryKey = $fullKey.key ?? $fullKey.value.key
            if ($recoveryKey) {
                $keyContent = @"
[bold white]BitLocker Recovery Key[/]

[grey]Key ID:[/]        $($selectedKey.id)
[grey]Device:[/]        $DeviceName
[grey]Volume Type:[/]   $($selectedKey.volumeType ?? 'N/A')
[grey]Created:[/]       $(Format-InTUIDate -DateString $selectedKey.createdDateTime)

[bold red]Recovery Key:[/]  [white]$recoveryKey[/]
"@
                Show-InTUIPanel -Title "[red]Recovery Key[/]" -Content $keyContent -BorderColor Red
            }
            elseif ($null -eq $fullKey -and (Test-InTUIBitLockerPermissionError -ErrorInfo $script:LastGraphError)) {
                Show-InTUIBitLockerPermissionWarning
            }
            else {
                Show-InTUIWarning "Could not retrieve the recovery key. Check permissions."
            }

            Read-InTUIKey
        }
    }
}

function Test-InTUIBitLockerPermissionError {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$ErrorInfo
    )

    if ($null -eq $ErrorInfo) {
        return $false
    }

    $statusCode = [string]$ErrorInfo.StatusCode
    return ($statusCode -eq 'Forbidden' -or $statusCode -eq '403') -and
        ([string]$ErrorInfo.Uri -match '/informationProtection/bitlocker/recoveryKeys')
}

function Show-InTUIBitLockerPermissionWarning {
    [CmdletBinding()]
    param()

    Show-InTUIWarning "BitLocker recovery keys require Graph permissions BitlockerKey.ReadBasic.All and BitlockerKey.Read.All plus a supported Entra role. Reconnect to Microsoft Graph and consent/admin-consent these scopes."
}

function Show-InTUIDefenderOverview {
    <#
    .SYNOPSIS
        Displays Microsoft Defender aggregate status across all Windows devices.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Security', 'Microsoft Defender Overview')

    Write-InTUILog -Message "Loading Defender overview"

    $data = Show-InTUILoading -Title "[red]Loading Defender status...[/]" -ScriptBlock {
        # Get Windows devices with protection state
        $devices = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=contains(operatingSystem,'Windows')&`$select=id,deviceName,windowsProtectionState&`$top=200" -Beta

        if (-not $devices.value) {
            return $null
        }

        $stats = @{
            Total = 0
            RTPEnabled = 0
            RTPDisabled = 0
            MalwareProtectionEnabled = 0
            SignaturesUpToDate = 0
            SignaturesOutdated = 0
            RebootRequired = 0
            FullScanRequired = 0
            ThreatLevels = @{
                None = 0
                Low = 0
                Medium = 0
                High = 0
                Severe = 0
                Unknown = 0
            }
            DevicesWithThreats = @()
        }

        foreach ($device in $devices.value) {
            if (-not $device.windowsProtectionState) { continue }

            $stats.Total++
            $defender = $device.windowsProtectionState

            if ($defender.realTimeProtectionEnabled) { $stats.RTPEnabled++ } else { $stats.RTPDisabled++ }
            if ($defender.malwareProtectionEnabled) { $stats.MalwareProtectionEnabled++ }
            if ($defender.signatureUpdateOverdue) { $stats.SignaturesOutdated++ } else { $stats.SignaturesUpToDate++ }
            if ($defender.rebootRequired) { $stats.RebootRequired++ }
            if ($defender.fullScanRequired) { $stats.FullScanRequired++ }

            $threatState = $defender.deviceThreatState ?? 'unknown'
            switch ($threatState) {
                'none'   { $stats.ThreatLevels.None++ }
                'low'    { $stats.ThreatLevels.Low++ }
                'medium' { $stats.ThreatLevels.Medium++ }
                'high'   { $stats.ThreatLevels.High++; $stats.DevicesWithThreats += $device }
                'severe' { $stats.ThreatLevels.Severe++; $stats.DevicesWithThreats += $device }
                default  { $stats.ThreatLevels.Unknown++ }
            }
        }

        $stats
    }

    if ($null -eq $data -or $data.Total -eq 0) {
        Show-InTUIWarning "No Windows devices with Defender data found."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Defender overview loaded" -Context @{
        TotalDevices = $data.Total
        RTPEnabled = $data.RTPEnabled
        ThreatCount = $data.ThreatLevels.High + $data.ThreatLevels.Severe
    }

    # Protection Status Panel
    $rtpPercent = if ($data.Total -gt 0) { [math]::Round(($data.RTPEnabled / $data.Total) * 100) } else { 0 }

    $protectionContent = @"
[bold]Real-Time Protection[/]
[green]Enabled:[/]           $($data.RTPEnabled) devices ($rtpPercent%)
[red]Disabled:[/]          $($data.RTPDisabled) devices

[bold]Malware Protection[/]
[green]Enabled:[/]           $($data.MalwareProtectionEnabled) devices

[bold]Signature Status[/]
[green]Up to Date:[/]        $($data.SignaturesUpToDate) devices
[red]Outdated:[/]          $($data.SignaturesOutdated) devices

[bold]Actions Required[/]
[yellow]Reboot Required:[/]   $($data.RebootRequired) devices
[yellow]Full Scan Required:[/] $($data.FullScanRequired) devices
"@

    Show-InTUIPanel -Title "[red]Protection Status ($($data.Total) Windows Devices)[/]" -Content $protectionContent -BorderColor Red

    # Threat Levels Panel
    $threatContent = @"
[green]None:[/]      $($data.ThreatLevels.None) devices
[yellow]Low:[/]       $($data.ThreatLevels.Low) devices
[orange1]Medium:[/]    $($data.ThreatLevels.Medium) devices
[red]High:[/]      $($data.ThreatLevels.High) devices
[red bold]Severe:[/]    $($data.ThreatLevels.Severe) devices
"@

    Show-InTUIPanel -Title "[red]Threat Levels[/]" -Content $threatContent -BorderColor Red

    # Show devices with high/severe threats
    if ($data.DevicesWithThreats.Count -gt 0) {
        Write-InTUIText "[red bold]Devices with High/Severe Threats:[/]"
        Write-InTUIText ""

        $rows = @()
        foreach ($device in $data.DevicesWithThreats) {
            $threatLevel = Get-InTUIThreatLevelDisplay -ThreatLevel $device.windowsProtectionState.deviceThreatState
            $rows += , @(
                ($device.deviceName ?? 'N/A'),
                $threatLevel
            )
        }

        Show-InTUITable -Title "Devices Requiring Attention" -Columns @('Device', 'Threat Level') -Rows $rows -BorderColor Red
    }

    Read-InTUIKey
}
