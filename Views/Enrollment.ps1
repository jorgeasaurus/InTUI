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
            'Deployment Monitor',
            'Enrollment Configurations',
            'Apple Push Certificate',
            'Apple DEP/ABM Tokens',
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
            'Deployment Monitor' {
                Show-InTUIAutopilotMonitor
            }
            'Enrollment Configurations' {
                Show-InTUIEnrollmentConfigList
            }
            'Apple Push Certificate' {
                Show-InTUIApplePushCertificate
            }
            'Apple DEP/ABM Tokens' {
                Show-InTUIAppleDEPTokens
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

        $choiceMap = Get-InTUIChoiceMap -Choices $deviceChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $devices.TotalCount -Showing $devices.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select an Autopilot device[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $devices.Results.Count) {
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

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $profile.displayName)[/] [grey]| $modified[/]"
            $profileChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $profileChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $profiles.TotalCount -Showing $profiles.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select a profile[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $profiles.Results.Count) {
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
[bold white]$(ConvertTo-InTUISafeMarkup -Text $profile.displayName)[/]

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

            $displayName = "[white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/] [grey]| $priority | $modified[/]"
            $configChoices += $displayName
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $configChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $configs.TotalCount -Showing $configs.Results.Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select a configuration[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitList = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $configs.Results.Count) {
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
[bold white]$(ConvertTo-InTUISafeMarkup -Text $config.displayName)[/]

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
        Write-InTUIText "[red]WARNING: Apple Push Certificate is expiring soon. Renew immediately to avoid enrollment issues.[/]"
        Write-InTUIText ""
    }

    Write-InTUILog -Message "Viewed Apple Push Certificate" -Context @{
        AppleIdentifier = $cert.appleIdentifier
        Expiration = $cert.expirationDateTime
        ExpirationWarning = $expirationWarning
    }

    Read-InTUIKey
}

function Show-InTUIAppleDEPTokens {
    <#
    .SYNOPSIS
        Displays Apple DEP/ABM enrollment program tokens.
    #>
    [CmdletBinding()]
    param()

    $exitList = $false

    while (-not $exitList) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Apple DEP/ABM Tokens')

        $tokens = Show-InTUILoading -Title "[steelblue1_1]Loading DEP/ABM tokens...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri '/deviceManagement/depOnboardingSettings' -Beta
        }

        if (-not $tokens.value) {
            Show-InTUIWarning "No Apple DEP/ABM tokens configured."
            Read-InTUIKey
            $exitList = $true
            continue
        }

        Write-InTUILog -Message "DEP tokens loaded" -Context @{ Count = @($tokens.value).Count }

        $tokenChoices = @()
        foreach ($token in $tokens.value) {
            $expiration = if ($token.tokenExpirationDateTime) {
                try {
                    $expDate = [DateTime]::Parse($token.tokenExpirationDateTime)
                    $daysUntil = ($expDate - [DateTime]::UtcNow).TotalDays

                    if ($daysUntil -le 30) {
                        "[red]Expires: $(Format-InTUIDate -DateString $token.tokenExpirationDateTime)[/]"
                    }
                    elseif ($daysUntil -le 60) {
                        "[yellow]Expires: $(Format-InTUIDate -DateString $token.tokenExpirationDateTime)[/]"
                    }
                    else {
                        "[green]Expires: $(Format-InTUIDate -DateString $token.tokenExpirationDateTime)[/]"
                    }
                }
                catch {
                    "Expires: $(Format-InTUIDate -DateString $token.tokenExpirationDateTime)"
                }
            }
            else {
                "[grey]No expiration[/]"
            }

            $tokenName = $token.tokenName ?? $token.appleIdentifier ?? 'Unknown Token'
            $tokenChoices += "[white]$tokenName[/] [grey]| $expiration[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $tokenChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Sync All Tokens' + 'Back')

        Show-InTUIStatusBar -Total @($tokens.value).Count -Showing @($tokens.value).Count

        $selection = Show-InTUIMenu -Title "[steelblue1_1]Select a DEP/ABM token[/]" -Choices $menuChoices

        switch ($selection) {
            'Back' {
                $exitList = $true
            }
            'Sync All Tokens' {
                Invoke-InTUIDEPSync
            }
            '─────────────' {
                continue
            }
            default {
                $idx = $choiceMap.IndexMap[$selection]
                if ($null -ne $idx -and $idx -lt @($tokens.value).Count) {
                    Show-InTUIAppleDEPTokenDetail -TokenId @($tokens.value)[$idx].id
                }
            }
        }
    }
}

function Show-InTUIAppleDEPTokenDetail {
    <#
    .SYNOPSIS
        Displays detailed information about a specific DEP/ABM token.
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

        $token = Show-InTUILoading -Title "[steelblue1_1]Loading token details...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/depOnboardingSettings/$TokenId" -Beta
        }

        if ($null -eq $token) {
            Show-InTUIError "Failed to load DEP/ABM token details."
            Read-InTUIKey
            return
        }

        $tokenName = $token.tokenName ?? $token.appleIdentifier ?? 'DEP Token'
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Apple DEP/ABM Tokens', $tokenName)

        # Check expiration
        $expirationDisplay = Format-InTUIDate -DateString $token.tokenExpirationDateTime
        $expirationWarning = $false
        if ($token.tokenExpirationDateTime) {
            try {
                $expDate = [DateTime]::Parse($token.tokenExpirationDateTime)
                $daysUntil = ($expDate - [DateTime]::UtcNow).TotalDays

                if ($daysUntil -le 30) {
                    $expirationDisplay = "[red]$expirationDisplay (EXPIRES in $([math]::Floor($daysUntil)) days!)[/]"
                    $expirationWarning = $true
                }
                elseif ($daysUntil -le 60) {
                    $expirationDisplay = "[yellow]$expirationDisplay ($([math]::Floor($daysUntil)) days remaining)[/]"
                }
                else {
                    $expirationDisplay = "[green]$expirationDisplay ($([math]::Floor($daysUntil)) days remaining)[/]"
                }
            }
            catch {
                # Use default display
            }
        }

        $tokenType = switch ($token.tokenType) {
            'dep'    { 'Device Enrollment Program (DEP)' }
            'appleSchoolManager' { 'Apple School Manager' }
            'appleBusinessManager' { 'Apple Business Manager' }
            default  { $token.tokenType ?? 'Unknown' }
        }

        $propsContent = @"
[bold white]$tokenName[/]

[grey]Token Type:[/]              $tokenType
[grey]Apple Identifier:[/]        $($token.appleIdentifier ?? 'N/A')
[grey]Token Name:[/]              $($token.tokenName ?? 'N/A')
[grey]Token Expiration:[/]        $expirationDisplay
[grey]Last Modified:[/]           $(Format-InTUIDate -DateString $token.lastModifiedDateTime)
[grey]Last Successful Sync:[/]    $(Format-InTUIDate -DateString $token.lastSuccessfulSyncDateTime)
[grey]Last Sync Error:[/]         $(Format-InTUIDate -DateString $token.lastSyncErrorCode)
[grey]Sync Triggered By:[/]       $($token.lastSyncTriggeredDateTime ?? 'N/A')
[grey]Data Sharing Consent:[/]    $($token.dataSharingConsentGranted ?? $false)
"@

        Show-InTUIPanel -Title "[steelblue1_1]DEP/ABM Token Properties[/]" -Content $propsContent -BorderColor SteelBlue1_1

        if ($expirationWarning) {
            Write-InTUIText "[red]WARNING: This token is expiring soon. Renew in Apple Business/School Manager.[/]"
            Write-InTUIText ""
        }

        # Enrollment profiles linked to this token
        $profilesContent = "[grey]View linked enrollment profiles in Autopilot Deployment Profiles[/]"
        Show-InTUIPanel -Title "[steelblue1_1]Enrollment Profiles[/]" -Content $profilesContent -BorderColor SteelBlue1_1

        Write-InTUILog -Message "Viewed DEP token detail" -Context @{
            TokenId = $TokenId
            TokenName = $tokenName
            ExpirationWarning = $expirationWarning
        }

        $actionChoices = @(
            'Sync This Token',
            '─────────────',
            'Back'
        )

        $action = Show-InTUIMenu -Title "[steelblue1_1]Actions[/]" -Choices $actionChoices

        switch ($action) {
            'Sync This Token' {
                Invoke-InTUIDEPSync -TokenId $TokenId
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

function Invoke-InTUIDEPSync {
    <#
    .SYNOPSIS
        Triggers a sync for DEP/ABM tokens.
    .PARAMETER TokenId
        Optional specific token ID to sync. If not provided, syncs all tokens.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TokenId
    )

    $confirm = Show-InTUIConfirm -Message "[yellow]Sync DEP/ABM devices from Apple?[/]"

    if (-not $confirm) {
        return
    }

    if ($TokenId) {
        Write-InTUILog -Message "Syncing specific DEP token" -Context @{ TokenId = $TokenId }

        $result = Show-InTUILoading -Title "[steelblue1_1]Syncing DEP token...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri "/deviceManagement/depOnboardingSettings/$TokenId/syncWithAppleDeviceEnrollmentProgram" -Method POST -Beta
        }

        if ($null -ne $result) {
            Show-InTUISuccess "DEP sync initiated successfully."
        }
        else {
            Show-InTUIError "Failed to initiate DEP sync."
        }
    }
    else {
        # Sync all tokens
        Write-InTUILog -Message "Syncing all DEP tokens"

        $tokens = Show-InTUILoading -Title "[steelblue1_1]Loading tokens...[/]" -ScriptBlock {
            Invoke-InTUIGraphRequest -Uri '/deviceManagement/depOnboardingSettings' -Beta
        }

        if (-not $tokens.value) {
            Show-InTUIWarning "No DEP tokens found to sync."
            Read-InTUIKey
            return
        }

        $successCount = 0
        $failCount = 0

        foreach ($token in $tokens.value) {
            $result = Invoke-InTUIGraphRequest -Uri "/deviceManagement/depOnboardingSettings/$($token.id)/syncWithAppleDeviceEnrollmentProgram" -Method POST -Beta

            if ($null -ne $result) {
                $successCount++
            }
            else {
                $failCount++
            }
        }

        Write-InTUILog -Message "DEP sync completed" -Context @{ Success = $successCount; Failed = $failCount }

        if ($failCount -eq 0) {
            Show-InTUISuccess "Sync initiated for $successCount token(s)."
        }
        else {
            Show-InTUIWarning "Sync initiated for $successCount token(s), $failCount failed."
        }
    }

    Read-InTUIKey
}

function Show-InTUIAutopilotMonitor {
    <#
    .SYNOPSIS
        Auto-refreshing monitor for tracking an Autopilot deployment by serial number.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Deployment Monitor')

    $serial = Read-InTUITextInput -Message "[steelblue1_1]Enter device serial number[/]"
    if ([string]::IsNullOrWhiteSpace($serial)) { return }

    $safeSerial = ConvertTo-InTUISafeFilterValue -Value $serial.Trim()

    Write-InTUILog -Message "Starting Autopilot deployment monitor" -Context @{ SerialNumber = $safeSerial }

    $refreshInterval = $script:InTUIConfig.RefreshInterval
    $exitMonitor = $false

    while (-not $exitMonitor) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Enrollment', 'Deployment Monitor', $safeSerial)

        # Fetch Autopilot identity
        $autopilot = Invoke-InTUIGraphRequest -Uri "/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$safeSerial')" -Beta

        $apDevice = if ($autopilot.value) { @($autopilot.value)[0] } else { $null }

        # Fetch managed device
        $managed = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=serialNumber eq '$safeSerial'" -Beta
        $mgDevice = if ($managed.value) { @($managed.value)[0] } else { $null }

        # Determine enrollment state and progress
        $enrollState = $apDevice.enrollmentState ?? 'notFound'
        $progressPct = switch ($enrollState) {
            'notRegistered' { 0 }
            'registered'    { 25 }
            'enrolling'     { 50 }
            'enrolled'      { 75 }
            default         { 0 }
        }

        if ($mgDevice -and $mgDevice.complianceState -eq 'compliant') {
            $progressPct = 100
        }

        $progressBar = Get-InTUIProgressBar -Percentage $progressPct -Width 30

        # Build status panel
        $statusContent = @"
[bold white]Serial Number:[/]     $safeSerial
"@

        if ($apDevice) {
            $statusContent += @"

[grey]Model:[/]              $($apDevice.model ?? 'N/A')
[grey]Manufacturer:[/]       $($apDevice.manufacturer ?? 'N/A')
[grey]Group Tag:[/]          $($apDevice.groupTag ?? 'N/A')
[grey]Enrollment State:[/]   [white]$enrollState[/]
[grey]Deployment Profile:[/] $($apDevice.deploymentProfileAssignmentStatus ?? 'N/A')
[grey]Last Contact:[/]       $(Format-InTUIDate -DateString $apDevice.lastContactedDateTime)
"@
        }
        else {
            $statusContent += "`n[yellow]No Autopilot identity found for this serial number.[/]"
        }

        if ($mgDevice) {
            $compColor = Get-InTUIComplianceColor -State $mgDevice.complianceState
            $statusContent += @"

[bold]Managed Device Info[/]
[grey]Device Name:[/]        $($mgDevice.deviceName ?? 'N/A')
[grey]Compliance:[/]         [$compColor]$($mgDevice.complianceState ?? 'N/A')[/]
[grey]Last Sync:[/]          $(Format-InTUIDate -DateString $mgDevice.lastSyncDateTime)
[grey]OS Version:[/]         $($mgDevice.osVersion ?? 'N/A')
"@
        }

        $statusContent += @"

[bold]Progress:[/] $progressBar [white]$progressPct%[/]
"@

        Show-InTUIPanel -Title "[steelblue1_1]Autopilot Deployment Status[/]" -Content $statusContent -BorderColor SteelBlue1_1

        Write-InTUIText "[grey]Auto-refresh in ${refreshInterval}s | Q to quit[/]"

        # Wait loop with key check
        $elapsed = 0
        while ($elapsed -lt $refreshInterval) {
            Start-Sleep -Seconds 1
            $elapsed++

            if ([Console]::KeyAvailable) {
                $keyInfo = [Console]::ReadKey($true)
                if ($keyInfo.KeyChar -eq 'q' -or $keyInfo.KeyChar -eq 'Q') {
                    $exitMonitor = $true
                    break
                }
            }
        }
    }
}
