function Connect-InTUI {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for InTUI usage.
    .DESCRIPTION
        Establishes a connection to Microsoft Graph with the required scopes
        for Intune device, app, user, and group management. Supports multiple
        cloud environments including Commercial/GCC, GCC High, DoD, and China.
    .PARAMETER TenantId
        Optional tenant ID or domain to connect to a specific tenant.
    .PARAMETER Scopes
        Optional custom scopes. Defaults to Intune management scopes.
    .PARAMETER Environment
        Cloud environment to connect to: Global, USGov, USGovDoD, or China.
    .EXAMPLE
        Connect-InTUI
    .EXAMPLE
        Connect-InTUI -TenantId "contoso.onmicrosoft.com"
    .EXAMPLE
        Connect-InTUI -Environment USGov -TenantId "contoso.onmicrosoft.us"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string[]]$Scopes,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global'
    )

    $params = @{ Environment = $Environment }
    if ($TenantId) { $params['TenantId'] = $TenantId }
    if ($Scopes) { $params['Scopes'] = $Scopes }

    Clear-Host
    Show-InTUIHeader

    $envLabel = $script:CloudEnvironments[$Environment].Label
    Write-InTUILog -Message "Initiating connection" -Context @{ Environment = $Environment; TenantId = $TenantId }

    $result = Show-InTUILoading -Title "[blue]Connecting to Microsoft Graph ($envLabel)...[/]" -ScriptBlock {
        Connect-InTUIGraph @params
    }

    if ($result) {
        Show-InTUISuccess "Connected to Microsoft Graph ($envLabel)"
        Write-SpectreHost "[grey]Tenant:[/] [cyan]$($script:TenantId)[/]"
        Write-SpectreHost "[grey]Account:[/] [cyan]$($script:Account)[/]"
        Write-SpectreHost "[grey]Environment:[/] [cyan]$envLabel[/]"
    }
    else {
        Show-InTUIError "Failed to connect to Microsoft Graph ($envLabel)"
    }

    return $result
}
