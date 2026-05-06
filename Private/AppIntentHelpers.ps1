function Get-InTUIAppIntentMobileApp {
    <#
    .SYNOPSIS
        Extracts mobile app entries from Graph mobileAppIntentAndState responses.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Response
    )

    if ($null -eq $Response -or $Response -eq $true) {
        return @()
    }

    if ($Response -is [string]) {
        $Response = $Response | ConvertFrom-Json -ErrorAction Stop
    }

    $intentStates = if ($Response.PSObject.Properties['value']) {
        @($Response.value)
    }
    else {
        @($Response)
    }

    $mobileApps = foreach ($intentState in $intentStates) {
        if ($intentState.mobileAppList) {
            @($intentState.mobileAppList)
        }
    }

    return @($mobileApps)
}
