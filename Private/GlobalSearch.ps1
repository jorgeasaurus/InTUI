# InTUI Global Search
# Cross-entity incremental search

function Invoke-InTUIGlobalSearch {
    <#
    .SYNOPSIS
        Performs a global search across devices, apps, users, and groups.
    #>
    [CmdletBinding()]
    param()

    $exitSearch = $false

    while (-not $exitSearch) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Global Search')

        Write-SpectreHost "[bold]Global Search[/]"
        Write-SpectreHost "[grey]Search across devices, apps, users, and groups[/]"
        Write-SpectreHost ""

        $searchTerm = Read-SpectreText -Message "[blue]Enter search term (min 3 characters)[/]"

        if (-not $searchTerm -or $searchTerm.Length -lt 3) {
            if (-not $searchTerm) {
                $exitSearch = $true
                continue
            }
            Show-InTUIWarning "Search term must be at least 3 characters."
            Read-InTUIKey
            continue
        }

        Write-InTUILog -Message "Global search initiated" -Context @{ SearchTerm = $searchTerm }

        $results = Show-InTUILoading -Title "[blue]Searching...[/]" -ScriptBlock {
            $safe = ConvertTo-InTUISafeFilterValue -Value $searchTerm
            $allResults = @{
                Devices = @()
                Apps = @()
                Users = @()
                Groups = @()
            }

            # Search devices
            $deviceResponse = Invoke-InTUIGraphRequest -Uri "/deviceManagement/managedDevices?`$filter=contains(deviceName,'$safe')&`$select=id,deviceName,operatingSystem,complianceState&`$top=10" -Beta
            if ($deviceResponse.value) {
                $allResults.Devices = @($deviceResponse.value)
            }

            # Search apps
            $appResponse = Invoke-InTUIGraphRequest -Uri "/deviceAppManagement/mobileApps?`$filter=contains(displayName,'$safe')&`$select=id,displayName&`$top=10" -Beta
            if ($appResponse.value) {
                $allResults.Apps = @($appResponse.value)
            }

            # Search users
            $userResponse = Invoke-InTUIGraphRequest -Uri "/users?`$filter=startswith(displayName,'$safe') or startswith(userPrincipalName,'$safe')&`$select=id,displayName,userPrincipalName&`$top=10"
            if ($userResponse.value) {
                $allResults.Users = @($userResponse.value)
            }

            # Search groups
            $groupResponse = Invoke-InTUIGraphRequest -Uri "/groups?`$filter=startswith(displayName,'$safe')&`$select=id,displayName,description&`$top=10"
            if ($groupResponse.value) {
                $allResults.Groups = @($groupResponse.value)
            }

            $allResults
        }

        $totalCount = $results.Devices.Count + $results.Apps.Count + $results.Users.Count + $results.Groups.Count

        if ($totalCount -eq 0) {
            Show-InTUIWarning "No results found for '$searchTerm'."
            Read-InTUIKey
            continue
        }

        Write-InTUILog -Message "Search completed" -Context @{
            SearchTerm = $searchTerm
            Devices = $results.Devices.Count
            Apps = $results.Apps.Count
            Users = $results.Users.Count
            Groups = $results.Groups.Count
        }

        # Build results menu
        $resultChoices = @()
        $resultMap = @{}

        # Add devices
        if ($results.Devices.Count -gt 0) {
            $resultChoices += "[blue]--- Devices ($($results.Devices.Count)) ---[/]"
            foreach ($device in $results.Devices) {
                $compColor = Get-InTUIComplianceColor -State $device.complianceState
                $choice = "[blue]D[/] [white]$($device.deviceName)[/] [grey]| $($device.operatingSystem) |[/] [$compColor]$($device.complianceState)[/]"
                $resultChoices += $choice
                $resultMap[$choice] = @{ Type = 'Device'; Id = $device.id; Name = $device.deviceName }
            }
        }

        # Add apps
        if ($results.Apps.Count -gt 0) {
            $resultChoices += "[green]--- Apps ($($results.Apps.Count)) ---[/]"
            foreach ($app in $results.Apps) {
                $appType = Get-InTUIAppTypeFriendlyName -ODataType $app.'@odata.type'
                $choice = "[green]A[/] [white]$(ConvertTo-InTUISafeMarkup -Text $app.displayName)[/] [grey]| $appType[/]"
                $resultChoices += $choice
                $resultMap[$choice] = @{ Type = 'App'; Id = $app.id; Name = $app.displayName }
            }
        }

        # Add users
        if ($results.Users.Count -gt 0) {
            $resultChoices += "[yellow]--- Users ($($results.Users.Count)) ---[/]"
            foreach ($user in $results.Users) {
                $choice = "[yellow]U[/] [white]$(ConvertTo-InTUISafeMarkup -Text $user.displayName)[/] [grey]| $($user.userPrincipalName)[/]"
                $resultChoices += $choice
                $resultMap[$choice] = @{ Type = 'User'; Id = $user.id; Name = $user.displayName }
            }
        }

        # Add groups
        if ($results.Groups.Count -gt 0) {
            $resultChoices += "[cyan]--- Groups ($($results.Groups.Count)) ---[/]"
            foreach ($group in $results.Groups) {
                $desc = if ($group.description) { $group.description.Substring(0, [Math]::Min(30, $group.description.Length)) } else { 'No description' }
                $choice = "[cyan]G[/] [white]$(ConvertTo-InTUISafeMarkup -Text $group.displayName)[/] [grey]| $desc[/]"
                $resultChoices += $choice
                $resultMap[$choice] = @{ Type = 'Group'; Id = $group.id; Name = $group.displayName }
            }
        }

        $resultChoices += '─────────────'
        $resultChoices += 'New Search'
        $resultChoices += 'Back to Home'

        Show-InTUIStatusBar -Total $totalCount -Showing $totalCount -FilterText "Search: $searchTerm"

        $selection = Show-InTUIMenu -Title "[blue]Search Results[/]" -Choices $resultChoices -PageSize 20

        switch ($selection) {
            'New Search' {
                continue
            }
            'Back to Home' {
                $exitSearch = $true
            }
            '─────────────' {
                continue
            }
            default {
                # Skip header lines (not in resultMap)
                $selected = $resultMap[$selection]
                if (-not $selected) { continue }

                Write-InTUILog -Message "Search result selected" -Context @{
                    Type = $selected.Type
                    Id = $selected.Id
                    Name = $selected.Name
                }

                switch ($selected.Type) {
                    'Device' { Show-InTUIDeviceDetail -DeviceId $selected.Id }
                    'App'    { Show-InTUIAppDetail -AppId $selected.Id }
                    'User'   { Show-InTUIUserDetail -UserId $selected.Id }
                    'Group'  { Show-InTUIGroupDetail -GroupId $selected.Id }
                }
            }
        }
    }
}
