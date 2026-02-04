function Connect-InTUI {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for InTUI usage.
    .DESCRIPTION
        Establishes a connection to Microsoft Graph with the required scopes
        for Intune device, app, user, and group management.
    .PARAMETER TenantId
        Optional tenant ID to connect to a specific tenant.
    .PARAMETER Scopes
        Optional custom scopes. Defaults to Intune management scopes.
    .EXAMPLE
        Connect-InTUI
    .EXAMPLE
        Connect-InTUI -TenantId "contoso.onmicrosoft.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string[]]$Scopes
    )

    $params = @{}
    if ($TenantId) { $params['TenantId'] = $TenantId }
    if ($Scopes) { $params['Scopes'] = $Scopes }

    Clear-Host
    Show-InTUIHeader

    $result = Show-InTUILoading -Title "[blue]Connecting to Microsoft Graph...[/]" -ScriptBlock {
        Connect-InTUIGraph @params
    }

    if ($result) {
        Show-InTUISuccess "Connected to Microsoft Graph"
        Write-SpectreHost "[grey]Tenant:[/] [cyan]$($script:TenantId)[/]"
        Write-SpectreHost "[grey]Account:[/] [cyan]$($script:Account)[/]"
    }
    else {
        Show-InTUIError "Failed to connect to Microsoft Graph"
    }

    return $result
}
