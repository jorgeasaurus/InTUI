function Connect-InTUI {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for InTUI usage.
    .DESCRIPTION
        Establishes a connection to Microsoft Graph with the required scopes
        for Intune device, app, user, and group management. Supports interactive
        auth (browser-based) and service principal auth (ClientId/ClientSecret).
    .PARAMETER TenantId
        Optional tenant ID or domain to connect to a specific tenant.
        Required for service principal auth.
    .PARAMETER ClientId
        Application (client) ID for service principal authentication.
    .PARAMETER ClientSecret
        Client secret for service principal authentication.
    .PARAMETER Scopes
        Optional custom scopes. Defaults to Intune management scopes.
        Only used for interactive auth.
    .PARAMETER UseDeviceCode
        Use device code flow for headless/remote terminals.
    .PARAMETER Interactive
        Launch the interactive connection wizard to choose environment,
        auth method, and enter credentials via TUI menus.
    .PARAMETER Environment
        Cloud environment to connect to: Global, USGov, USGovDoD, or China.
    .EXAMPLE
        Connect-InTUI
    .EXAMPLE
        Connect-InTUI -Interactive
    .EXAMPLE
        Connect-InTUI -TenantId "contoso.onmicrosoft.com"
    .EXAMPLE
        Connect-InTUI -TenantId $tid -ClientId $cid -ClientSecret $sec
    .EXAMPLE
        Connect-InTUI -UseDeviceCode
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$ClientSecret,

        [Parameter()]
        [string[]]$Scopes,

        [Parameter()]
        [switch]$UseDeviceCode,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global'
    )

    if ($Interactive) {
        $wizardResult = Show-InTUIConnectionWizard
        if (-not $wizardResult) { return $false }

        # If connecting via saved profile, route to tenant switcher logic
        if ($wizardResult.FromProfile) {
            $selectedProfile = $wizardResult.Profile
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            $script:Connected = $false
            $connected = Connect-InTUI -TenantId $selectedProfile.TenantId -Environment $selectedProfile.Environment
            if ($connected) {
                $selectedProfile.LastUsed = (Get-Date).ToString('yyyy-MM-dd HH:mm')
                $selectedProfile.Account = $script:Account
                $allProfiles = @(Get-InTUITenantProfiles)
                $allProfiles | ConvertTo-Json -Depth 5 | Set-Content $script:TenantProfilePath -Encoding UTF8
            }
            return $connected
        }

        # Apply wizard selections
        $Environment = $wizardResult.Environment
        if ($wizardResult.TenantId) { $TenantId = $wizardResult.TenantId }
        if ($wizardResult.ClientId) { $ClientId = $wizardResult.ClientId }
        if ($wizardResult.ClientSecret) { $ClientSecret = $wizardResult.ClientSecret }
        if ($wizardResult.UseDeviceCode) { $UseDeviceCode = [switch]$true }
    }

    $params = @{ Environment = $Environment }
    if ($TenantId) { $params['TenantId'] = $TenantId }
    if ($ClientId) { $params['ClientId'] = $ClientId }
    if ($ClientSecret) { $params['ClientSecret'] = $ClientSecret }
    if ($Scopes) { $params['Scopes'] = $Scopes }
    if ($UseDeviceCode) { $params['UseDeviceCode'] = $true }

    Clear-Host
    Show-InTUIHeader

    $envLabel = $script:CloudEnvironments[$Environment].Label
    $authMode = if ($ClientId -and $ClientSecret) { 'Service Principal' }
                elseif ($UseDeviceCode) { 'Device Code' }
                else { 'Interactive' }
    Write-InTUILog -Message "Initiating connection" -Context @{ Environment = $Environment; TenantId = $TenantId; AuthMode = $authMode }

    $result = Show-InTUILoading -Title "[blue]Connecting to Microsoft Graph ($envLabel - $authMode)...[/]" -ScriptBlock {
        Connect-InTUIGraph @params
    }

    if (-not $result) {
        Show-InTUIError "Failed to connect to Microsoft Graph ($envLabel)"
        return $result
    }

    Show-InTUISuccess "Connected to Microsoft Graph ($envLabel)"
    $maskedTenant = $script:TenantId
    if ($maskedTenant -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        $tParts = $maskedTenant -split '-'
        $maskedTenant = '{0}-****-****-****-********{1}' -f $tParts[0], $tParts[4].Substring(8)
    }
    Write-InTUIText "[grey]Tenant:[/] [cyan]$maskedTenant[/]"
    Write-InTUIText "[grey]Account:[/] [cyan]$($script:Account)[/]"
    Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"

    if ($Interactive) {
        Write-Host ''
        $save = Read-InTUIConfirmInput -Message "[blue]Save this connection as a tenant profile?[/]"
        if ($save) {
            Save-InTUITenantProfile
        }
    }

    return $result
}
