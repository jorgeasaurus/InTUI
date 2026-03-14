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
    .PARAMETER Environment
        Cloud environment to connect to: Global, USGov, USGovDoD, or China.
    .EXAMPLE
        Connect-InTUI
    .EXAMPLE
        Connect-InTUI -TenantId "contoso.onmicrosoft.com"
    .EXAMPLE
        Connect-InTUI -TenantId $tid -ClientId $cid -ClientSecret $sec
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
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global'
    )

    $params = @{ Environment = $Environment }
    if ($TenantId) { $params['TenantId'] = $TenantId }
    if ($ClientId) { $params['ClientId'] = $ClientId }
    if ($ClientSecret) { $params['ClientSecret'] = $ClientSecret }
    if ($Scopes) { $params['Scopes'] = $Scopes }

    Clear-Host
    Show-InTUIHeader

    $envLabel = $script:CloudEnvironments[$Environment].Label
    $authMode = if ($ClientId -and $ClientSecret) { 'Service Principal' } else { 'Interactive' }
    Write-InTUILog -Message "Initiating connection" -Context @{ Environment = $Environment; TenantId = $TenantId; AuthMode = $authMode }

    $result = Show-InTUILoading -Title "[blue]Connecting to Microsoft Graph ($envLabel - $authMode)...[/]" -ScriptBlock {
        Connect-InTUIGraph @params
    }

    if (-not $result) {
        Show-InTUIError "Failed to connect to Microsoft Graph ($envLabel)"
        return $result
    }

    Show-InTUISuccess "Connected to Microsoft Graph ($envLabel)"
    Write-InTUIText "[grey]Tenant:[/] [cyan]$($script:TenantId)[/]"
    Write-InTUIText "[grey]Account:[/] [cyan]$($script:Account)[/]"
    Write-InTUIText "[grey]Environment:[/] [cyan]$envLabel[/]"
    return $result
}
