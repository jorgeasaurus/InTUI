# InTUI Navigation History
# Tracks recently visited detail views for quick re-navigation

$script:NavigationHistory = @()

function Initialize-InTUIHistory {
    <#
    .SYNOPSIS
        Loads navigation history from disk.
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $script:HistoryPath) {
        try {
            $data = Get-Content $script:HistoryPath -Raw | ConvertFrom-Json
            $script:NavigationHistory = @($data)
            Write-InTUILog -Message "Navigation history loaded" -Context @{ Count = $script:NavigationHistory.Count }
        }
        catch {
            Write-InTUILog -Level 'WARN' -Message "Failed to load navigation history: $($_.Exception.Message)"
            $script:NavigationHistory = @()
        }
    }
}

function Add-InTUIHistoryEntry {
    <#
    .SYNOPSIS
        Adds an entry to the navigation history stack.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ViewType,

        [Parameter(Mandatory)]
        [string]$ViewId,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $entry = [PSCustomObject]@{
        ViewType    = $ViewType
        ViewId      = $ViewId
        DisplayName = $DisplayName
        Timestamp   = [DateTime]::UtcNow.ToString('o')
    }

    # Remove duplicate (same ViewType+ViewId)
    $script:NavigationHistory = @($script:NavigationHistory | Where-Object {
        -not ($_.ViewType -eq $ViewType -and $_.ViewId -eq $ViewId)
    })

    # Prepend new entry
    $script:NavigationHistory = @($entry) + @($script:NavigationHistory)

    # Trim to 20
    if ($script:NavigationHistory.Count -gt 20) {
        $script:NavigationHistory = $script:NavigationHistory[0..19]
    }

    # Save to disk
    try {
        $script:NavigationHistory | ConvertTo-Json -Depth 5 | Set-Content $script:HistoryPath -Encoding UTF8
    }
    catch {
        Write-InTUILog -Level 'WARN' -Message "Failed to save navigation history: $($_.Exception.Message)"
    }
}

function Get-InTUIHistory {
    <#
    .SYNOPSIS
        Returns the current navigation history entries.
    #>
    [CmdletBinding()]
    param()

    return $script:NavigationHistory
}

function Show-InTUIRecentHistory {
    <#
    .SYNOPSIS
        Displays recent navigation history as a selectable menu.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Recent History')

    if ($script:NavigationHistory.Count -eq 0) {
        Show-InTUIWarning "No recent history."
        Read-InTUIKey
        return
    }

    $choices = @()
    foreach ($entry in $script:NavigationHistory) {
        $timeAgo = Format-InTUIDate -DateString $entry.Timestamp
        $choices += "[white]$(ConvertTo-InTUISafeMarkup -Text $entry.DisplayName)[/] [grey]| $($entry.ViewType) | $timeAgo[/]"
    }

    $choiceMap = Get-InTUIChoiceMap -Choices $choices
    $menuChoices = @($choiceMap.Choices + '─────────────' + 'Back')

    $selection = Show-InTUIMenu -Title "[blue]Recent History[/]" -Choices $menuChoices

    if ($selection -eq 'Back') {
        return
    }
    elseif ($selection -ne '─────────────') {
        $idx = $choiceMap.IndexMap[$selection]
        if ($null -ne $idx -and $idx -lt $script:NavigationHistory.Count) {
            $entry = $script:NavigationHistory[$idx]

            switch ($entry.ViewType) {
                'Device' {
                    Show-InTUIDeviceDetail -DeviceId $entry.ViewId
                }
                'App' {
                    Show-InTUIAppDetail -AppId $entry.ViewId
                }
                'User' {
                    Show-InTUIUserDetail -UserId $entry.ViewId
                }
                'Group' {
                    Show-InTUIGroupDetail -GroupId $entry.ViewId
                }
                'ConfigProfile' {
                    Show-InTUILegacyProfileDetail -ProfileId $entry.ViewId
                }
                'CatalogProfile' {
                    Show-InTUICatalogProfileDetail -ProfileId $entry.ViewId
                }
                'CompliancePolicy' {
                    Show-InTUICompliancePolicyDetail -PolicyId $entry.ViewId
                }
                default {
                    Show-InTUIWarning "Unknown history type: $($entry.ViewType)"
                    Read-InTUIKey
                }
            }
        }
    }
}
