function Show-InTUIReportsView {
    <#
    .SYNOPSIS
        Displays the Reports view with stale devices, app install failures, and license utilization.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Reports')

        $reportChoices = @(
            'Stale Devices Report',
            'Stale Users Report',
            'App Install Failures',
            'License Utilization',
            'Compliance Trend Chart',
            'Enrollment Trend Chart',
            '-------------',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[DarkOrange]Reports[/]" -Choices $reportChoices

        Write-InTUILog -Message "Reports view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Stale Devices Report' {
                Show-InTUIStaleDevicesReport
            }
            'Stale Users Report' {
                Show-InTUIStaleUsersReport
            }
            'App Install Failures' {
                Show-InTUIAppInstallFailures
            }
            'License Utilization' {
                Show-InTUILicenseUtilization
            }
            'Compliance Trend Chart' {
                Show-InTUIComplianceTrendChart
            }
            'Enrollment Trend Chart' {
                Show-InTUIEnrollmentTrendChart
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

function Show-InTUIStaleDevicesReport {
    <#
    .SYNOPSIS
        Displays a report of devices that have not synced within a specified number of days.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'Stale Devices')

    $daysInput = Read-InTUITextInput -Message "[DarkOrange]Enter days threshold for stale devices[/]" -DefaultAnswer "30"
    $days = 30
    if ($daysInput -match '^\d+$') {
        $days = [int]$daysInput
    }

    Write-InTUILog -Message "Running stale devices report" -Context @{ DaysThreshold = $days }

    $cutoff = [DateTime]::UtcNow.AddDays(-$days).ToString('yyyy-MM-ddTHH:mm:ssZ')

    $devices = Show-InTUILoading -Title "[DarkOrange]Loading stale devices...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceManagement/managedDevices' -Beta -PageSize 50 `
            -Filter "lastSyncDateTime le $cutoff" `
            -Select 'id,deviceName,operatingSystem,lastSyncDateTime,userPrincipalName,complianceState,managedDeviceOwnerType'
    }

    if ($null -eq $devices -or $devices.Results.Count -eq 0) {
        Show-InTUIWarning "No stale devices found (threshold: $days days)."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Stale devices found" -Context @{ Count = $devices.Results.Count; DaysThreshold = $days }

    $rows = @()
    foreach ($device in $devices.Results) {
        $daysSinceSync = ([DateTime]::UtcNow - [DateTime]::Parse($device.lastSyncDateTime)).Days
        $lastSync = Format-InTUIDate -DateString $device.lastSyncDateTime

        $compColor = switch ($device.complianceState) {
            'compliant'    { 'green' }
            'noncompliant' { 'red' }
            default        { 'yellow' }
        }

        $user = if ($device.userPrincipalName) { $device.userPrincipalName } else { 'Unassigned' }

        $rows += , @(
            $device.deviceName,
            ($device.operatingSystem ?? 'N/A'),
            $lastSync,
            "$daysSinceSync",
            $user,
            "[$compColor]$($device.complianceState)[/]"
        )
    }

    Show-InTUIStatusBar -Total $devices.TotalCount -Showing $devices.Results.Count -FilterText "Stale > $days days"

    Show-InTUISortableTable -Title "Stale Devices Report" -Columns @('Device Name', 'OS', 'Last Sync', 'Days Since Sync', 'User', 'Compliance') -Rows $rows -BorderColor DarkOrange
}

function Show-InTUIAppInstallFailures {
    <#
    .SYNOPSIS
        Displays app install failure report by letting the user select an app and viewing failed device statuses.
    #>
    [CmdletBinding()]
    param()

    $exitReport = $false

    while (-not $exitReport) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'App Install Failures')

        Write-InTUILog -Message "Loading apps for install failure report"

        $apps = Show-InTUILoading -Title "[DarkOrange]Loading apps...[/]" -ScriptBlock {
            Get-InTUIPagedResults -Uri '/deviceAppManagement/mobileApps' -Beta -PageSize 50 `
                -Select 'id,displayName'
        }

        if ($null -eq $apps -or $apps.Results.Count -eq 0) {
            Show-InTUIWarning "No apps found."
            Read-InTUIKey
            $exitReport = $true
            continue
        }

        $appChoices = @()
        foreach ($app in $apps.Results) {
            $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
            $appChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text $app.displayName)[/] [grey]| $appType[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $appChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        Show-InTUIStatusBar -Total $apps.TotalCount -Showing $apps.Results.Count

        $selection = Show-InTUIMenu -Title "[DarkOrange]Select an app to check failures[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitReport = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $apps.Results.Count) {
                $selectedApp = $apps.Results[$idx]
                Show-InTUIAppFailureDetail -AppId $selectedApp.id -AppName $selectedApp.displayName
            }
        }
    }
}

function Show-InTUIAppFailureDetail {
    <#
    .SYNOPSIS
        Displays failed device install statuses for a specific app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$AppName
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'App Install Failures', $AppName)

    Write-InTUILog -Message "Loading install failures for app" -Context @{ AppId = $AppId; AppName = $AppName }

    $statuses = Show-InTUILoading -Title "[DarkOrange]Loading device statuses for $AppName...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/deviceStatuses?`$top=50" -Beta
    }

    if (-not $statuses.value) {
        Show-InTUISuccess "No install status data available for this app."
        Read-InTUIKey
        return
    }

    $failures = @($statuses.value | Where-Object { $_.installState -eq 'failed' })

    if ($failures.Count -eq 0) {
        Show-InTUISuccess "No install failures for this app."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "App install failures found" -Context @{ AppName = $AppName; FailureCount = $failures.Count }

    $exitDrillDown = $false

    while (-not $exitDrillDown) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'App Install Failures', $AppName)

        $rows = @()
        $failureChoices = @()
        foreach ($status in $failures) {
            $rows += , @(
                ($status.deviceName ?? 'N/A'),
                "[red]$($status.installState)[/]",
                ($status.errorCode ?? 'N/A'),
                ($status.userPrincipalName ?? 'N/A'),
                (Format-InTUIDate -DateString $status.lastSyncDateTime)
            )
            $errorHex = if ($status.errorCode) {
                '0x{0:X8}' -f [int64]$status.errorCode
            } else { 'N/A' }
            $failureChoices += "[white]$(ConvertTo-InTUISafeMarkup -Text ($status.deviceName ?? 'N/A'))[/] [grey]| $errorHex[/]"
        }

        Show-InTUIStatusBar -Total $failures.Count -Showing $failures.Count -FilterText "Failed installs"

        Render-InTUITable -Title "Install Failures - $AppName" -Columns @('Device', 'Status', 'Error Code', 'User', 'Last Sync') -Rows $rows -BorderColor DarkOrange

        $choiceMap = Get-InTUIChoiceMap -Choices $failureChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

        $selection = Show-InTUIMenu -Title "[DarkOrange]Select a failure for details[/]" -Choices $menuChoices

        if ($selection -eq 'Back') {
            $exitDrillDown = $true
        }
        elseif ($selection -ne '─────────────') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $failures.Count) {
                $failureStatus = $failures[$idx]
                $errorHex = if ($failureStatus.errorCode) {
                    '0x{0:X8}' -f [int64]$failureStatus.errorCode
                } else { 'N/A' }

                $errorInfo = Get-InTUIErrorCodeInfo -ErrorCode $errorHex

                Clear-Host
                Show-InTUIHeader
                Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'App Install Failures', $AppName, ($failureStatus.deviceName ?? 'N/A'))

                if ($errorInfo) {
                    $drillContent = @"
[bold white]Error Code:[/]   $errorHex
[grey]Description:[/]  [white]$($errorInfo.Description)[/]
[grey]Category:[/]     [yellow]$($errorInfo.Category)[/]

[bold]Remediation:[/]
[green]$($errorInfo.Remediation)[/]

[grey]Device:[/]       $($failureStatus.deviceName ?? 'N/A')
[grey]User:[/]         $($failureStatus.userPrincipalName ?? 'N/A')
[grey]Last Sync:[/]    $(Format-InTUIDate -DateString $failureStatus.lastSyncDateTime)
"@
                }
                else {
                    $drillContent = @"
[bold white]Error Code:[/]   $errorHex
[yellow]Unknown error code.[/]

Check Microsoft Intune troubleshooting docs for this error code.
Review IME logs on the device: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs

[grey]Device:[/]       $($failureStatus.deviceName ?? 'N/A')
[grey]User:[/]         $($failureStatus.userPrincipalName ?? 'N/A')
[grey]Last Sync:[/]    $(Format-InTUIDate -DateString $failureStatus.lastSyncDateTime)
"@
                }

                Show-InTUIPanel -Title "[DarkOrange]Error Details[/]" -Content $drillContent -BorderColor DarkOrange
                Read-InTUIKey
            }
        }
    }
}

function Show-InTUILicenseUtilization {
    <#
    .SYNOPSIS
        Displays license utilization report showing assigned vs available licenses per SKU.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'License Utilization')

    Write-InTUILog -Message "Loading license utilization data"

    $response = Show-InTUILoading -Title "[DarkOrange]Loading license data...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri '/subscribedSkus'
    }

    if ($null -eq $response -or -not $response.value) {
        Show-InTUIWarning "No license data available."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "License data loaded" -Context @{ SKUCount = @($response.value).Count }

    $rows = @()
    foreach ($sku in $response.value) {
        $skuName = $sku.skuPartNumber
        $total = $sku.prepaidUnits.enabled
        $consumed = $sku.consumedUnits
        $available = $total - $consumed

        if ($total -gt 0) {
            $utilization = [math]::Round(($consumed / $total) * 100, 1)
        }
        else {
            $utilization = 0
        }

        $utilColor = if ($utilization -gt 90) { 'red' }
                     elseif ($utilization -gt 70) { 'yellow' }
                     else { 'green' }

        $rows += , @(
            $skuName,
            "$total",
            "$consumed",
            "$available",
            "[$utilColor]$utilization%[/]"
        )
    }

    Show-InTUISortableTable -Title "License Utilization" -Columns @('License', 'Total', 'Assigned', 'Available', 'Utilization %') -Rows $rows -BorderColor DarkOrange
}

function Show-InTUIComplianceTrendChart {
    <#
    .SYNOPSIS
        Displays a bar chart of device compliance states.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'Compliance Trend Chart')

    Write-InTUILog -Message "Loading compliance chart data"

    $data = Show-InTUILoading -Title "[DarkOrange]Loading compliance data...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta
    }

    if ($null -eq $data) {
        Show-InTUIWarning "Could not load compliance data."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Compliance chart data loaded" -Context @{
        Compliant = $data.compliantDeviceCount
        NonCompliant = $data.nonCompliantDeviceCount
    }

    # Build chart data
    $chartData = @(
        @{ Label = "Compliant"; Value = ($data.compliantDeviceCount ?? 0); Color = "green" }
        @{ Label = "Non-Compliant"; Value = ($data.nonCompliantDeviceCount ?? 0); Color = "red" }
        @{ Label = "In Grace Period"; Value = ($data.inGracePeriodCount ?? 0); Color = "yellow" }
        @{ Label = "Conflict"; Value = ($data.conflictDeviceCount ?? 0); Color = "orange" }
        @{ Label = "Error"; Value = ($data.errorCount ?? 0); Color = "red" }
        @{ Label = "Not Evaluated"; Value = ($data.notEvaluatedDeviceCount ?? 0); Color = "grey" }
    )

    # Filter out zero values for cleaner display
    $chartData = @($chartData | Where-Object { $_.Value -gt 0 })

    if ($chartData.Count -eq 0) {
        Show-InTUIWarning "No compliance data to display."
        Read-InTUIKey
        return
    }

    Render-InTUIBarChart -Title "Compliance Distribution" -Items $chartData

    # Summary table
    $total = ($data.compliantDeviceCount ?? 0) + ($data.nonCompliantDeviceCount ?? 0) +
             ($data.inGracePeriodCount ?? 0) + ($data.conflictDeviceCount ?? 0) +
             ($data.errorCount ?? 0) + ($data.notEvaluatedDeviceCount ?? 0)

    $complianceRate = if ($total -gt 0) {
        [math]::Round((($data.compliantDeviceCount ?? 0) / $total) * 100, 1)
    } else { 0 }

    $summaryContent = @"
[grey]Total Devices:[/]        [white]$total[/]
[grey]Compliance Rate:[/]      [white]$complianceRate%[/]
[grey]Compliant:[/]            [green]$($data.compliantDeviceCount ?? 0)[/]
[grey]Non-Compliant:[/]        [red]$($data.nonCompliantDeviceCount ?? 0)[/]
"@

    Show-InTUIPanel -Title "[DarkOrange]Summary[/]" -Content $summaryContent -BorderColor DarkOrange

    Read-InTUIKey
}

function Show-InTUIEnrollmentTrendChart {
    <#
    .SYNOPSIS
        Displays a bar chart of device enrollment by OS platform.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'Enrollment Trend Chart')

    Write-InTUILog -Message "Loading enrollment chart data"

    $data = Show-InTUILoading -Title "[DarkOrange]Loading enrollment data...[/]" -ScriptBlock {
        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDeviceOverview' -Beta
    }

    if ($null -eq $data -or $null -eq $data.deviceOperatingSystemSummary) {
        Show-InTUIWarning "Could not load enrollment data."
        Read-InTUIKey
        return
    }

    $osSummary = $data.deviceOperatingSystemSummary

    Write-InTUILog -Message "Enrollment chart data loaded" -Context @{
        Windows = $osSummary.windowsCount
        iOS = $osSummary.iosCount
        macOS = $osSummary.macOSCount
        Android = $osSummary.androidCount
    }

    # Build chart data
    $chartData = @(
        @{ Label = "Windows"; Value = ($osSummary.windowsCount ?? 0); Color = "blue" }
        @{ Label = "iOS/iPadOS"; Value = ($osSummary.iosCount ?? 0); Color = "grey" }
        @{ Label = "macOS"; Value = ($osSummary.macOSCount ?? 0); Color = "grey" }
        @{ Label = "Android"; Value = ($osSummary.androidCount ?? 0); Color = "green" }
        @{ Label = "Linux"; Value = ($osSummary.linuxCount ?? 0); Color = "yellow" }
    )

    # Filter out zero values
    $chartData = @($chartData | Where-Object { $_.Value -gt 0 })

    if ($chartData.Count -eq 0) {
        Show-InTUIWarning "No enrollment data to display."
        Read-InTUIKey
        return
    }

    Render-InTUIBarChart -Title "Enrollment by Platform" -Items $chartData

    # Summary table
    $total = $data.enrolledDeviceCount ?? 0

    $summaryContent = @"
[grey]Total Enrolled:[/]       [white]$total[/]
[grey]MDM Enrolled:[/]         [white]$($data.mdmEnrolledCount ?? 0)[/]
[grey]Dual Enrolled:[/]        [white]$($data.dualEnrolledDeviceCount ?? 0)[/]

[bold]By Platform:[/]
[blue]Windows:[/]              $($osSummary.windowsCount ?? 0)
[grey]iOS/iPadOS:[/]           $($osSummary.iosCount ?? 0)
[grey]macOS:[/]                $($osSummary.macOSCount ?? 0)
[green]Android:[/]              $($osSummary.androidCount ?? 0)
[yellow]Linux:[/]                $($osSummary.linuxCount ?? 0)
"@

    Show-InTUIPanel -Title "[DarkOrange]Enrollment Summary[/]" -Content $summaryContent -BorderColor DarkOrange

    Read-InTUIKey
}

function Show-InTUIStaleUsersReport {
    <#
    .SYNOPSIS
        Displays a report of users who have not signed in within a specified number of days.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Reports', 'Stale Users')

    $daysInput = Read-InTUITextInput -Message "[DarkOrange]Enter days threshold for stale users[/]" -DefaultAnswer "90"
    $days = 90
    if ($daysInput -match '^\d+$') {
        $days = [int]$daysInput
    }

    Write-InTUILog -Message "Running stale users report" -Context @{ DaysThreshold = $days }

    $cutoff = [DateTime]::UtcNow.AddDays(-$days).ToString('yyyy-MM-ddTHH:mm:ssZ')

    $users = Show-InTUILoading -Title "[DarkOrange]Loading stale users...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/users' -PageSize 50 `
            -Filter "signInActivity/lastSignInDateTime le $cutoff" `
            -Select 'id,displayName,userPrincipalName,signInActivity,assignedLicenses' `
            -Headers @{ ConsistencyLevel = 'eventual' } `
            -IncludeCount
    }

    if ($null -eq $users -or $users.Results.Count -eq 0) {
        Show-InTUIWarning "No stale users found (threshold: $days days)."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Stale users found" -Context @{ Count = $users.Results.Count; DaysThreshold = $days }

    $rows = @()
    foreach ($user in $users.Results) {
        $lastSignIn = $user.signInActivity.lastSignInDateTime
        $daysSince = if ($lastSignIn) {
            ([DateTime]::UtcNow - [DateTime]::Parse($lastSignIn)).Days
        } else { 'Never' }

        $formattedDate = Format-InTUIDate -DateString $lastSignIn
        $licenseCount = if ($user.assignedLicenses) { @($user.assignedLicenses).Count } else { 0 }

        $rows += , @(
            ($user.displayName ?? 'N/A'),
            ($user.userPrincipalName ?? 'N/A'),
            $formattedDate,
            "$daysSince",
            "$licenseCount"
        )
    }

    Show-InTUIStatusBar -Total $users.TotalCount -Showing $users.Results.Count -FilterText "Stale > $days days"

    Show-InTUISortableTable -Title "Stale Users Report" -Columns @('Display Name', 'UPN', 'Last Sign-In', 'Days Since', 'Licenses') -Rows $rows -BorderColor DarkOrange
}
