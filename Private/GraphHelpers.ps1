function Connect-InTUIGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune management.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Scopes = @(
            'DeviceManagementManagedDevices.ReadWrite.All',
            'DeviceManagementApps.ReadWrite.All',
            'User.Read.All',
            'Group.Read.All',
            'GroupMember.Read.All',
            'DeviceManagementConfiguration.Read.All',
            'Directory.Read.All'
        ),

        [Parameter()]
        [string]$TenantId
    )

    $params = @{
        Scopes = $Scopes
        NoWelcome = $true
    }

    if ($TenantId) {
        $params['TenantId'] = $TenantId
    }

    try {
        Connect-MgGraph @params
        $context = Get-MgContext
        if ($context) {
            $script:Connected = $true
            $script:TenantId = $context.TenantId
            $script:Account = $context.Account
            return $true
        }
    }
    catch {
        Write-SpectreHost "[red]Failed to connect to Microsoft Graph: $($_.Exception.Message)[/]"
        return $false
    }
    return $false
}

function Invoke-InTUIGraphRequest {
    <#
    .SYNOPSIS
        Wrapper around Invoke-MgGraphRequest with error handling and pagination support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [switch]$Beta,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [int]$Top = 0
    )

    if (-not $script:Connected) {
        Write-SpectreHost "[red]Not connected to Microsoft Graph. Run Connect-InTUI first.[/]"
        return $null
    }

    $baseUrl = if ($Beta) { $script:GraphBetaUrl } else { $script:GraphBaseUrl }

    # Build the full URI
    if ($Uri -notmatch '^https://') {
        $fullUri = "$baseUrl/$($Uri.TrimStart('/'))"
    }
    else {
        $fullUri = $Uri
    }

    # Add $top parameter if specified
    if ($Top -gt 0 -and $Method -eq 'GET') {
        $separator = if ($fullUri -match '\?') { '&' } else { '?' }
        $fullUri = "$fullUri$separator`$top=$Top"
    }

    $params = @{
        Uri    = $fullUri
        Method = $Method
        OutputType = 'PSObject'
    }

    if ($Body) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10
        $params['ContentType'] = 'application/json'
    }

    try {
        $response = Invoke-MgGraphRequest @params

        if ($All -and $Method -eq 'GET') {
            # Handle pagination
            $allResults = @()
            if ($response.value) {
                $allResults += $response.value
            }

            while ($response.'@odata.nextLink') {
                $response = Invoke-MgGraphRequest -Uri $response.'@odata.nextLink' -Method GET -OutputType PSObject
                if ($response.value) {
                    $allResults += $response.value
                }
            }

            return $allResults
        }

        if ($response.value) {
            return $response
        }

        return $response
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorDetail = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = "$($errorDetail.error.code): $($errorDetail.error.message)"
            }
            catch {
                $errorMessage = $_.ErrorDetails.Message
            }
        }
        Write-SpectreHost "[red]Graph API Error: $errorMessage[/]"
        return $null
    }
}

function Get-InTUIPagedResults {
    <#
    .SYNOPSIS
        Gets paged results from Graph API with navigation support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [switch]$Beta,

        [Parameter()]
        [int]$PageSize = $script:PageSize,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Search,

        [Parameter()]
        [string]$Select,

        [Parameter()]
        [string]$OrderBy,

        [Parameter()]
        [string]$Expand
    )

    $queryParams = @()

    if ($PageSize -gt 0) {
        $queryParams += "`$top=$PageSize"
    }
    if ($Filter) {
        $queryParams += "`$filter=$Filter"
    }
    if ($Search) {
        $queryParams += "`$search=`"$Search`""
    }
    if ($Select) {
        $queryParams += "`$select=$Select"
    }
    if ($OrderBy) {
        $queryParams += "`$orderby=$OrderBy"
    }
    if ($Expand) {
        $queryParams += "`$expand=$Expand"
    }

    $fullUri = $Uri
    if ($queryParams.Count -gt 0) {
        $fullUri = "$Uri`?$($queryParams -join '&')"
    }

    $params = @{
        Uri    = $fullUri
        Method = 'GET'
    }
    if ($Beta) { $params['Beta'] = $true }

    $response = Invoke-InTUIGraphRequest @params

    return @{
        Results  = if ($response.value) { $response.value } elseif ($response -is [array]) { $response } else { @($response) }
        NextLink = $response.'@odata.nextLink'
        Count    = $response.'@odata.count'
    }
}

function Format-InTUIDate {
    <#
    .SYNOPSIS
        Formats a date string for display.
    #>
    param([string]$DateString)

    if ([string]::IsNullOrEmpty($DateString)) { return 'N/A' }

    try {
        $date = [DateTime]::Parse($DateString)
        $now = [DateTime]::UtcNow
        $diff = $now - $date

        if ($diff.TotalMinutes -lt 60) {
            return "$([math]::Floor($diff.TotalMinutes))m ago"
        }
        elseif ($diff.TotalHours -lt 24) {
            return "$([math]::Floor($diff.TotalHours))h ago"
        }
        elseif ($diff.TotalDays -lt 7) {
            return "$([math]::Floor($diff.TotalDays))d ago"
        }
        else {
            return $date.ToString('yyyy-MM-dd HH:mm')
        }
    }
    catch {
        return $DateString
    }
}

function Get-InTUIComplianceColor {
    <#
    .SYNOPSIS
        Returns Spectre markup color based on compliance state.
    #>
    param([string]$State)

    switch ($State) {
        'compliant'    { return 'green' }
        'noncompliant' { return 'red' }
        'inGracePeriod' { return 'yellow' }
        'configManager' { return 'blue' }
        'conflict'     { return 'orange1' }
        'error'        { return 'red' }
        'unknown'      { return 'grey' }
        default        { return 'grey' }
    }
}

function Get-InTUIDeviceIcon {
    <#
    .SYNOPSIS
        Returns an icon character based on OS type.
    #>
    param([string]$OperatingSystem)

    switch -Wildcard ($OperatingSystem) {
        '*Windows*' { return '[blue]■[/]' }
        '*iOS*'     { return '[grey]●[/]' }
        '*macOS*'   { return '[grey]◆[/]' }
        '*Android*' { return '[green]▲[/]' }
        '*Linux*'   { return '[yellow]◇[/]' }
        default     { return '[grey]○[/]' }
    }
}
