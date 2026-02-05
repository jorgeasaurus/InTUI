function Show-InTUIEnrollmentView {
    <#
    .SYNOPSIS
        Displays the Enrollment management view mimicking the Intune Enrollment blade.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment')

        $choices = @(
            'Autopilot Devices',
            'Autopilot Deployment Profiles',
            'Enrollment Configurations',
            'Apple Push Certificate',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Enrollment[/]" -Choices $choices

        Write-InTUILog -Message "Enrollment view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Autopilot Devices' {
                Show-InTUIAutopilotDeviceList
            }
            'Autopilot Deployment Profiles' {
                Show-InTUIAutopilotProfileList
            }
            'Enrollment Configurations' {
                Show-InTUIEnrollmentConfigList
            }
            'Apple Push Certificate' {
                Show-InTUIApplePushCertificate
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

function Show-InTUIAutopilotDeviceList {
    <#
    .SYNOPSIS
        Displays a paginated list of Windows Autopilot device identities.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Autopilot Devices')

        $params = @{
            Uri      = '/deviceManagement/windowsAutopilotDeviceIdentities'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,serialNumber,model,manufacturer,groupTag,purchaseOrderIdentifier,enrollmentState,lastContactedDateTime'
        }

        $devices = Show-InTUILoading -Title "[steelblue1_1]Loading Autopilot devices...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $devices -or $devices.Results.Count -eq 0) {
            Show-InTUIWarning "No Autopilot devices found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $deviceChoices = @()
        foreach ($device in $devices.Results) {
            $lastContact = Format-InTUIDate -DateString $device.lastContactedDateTime
            $groupTag = if ($device.groupTag) { $device.groupTag } else { 'None' }
            $enrollState = $device.enrollmentState ?? 'Unknown'

            $displayName = "[white]$($device.serialNumber)[/] [grey]| $($device.model) | $groupTag | $enrollState | $lastContact[/]"
            $deviceChoices += $displayName
        }

        $deviceChoices += '─────────────'
        $deviceChoices += 'Back'

        Show-InTUIStatusBar -Total ($devices.Count ?? $devices.Results.Count) -Showing $devices.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select an Autopilot device[/]" -Choices $deviceChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $deviceChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $devices.Results.Count) {
                Show-InTUIAutopilotDeviceDetail -DeviceId $devices.Results[$idx].id
            }
        }
    }
}

function Show-InTUIAutopilotDeviceDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific Autopilot device identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $device = Show-InTUILoading -Title "[steelblue1_1]Loading Autopilot device details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/windowsAutopilotDeviceIdentities/$DeviceId" -Beta
        }

        if ($null -eq $device) {
            Show-InTUIError "Failed to load Autopilot device details."
            Read-InTUIKey
            return
        }

        $deviceLabel = if ($device.displayName) { $device.displayName } else { $device.serialNumber }
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Autopilot Devices', $deviceLabel)

        $propsContent = @"
[bold white]$($device.displayName ?? $device.serialNumber)[/]

[grey]Serial Number:[/]              $($device.serialNumber ?? 'N/A')
[grey]Manufacturer:[/]               $($device.manufacturer ?? 'N/A')
[grey]Model:[/]                      $($device.model ?? 'N/A')
[grey]Group Tag:[/]                  $($device.groupTag ?? 'N/A')
[grey]Purchase Order:[/]             $($device.purchaseOrderIdentifier ?? 'N/A')
[grey]Enrollment State:[/]           $($device.enrollmentState ?? 'N/A')
[grey]Addressable User Name:[/]      $($device.addressableUserName ?? 'N/A')
[grey]User Principal Name:[/]        $($device.userPrincipalName ?? 'N/A')
[grey]Azure AD Device ID:[/]         $($device.azureActiveDirectoryDeviceId ?? 'N/A')
[grey]Managed Device ID:[/]          $($device.managedDeviceId ?? 'N/A')
[grey]Last Contacted:[/]             $(Format-InTUIDate -DateString $device.lastContactedDateTime)
"@

        Show-InTUIPanel -Title "[steelblue1_1]Autopilot Device Properties[/]" -Content $propsContent -BorderColor SteelBlue1_1

        Write-InTUILog -Message "Viewing Autopilot device detail" -Context @{ DeviceId = $DeviceId; SerialNumber = $device.serialNumber }

        $actionChoices = @(
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[steelblue1_1]Actions[/]" -Choices $actionChoices

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

function Show-InTUIAutopilotProfileList {
    <#
    .SYNOPSIS
        Displays a paginated list of Windows Autopilot deployment profiles.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Autopilot Deployment Profiles')

        $params = @{
            Uri      = '/deviceManagement/windowsAutopilotDeploymentProfiles'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime'
        }

        $profiles = Show-InTUILoading -Title "[steelblue1_1]Loading Autopilot profiles...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $profiles -or $profiles.Results.Count -eq 0) {
            Show-InTUIWarning "No Autopilot deployment profiles found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $profileChoices = @()
        foreach ($profile in $profiles.Results) {
            $modified = Format-InTUIDate -DateString $profile.lastModifiedDateTime

            $displayName = "[white]$($profile.displayName)[/] [grey]| $modified[/]"
            $profileChoices += $displayName
        }

        $profileChoices += '─────────────'
        $profileChoices += 'Back'

        Show-InTUIStatusBar -Total ($profiles.Count ?? $profiles.Results.Count) -Showing $profiles.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select a profile[/]" -Choices $profileChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $profileChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $profiles.Results.Count) {
                Show-InTUIAutopilotProfileDetail -ProfileId $profiles.Results[$idx].id
            }
        }
    }
}

function Show-InTUIAutopilotProfileDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific Autopilot deployment profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId
    )

    $exitDetail = $false

    while (-not $exitDetail) {
        Clear-Host
        Show-InTUIHeader

        $detailData = Show-InTUILoading -Title "[steelblue1_1]Loading Autopilot profile details...[/]" -ScriptBlock {
            $prof = Invoke-InTUIGraphRequest -Uri "/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments" -Beta

            @{
                Profile     = $prof
                Assignments = $assign
            }
        }

        $profile = $detailData.Profile
        $assignments = $detailData.Assignments

        if ($null -eq $profile) {
            Show-InTUIError "Failed to load Autopilot profile details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Autopilot Deployment Profiles', $profile.displayName)

        $propsContent = @"
[bold white]$($profile.displayName)[/]

[grey]Description:[/]               $(if ($profile.description) { $profile.description.Substring(0, [Math]::Min(200, $profile.description.Length)) } else { 'N/A' })
"@

        $oobe = $profile.outOfBoxExperienceSettings
        if ($null -ne $oobe) {
            $propsContent += @"

[grey]Hide Privacy Settings:[/]      $($oobe.hidePrivacySettings ?? 'N/A')
[grey]Hide EULA:[/]                  $($oobe.hideEULA ?? 'N/A')
[grey]User Type:[/]                  $($oobe.userType ?? 'N/A')
[grey]Hide Escape Link:[/]           $($oobe.hideEscapeLink ?? 'N/A')
[grey]Language:[/]                    $($profile.language ?? 'N/A')
[grey]Device Name Template:[/]       $($profile.deviceNameTemplate ?? 'N/A')
"@
        }

        $propsContent += @"

[grey]Created:[/]                    $(Format-InTUIDate -DateString $profile.createdDateTime)
[grey]Last Modified:[/]              $(Format-InTUIDate -DateString $profile.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[steelblue1_1]Profile Properties[/]" -Content $propsContent -BorderColor SteelBlue1_1

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

        Show-InTUIPanel -Title "[steelblue1_1]Assignments[/]" -Content $assignContent -BorderColor SteelBlue1_1

        Write-InTUILog -Message "Viewing Autopilot profile detail" -Context @{ ProfileId = $ProfileId; ProfileName = $profile.displayName }

        $actionChoices = @(
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[steelblue1_1]Actions[/]" -Choices $actionChoices

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

function Get-InTUIEnrollmentConfigTypeFriendlyName {
    <#
    .SYNOPSIS
        Converts enrollment configuration @odata.type to a friendly name.
    #>
    param([string]$ODataType)

    switch -Wildcard ($ODataType) {
        '*deviceEnrollmentPlatformRestrictionsConfiguration'   { return 'Platform Restrictions' }
        '*deviceEnrollmentWindowsHelloForBusinessConfiguration' { return 'Windows Hello for Business' }
        '*deviceEnrollmentLimitConfiguration'                   { return 'Device Limit' }
        '*windows10EnrollmentCompletionPageConfiguration'       { return 'Enrollment Status Page' }
        '*deviceComanagementAuthorityConfiguration'             { return 'Co-management Authority' }
        '*deviceEnrollmentPlatformRestrictionConfiguration'     { return 'Platform Restriction (Single)' }
        default { return ($ODataType -replace '#microsoft\.graph\.', '') }
    }
}

function Show-InTUIEnrollmentConfigList {
    <#
    .SYNOPSIS
        Displays a paginated list of device enrollment configurations (ESP and others).
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Enrollment Configurations')

        $params = @{
            Uri      = '/deviceManagement/deviceEnrollmentConfigurations'
            Beta     = $true
            PageSize = 25
            Select   = 'id,displayName,description,lastModifiedDateTime,createdDateTime,priority'
        }

        $configs = Show-InTUILoading -Title "[steelblue1_1]Loading enrollment configurations...[/]" -ScriptBlock {
            Get-InTUIPagedResults @params
        }

        if ($null -eq $configs -or $configs.Results.Count -eq 0) {
            Show-InTUIWarning "No enrollment configurations found."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        $configChoices = @()
        foreach ($config in $configs.Results) {
            $modified = Format-InTUIDate -DateString $config.lastModifiedDateTime
            $priority = $config.priority ?? 'N/A'

            $displayName = "[white]$($config.displayName)[/] [grey]| $priority | $modified[/]"
            $configChoices += $displayName
        }

        $configChoices += '─────────────'
        $configChoices += 'Back'

        Show-InTUIStatusBar -Total ($configs.Count ?? $configs.Results.Count) -Showing $configs.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select a configuration[/]" -Choices $configChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $configChoices.IndexOf($selection)
            if ($idx -ge 0 -and $idx -lt $configs.Results.Count) {
                Show-InTUIEnrollmentConfigDetail -ConfigId $configs.Results[$idx].id
            }
        }
    }
}

function Show-InTUIEnrollmentConfigDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific enrollment configuration.
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

        $detailData = Show-InTUILoading -Title "[steelblue1_1]Loading enrollment configuration details...[/]" -ScriptBlock {
            $conf = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceEnrollmentConfigurations/$ConfigId" -Beta
            $assign = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceEnrollmentConfigurations/$ConfigId/assignments" -Beta

            @{
                Config      = $conf
                Assignments = $assign
            }
        }

        $config = $detailData.Config
        $assignments = $detailData.Assignments

        if ($null -eq $config) {
            Show-InTUIError "Failed to load enrollment configuration details."
            Read-InTUIKey
            return
        }

        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Enrollment Configurations', $config.displayName)

        $friendlyType = Get-InTUIEnrollmentConfigTypeFriendlyName -ODataType $config.'@odata.type'

        $propsContent = @"
[bold white]$($config.displayName)[/]

[grey]Type:[/]              $friendlyType
[grey]Description:[/]       $(if ($config.description) { $config.description.Substring(0, [Math]::Min(200, $config.description.Length)) } else { 'N/A' })
[grey]Priority:[/]          $($config.priority ?? 'N/A')
[grey]Created:[/]           $(Format-InTUIDate -DateString $config.createdDateTime)
[grey]Last Modified:[/]     $(Format-InTUIDate -DateString $config.lastModifiedDateTime)
"@

        Show-InTUIPanel -Title "[steelblue1_1]Configuration Properties[/]" -Content $propsContent -BorderColor SteelBlue1_1

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

        Show-InTUIPanel -Title "[steelblue1_1]Assignments[/]" -Content $assignContent -BorderColor SteelBlue1_1

        Write-InTUILog -Message "Viewing enrollment configuration detail" -Context @{ ConfigId = $ConfigId; ConfigName = $config.displayName }

        $actionChoices = @(
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[steelblue1_1]Actions[/]" -Choices $actionChoices

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

function Show-InTUIApplePushCertificate {
    <#
    .SYNOPSIS
        Displays the Apple Push Notification Certificate details.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Apple Push Certificate')

    Write-InTUILog -Message "Loading Apple Push Certificate"

    $cert = Show-InTUILoading -Title "[steelblue1_1]Loading Apple Push Certificate...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri '/deviceManagement/applePushNotificationCertificate' -Beta
    }

    if ($null -eq $cert) {
        Show-InTUIWarning "No Apple Push Certificate configured."
        Read-InTUIKey
        return
    }

    # Check expiration proximity
    $expirationDisplay = Format-InTUIDate -DateString $cert.expirationDateTime
    $expirationWarning = $false
    if ($cert.expirationDateTime) {
        try {
            $expDate = [DateTime]::Parse($cert.expirationDateTime)
            $daysUntilExpiry = ($expDate - [DateTime]::UtcNow).TotalDays
            if ($daysUntilExpiry -le 30) {
                $expirationDisplay = "[red]$expirationDisplay (EXPIRES in $([math]::Floor($daysUntilExpiry)) days!)[/]"
                $expirationWarning = $true
            }
        }
        catch {
            # Use default display if parsing fails
        }
    }

    $propsContent = @"
[bold white]Apple Push Notification Certificate[/]

[grey]Apple Identifier:[/]           $($cert.appleIdentifier ?? 'N/A')
[grey]Topic Identifier:[/]           $($cert.topicIdentifier ?? 'N/A')
[grey]Last Modified:[/]              $(Format-InTUIDate -DateString $cert.lastModifiedDateTime)
[grey]Expiration:[/]                 $expirationDisplay
[grey]Certificate Upload Status:[/]  $($cert.certificateUploadStatus ?? 'N/A')
"@

    Show-InTUIPanel -Title "[steelblue1_1]Apple Push Certificate[/]" -Content $propsContent -BorderColor SteelBlue1_1

    if ($expirationWarning) {
        Write-SpectreHost "[red]WARNING: Apple Push Certificate is expiring soon. Renew immediately to avoid enrollment issues.[/]"
        Write-SpectreHost ""
    }

    Write-InTUILog -Message "Viewed Apple Push Certificate" -Context @{
        AppleIdentifier = $cert.appleIdentifier
        Expiration = $cert.expirationDateTime
        ExpirationWarning = $expirationWarning
    }

    Read-InTUIKey
}
