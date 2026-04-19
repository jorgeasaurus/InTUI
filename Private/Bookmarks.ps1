# InTUI Bookmarks
# Provides bookmarkable view management

$script:BookmarkIcons = @{
    Device           = '[blue]D[/]'
    App              = '[green]A[/]'
    User             = '[yellow]U[/]'
    Group            = '[cyan]G[/]'
    ConfigProfile    = '[cyan]C[/]'
    CompliancePolicy = '[orange1]P[/]'
    SecurityBaseline = '[red]S[/]'
}

function Get-InTUIBookmarks {
    <#
    .SYNOPSIS
        Retrieves saved bookmarks from disk.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:BookmarksPath)) {
        return @()
    }

    try {
        $bookmarks = Get-Content $script:BookmarksPath -Raw | ConvertFrom-Json
        Write-InTUILog -Message "Bookmarks loaded" -Context @{ Count = @($bookmarks).Count }
        return @($bookmarks)
    }
    catch {
        Write-InTUILog -Level 'WARN' -Message "Failed to load bookmarks: $($_.Exception.Message)"
        return @()
    }
}

function Save-InTUIBookmark {
    <#
    .SYNOPSIS
        Saves a bookmark for a view.
    .PARAMETER ViewType
        The type of view (e.g., Device, App, User, Group, Profile).
    .PARAMETER ViewId
        The ID of the resource being bookmarked.
    .PARAMETER DisplayName
        The display name for the bookmark.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Device', 'App', 'User', 'Group', 'ConfigProfile', 'CompliancePolicy', 'SecurityBaseline')]
        [string]$ViewType,

        [Parameter(Mandatory)]
        [string]$ViewId,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $bookmarks = Get-InTUIBookmarks

    # Check if already bookmarked
    $existing = $bookmarks | Where-Object { $_.ViewType -eq $ViewType -and $_.ViewId -eq $ViewId }
    if ($existing) {
        Write-InTUILog -Message "Bookmark already exists" -Context @{ ViewType = $ViewType; ViewId = $ViewId }
        return $false
    }

    $bookmark = [PSCustomObject]@{
        Id          = [Guid]::NewGuid().ToString()
        ViewType    = $ViewType
        ViewId      = $ViewId
        DisplayName = $DisplayName
        TenantId    = $script:TenantId
        CreatedAt   = [DateTime]::UtcNow.ToString('o')
    }

    $bookmarks = @($bookmarks) + $bookmark

    try {
        $bookmarks | ConvertTo-Json -Depth 5 | Set-Content $script:BookmarksPath -Encoding UTF8
        Write-InTUILog -Message "Bookmark saved" -Context @{
            ViewType = $ViewType
            ViewId = $ViewId
            DisplayName = $DisplayName
        }
        return $true
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to save bookmark: $($_.Exception.Message)"
        return $false
    }
}

function Remove-InTUIBookmark {
    <#
    .SYNOPSIS
        Removes a bookmark by ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BookmarkId
    )

    $bookmarks = Get-InTUIBookmarks
    $bookmarks = @($bookmarks | Where-Object { $_.Id -ne $BookmarkId })

    try {
        if ($bookmarks.Count -eq 0) {
            Remove-Item $script:BookmarksPath -Force -ErrorAction SilentlyContinue
        }
        else {
            $bookmarks | ConvertTo-Json -Depth 5 | Set-Content $script:BookmarksPath -Encoding UTF8
        }
        Write-InTUILog -Message "Bookmark removed" -Context @{ BookmarkId = $BookmarkId }
        return $true
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to remove bookmark: $($_.Exception.Message)"
        return $false
    }
}

function Show-InTUIBookmarks {
    <#
    .SYNOPSIS
        Displays the bookmarks list and allows navigation.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Bookmarks')

        $bookmarks = Get-InTUIBookmarks

        # Filter to current tenant
        $tenantBookmarks = @($bookmarks | Where-Object { $_.TenantId -eq $script:TenantId })

        if ($tenantBookmarks.Count -eq 0) {
            Show-InTUIWarning "No bookmarks saved for this tenant."
            Write-InTUIText ""
            Write-InTUIText "[grey]To add a bookmark, use the 'Add Bookmark' action in any detail view.[/]"
            Read-InTUIKey
            $exitView = $true
            continue
        }

        Write-InTUIText "[bold]Saved Bookmarks[/]"
        Write-InTUIText "[grey]Select a bookmark to navigate, or manage bookmarks[/]"
        Write-InTUIText ""

        $bookmarkChoices = @()
        foreach ($bm in $tenantBookmarks) {
            $icon = $script:BookmarkIcons[$bm.ViewType] ?? '[grey]?[/]'
            $created = Format-InTUIDate -DateString $bm.CreatedAt
            $bookmarkChoices += "$icon [white]$($bm.DisplayName)[/] [grey]| $($bm.ViewType) | $created[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $bookmarkChoices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'Clear All Bookmarks' + 'Back')

        Show-InTUIStatusBar -Total $tenantBookmarks.Count -Showing $tenantBookmarks.Count

        $selection = Show-InTUIMenu -Title "[cyan]Bookmarks[/]" -Choices $menuChoices

        switch ($selection) {
            'Back' {
                $exitView = $true
            }
            'Clear All Bookmarks' {
                $confirm = Show-InTUIConfirm -Message "[yellow]Delete all bookmarks for this tenant?[/]"
                if ($confirm) {
                    foreach ($bm in $tenantBookmarks) {
                        Remove-InTUIBookmark -BookmarkId $bm.Id
                    }
                    Show-InTUISuccess "All bookmarks cleared."
                    Read-InTUIKey
                    $exitView = $true
                }
            }
            '─────────────' {
                continue
            }
            default {
                $idx = $choiceMap.IndexMap[$selection]
                if ($null -ne $idx -and $idx -lt $tenantBookmarks.Count) {
                    $selectedBookmark = $tenantBookmarks[$idx]

                    $actionChoices = @(
                        'Navigate to View',
                        'Delete Bookmark',
                        'Cancel'
                    )

                    $action = Show-InTUIMenu -Title "[cyan]Bookmark Action[/]" -Choices $actionChoices

                    switch ($action) {
                        'Navigate to View' {
                            Invoke-InTUIBookmark -Bookmark $selectedBookmark
                            $exitView = $true
                        }
                        'Delete Bookmark' {
                            if (Remove-InTUIBookmark -BookmarkId $selectedBookmark.Id) {
                                Show-InTUISuccess "Bookmark deleted."
                            }
                            Read-InTUIKey
                        }
                    }
                }
            }
        }
    }
}

function Invoke-InTUIBookmark {
    <#
    .SYNOPSIS
        Navigates to a bookmarked view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Bookmark
    )

    Write-InTUILog -Message "Navigating to bookmark" -Context @{
        ViewType = $Bookmark.ViewType
        ViewId = $Bookmark.ViewId
        DisplayName = $Bookmark.DisplayName
    }

    switch ($Bookmark.ViewType) {
        'Device' {
            Show-InTUIDeviceDetail -DeviceId $Bookmark.ViewId
        }
        'App' {
            Show-InTUIAppDetail -AppId $Bookmark.ViewId
        }
        'User' {
            Show-InTUIUserDetail -UserId $Bookmark.ViewId
        }
        'Group' {
            Show-InTUIGroupDetail -GroupId $Bookmark.ViewId
        }
        'ConfigProfile' {
            Show-InTUILegacyProfileDetail -ProfileId $Bookmark.ViewId
        }
        'CompliancePolicy' {
            Show-InTUICompliancePolicyDetail -PolicyId $Bookmark.ViewId
        }
        'SecurityBaseline' {
            Show-InTUISecurityBaselineDetail -IntentId $Bookmark.ViewId
        }
        default {
            Show-InTUIWarning "Unknown bookmark type: $($Bookmark.ViewType)"
            Read-InTUIKey
        }
    }
}
