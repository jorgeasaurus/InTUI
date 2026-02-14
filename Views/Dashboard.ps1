function Show-InTUIDashboard {
    <#
    .SYNOPSIS
        Displays the main dashboard with summary counts and status overview.
    #>
    [CmdletBinding()]
    param()

    Write-InTUILog -Message "Loading dashboard data"

    $dashData = Show-InTUILoading -Title "[blue]Loading dashboard data...[/]" -ScriptBlock {
        $countHeaders = @{ ConsistencyLevel = 'eventual' }
        $devices = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
        $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Headers $countHeaders
        $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Headers $countHeaders

        # mobileApps doesn't support $count properly, so fetch all IDs to count
        $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$select=id' -Beta -All

        $compliance = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta

        @{
            DeviceCount       = $devices.'@odata.count' ?? @($devices.value).Count
            AppCount          = @($apps).Count
            UserCount         = $users.'@odata.count' ?? @($users.value).Count
            GroupCount        = $groups.'@odata.count' ?? @($groups.value).Count
            CompliantCount    = $compliance.compliantDeviceCount ?? 0
            NoncompliantCount = $compliance.nonCompliantDeviceCount ?? 0
            InGracePeriod     = $compliance.inGracePeriodCount ?? 0
            ErrorCount        = $compliance.errorCount ?? 0
        }
    }

    if ($null -eq $dashData) {
        Write-InTUILog -Level 'WARN' -Message "Failed to load dashboard data"
        Show-InTUIWarning "Could not load dashboard data. Check your connection and permissions."
        return
    }

    Write-InTUILog -Message "Dashboard data loaded" -Context @{
        Devices = $dashData.DeviceCount
        Apps = $dashData.AppCount
        Users = $dashData.UserCount
        Groups = $dashData.GroupCount
    }

    # Calculate compliance percentage for progress bar
    $totalDevices = [int]$dashData.CompliantCount + [int]$dashData.NoncompliantCount + [int]$dashData.InGracePeriod + [int]$dashData.ErrorCount
    $compliancePercent = if ($totalDevices -gt 0) { [Math]::Round(([int]$dashData.CompliantCount / $totalDevices) * 100, 1) } else { 0 }
    $complianceBar = Get-InTUIProgressBar -Percentage $compliancePercent -Width 25

    # Device panel with enhanced visuals
    $devicePanel = Format-SpectrePanel -Data @"
  $([char]0x25A0) [white bold]$($dashData.DeviceCount)[/] [grey]managed devices[/]

  [bold]Compliance Status[/]
  $complianceBar [white]$compliancePercent%[/]

  [green]$([char]0x25CF)[/] Compliant       [white bold]$($dashData.CompliantCount)[/]
  [red]$([char]0x25CF)[/] Non-compliant   [white bold]$($dashData.NoncompliantCount)[/]
  [yellow]$([char]0x25CF)[/] Grace Period    [white bold]$($dashData.InGracePeriod)[/]
  [red]$([char]0x25CF)[/] Error           [white bold]$($dashData.ErrorCount)[/]
"@ -Title "[blue]$([char]0x2630) Devices[/]" -Color Blue

    # App panel with icon
    $appPanel = Format-SpectrePanel -Data @"
  $([char]0x25A3) [white bold]$($dashData.AppCount)[/] [grey]applications[/]

  [grey dim]Managed apps across all platforms[/]
"@ -Title "[green]$([char]0x25A6) Apps[/]" -Color Green

    # User panel with icon
    $userPanel = Format-SpectrePanel -Data @"
  $([char]0x263A) [white bold]$($dashData.UserCount)[/] [grey]users[/]

  [grey dim]Azure AD directory users[/]
"@ -Title "[yellow]$([char]0x26AB) Users[/]" -Color Yellow

    # Group panel with icon
    $groupPanel = Format-SpectrePanel -Data @"
  $([char]0x2687) [white bold]$($dashData.GroupCount)[/] [grey]groups[/]

  [grey dim]Security and distribution groups[/]
"@ -Title "[cyan]$([char]0x2756) Groups[/]" -Color Cyan1

    $devicePanel | Out-SpectreHost
    $appPanel | Out-SpectreHost
    $userPanel | Out-SpectreHost
    $groupPanel | Out-SpectreHost

    # Quick stats footer
    Write-SpectreHost ""
    Write-SpectreHost "[grey dim]$(([string][char]0x2500) * 60)[/]"
    Write-SpectreHost "[grey]Quick Stats:[/] [blue]$([char]0x25B6)[/] [white]$($dashData.DeviceCount)[/] devices  [green]$([char]0x25B6)[/] [white]$($dashData.AppCount)[/] apps  [yellow]$([char]0x25B6)[/] [white]$($dashData.UserCount)[/] users  [cyan]$([char]0x25B6)[/] [white]$($dashData.GroupCount)[/] groups"
    Write-SpectreHost ""
}

function Start-InTUIAutoRefresh {
    <#
    .SYNOPSIS
        Starts an auto-refresh loop for the dashboard.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$IntervalSeconds = 30
    )

    if ($IntervalSeconds -lt 10) { $IntervalSeconds = 10 }
    if ($IntervalSeconds -gt 300) { $IntervalSeconds = 300 }

    Write-InTUILog -Message "Auto-refresh started" -Context @{ Interval = $IntervalSeconds }

    $exitRefresh = $false

    while (-not $exitRefresh) {
        Clear-Host
        Show-InTUIHeader -Subtitle "[grey]Live Dashboard - Auto-refresh every ${IntervalSeconds}s | Press any key to stop[/]"
        Show-InTUIBreadcrumb -Path @('Home', 'Live Dashboard')
        Show-InTUIDashboard

        Write-SpectreHost ""
        Write-SpectreHost "[grey]Last refresh: $([DateTime]::Now.ToString('HH:mm:ss')) | Next refresh in ${IntervalSeconds}s[/]"
        Write-SpectreHost "[yellow]Press any key to stop auto-refresh...[/]"

        # Wait for interval or key press
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while ($stopwatch.Elapsed.TotalSeconds -lt $IntervalSeconds) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                $exitRefresh = $true
                break
            }

            # Update countdown
            $remaining = $IntervalSeconds - [math]::Floor($stopwatch.Elapsed.TotalSeconds)
            Write-Host -NoNewline "`r[grey]Refreshing in ${remaining}s...    [/]"

            Start-Sleep -Milliseconds 500
        }

        $stopwatch.Stop()
    }

    Write-InTUILog -Message "Auto-refresh stopped"
    Show-InTUISuccess "Auto-refresh stopped."
    Read-InTUIKey
}
