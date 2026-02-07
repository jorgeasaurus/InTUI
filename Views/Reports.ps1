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
            'App Install Failures',
            'License Utilization',
            'Compliance Trend Chart',
            'Enrollment Trend Chart',
            '─────────────',
            'Back to Home'
        )

        $selection = Show-InTUIMenu -Title "[DarkOrange]Reports[/]" -Choices $reportChoices

        Write-InTUILog -Message "Reports view selection" -Context @{ Selection = $selection }

        switch ($selection) {
            'Stale Devices Report' {
                Show-InTUIStaleDevicesReport
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

    $daysInput = Read-SpectreText -Message "[DarkOrange]Enter days threshold for stale devices[/]" -DefaultAnswer "30"
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

    Show-InTUIStatusBar -Total ($devices.Count ?? $devices.Results.Count) -Showing $devices.Results.Count -FilterText "Stale > $days days"

    Show-InTUITable -Title "Stale Devices Report" -Columns @('Device Name', 'OS', 'Last Sync', 'Days Since Sync', 'User', 'Compliance') -Rows $rows -BorderColor DarkOrange

    Read-InTUIKey
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

        Show-InTUIStatusBar -Total ($apps.Count ?? $apps.Results.Count) -Showing $apps.Results.Count

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

    $rows = @()
    foreach ($status in $failures) {
        $rows += , @(
            ($status.deviceName ?? 'N/A'),
            "[red]$($status.installState)[/]",
            ($status.errorCode ?? 'N/A'),
            ($status.userPrincipalName ?? 'N/A'),
            (Format-InTUIDate -DateString $status.lastSyncDateTime)
        )
    }

    Show-InTUIStatusBar -Total $failures.Count -Showing $failures.Count -FilterText "Failed installs"

    Show-InTUITable -Title "Install Failures - $AppName" -Columns @('Device', 'Status', 'Error Code', 'User', 'Last Sync') -Rows $rows -BorderColor DarkOrange

    Read-InTUIKey
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

    Show-InTUITable -Title "License Utilization" -Columns @('License', 'Total', 'Assigned', 'Available', 'Utilization %') -Rows $rows -BorderColor DarkOrange

    Read-InTUIKey
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

    Write-SpectreHost "[bold]Device Compliance Status[/]"
    Write-SpectreHost ""

    # Build chart data
    $chartData = @(
        @{ Label = "Compliant"; Value = ($data.compliantDeviceCount ?? 0); Color = "Green" }
        @{ Label = "Non-Compliant"; Value = ($data.nonCompliantDeviceCount ?? 0); Color = "Red" }
        @{ Label = "In Grace Period"; Value = ($data.inGracePeriodCount ?? 0); Color = "Yellow" }
        @{ Label = "Conflict"; Value = ($data.conflictDeviceCount ?? 0); Color = "Orange1" }
        @{ Label = "Error"; Value = ($data.errorCount ?? 0); Color = "Red3" }
        @{ Label = "Not Evaluated"; Value = ($data.notEvaluatedDeviceCount ?? 0); Color = "Grey" }
    )

    # Filter out zero values for cleaner display
    $chartData = @($chartData | Where-Object { $_.Value -gt 0 })

    if ($chartData.Count -eq 0) {
        Show-InTUIWarning "No compliance data to display."
        Read-InTUIKey
        return
    }

    # Create bar chart using PwshSpectreConsole
    $chartItems = @()
    foreach ($item in $chartData) {
        $chartItems += New-SpectreChartItem -Label $item.Label -Value $item.Value -Color $item.Color
    }

    $chartItems | Format-SpectreBarChart -Label "Compliance Distribution" -Width 60

    Write-SpectreHost ""

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

    Write-SpectreHost "[bold]Device Enrollment by Platform[/]"
    Write-SpectreHost ""

    # Build chart data
    $chartData = @(
        @{ Label = "Windows"; Value = ($osSummary.windowsCount ?? 0); Color = "Blue" }
        @{ Label = "iOS/iPadOS"; Value = ($osSummary.iosCount ?? 0); Color = "Grey" }
        @{ Label = "macOS"; Value = ($osSummary.macOSCount ?? 0); Color = "Grey54" }
        @{ Label = "Android"; Value = ($osSummary.androidCount ?? 0); Color = "Green" }
        @{ Label = "Linux"; Value = ($osSummary.linuxCount ?? 0); Color = "Yellow" }
    )

    # Filter out zero values
    $chartData = @($chartData | Where-Object { $_.Value -gt 0 })

    if ($chartData.Count -eq 0) {
        Show-InTUIWarning "No enrollment data to display."
        Read-InTUIKey
        return
    }

    # Create bar chart
    $chartItems = @()
    foreach ($item in $chartData) {
        $chartItems += New-SpectreChartItem -Label $item.Label -Value $item.Value -Color $item.Color
    }

    $chartItems | Format-SpectreBarChart -Label "Enrollment by Platform" -Width 60

    Write-SpectreHost ""

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
