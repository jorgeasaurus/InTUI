function Connect-InTUIGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune management.
    .PARAMETER Scopes
        Graph API permission scopes to request.
    .PARAMETER TenantId
        Optional tenant ID or domain.
    .PARAMETER Environment
        Cloud environment: Global, USGov, USGovDoD, or China.
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
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global'
    )

    $script:CloudEnvironment = $Environment
    $envConfig = $script:CloudEnvironments[$Environment]
    $script:GraphBaseUrl = $envConfig.GraphBaseUrl
    $script:GraphBetaUrl = $envConfig.GraphBetaUrl

    Write-InTUILog -Message "Connecting to Microsoft Graph" -Context @{
        Environment = $Environment
        GraphBaseUrl = $script:GraphBaseUrl
        TenantId = $TenantId
    }

    $params = @{
        Scopes = $Scopes
        NoWelcome = $true
        Environment = $envConfig.MgEnvironment
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
            Write-InTUILog -Message "Connected to Microsoft Graph" -Context @{
                TenantId = $context.TenantId
                Account = $context.Account
                Environment = $Environment
            }
            return $true
        }
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
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
        [int]$Top = 0,

        [Parameter()]
        [hashtable]$Headers
    )

    if (-not $script:Connected) {
        Write-InTUILog -Level 'WARN' -Message "Graph request attempted while not connected" -Context @{ Uri = $Uri }
        Write-SpectreHost "[red]Not connected to Microsoft Graph. Run Connect-InTUI first.[/]"
        return $null
    }

    $baseUrl = if ($Beta) { $script:GraphBetaUrl } else { $script:GraphBaseUrl }

    if ($Uri -notmatch '^https://') {
        $fullUri = "$baseUrl/$($Uri.TrimStart('/'))"
    }
    else {
        $fullUri = $Uri
    }

    if ($Top -gt 0 -and $Method -eq 'GET') {
        $separator = if ($fullUri -match '\?') { '&' } else { '?' }
        $fullUri = "$fullUri$separator`$top=$Top"
    }

    # Check cache for GET requests
    if ($Method -eq 'GET' -and $script:CacheEnabled) {
        $cached = Get-InTUICachedResponse -Uri $fullUri -Method $Method -Beta:$Beta
        if ($null -ne $cached) {
            return $cached
        }
    }

    Write-InTUILog -Message "Graph API request" -Context @{
        Method = $Method
        Uri = $fullUri
        Beta = [bool]$Beta
        All = [bool]$All
        Environment = $script:CloudEnvironment
    }

    # Record action for script recording (only write operations)
    if ($script:RecordingEnabled -and $Method -ne 'GET') {
        Add-InTUIRecordedAction -Method $Method -Uri $Uri -Body $Body -Beta:$Beta
    }

    $params = @{
        Uri    = $fullUri
        Method = $Method
        OutputType = 'PSObject'
    }

    if ($Headers) {
        $params['Headers'] = $Headers
    }

    if ($Body) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10
        $params['ContentType'] = 'application/json'
    }

    try {
        $response = Invoke-MgGraphRequest @params

        if ($All -and $Method -eq 'GET') {
            $allResults = [System.Collections.Generic.List[object]]::new()
            if ($response.value) {
                $allResults.AddRange(@($response.value))
            }

            $pageCount = 1
            while ($response.'@odata.nextLink') {
                $pageCount++
                Write-InTUILog -Message "Fetching pagination page $pageCount" -Context @{ NextLink = $response.'@odata.nextLink' }
                $response = Invoke-MgGraphRequest -Uri $response.'@odata.nextLink' -Method GET -OutputType PSObject
                if ($response.value) {
                    $allResults.AddRange(@($response.value))
                }
            }

            Write-InTUILog -Message "Graph API request completed" -Context @{ TotalResults = $allResults.Count; Pages = $pageCount }

            # Cache the paginated results
            if ($script:CacheEnabled) {
                Set-InTUICachedResponse -Uri $fullUri -Data $allResults -Method $Method -Beta:$Beta
            }

            return $allResults
        }

        $resultCount = if ($response.value) { @($response.value).Count } else { 1 }
        Write-InTUILog -Message "Graph API request completed" -Context @{ ResultCount = $resultCount }

        # Cache single-page response
        if ($Method -eq 'GET' -and $script:CacheEnabled) {
            Set-InTUICachedResponse -Uri $fullUri -Data $response -Method $Method -Beta:$Beta
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
        Write-InTUILog -Level 'ERROR' -Message "Graph API Error: $errorMessage" -Context @{ Uri = $fullUri; Method = $Method }
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
        [string]$Expand,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [switch]$IncludeCount
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
    if ($IncludeCount) {
        $queryParams += "`$count=true"
    }

    $fullUri = $Uri
    if ($queryParams.Count -gt 0) {
        $fullUri = "$Uri`?$($queryParams -join '&')"
    }

    $params = @{ Uri = $fullUri }
    if ($Beta) { $params['Beta'] = $true }
    if ($Headers) { $params['Headers'] = $Headers }

    $response = Invoke-InTUIGraphRequest @params

    $results = if ($response.value) { $response.value }
               elseif ($response -is [array]) { $response }
               else { @($response) }

    $totalCount = $response.'@odata.count' ?? @($results).Count

    return @{
        Results  = $results
        NextLink = $response.'@odata.nextLink'
        Count    = $totalCount
    }
}

function ConvertTo-InTUISafeFilterValue {
    <#
    .SYNOPSIS
        Escapes a string for safe use inside an OData $filter expression.
    #>
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    return $Value -replace "'", "''"
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
        'compliant'     { return 'green' }
        'noncompliant'  { return 'red' }
        'error'         { return 'red' }
        'inGracePeriod' { return 'yellow' }
        'configManager' { return 'blue' }
        'conflict'      { return 'orange1' }
        default         { return 'grey' }
    }
}

function Get-InTUIInstallStateColor {
    <#
    .SYNOPSIS
        Returns Spectre markup color based on app install state.
    #>
    param([string]$State)

    switch ($State) {
        'installed'       { return 'green' }
        'failed'          { return 'red' }
        'uninstallFailed' { return 'red' }
        'notInstalled'    { return 'grey' }
        'notApplicable'   { return 'grey' }
        default           { return 'yellow' }
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
