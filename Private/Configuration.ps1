$script:ConfigPath = Join-Path $HOME '.intui_config.json'

$script:InTUIConfig = @{
    PageSize        = 50
    RefreshInterval = 30
    DefaultExportPath = $PWD
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
        $script:InTUIConfig | ConvertTo-Json -Depth 3 | Set-Content $script:ConfigPath -Encoding UTF8
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
[grey]Config File:[/]        [white]$($script:ConfigPath)[/]
"@

        Show-InTUIPanel -Title "[blue]Current Settings[/]" -Content $content -BorderColor Blue

        $choices = @(
            'Change Page Size',
            'Change Refresh Interval',
            'Change Default Export Path',
            'Reset to Defaults',
            '─────────────',
            'Back'
        )

        $selection = Show-InTUIMenu -Title "[blue]Settings[/]" -Choices $choices

        Write-InTUILog -Message "Settings action" -Context @{ Selection = $selection }

        switch ($selection) {
            'Change Page Size' {
                $newSize = Read-SpectreText -Prompt "[blue]Page size (10-100)[/]" -DefaultValue "$($script:InTUIConfig.PageSize)"
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
                $newInterval = Read-SpectreText -Prompt "[blue]Refresh interval in seconds (10-300)[/]" -DefaultValue "$($script:InTUIConfig.RefreshInterval)"
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
                $newPath = Read-SpectreText -Prompt "[blue]Default export path[/]" -DefaultValue "$($script:InTUIConfig.DefaultExportPath)"
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
            'Reset to Defaults' {
                $confirm = Show-InTUIConfirm -Message "[yellow]Reset all settings to defaults?[/]"
                if ($confirm) {
                    $script:InTUIConfig = @{
                        PageSize        = 50
                        RefreshInterval = 30
                        DefaultExportPath = $PWD
                    }
                    $script:PageSize = 50
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
