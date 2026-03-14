function Show-InTUICommandPalette {
    <#
    .SYNOPSIS
        Quick-jump command palette with fuzzy search across views, history, and bookmarks.
    #>
    [CmdletBinding()]
    param()

    # Build navigable targets
    $targets = @(
        @{ Name = 'Devices';                 Category = 'view';     Action = 'Devices' }
        @{ Name = 'Apps';                    Category = 'view';     Action = 'Apps' }
        @{ Name = 'Users';                   Category = 'view';     Action = 'Users' }
        @{ Name = 'Groups';                  Category = 'view';     Action = 'Groups' }
        @{ Name = 'Configuration Profiles';  Category = 'view';     Action = 'ConfigProfiles' }
        @{ Name = 'Compliance Policies';     Category = 'view';     Action = 'CompliancePolicies' }
        @{ Name = 'Conditional Access';      Category = 'view';     Action = 'ConditionalAccess' }
        @{ Name = 'Enrollment';              Category = 'view';     Action = 'Enrollment' }
        @{ Name = 'Scripts & Remediations';  Category = 'view';     Action = 'Scripts' }
        @{ Name = 'Security';                Category = 'view';     Action = 'Security' }
        @{ Name = 'Reports';                 Category = 'view';     Action = 'Reports' }
        @{ Name = 'Global Search';           Category = 'tool';     Action = 'Search' }
        @{ Name = 'Bookmarks';              Category = 'tool';     Action = 'Bookmarks' }
        @{ Name = 'Settings';                Category = 'tool';     Action = 'Settings' }
        @{ Name = "What's Applied?";         Category = 'tool';     Action = 'WhatsApplied' }
        @{ Name = 'Assignment Conflicts';    Category = 'tool';     Action = 'AssignmentConflicts' }
        @{ Name = 'Policy Diff';             Category = 'tool';     Action = 'PolicyDiff' }
        @{ Name = 'Recent History';          Category = 'tool';     Action = 'RecentHistory' }
        @{ Name = 'Help';                    Category = 'tool';     Action = 'Help' }
    )

    # Add recent history entries
    $history = Get-InTUIHistory
    foreach ($entry in $history) {
        $targets += @{
            Name     = "$($entry.DisplayName)"
            Category = 'recent'
            Action   = 'HistoryEntry'
            Data     = $entry
        }
    }

    # Add bookmarks
    $bookmarks = Get-InTUIBookmarks
    foreach ($bm in $bookmarks) {
        $targets += @{
            Name     = "$($bm.DisplayName)"
            Category = 'bookmark'
            Action   = 'BookmarkEntry'
            Data     = $bm
        }
    }

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset
    $searchString = ''
    $selectedIndex = 0
    $maxResults = 10

    while ($true) {
        # Filter targets
        $filtered = if ([string]::IsNullOrEmpty($searchString)) {
            $targets
        }
        else {
            @($targets | Where-Object { $_.Name -like "*$searchString*" })
        }

        if ($filtered.Count -gt $maxResults) {
            $filtered = $filtered[0..($maxResults - 1)]
        }

        if ($selectedIndex -ge $filtered.Count) {
            $selectedIndex = [Math]::Max(0, $filtered.Count - 1)
        }

        # Render
        Clear-Host
        Show-InTUIHeader

        $borderAnsi = $palette.Blue
        $horizontal = [char]0x2500
        $vertical = [char]0x2502
        $topLeft = [char]0x256D
        $topRight = [char]0x256E
        $bottomLeft = [char]0x2570
        $bottomRight = [char]0x256F

        $innerWidth = Get-InTUIConsoleInnerWidth
        $boxWidth = [Math]::Min(60, $innerWidth - 4)

        Write-Host "$borderAnsi$topLeft$([string]::new($horizontal, $boxWidth - 2))$topRight$reset"
        Write-Host "$borderAnsi$vertical$reset $($palette.Bold)Search:$reset $searchString$(' ' * [Math]::Max(0, $boxWidth - 11 - $searchString.Length))$borderAnsi$vertical$reset"
        Write-Host "$borderAnsi$vertical$reset$([string]::new($horizontal, $boxWidth - 2))$borderAnsi$vertical$reset"

        if ($filtered.Count -eq 0) {
            $noResult = 'No matches'
            Write-Host "$borderAnsi$vertical$reset $($palette.Dim)$noResult$(' ' * [Math]::Max(0, $boxWidth - 4 - $noResult.Length))$reset $borderAnsi$vertical$reset"
        }
        else {
            for ($i = 0; $i -lt $filtered.Count; $i++) {
                $item = $filtered[$i]
                $tag = switch ($item.Category) {
                    'view'     { '' }
                    'tool'     { '' }
                    'recent'   { "$($palette.Dim)[recent]$reset " }
                    'bookmark' { "$($palette.Cyan)[bookmark]$reset " }
                    default    { '' }
                }

                $displayName = $item.Name
                $line = "$tag$displayName"
                $plainLen = ($tag -replace '\e\[[^m]*m', '').Length + $displayName.Length

                if ($i -eq $selectedIndex) {
                    $pad = [Math]::Max(0, $boxWidth - 4 - $plainLen)
                    Write-Host "$borderAnsi$vertical$reset $($palette.BgSelect)$($palette.White)$line$(' ' * $pad)$reset $borderAnsi$vertical$reset"
                }
                else {
                    $pad = [Math]::Max(0, $boxWidth - 4 - $plainLen)
                    Write-Host "$borderAnsi$vertical$reset $($palette.Text)$line$(' ' * $pad)$reset $borderAnsi$vertical$reset"
                }
            }
        }

        Write-Host "$borderAnsi$bottomLeft$([string]::new($horizontal, $boxWidth - 2))$bottomRight$reset"
        Write-Host "$($palette.Dim)Type to search | Up/Down to navigate | Enter to select | Esc to cancel$reset"

        # Read input
        $keyInfo = [Console]::ReadKey($true)

        switch ($keyInfo.Key) {
            'Escape' {
                return $null
            }
            'Enter' {
                if ($filtered.Count -gt 0) {
                    $selected = $filtered[$selectedIndex]
                    Invoke-InTUICommandPaletteAction -Target $selected
                    return
                }
            }
            'UpArrow' {
                if ($selectedIndex -gt 0) { $selectedIndex-- }
            }
            'DownArrow' {
                if ($selectedIndex -lt ($filtered.Count - 1)) { $selectedIndex++ }
            }
            'Backspace' {
                if ($searchString.Length -gt 0) {
                    $searchString = $searchString.Substring(0, $searchString.Length - 1)
                    $selectedIndex = 0
                }
            }
            default {
                $ch = $keyInfo.KeyChar
                if ($ch -and [char]::IsLetterOrDigit($ch) -or $ch -eq ' ' -or $ch -eq "'" -or $ch -eq '-') {
                    $searchString += $ch
                    $selectedIndex = 0
                }
            }
        }
    }
}

function Invoke-InTUICommandPaletteAction {
    <#
    .SYNOPSIS
        Dispatches the selected command palette target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Target
    )

    switch ($Target.Action) {
        'Devices'              { Show-InTUIDevicesView }
        'Apps'                 { Show-InTUIAppsView }
        'Users'                { Show-InTUIUsersView }
        'Groups'               { Show-InTUIGroupsView }
        'ConfigProfiles'       { Show-InTUIConfigProfilesView }
        'CompliancePolicies'   { Show-InTUICompliancePoliciesView }
        'ConditionalAccess'    { Show-InTUIConditionalAccessView }
        'Enrollment'           { Show-InTUIEnrollmentView }
        'Scripts'              { Show-InTUIScriptsView }
        'Security'             { Show-InTUISecurityView }
        'Reports'              { Show-InTUIReportsView }
        'Search'               { Invoke-InTUIGlobalSearch }
        'Bookmarks'            { Show-InTUIBookmarks }
        'Settings'             { Show-InTUISettings }
        'WhatsApplied'         { Show-InTUIWhatsAppliedView }
        'AssignmentConflicts'  { Show-InTUIAssignmentConflictView }
        'PolicyDiff'           { Show-InTUIPolicyDiffView }
        'RecentHistory'        { Show-InTUIRecentHistory }
        'Help'                 { Show-InTUIHelp }
        'HistoryEntry' {
            $entry = $Target.Data
            switch ($entry.ViewType) {
                'Device'           { Show-InTUIDeviceDetail -DeviceId $entry.ViewId }
                'App'              { Show-InTUIAppDetail -AppId $entry.ViewId }
                'User'             { Show-InTUIUserDetail -UserId $entry.ViewId }
                'Group'            { Show-InTUIGroupDetail -GroupId $entry.ViewId }
                'ConfigProfile'    { Show-InTUILegacyProfileDetail -ProfileId $entry.ViewId }
                'CatalogProfile'   { Show-InTUICatalogProfileDetail -ProfileId $entry.ViewId }
                'CompliancePolicy' { Show-InTUICompliancePolicyDetail -PolicyId $entry.ViewId }
            }
        }
        'BookmarkEntry' {
            Invoke-InTUIBookmark -Bookmark $Target.Data
        }
    }
}
