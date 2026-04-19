function Show-InTUIConnectionWizard {
    <#
    .SYNOPSIS
        Interactive TUI-driven connection wizard for Microsoft Graph.
    .DESCRIPTION
        Presents a guided menu flow for selecting cloud environment, auth method,
        and credentials. Returns connection parameters or $null if cancelled.
    #>
    [CmdletBinding()]
    param()

    # Step 0: Check for saved tenant profiles
    $profiles = @(Get-InTUITenantProfiles)

    if ($profiles.Count -gt 0) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Connect')

        $choices = @()
        foreach ($tp in $profiles) {
            $envLabel = if ($script:CloudEnvironments[$tp.Environment]) {
                $script:CloudEnvironments[$tp.Environment].Label
            } else { $tp.Environment }
            $choices += "$($tp.Label) [grey]| $envLabel | Last: $($tp.LastUsed)[/]"
        }

        $choiceMap = Get-InTUIChoiceMap -Choices $choices
        $menuChoices = @($choiceMap.Choices + '─────────────' + 'New Connection' + 'Cancel')

        $selection = Show-InTUIMenu -Title "[blue]Saved Tenant Profiles[/]" -Choices $menuChoices

        if ($selection -eq 'Cancel') { return $null }

        if ($selection -ne 'New Connection') {
            $idx = $choiceMap.IndexMap[$selection]
            if ($null -ne $idx -and $idx -lt $profiles.Count) {
                $selected = $profiles[$idx]
                Write-InTUILog -Message "Connecting via saved profile" -Context @{
                    Label = $selected.Label
                    TenantId = $selected.TenantId
                    Environment = $selected.Environment
                }
                return @{
                    TenantId    = $selected.TenantId
                    Environment = $selected.Environment
                    FromProfile = $true
                    Profile     = $selected
                }
            }
        }
    }

    # Step 1: Select cloud environment
    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Connect', 'Environment')

    $envChoices = @()
    foreach ($envKey in @('Global', 'USGov', 'USGovDoD', 'China')) {
        $envDef = $script:CloudEnvironments[$envKey]
        $envChoices += $envDef.Label
    }
    $envChoices += '─────────────'
    $envChoices += 'Cancel'

    $envSelection = Show-InTUIMenu -Title "[blue]Select Cloud Environment[/]" -Choices $envChoices
    if ($envSelection -eq 'Cancel') { return $null }

    $environment = switch -Wildcard ($envSelection) {
        '*DoD*'        { 'USGovDoD' }
        '*GCC High*'   { 'USGov' }
        '*Commercial*' { 'Global' }
        '*China*'      { 'China' }
        default        { 'Global' }
    }

    # Step 2: Select auth method
    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Connect', 'Auth Method')

    $envLabel = $script:CloudEnvironments[$environment].Label
    Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"
    Write-Host ''

    $authChoices = @(
        'Interactive (Browser)',
        'Device Code (Headless)',
        'Service Principal (App)',
        '─────────────',
        'Back'
    )

    $authSelection = Show-InTUIMenu -Title "[blue]Select Authentication Method[/]" -Choices $authChoices
    if ($authSelection -eq 'Back') { return Show-InTUIConnectionWizard }

    $params = @{ Environment = $environment }

    switch ($authSelection) {
        'Interactive (Browser)' {
            Clear-Host
            Show-InTUIHeader
            Show-InTUIBreadcrumb -Path @('Connect', 'Interactive')

            Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"
            Write-InTUIText "[grey]Auth:[/]        [cyan]Interactive (Browser)[/]"
            Write-Host ''

            $tenantId = Read-InTUITextInput -Message "[blue]Tenant ID or domain[/] [grey](optional, press Enter to skip)[/]"
            if ($tenantId) { $params['TenantId'] = $tenantId }
        }

        'Device Code (Headless)' {
            Clear-Host
            Show-InTUIHeader
            Show-InTUIBreadcrumb -Path @('Connect', 'Device Code')

            Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"
            Write-InTUIText "[grey]Auth:[/]        [cyan]Device Code[/]"
            Write-Host ''

            $tenantId = Read-InTUITextInput -Message "[blue]Tenant ID or domain[/] [grey](optional, press Enter to skip)[/]"
            if ($tenantId) { $params['TenantId'] = $tenantId }
            $params['UseDeviceCode'] = $true
        }

        'Service Principal (App)' {
            Clear-Host
            Show-InTUIHeader
            Show-InTUIBreadcrumb -Path @('Connect', 'Service Principal')

            Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"
            Write-InTUIText "[grey]Auth:[/]        [cyan]Service Principal[/]"
            Write-Host ''

            $tenantId = Read-InTUITextInput -Message "[blue]Tenant ID[/] [grey](required)[/]"
            if (-not $tenantId) {
                Show-InTUIWarning "Tenant ID is required for service principal auth."
                Read-InTUIKey
                return Show-InTUIConnectionWizard
            }

            $clientId = Read-InTUITextInput -Message "[blue]Application (Client) ID[/] [grey](required)[/]"
            if (-not $clientId) {
                Show-InTUIWarning "Client ID is required for service principal auth."
                Read-InTUIKey
                return Show-InTUIConnectionWizard
            }

            $ansiMsg = ConvertFrom-InTUIMarkup -Text "[blue]Client Secret[/] [grey](required)[/]"
            Write-Host "${ansiMsg}: " -NoNewline
            $clientSecret = Read-Host -MaskInput
            if (-not $clientSecret) {
                Show-InTUIWarning "Client Secret is required for service principal auth."
                Read-InTUIKey
                return Show-InTUIConnectionWizard
            }

            $params['TenantId'] = $tenantId
            $params['ClientId'] = $clientId
            $params['ClientSecret'] = $clientSecret
        }

        default { return $null }
    }

    return $params
}
