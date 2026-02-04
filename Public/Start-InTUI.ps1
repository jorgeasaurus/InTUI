function Start-InTUI {
    <#
    .SYNOPSIS
        Launches the InTUI - Intune Terminal User Interface.
    .DESCRIPTION
        Starts the interactive terminal UI for managing Microsoft Intune
        resources including Devices, Apps, Users, and Groups.
    .PARAMETER TenantId
        Optional tenant ID to connect to a specific tenant.
    .PARAMETER SkipConnect
        Skip the connection step (useful if already connected).
    .EXAMPLE
        Start-InTUI
    .EXAMPLE
        Start-InTUI -TenantId "contoso.onmicrosoft.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$SkipConnect
    )

    # Check if already connected
    if (-not $SkipConnect) {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            $script:Connected = $true
            $script:TenantId = $context.TenantId
            $script:Account = $context.Account
        }
        else {
            $params = @{}
            if ($TenantId) { $params['TenantId'] = $TenantId }
            $connected = Connect-InTUI @params
            if (-not $connected) {
                return
            }
        }
    }

    # Main navigation loop
    $exitApp = $false

    while (-not $exitApp) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home')
        Show-InTUIDashboard

        $mainChoices = @(
            'Devices',
            'Apps',
            'Users',
            'Groups',
            '─────────────',
            'Refresh Dashboard',
            'Switch Tenant',
            'Exit'
        )

        $selection = Show-InTUIMenu -Title "[blue]Navigate to[/]" -Choices $mainChoices

        switch ($selection) {
            'Devices' {
                Show-InTUIDevicesView
            }
            'Apps' {
                Show-InTUIAppsView
            }
            'Users' {
                Show-InTUIUsersView
            }
            'Groups' {
                Show-InTUIGroupsView
            }
            'Refresh Dashboard' {
                continue
            }
            'Switch Tenant' {
                $newTenant = Read-SpectreText -Prompt "[blue]Enter Tenant ID or domain[/]"
                if ($newTenant) {
                    Disconnect-MgGraph -ErrorAction SilentlyContinue
                    $script:Connected = $false
                    Connect-InTUI -TenantId $newTenant
                }
            }
            'Exit' {
                $exitApp = $true
            }
            default {
                continue
            }
        }
    }

    Clear-Host
    Write-SpectreHost "[blue]Thanks for using InTUI![/]"
}
