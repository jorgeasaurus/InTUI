function Connect-InTUIGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune management.
    .PARAMETER Scopes
        Graph API permission scopes to request (interactive auth only).
    .PARAMETER TenantId
        Optional tenant ID or domain.
    .PARAMETER ClientId
        Application (client) ID for service principal auth.
    .PARAMETER ClientSecret
        Client secret for service principal auth.
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
            'Directory.Read.All',
            'AuditLog.Read.All'
        ),

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$ClientSecret,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global'
    )

    $script:CloudEnvironment = $Environment
    $envConfig = $script:CloudEnvironments[$Environment]
    $script:GraphBaseUrl = $envConfig.GraphBaseUrl
    $script:GraphBetaUrl = $envConfig.GraphBetaUrl

    $useClientCredential = $ClientId -and $ClientSecret -and $TenantId

    Write-InTUILog -Message "Connecting to Microsoft Graph" -Context @{
        Environment  = $Environment
        GraphBaseUrl = $script:GraphBaseUrl
        TenantId     = $TenantId
        AuthMode     = if ($useClientCredential) { 'ClientCredential' } else { 'Interactive' }
    }

    try {
        if ($useClientCredential) {
            $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new($ClientId, $secureSecret)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -Environment $envConfig.MgEnvironment
        }
        else {
            $params = @{
                Scopes      = $Scopes
                NoWelcome   = $true
                Environment = $envConfig.MgEnvironment
            }
            if ($TenantId) { $params['TenantId'] = $TenantId }
            Connect-MgGraph @params
        }

        $context = Get-MgContext
        if (-not $context) { return $false }

        $script:Connected = $true
        $script:TenantId = $context.TenantId
        $script:Account = $context.Account ?? $ClientId
        Write-InTUILog -Message "Connected to Microsoft Graph" -Context @{
            TenantId    = $context.TenantId
            Account     = $script:Account
            Environment = $Environment
        }
        return $true
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        Write-InTUIText "[red]Failed to connect to Microsoft Graph: $($_.Exception.Message)[/]"
        return $false
    }
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
        Write-InTUIText "[red]Not connected to Microsoft Graph. Run Connect-InTUI first.[/]"
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

        # Return $true for no-content success (e.g., 204) so $null exclusively means error
        return ($response ?? $true)
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
        Write-InTUIText "[red]Graph API Error: $errorMessage[/]"
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

    # Guard: null or non-object response (e.g. $true from 204 No Content)
    if ($null -eq $response -or $response -is [bool]) {
        return @{ Results = @(); NextLink = $null; TotalCount = 0 }
    }

    $results = if ($response.value) { @($response.value) }
               elseif ($response -is [array]) { $response }
               else { @() }

    $resultCount = @($results).Count
    $odataCount = $response.'@odata.count'
    # Use @odata.count only when present and sensible (>= page results); otherwise use actual count
    $totalCount = if ($null -ne $odataCount -and $odataCount -ge $resultCount) { $odataCount } else { $resultCount }

    return @{
        Results    = $results
        NextLink   = $response.'@odata.nextLink'
        TotalCount = $totalCount
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
        Returns markup color name based on compliance state.
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
        Returns markup color name based on app install state.
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
        '*Windows*' { return '[blue]W[/]' }
        '*iOS*'     { return '[grey]i[/]' }
        '*iPadOS*'  { return '[grey]P[/]' }
        '*macOS*'   { return '[grey]m[/]' }
        '*Android*' { return '[green]A[/]' }
        '*Linux*'   { return '[yellow]L[/]' }
        default     { return '[grey]-[/]' }
    }
}

function Get-InTUIAppTypeIcon {
    <#
    .SYNOPSIS
        Returns an icon based on application type.
    #>
    param([string]$AppType)

    switch -Wildcard ($AppType) {
        '*win32*'           { return '[blue]W[/]' }
        '*msi*'             { return '[blue]M[/]' }
        '*ios*'             { return '[grey]i[/]' }
        '*android*'         { return '[green]A[/]' }
        '*webApp*'          { return '[cyan]w[/]' }
        '*office*'          { return '[orange1]O[/]' }
        '*microsoft*'       { return '[blue]M[/]' }
        '*store*'           { return '[cyan]S[/]' }
        '*managed*'         { return '[yellow]m[/]' }
        default             { return '[grey]-[/]' }
    }
}

function Get-InTUIPolicyIcon {
    <#
    .SYNOPSIS
        Returns an icon based on policy type.
    #>
    param([string]$PolicyType)

    switch -Wildcard ($PolicyType) {
        '*compliance*'      { return '[green]+[/]' }
        '*configuration*'   { return '[blue]*[/]' }
        '*conditional*'     { return '[yellow]![/]' }
        '*security*'        { return '[red]#[/]' }
        '*update*'          { return '[cyan]~[/]' }
        default             { return '[grey]-[/]' }
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
        'Shield'  { return '[blue]#[/]' }
        'Lock'    { return '[green]#[/]' }
        'Unlock'  { return '[yellow]-[/]' }
        'Key'     { return '[yellow]k[/]' }
        'Warning' { return '[yellow]![/]' }
        'Error'   { return '[red]x[/]' }
        'Check'   { return '[green]+[/]' }
        'Cross'   { return '[red]x[/]' }
    }
}
