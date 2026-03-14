$script:ConfigPath = Join-Path $HOME '.intui_config.json'

$script:InTUIConfig = @{
    PageSize        = 50
    RefreshInterval = 30
    DefaultExportPath = $PWD
    CacheEnabled    = $true
    CacheTTL        = 300
    Theme           = 'Mocha'
}

function Initialize-InTUIConfig {
    <#
    .SYNOPSIS
        Loads user configuration from disk or creates defaults.
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $script:ConfigPath) {
        try {
            $saved = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            if ($saved.PageSize) { $script:InTUIConfig.PageSize = $saved.PageSize; $script:PageSize = $saved.PageSize }
            if ($saved.RefreshInterval) { $script:InTUIConfig.RefreshInterval = $saved.RefreshInterval }
            if ($saved.DefaultExportPath) { $script:InTUIConfig.DefaultExportPath = $saved.DefaultExportPath }
            if ($null -ne $saved.CacheEnabled) { $script:InTUIConfig.CacheEnabled = $saved.CacheEnabled; $script:CacheEnabled = $saved.CacheEnabled }
            if ($saved.CacheTTL) { $script:InTUIConfig.CacheTTL = $saved.CacheTTL; $script:CacheTTL = $saved.CacheTTL }
            if ($saved.Theme) { $script:InTUIConfig.Theme = $saved.Theme }
            Write-InTUILog -Message "Configuration loaded" -Context @{ Path = $script:ConfigPath }
        }
        catch {
            Write-InTUILog -Level 'WARN' -Message "Failed to load config: $($_.Exception.Message)"
        }
    }
}

function Save-InTUIConfig {
    <#
    .SYNOPSIS
        Saves current configuration to disk.
    #>
    [CmdletBinding()]
    param()

    try {
        $script:InTUIConfig | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath -Encoding UTF8
        Write-InTUILog -Message "Configuration saved" -Context @{ Path = $script:ConfigPath }
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to save config: $($_.Exception.Message)"
    }
}

function Show-InTUISettings {
    <#
    .SYNOPSIS
        Displays and allows editing of InTUI settings.
    #>
    [CmdletBinding()]
    param()

    $exitSettings = $false

    while (-not $exitSettings) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Settings')

        $content = @"
[grey]Page Size:[/]          [white]$($script:InTUIConfig.PageSize)[/]
[grey]Refresh Interval:[/]   [white]$($script:InTUIConfig.RefreshInterval)s[/]
[grey]Default Export Path:[/] [white]$($script:InTUIConfig.DefaultExportPath)[/]
[grey]Cache Enabled:[/]      [white]$($script:CacheEnabled)[/]
[grey]Cache TTL:[/]          [white]$($script:CacheTTL)s[/]
[grey]Theme:[/]              [white]$($script:InTUIConfig.Theme)[/]
[grey]Config File:[/]        [white]$($script:ConfigPath)[/]
"@

        Show-InTUIPanel -Title "[blue]Current Settings[/]" -Content $content -BorderColor Blue

        $choices = @(
            'Change Page Size',
            'Change Refresh Interval',
            'Change Default Export Path',
            'Toggle Cache',
            'Change Cache TTL',
            'Clear Cache',
            'View Cache Stats',
            'Change Theme',
            'Reset to Defaults',
            '─────────────',
            'Back'
        )

        $selection = Show-InTUIMenu -Title "[blue]Settings[/]" -Choices $choices

        Write-InTUILog -Message "Settings action" -Context @{ Selection = $selection }

        switch ($selection) {
            'Change Page Size' {
                $newSize = Read-InTUITextInput -Message "[blue]Page size (10-100)[/]" -DefaultAnswer "$($script:InTUIConfig.PageSize)"
                $parsed = 0
                if ([int]::TryParse($newSize, [ref]$parsed) -and $parsed -ge 10 -and $parsed -le 100) {
                    $script:InTUIConfig.PageSize = $parsed
                    $script:PageSize = $parsed
                    Save-InTUIConfig
                    Show-InTUISuccess "Page size set to $parsed"
                }
                else {
                    Show-InTUIWarning "Invalid value. Must be between 10 and 100."
                }
                Read-InTUIKey
            }
            'Change Refresh Interval' {
                $newInterval = Read-InTUITextInput -Message "[blue]Refresh interval in seconds (10-300)[/]" -DefaultAnswer "$($script:InTUIConfig.RefreshInterval)"
                $parsed = 0
                if ([int]::TryParse($newInterval, [ref]$parsed) -and $parsed -ge 10 -and $parsed -le 300) {
                    $script:InTUIConfig.RefreshInterval = $parsed
                    Save-InTUIConfig
                    Show-InTUISuccess "Refresh interval set to ${parsed}s"
                }
                else {
                    Show-InTUIWarning "Invalid value. Must be between 10 and 300."
                }
                Read-InTUIKey
            }
            'Change Default Export Path' {
                $newPath = Read-InTUITextInput -Message "[blue]Default export path[/]" -DefaultAnswer "$($script:InTUIConfig.DefaultExportPath)"
                if (Test-Path $newPath -PathType Container) {
                    $script:InTUIConfig.DefaultExportPath = $newPath
                    Save-InTUIConfig
                    Show-InTUISuccess "Export path set to $newPath"
                }
                else {
                    Show-InTUIWarning "Directory does not exist."
                }
                Read-InTUIKey
            }
            'Toggle Cache' {
                $script:CacheEnabled = -not $script:CacheEnabled
                $script:InTUIConfig.CacheEnabled = $script:CacheEnabled
                Save-InTUIConfig
                $status = if ($script:CacheEnabled) { 'enabled' } else { 'disabled' }
                Show-InTUISuccess "Cache $status"
                Read-InTUIKey
            }
            'Change Cache TTL' {
                $newTTL = Read-InTUITextInput -Message "[blue]Cache TTL in seconds (60-3600)[/]" -DefaultAnswer "$($script:CacheTTL)"
                $parsed = 0
                if ([int]::TryParse($newTTL, [ref]$parsed) -and $parsed -ge 60 -and $parsed -le 3600) {
                    $script:CacheTTL = $parsed
                    $script:InTUIConfig.CacheTTL = $parsed
                    Save-InTUIConfig
                    Show-InTUISuccess "Cache TTL set to ${parsed}s"
                }
                else {
                    Show-InTUIWarning "Invalid value. Must be between 60 and 3600."
                }
                Read-InTUIKey
            }
            'Clear Cache' {
                $confirm = Show-InTUIConfirm -Message "[yellow]Clear all cached data?[/]"
                if ($confirm) {
                    $count = Clear-InTUICache
                    Show-InTUISuccess "Cleared $count cached entries."
                }
                Read-InTUIKey
            }
            'View Cache Stats' {
                $stats = Get-InTUICacheStats
                $content = @"
[grey]Cache Enabled:[/]   [white]$($stats.Enabled)[/]
[grey]Cache TTL:[/]       [white]$($stats.TTL)s[/]
[grey]Total Entries:[/]   [white]$($stats.EntryCount)[/]
[grey]Valid Entries:[/]   [green]$($stats.ValidCount)[/]
[grey]Expired Entries:[/] [yellow]$($stats.ExpiredCount)[/]
[grey]Total Size:[/]      [white]$([math]::Round($stats.TotalSize / 1KB, 1)) KB[/]
"@
                Show-InTUIPanel -Title "[blue]Cache Statistics[/]" -Content $content -BorderColor Blue
                Read-InTUIKey
            }
            'Change Theme' {
                $themeChoices = @('Mocha', 'Macchiato', 'Frappe', 'Latte', 'Cancel')
                $themeSelection = Show-InTUIMenu -Title "[blue]Select Theme[/]" -Choices $themeChoices
                if ($themeSelection -ne 'Cancel' -and $script:CatppuccinThemes.ContainsKey($themeSelection)) {
                    $script:InTUIConfig.Theme = $themeSelection
                    Save-InTUIConfig
                    Show-InTUISuccess "Theme changed to $themeSelection"
                }
                Read-InTUIKey
            }
            'Reset to Defaults' {
                $confirm = Show-InTUIConfirm -Message "[yellow]Reset all settings to defaults?[/]"
                if ($confirm) {
                    $script:InTUIConfig = @{
                        PageSize        = 50
                        RefreshInterval = 30
                        DefaultExportPath = $PWD
                        CacheEnabled    = $true
                        CacheTTL        = 300
                        Theme           = 'Mocha'
                    }
                    $script:PageSize = 50
                    $script:CacheEnabled = $true
                    $script:CacheTTL = 300
                    Save-InTUIConfig
                    Show-InTUISuccess "Settings reset to defaults."
                }
                Read-InTUIKey
            }
            'Back' {
                $exitSettings = $true
            }
            default { continue }
        }
    }
}
