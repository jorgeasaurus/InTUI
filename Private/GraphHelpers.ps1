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
        # Fallback if message is still empty
        if ([string]::IsNullOrWhiteSpace($errorMessage)) {
            $errorMessage = "Request failed (HTTP $($_.Exception.Response.StatusCode))"
            if ($_.Exception.Response.ReasonPhrase) {
                $errorMessage += " - $($_.Exception.Response.ReasonPhrase)"
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
        '*Windows*' { return "[blue]$([char]0x25A0)[/]" }      # Filled square
        '*iOS*'     { return "[grey]$([char]0x25CF)[/]" }      # Filled circle
        '*iPadOS*'  { return "[grey]$([char]0x25A3)[/]" }      # Square with dot
        '*macOS*'   { return "[grey]$([char]0x25C6)[/]" }      # Filled diamond
        '*Android*' { return "[green]$([char]0x25B2)[/]" }     # Filled triangle
        '*Linux*'   { return "[yellow]$([char]0x25C7)[/]" }    # Hollow diamond
        default     { return "[grey]$([char]0x25CB)[/]" }      # Hollow circle
    }
}

function Get-InTUIAppTypeIcon {
    <#
    .SYNOPSIS
        Returns an icon based on application type.
    #>
    param([string]$AppType)

    switch -Wildcard ($AppType) {
        '*win32*'           { return "[blue]$([char]0x2B1B)[/]" }
        '*msi*'             { return "[blue]$([char]0x229E)[/]" }
        '*ios*'             { return "[grey]$([char]0x25C9)[/]" }
        '*android*'         { return "[green]$([char]0x25B2)[/]" }
        '*webApp*'          { return "[cyan]$([char]0x2B58)[/]" }
        '*office*'          { return "[orange1]$([char]0x25A3)[/]" }
        '*microsoft*'       { return "[blue]$([char]0x25A0)[/]" }
        '*store*'           { return "[cyan]$([char]0x25A6)[/]" }
        '*managed*'         { return "[yellow]$([char]0x25A8)[/]" }
        default             { return "[grey]$([char]0x25A1)[/]" }
    }
}

function Get-InTUIPolicyIcon {
    <#
    .SYNOPSIS
        Returns an icon based on policy type.
    #>
    param([string]$PolicyType)

    switch -Wildcard ($PolicyType) {
        '*compliance*'      { return "[green]$([char]0x2713)[/]" }    # Check mark
        '*configuration*'   { return "[blue]$([char]0x2699)[/]" }     # Gear
        '*conditional*'     { return "[yellow]$([char]0x26A0)[/]" }   # Warning
        '*security*'        { return "[red]$([char]0x26E8)[/]" }      # Shield
        '*update*'          { return "[cyan]$([char]0x21BB)[/]" }     # Circular arrow
        default             { return "[grey]$([char]0x25A1)[/]" }     # Square
    }
}

function Get-InTUISecurityIcon {
    <#
    .SYNOPSIS
        Returns security-related icons.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Shield', 'Lock', 'Unlock', 'Key', 'Warning', 'Error', 'Check', 'Cross')]
        [string]$Type
    )

    switch ($Type) {
        'Shield'  { return "[blue]$([char]0x26E8)[/]" }
        'Lock'    { return "[green]$([char]0x25A3)[/]" }
        'Unlock'  { return "[yellow]$([char]0x25A2)[/]" }
        'Key'     { return "[yellow]$([char]0x2318)[/]" }
        'Warning' { return "[yellow]$([char]0x26A0)[/]" }
        'Error'   { return "[red]$([char]0x2717)[/]" }
        'Check'   { return "[green]$([char]0x2713)[/]" }
        'Cross'   { return "[red]$([char]0x2717)[/]" }
    }
}
