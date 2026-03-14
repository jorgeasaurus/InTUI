# InTUI Keyboard Shortcuts
# Provides keyboard shortcut handling and help display

$script:InTUIShortcuts = @{
    'd' = @{ Action = 'Devices'; Description = 'Go to Devices' }
    'a' = @{ Action = 'Apps'; Description = 'Go to Apps' }
    'u' = @{ Action = 'Users'; Description = 'Go to Users' }
    'g' = @{ Action = 'Groups'; Description = 'Go to Groups' }
    'r' = @{ Action = 'Reports'; Description = 'Go to Reports' }
    's' = @{ Action = 'Settings'; Description = 'Open Settings' }
    '/' = @{ Action = 'Search'; Description = 'Global Search' }
    '?' = @{ Action = 'Help'; Description = 'Show Help' }
    'c' = @{ Action = 'ConfigProfiles'; Description = 'Configuration Profiles' }
    'p' = @{ Action = 'CompliancePolicies'; Description = 'Compliance Policies' }
    'e' = @{ Action = 'Enrollment'; Description = 'Enrollment' }
    'x' = @{ Action = 'Security'; Description = 'Security' }
    'b' = @{ Action = 'Bookmarks'; Description = 'Bookmarks' }
    't' = @{ Action = 'CommandPalette'; Description = 'Command Palette' }
}

function Show-InTUIShortcutBar {
    <#
    .SYNOPSIS
        Displays the keyboard shortcut bar at the bottom of the screen.
    #>
    [CmdletBinding()]
    param()

    $shortcuts = @(
        "[grey]d[/]:Devices"
        "[grey]a[/]:Apps"
        "[grey]u[/]:Users"
        "[grey]g[/]:Groups"
        "[grey]r[/]:Reports"
        "[grey]s[/]:Settings"
        "[grey]/[/]:Search"
        "[grey]t[/]:Palette"
        "[grey]?[/]:Help"
    )

    $bar = $shortcuts -join " [grey]|[/] "
    Write-InTUIText $bar
}

function Invoke-InTUIShortcut {
    <#
    .SYNOPSIS
        Executes the action for a given keyboard shortcut.
    .OUTPUTS
        Returns the action name if valid, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $shortcut = $script:InTUIShortcuts[$Key.ToLower()]

    if ($shortcut) {
        Write-InTUILog -Message "Shortcut invoked" -Context @{ Key = $Key; Action = $shortcut.Action }
        return $shortcut.Action
    }

    return $null
}

function Show-InTUIHelp {
    <#
    .SYNOPSIS
        Displays the help panel with all keyboard shortcuts and navigation tips.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Help')

    Write-InTUILog -Message "Viewing help"

    # Keyboard shortcuts section
    $shortcutContent = @"
[bold]Navigation Shortcuts[/]
[cyan]d[/]  - Devices view
[cyan]a[/]  - Apps view
[cyan]u[/]  - Users view
[cyan]g[/]  - Groups view
[cyan]c[/]  - Configuration Profiles
[cyan]p[/]  - Compliance Policies
[cyan]e[/]  - Enrollment
[cyan]x[/]  - Security
[cyan]r[/]  - Reports

[bold]Actions[/]
[cyan]s[/]  - Settings
[cyan]/[/]  - Global Search
[cyan]b[/]  - Bookmarks
[cyan]t[/]  - Command Palette
[cyan]?[/]  - This Help

[bold]Menu Navigation[/]
[cyan]Up/Down[/]    - Navigate menu items
[cyan]Enter[/]      - Select item
[cyan]Escape[/]     - Go back (in some views)
"@

    Show-InTUIPanel -Title "[blue]Keyboard Shortcuts[/]" -Content $shortcutContent -BorderColor Blue

    # Features section
    $featuresContent = @"
[bold]Caching[/]
API responses are cached locally to improve navigation speed.
Configure in Settings: Toggle, TTL, Clear cache.

[bold]Script Recording[/]
Record your Graph API actions and export as a PowerShell script.
Access via the main menu Recording option.

[bold]Bookmarks[/]
Save frequently accessed views for quick navigation.
Access via the Bookmarks option.

"@

    Show-InTUIPanel -Title "[blue]Features[/]" -Content $featuresContent -BorderColor Blue

    # About section
    $aboutContent = @"
[bold]InTUI[/] - Intune Terminal User Interface
Version: $($script:InTUIVersion)

A terminal UI for Microsoft Intune management.

[grey]Powered by:[/]
- Microsoft Graph API
- Microsoft.Graph.Authentication
- Custom ANSI TUI Engine
"@

    Show-InTUIPanel -Title "[blue]About[/]" -Content $aboutContent -BorderColor Blue

    Read-InTUIKey
}

function Read-InTUIShortcutKey {
    <#
    .SYNOPSIS
        Reads a key press and checks if it's a valid shortcut.
    .OUTPUTS
        Returns the action name if a shortcut key was pressed, $null otherwise.
    #>
    [CmdletBinding()]
    param()

    if (-not [Console]::KeyAvailable) {
        return $null
    }

    $keyInfo = [Console]::ReadKey($true)
    return Invoke-InTUIShortcut -Key $keyInfo.KeyChar.ToString()
}
