function Get-InTUIPimRequiredScopes {
    [CmdletBinding()]
    param()

    return @(
        'RoleEligibilitySchedule.Read.Directory',
        'RoleAssignmentSchedule.ReadWrite.Directory',
        'RoleManagement.Read.Directory'
    )
}

function Get-InTUIPimConnectionScopes {
    [CmdletBinding()]
    param()

    $baseScopes = @(
        'DeviceManagementManagedDevices.ReadWrite.All',
        'DeviceManagementManagedDevices.PrivilegedOperations.All',
        'DeviceManagementApps.ReadWrite.All',
        'User.Read.All',
        'Group.Read.All',
        'GroupMember.Read.All',
        'DeviceManagementConfiguration.Read.All',
        'DeviceManagementServiceConfig.Read.All',
        'Directory.Read.All',
        'AuditLog.Read.All',
        'BitlockerKey.ReadBasic.All',
        'BitlockerKey.Read.All'
    )

    return @($baseScopes + (Get-InTUIPimRequiredScopes) | Select-Object -Unique)
}

function Test-InTUIPimDelegatedContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Context = (Get-MgContext)
    )

    if ($null -eq $Context) {
        return $false
    }

    $authType = [string]($Context.AuthType ?? '')
    if ($authType -match 'AppOnly|ClientCredential|ManagedIdentity') {
        return $false
    }

    return -not [string]::IsNullOrWhiteSpace([string]$Context.Account)
}

function Test-InTUIPimPermissionError {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$ErrorInfo
    )

    if ($null -eq $ErrorInfo) {
        return $false
    }

    $statusCode = [string]$ErrorInfo.StatusCode
    return ($statusCode -eq 'Forbidden' -or $statusCode -eq 'Unauthorized' -or $statusCode -eq '403' -or $statusCode -eq '401') -and
        ([string]$ErrorInfo.Uri -match '/roleManagement/directory/')
}

function ConvertTo-InTUIPimDuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 24)]
        [int]$Hours
    )

    return "PT$($Hours)H"
}

function Test-InTUIPimReason {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Reason
    )

    return -not [string]::IsNullOrWhiteSpace($Reason)
}

function ConvertTo-InTUIPimRedactedReason {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Reason,

        [Parameter()]
        [int]$PrefixLength = 40
    )

    if ([string]::IsNullOrWhiteSpace($Reason)) {
        return ''
    }

    $trimmed = $Reason.Trim()
    if ($trimmed.Length -le $PrefixLength) {
        return $trimmed
    }

    return "$($trimmed.Substring(0, $PrefixLength))... [redacted]"
}

function Get-InTUIPimRoleKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Role
    )

    return "$($Role.RoleDefinitionId)|$($Role.DirectoryScopeId)|$($Role.AppScopeId)"
}

function Get-InTUIPimScopeLabel {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DirectoryScopeId
    )

    if ([string]::IsNullOrWhiteSpace($DirectoryScopeId) -or $DirectoryScopeId -eq '/') {
        return 'Tenant'
    }

    return $DirectoryScopeId
}

function Get-InTUIPimObjectValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($itemName in $Name) {
            if ($InputObject.Contains($itemName)) {
                return $InputObject[$itemName]
            }
        }

        foreach ($key in $InputObject.Keys) {
            foreach ($itemName in $Name) {
                if ([string]::Equals([string]$key, $itemName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $InputObject[$key]
                }
            }
        }
    }

    foreach ($itemName in $Name) {
        $property = $InputObject.PSObject.Properties[$itemName]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        foreach ($itemName in $Name) {
            if ([string]::Equals($property.Name, $itemName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $property.Value
            }
        }
    }

    $additionalProperties = $InputObject.PSObject.Properties['AdditionalProperties']?.Value
    if ($additionalProperties -is [System.Collections.IDictionary]) {
        $value = Get-InTUIPimObjectValue -InputObject $additionalProperties -Name $Name
        if ($null -ne $value) {
            return $value
        }
    }

    foreach ($itemName in $Name) {
        try {
            $value = $InputObject[$itemName]
            if ($null -ne $value) {
                return $value
            }
        }
        catch {
            # Some Graph SDK objects do not expose an indexer.
        }
    }

    return $null
}

function ConvertTo-InTUIPimPlainObject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    try {
        $json = $InputObject | ConvertTo-Json -Depth 20 -Compress
        if ([string]::IsNullOrWhiteSpace($json) -or $json -eq 'null') {
            return $null
        }

        return ($json | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function ConvertTo-InTUIPimPlainObjectArray {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$InputObject = @()
    )

    if ($InputObject.Count -eq 0) {
        return @()
    }

    try {
        $json = @($InputObject) | ConvertTo-Json -Depth 20 -Compress
        if ([string]::IsNullOrWhiteSpace($json) -or $json -eq 'null') {
            return @()
        }

        return @($json | ConvertFrom-Json)
    }
    catch {
        return @()
    }
}

function Write-InTUIPimConversionDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Items = @(),

        [Parameter(Mandatory)]
        [string]$Source
    )

    if ($Items.Count -eq 0) {
        return
    }

    $first = $Items[0]
    if ($null -eq $first) {
        Write-InTUILog -Level 'WARN' -Message 'PIM role conversion produced no usable roles' -Context @{
            Source        = $Source
            FirstItemType = 'null'
            PropertyNames = ''
            Keys          = ''
        }
        return
    }

    $propertyNames = @($first.PSObject.Properties | Select-Object -ExpandProperty Name)
    $keys = @()
    if ($first -is [System.Collections.IDictionary]) {
        $keys = @($first.Keys)
    }

    Write-InTUILog -Level 'WARN' -Message 'PIM role conversion produced no usable roles' -Context @{
        Source        = $Source
        FirstItemType = $first.GetType().FullName
        PropertyNames = ($propertyNames -join ',')
        Keys          = ($keys -join ',')
    }
}

function ConvertTo-InTUIPimRoleCollection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Items = @(),

        [Parameter(Mandatory)]
        [string]$Source
    )

    $roles = @($Items | ForEach-Object { ConvertTo-InTUIPimRoleItem -Schedule $_ } | Where-Object { $null -ne $_ } | Sort-Object DisplayName, DirectoryScopeId)
    if ($roles.Count -gt 0 -or $Items.Count -eq 0) {
        return $roles
    }

    $plainItems = ConvertTo-InTUIPimPlainObjectArray -InputObject $Items
    if ($plainItems.Count -gt 0) {
        $roles = @($plainItems | ForEach-Object { ConvertTo-InTUIPimRoleItem -Schedule $_ } | Where-Object { $null -ne $_ } | Sort-Object DisplayName, DirectoryScopeId)
        if ($roles.Count -gt 0) {
            return $roles
        }
    }

    Write-InTUIPimConversionDiagnostic -Items $Items -Source $Source
    return @()
}

function Get-InTUIPimGraphResultItems {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Response
    )

    if ($null -eq $Response) {
        return @()
    }

    if ($Response -is [System.Collections.IDictionary]) {
        if ($Response.Contains('value')) {
            return @($Response['value'])
        }

        return @($Response)
    }

    $valueProperty = $Response.PSObject.Properties['value']
    if ($null -ne $valueProperty) {
        return @($valueProperty.Value)
    }

    return @($Response)
}

function ConvertTo-InTUIPimRoleItem {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Schedule
    )

    if ($null -eq $Schedule) {
        return $null
    }

    $principalId = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('principalId', 'PrincipalId')
    $roleDefinitionId = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('roleDefinitionId', 'RoleDefinitionId')
    if ([string]::IsNullOrWhiteSpace([string]$principalId) -or
        [string]::IsNullOrWhiteSpace([string]$roleDefinitionId)) {
        $plainSchedule = ConvertTo-InTUIPimPlainObject -InputObject $Schedule
        if ($null -ne $plainSchedule -and -not [object]::ReferenceEquals($plainSchedule, $Schedule)) {
            $principalId = Get-InTUIPimObjectValue -InputObject $plainSchedule -Name @('principalId', 'PrincipalId')
            $roleDefinitionId = Get-InTUIPimObjectValue -InputObject $plainSchedule -Name @('roleDefinitionId', 'RoleDefinitionId')
            if (-not [string]::IsNullOrWhiteSpace([string]$principalId) -and
                -not [string]::IsNullOrWhiteSpace([string]$roleDefinitionId)) {
                $Schedule = $plainSchedule
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$principalId) -or
        [string]::IsNullOrWhiteSpace([string]$roleDefinitionId)) {
        return $null
    }

    $roleDefinition = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('roleDefinition', 'RoleDefinition')
    $roleName = (Get-InTUIPimObjectValue -InputObject $roleDefinition -Name @('displayName', 'DisplayName')) ??
        (Get-InTUIPimObjectValue -InputObject $Schedule -Name @('roleDefinitionDisplayName', 'RoleDefinitionDisplayName')) ??
        $roleDefinitionId ??
        'Unknown role'
    $scopeId = (Get-InTUIPimObjectValue -InputObject $Schedule -Name @('directoryScopeId', 'DirectoryScopeId')) ?? '/'

    [pscustomobject]@{
        Id               = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('id', 'Id')
        DisplayName      = [string]$roleName
        PrincipalId      = [string]$principalId
        RoleDefinitionId = [string]$roleDefinitionId
        DirectoryScopeId = [string]$scopeId
        AppScopeId       = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('appScopeId', 'AppScopeId')
        StartDateTime    = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('startDateTime', 'StartDateTime', 'createdDateTime', 'CreatedDateTime')
        EndDateTime      = Get-InTUIPimObjectValue -InputObject $Schedule -Name @('endDateTime', 'EndDateTime')
        Source           = $Schedule
    }
}

function Set-InTUIPimRoleDisplayName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Roles = @()
    )

    $rolesMissingNames = @($Roles | Where-Object { $_.DisplayName -eq $_.RoleDefinitionId })
    if ($rolesMissingNames.Count -eq 0) {
        return $Roles
    }

    $definitions = @(Invoke-InTUIGraphRequest -Uri '/roleManagement/directory/roleDefinitions?$select=id,displayName' -All -NoCache)
    if ($definitions.Count -eq 0) {
        return $Roles
    }

    $displayNamesById = @{}
    foreach ($definition in $definitions) {
        $id = Get-InTUIPimObjectValue -InputObject $definition -Name @('id', 'Id')
        $displayName = Get-InTUIPimObjectValue -InputObject $definition -Name @('displayName', 'DisplayName')
        if (-not [string]::IsNullOrWhiteSpace([string]$id) -and -not [string]::IsNullOrWhiteSpace([string]$displayName)) {
            $displayNamesById[[string]$id] = [string]$displayName
        }
    }

    foreach ($role in $Roles) {
        if ($displayNamesById.ContainsKey($role.RoleDefinitionId)) {
            $role.DisplayName = $displayNamesById[$role.RoleDefinitionId]
        }
    }

    return $Roles
}

function Get-InTUIPimEligibleDirectoryRole {
    [CmdletBinding()]
    param()

    $uri = "/roleManagement/directory/roleEligibilityScheduleInstances/filterByCurrentUser(on='principal')?`$expand=roleDefinition&`$select=id,principalId,roleDefinitionId,directoryScopeId,appScopeId,startDateTime,endDateTime"
    $response = Invoke-InTUIGraphRequest -Uri $uri -Beta -All -NoCache

    if ($null -eq $response) {
        return @()
    }

    $items = @(Get-InTUIPimGraphResultItems -Response $response)
    $roles = @(ConvertTo-InTUIPimRoleCollection -Items $items -Source 'ScheduleInstances')
    Write-InTUILog -Message 'PIM eligible roles loaded' -Context @{ RawCount = $items.Count; RoleCount = $roles.Count }
    if ($roles.Count -gt 0) {
        return (Set-InTUIPimRoleDisplayName -Roles $roles)
    }

    return (Get-InTUIPimEligibleDirectoryRoleSchedule)
}

function Get-InTUIPimEligibleDirectoryRoleSchedule {
    [CmdletBinding()]
    param()

    $uri = '/roleManagement/directory/roleEligibilitySchedules?$select=id,principalId,roleDefinitionId,directoryScopeId,appScopeId,createdDateTime,status,memberType'
    $response = Invoke-InTUIGraphRequest -Uri $uri -All -NoCache

    if ($null -eq $response) {
        return @()
    }

    $items = @(Get-InTUIPimGraphResultItems -Response $response)
    $roles = @(ConvertTo-InTUIPimRoleCollection -Items $items -Source 'EligibilitySchedules')
    $roles = @(Set-InTUIPimRoleDisplayName -Roles $roles)
    Write-InTUILog -Message 'PIM eligible role schedules loaded' -Context @{ RawCount = $items.Count; RoleCount = $roles.Count }
    return $roles
}

function Get-InTUIPimActiveDirectoryRole {
    [CmdletBinding()]
    param()

    $uri = "/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?`$expand=roleDefinition&`$select=id,principalId,roleDefinitionId,directoryScopeId,appScopeId,startDateTime,endDateTime,assignmentType"
    $response = Invoke-InTUIGraphRequest -Uri $uri -Beta -All -NoCache

    if ($null -eq $response) {
        return @()
    }

    $items = @(Get-InTUIPimGraphResultItems -Response $response)
    $roles = @(ConvertTo-InTUIPimRoleCollection -Items $items -Source 'ActiveAssignments')
    Write-InTUILog -Message 'PIM active roles loaded' -Context @{ RawCount = $items.Count; RoleCount = $roles.Count }
    return $roles
}

function Select-InTUIPimActivatableRole {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$EligibleRoles = @(),

        [Parameter()]
        [object[]]$ActiveRoles = @()
    )

    $activeKeys = @{}
    foreach ($role in @($ActiveRoles)) {
        $activeKeys[(Get-InTUIPimRoleKey -Role $role)] = $true
    }

    return @($EligibleRoles | Where-Object {
        -not $activeKeys.ContainsKey((Get-InTUIPimRoleKey -Role $_))
    })
}

function New-InTUIPimActivationRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Role,

        [Parameter(Mandatory)]
        [ValidateRange(1, 24)]
        [int]$Hours,

        [Parameter(Mandatory)]
        [string]$Reason,

        [Parameter()]
        [datetime]$StartDateTime = (Get-Date).ToUniversalTime()
    )

    if (-not (Test-InTUIPimReason -Reason $Reason)) {
        throw 'Activation reason is required.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$Role.PrincipalId)) {
        throw 'PIM activation role is missing PrincipalId.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$Role.RoleDefinitionId)) {
        throw 'PIM activation role is missing RoleDefinitionId.'
    }

    $body = @{
        action           = 'selfActivate'
        principalId      = $Role.PrincipalId
        roleDefinitionId = $Role.RoleDefinitionId
        directoryScopeId = if ($Role.DirectoryScopeId) { $Role.DirectoryScopeId } else { '/' }
        justification    = $Reason.Trim()
        isValidationOnly = $false
        scheduleInfo     = @{
            startDateTime = $StartDateTime.ToUniversalTime().ToString('o')
            expiration    = @{
                type     = 'afterDuration'
                duration = ConvertTo-InTUIPimDuration -Hours $Hours
            }
        }
    }

    if ($Role.AppScopeId) {
        $body['appScopeId'] = $Role.AppScopeId
    }

    return $body
}

function Invoke-InTUIPimRoleActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Roles,

        [Parameter(Mandatory)]
        [ValidateRange(1, 24)]
        [int]$Hours,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $redactedReason = ConvertTo-InTUIPimRedactedReason -Reason $Reason

    foreach ($role in @($Roles)) {
        $body = New-InTUIPimActivationRequestBody -Role $role -Hours $Hours -Reason $Reason
        Write-InTUILog -Message 'PIM activation requested' -Context @{
            RoleName         = $role.DisplayName
            RoleDefinitionId = $role.RoleDefinitionId
            DirectoryScopeId = $role.DirectoryScopeId
            Hours            = $Hours
            Reason           = $redactedReason
        }

        $response = Invoke-InTUIGraphRequest -Uri '/roleManagement/directory/roleAssignmentScheduleRequests' -Method POST -Body $body -Beta

        if ($null -eq $response) {
            $errorMessage = $script:LastGraphError.Message ?? 'Graph request failed'
            Write-InTUILog -Level 'ERROR' -Message 'PIM activation failed' -Context @{
                RoleName         = $role.DisplayName
                RoleDefinitionId = $role.RoleDefinitionId
                DirectoryScopeId = $role.DirectoryScopeId
                Error            = $errorMessage
                Reason           = $redactedReason
            }
            $results.Add([pscustomobject]@{
                Role        = $role
                RoleName    = $role.DisplayName
                Status      = 'Failed'
                RequestId   = $null
                Error       = $errorMessage
                RawResponse = $null
            })
            continue
        }

        $status = $response.status ?? 'Submitted'
        Write-InTUILog -Message 'PIM activation response received' -Context @{
            RoleName         = $role.DisplayName
            RoleDefinitionId = $role.RoleDefinitionId
            DirectoryScopeId = $role.DirectoryScopeId
            Status           = $status
            RequestId        = $response.id
            Reason           = $redactedReason
        }

        $results.Add([pscustomobject]@{
            Role        = $role
            RoleName    = $role.DisplayName
            Status      = $status
            RequestId   = $response.id
            Error       = $null
            RawResponse = $response
        })
    }

    return $results.ToArray()
}
