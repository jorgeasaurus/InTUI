function Show-InTUIScriptsView {
    <#
    .SYNOPSIS
        Displays the Scripts & Remediations view with navigation to device scripts and proactive remediations.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations')

        $choices = @(
            'Device Management Scripts',
            'Proactive Remediations',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[yellow]Scripts & Remediations[/]" -Choices $choices

        Write-InTUILog -Message "Scripts & Remediations view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Device Management Scripts' {
                Show-InTUIDeviceScriptList
            }
            'Proactive Remediations' {
                Show-InTUIRemediationList
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

function Show-InTUIDeviceScriptList {
    <#
    .SYNOPSIS
        Displays a list of device management scripts.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Device Management Scripts')

        $params = @{
            Uri      = '/deviceManagement/deviceManagementScripts'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime,fileName,runAsAccount,enforceSignatureCheck'
        }

        $scripts = Show-InTUILoading -Title "[yellow]Loading device management scripts...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $scripts -or $scripts.Results.Count -eq 0) {
            Show-InTUIWarning "No device management scripts found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $scriptChoices = @()
        foreach ($script in $scripts.Results) {
            $modified = Format-InTUIDate -DateString $script.lastModifiedDateTime
            $runAs = if ($script.runAsAccount -eq 'system') { 'System' } else { 'User' }

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $script.displayName)[/] [grey]| $($script.fileName) | $runAs | $modified[/]"
            $scriptChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $scriptChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $scripts.TotalCount -Showing $scripts.Results.Count

        $selection = Show-InTUIMenu -Title "[yellow]Select a script[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $scripts.Results.Count) {
                Show-InTUIDeviceScriptDetail -ScriptId $scripts.Results[$idx].id
            }
        }
    }
}

function Show-InTUIDeviceScriptDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific device management script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[yellow]Loading script details...[/]" -ScriptBlock {
            $scr = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceManagementScripts/$ScriptId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceManagementScripts/$ScriptId/assignments" -Beta
            $runStates = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceManagementScripts/$ScriptId/deviceRunStates?`$top=200" -Beta

            @{
                Script      = $scr
                Assignments = $assign
                RunStates   = $runStates
            }
        }

        $scriptObj = $detailData.Script
        $assignments = $detailData.Assignments
        $runStates = $detailData.RunStates

        if ($null -eq $scriptObj) {
            Show-InTUIError "Failed to load script details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Device Management Scripts', $scriptObj.displayName)

        $runAs = if ($scriptObj.runAsAccount -eq 'system') { 'System' } else { 'User' }

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $scriptObj.displayName)[/]

[grey]Description:[/]             $(if ($scriptObj.description) { $scriptObj.description.Substring(0, [Math]::Min(200, $scriptObj.description.Length)) } else { 'N/A' })
[grey]File Name:[/]               $($scriptObj.fileName ?? 'N/A')
[grey]Run As Account:[/]          $runAs
[grey]Enforce Signature Check:[/] $($scriptObj.enforceSignatureCheck ?? $false)
[grey]Run As 32-Bit:[/]           $($scriptObj.runAs32Bit ?? $false)
[grey]Created:[/]                 $(Format-InTUIDate -DateString $scriptObj.createdDateTime)
[grey]Last Modified:[/]           $(Format-InTUIDate -DateString $scriptObj.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[yellow]Script Properties[/]" -Content $propsContent -BorderColor Yellow

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

        Show-InTUIPanel -Title "[yellow]Assignments[/]" -Content $assignContent -BorderColor Yellow

        # Run state summary panel
        $runStateList = if ($runStates.value) { @($runStates.value) } else { @() }
        $succeeded = @($runStateList | Where-Object { $_.resultMessage -eq '' -or $_.errorCode -eq 0 }).Count
        $failed = @($runStateList | Where-Object { $_.errorCode -ne 0 -and $null -ne $_.errorCode }).Count
        $pending = $runStateList.Count - $succeeded - $failed

        $runSummaryContent = @"
[grey]Total Devices:[/]  [white]$($runStateList.Count)[/]
[green]Succeeded:[/]      $succeeded
[red]Failed:[/]         $failed
[yellow]Pending:[/]        $pending
"@

        Show-InTUIPanel -Title "[yellow]Run State Summary[/]" -Content $runSummaryContent -BorderColor Yellow

        $actionChoices = @(
            'View Device Run States',
            'View Script Content',
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[yellow]Script Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Device script detail action" -Context @{ ScriptId = $ScriptId; ScriptName = $scriptObj.displayName; Action = $action }

        switch ($action) {
            'View Device Run States' {
                Show-InTUIDeviceScriptRunStates -ScriptId $ScriptId -ScriptName $scriptObj.displayName
            }
            'View Script Content' {
                Show-InTUIDeviceScriptContent -ScriptId $ScriptId -ScriptName $scriptObj.displayName
            }
            'Back' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIDeviceScriptRunStates {
    <#
    .SYNOPSIS
        Displays device run states table for a device management script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptId,

        [Parameter()]
        [string]$ScriptName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Device Management Scripts', $ScriptName, 'Device Run States')

    $runStates = Show-InTUILoading -Title "[yellow]Loading device run states...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceManagementScripts/$ScriptId/deviceRunStates?`$top=50&`$expand=managedDevice(`$select=deviceName)" -Beta
    }

    if (-not $runStates.value) {
        Show-InTUIWarning "No device run state data available for this script."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($state in $runStates.value) {
        $deviceName = if ($state.managedDevice -and $state.managedDevice.deviceName) {
            $state.managedDevice.deviceName
        } else { 'N/A' }

        $stateColor = switch ($state.resultMessage) {
            { $state.errorCode -eq 0 }  { 'green' }
            { $state.errorCode -ne 0 }  { 'red' }
            default                      { 'yellow' }
        }

        $statusText = if ($state.errorCode -eq 0) { 'Succeeded' } elseif ($state.errorCode) { 'Failed' } else { 'Pending' }
        $resultMsg = if ($state.resultMessage) { $state.resultMessage.Substring(0, [Math]::Min(80, $state.resultMessage.Length)) } else { 'N/A' }

        $rows += , @(
            $deviceName,
            "[$stateColor]$statusText[/]",
            $resultMsg,
            (Format-InTUIDate -DateString $state.lastStateUpdateDateTime)
        )
    }

    Show-InTUITable -Title "Device Run States" -Columns @('Device', 'Status', 'Result Message', 'Last State Modified') -Rows $rows
    Read-InTUIKey
}

function Show-InTUIDeviceScriptContent {
    <#
    .SYNOPSIS
        Displays the decoded script content for a device management script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptId,

        [Parameter()]
        [string]$ScriptName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Device Management Scripts', $ScriptName, 'Script Content')

    $scriptObj = Show-InTUILoading -Title "[yellow]Loading script content...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceManagementScripts/$ScriptId" -Beta
    }

    if ($null -eq $scriptObj -or [string]::IsNullOrEmpty($scriptObj.scriptContent)) {
        Show-InTUIWarning "Script content not available."
        Read-InTUIKey
        return
    }

    try {
        $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($scriptObj.scriptContent))
    }
    catch {
        Show-InTUIWarning "Script content not available."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Viewing script content" -Context @{ ScriptId = $ScriptId; ScriptName = $ScriptName }

    Show-InTUIPanel -Title "[yellow]Script Content - $ScriptName[/]" -Content $decodedContent -BorderColor Yellow
    Read-InTUIKey
}

function Show-InTUIRemediationList {
    <#
    .SYNOPSIS
        Displays a list of proactive remediation (device health) scripts.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Proactive Remediations')

        $params = @{
            Uri      = '/deviceManagement/deviceHealthScripts'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime,isGlobalScript,publisher'
        }

        $remediations = Show-InTUILoading -Title "[yellow]Loading proactive remediations...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $remediations -or $remediations.Results.Count -eq 0) {
            Show-InTUIWarning "No proactive remediations found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $remediationChoices = @()
        foreach ($remediation in $remediations.Results) {
            $modified = Format-InTUIDate -DateString $remediation.lastModifiedDateTime
            $publisher = if ($remediation.publisher) { $remediation.publisher } else { 'N/A' }
            $globalScript = if ($remediation.isGlobalScript) { 'Yes' } else { 'No' }

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $remediation.displayName)[/] [grey]| $publisher | Global: $globalScript | $modified[/]"
            $remediationChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $remediationChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $remediations.TotalCount -Showing $remediations.Results.Count

        $selection = Show-InTUIMenu -Title "[yellow]Select a remediation[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $remediations.Results.Count) {
                Show-InTUIRemediationDetail -ScriptId $remediations.Results[$idx].id
            }
        }
    }
}

function Show-InTUIRemediationDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific proactive remediation script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[yellow]Loading remediation details...[/]" -ScriptBlock {
            $rem = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceHealthScripts/$ScriptId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceHealthScripts/$ScriptId/assignments" -Beta
            $runStates = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceHealthScripts/$ScriptId/deviceRunStates?`$top=200" -Beta

            @{
                Remediation = $rem
                Assignments = $assign
                RunStates   = $runStates
            }
        }

        $remediation = $detailData.Remediation
        $assignments = $detailData.Assignments
        $runStates = $detailData.RunStates

        if ($null -eq $remediation) {
            Show-InTUIError "Failed to load remediation details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Proactive Remediations', $remediation.displayName)

        $runAs = if ($remediation.runAsAccount -eq 'system') { 'System' } else { 'User' }

        $propsContent = @"
[bold white]$(ConvertTo-InTUISafeMarkup -Text $remediation.displayName)[/]

[grey]Description:[/]       $(if ($remediation.description) { $remediation.description.Substring(0, [Math]::Min(200, $remediation.description.Length)) } else { 'N/A' })
[grey]Publisher:[/]         $($remediation.publisher ?? 'N/A')
[grey]Global Script:[/]     $($remediation.isGlobalScript ?? $false)
[grey]Run As Account:[/]    $runAs
[grey]Run As 32-Bit:[/]     $($remediation.runAs32Bit ?? $false)
[grey]Created:[/]           $(Format-InTUIDate -DateString $remediation.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $remediation.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[yellow]Remediation Properties[/]" -Content $propsContent -BorderColor Yellow

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

        Show-InTUIPanel -Title "[yellow]Assignments[/]" -Content $assignContent -BorderColor Yellow

        # Run state summary panel
        $runStateList = if ($runStates.value) { @($runStates.value) } else { @() }
        $detectionSuccess = @($runStateList | Where-Object { $_.detectionState -eq 'success' }).Count
        $detectionFailed = @($runStateList | Where-Object { $_.detectionState -eq 'fail' }).Count
        $remediationSuccess = @($runStateList | Where-Object { $_.remediationState -eq 'success' }).Count
        $remediationFailed = @($runStateList | Where-Object { $_.remediationState -eq 'fail' }).Count

        $runSummaryContent = @"
[grey]Total Devices:[/]           [white]$($runStateList.Count)[/]

[bold]Detection:[/]
[green]  Succeeded:[/]             $detectionSuccess
[red]  Failed:[/]                $detectionFailed

[bold]Remediation:[/]
[green]  Succeeded:[/]             $remediationSuccess
[red]  Failed:[/]                $remediationFailed
"@

        Show-InTUIPanel -Title "[yellow]Run Summary[/]" -Content $runSummaryContent -BorderColor Yellow

        $actionChoices = @(
            'View Device Run States',
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[yellow]Remediation Actions[/]" -Choices $actionChoices

        Write-InTUILog -Message "Remediation detail action" -Context @{ ScriptId = $ScriptId; ScriptName = $remediation.displayName; Action = $action }

        switch ($action) {
            'View Device Run States' {
                Show-InTUIRemediationRunStates -ScriptId $ScriptId -ScriptName $remediation.displayName
            }
            'Back' {
                $exitDetail = $true
            }
            default {
                continue
            }
        }
    }
}

function Show-InTUIRemediationRunStates {
    <#
    .SYNOPSIS
        Displays device run states table for a proactive remediation script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptId,

        [Parameter()]
        [string]$ScriptName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Scripts & Remediations', 'Proactive Remediations', $ScriptName, 'Device Run States')

    $runStates = Show-InTUILoading -Title "[yellow]Loading device run states...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceHealthScripts/$ScriptId/deviceRunStates?`$top=50&`$expand=managedDevice(`$select=deviceName)" -Beta
    }

    if (-not $runStates.value) {
        Show-InTUIWarning "No device run state data available for this remediation."
        Read-InTUIKey
        return
    }

    $rows = @()
    foreach ($state in $runStates.value) {
        $deviceName = if ($state.managedDevice -and $state.managedDevice.deviceName) {
            $state.managedDevice.deviceName
        } else { 'N/A' }

        $detectionColor = switch ($state.detectionState) {
            'success' { 'green' }
            'fail'    { 'red' }
            default   { 'yellow' }
        }

        $remediationColor = switch ($state.remediationState) {
            'success' { 'green' }
            'fail'    { 'red' }
            default   { 'yellow' }
        }

        $detectionText = if ($state.detectionState) { $state.detectionState } else { 'N/A' }
        $remediationText = if ($state.remediationState) { $state.remediationState } else { 'N/A' }

        $rows += , @(
            $deviceName,
            "[$detectionColor]$detectionText[/]",
            "[$remediationColor]$remediationText[/]",
            (Format-InTUIDate -DateString $state.lastSyncDateTime)
        )
    }

    Show-InTUITable -Title "Device Run States" -Columns @('Device', 'Detection State', 'Remediation State', 'Last Sync') -Rows $rows
    Read-InTUIKey
}
