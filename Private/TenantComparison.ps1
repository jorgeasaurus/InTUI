# InTUI Tenant Comparison
# Side-by-side comparison of metrics across tenants

function Get-InTUITenantMetrics {
    <#
    .SYNOPSIS
        Collects key metrics from the current tenant.
    #>
    [CmdletBinding()]
    param()

    $countHeaders = @{ ConsistencyLevel = 'eventual' }

    $devices = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
    $apps = Invoke-InTUIGraphRequest -Uri '/deviceAppManagement/mobileApps?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
    $users = Invoke-InTUIGraphRequest -Uri '/users?$top=1&$select=id&$count=true' -Headers $countHeaders
    $groups = Invoke-InTUIGraphRequest -Uri '/groups?$top=1&$select=id&$count=true' -Headers $countHeaders
    $configPolicies = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceConfigurations?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
    $compliancePolicies = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicies?$top=1&$select=id&$count=true' -Beta -Headers $countHeaders
    $compliance = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta

    return @{
        DeviceCount = $devices.'@odata.count' ?? @($devices.value).Count
        AppCount = $apps.'@odata.count' ?? @($apps.value).Count
        UserCount = $users.'@odata.count' ?? @($users.value).Count
        GroupCount = $groups.'@odata.count' ?? @($groups.value).Count
        ConfigPolicyCount = $configPolicies.'@odata.count' ?? @($configPolicies.value).Count
        CompliancePolicyCount = $compliancePolicies.'@odata.count' ?? @($compliancePolicies.value).Count
        CompliantDevices = $compliance.compliantDeviceCount ?? 0
        NonCompliantDevices = $compliance.nonCompliantDeviceCount ?? 0
    }
}

function Show-InTUITenantComparison {
    <#
    .SYNOPSIS
        Compares metrics between two tenants side-by-side.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Compare Tenants')

    Write-SpectreHost "[bold]Tenant Comparison[/]"
    Write-SpectreHost "[grey]Compare key metrics between two tenants[/]"
    Write-SpectreHost ""

    # Save current connection info
    $originalContext = Get-MgContext
    $originalTenantId = $script:TenantId
    $originalEnvironment = $script:CloudEnvironment

    if (-not $originalContext) {
        Show-InTUIWarning "Not connected to a tenant. Please connect first."
        Read-InTUIKey
        return
    }

    Write-SpectreHost "[grey]Current tenant: [cyan]$originalTenantId[/][/]"
    Write-SpectreHost ""

    # Get metrics for current tenant
    Write-SpectreHost "[grey]Collecting metrics from current tenant...[/]"

    $tenant1Metrics = Show-InTUILoading -Title "[blue]Loading current tenant metrics...[/]" -ScriptBlock {
        Get-InTUITenantMetrics
    }

    $tenant1Name = $originalTenantId

    if ($null -eq $tenant1Metrics) {
        Show-InTUIError "Failed to collect metrics from current tenant."
        Read-InTUIKey
        return
    }

    Write-InTUILog -Message "Collected metrics from tenant 1" -Context @{ TenantId = $tenant1Name }

    # Prompt for second tenant
    $tenant2Id = Read-SpectreText -Message "[blue]Enter second tenant ID or domain to compare[/]"

    if (-not $tenant2Id) {
        Show-InTUIWarning "Comparison cancelled."
        Read-InTUIKey
        return
    }

    # Connect to second tenant
    Write-SpectreHost ""
    Write-SpectreHost "[grey]Connecting to second tenant...[/]"

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        $script:Connected = $false

        $connected = Connect-InTUI -TenantId $tenant2Id -Environment $originalEnvironment

        if (-not $connected) {
            Show-InTUIError "Failed to connect to second tenant."

            # Restore original connection
            if ($originalTenantId) {
                Connect-InTUI -TenantId $originalTenantId -Environment $originalEnvironment
            }
            Read-InTUIKey
            return
        }

        $tenant2Name = $script:TenantId

        # Get metrics for second tenant
        $tenant2Metrics = Show-InTUILoading -Title "[blue]Loading second tenant metrics...[/]" -ScriptBlock {
            Get-InTUITenantMetrics
        }

        if ($null -eq $tenant2Metrics) {
            Show-InTUIError "Failed to collect metrics from second tenant."

            # Restore original connection
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            Connect-InTUI -TenantId $originalTenantId -Environment $originalEnvironment
            Read-InTUIKey
            return
        }

        Write-InTUILog -Message "Collected metrics from tenant 2" -Context @{ TenantId = $tenant2Name }

    }
    finally {
        # Always restore original connection
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        $script:Connected = $false

        if ($originalTenantId) {
            Connect-InTUI -TenantId $originalTenantId -Environment $originalEnvironment
        }
    }

    # Display comparison
    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Compare Tenants', 'Results')

    Write-InTUILog -Message "Displaying tenant comparison" -Context @{
        Tenant1 = $tenant1Name
        Tenant2 = $tenant2Name
    }

    # Create comparison table
    $metricPairs = @(
        @{ Name = "Managed Devices"; Key = 'DeviceCount' }
        @{ Name = "Mobile Apps"; Key = 'AppCount' }
        @{ Name = "Users"; Key = 'UserCount' }
        @{ Name = "Groups"; Key = 'GroupCount' }
        @{ Name = "Config Policies"; Key = 'ConfigPolicyCount' }
        @{ Name = "Compliance Policies"; Key = 'CompliancePolicyCount' }
        @{ Name = "Compliant Devices"; Key = 'CompliantDevices' }
        @{ Name = "Non-Compliant Devices"; Key = 'NonCompliantDevices' }
    )

    $rows = $metricPairs | ForEach-Object {
        $v1 = $tenant1Metrics[$_.Key]
        $v2 = $tenant2Metrics[$_.Key]
        @($_.Name, "$v1", "$v2", (Get-InTUIComparisonIndicator $v1 $v2))
    }

    # Truncate tenant names for display
    $t1Display = if ($tenant1Name.Length -gt 20) { $tenant1Name.Substring(0, 17) + "..." } else { $tenant1Name }
    $t2Display = if ($tenant2Name.Length -gt 20) { $tenant2Name.Substring(0, 17) + "..." } else { $tenant2Name }

    Show-InTUITable -Title "Tenant Comparison" -Columns @('Metric', $t1Display, $t2Display, 'Diff') -Rows $rows -BorderColor Blue

    Write-SpectreHost ""
    Write-SpectreHost "[grey]Comparison completed. You are now reconnected to: [cyan]$originalTenantId[/][/]"

    Read-InTUIKey
}

function Get-InTUIComparisonIndicator {
    <#
    .SYNOPSIS
        Returns a visual indicator for comparing two values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Value1,

        [Parameter(Mandatory)]
        [int]$Value2
    )

    $diff = $Value1 - $Value2

    if ($diff -eq 0) {
        return "[grey]=[/]"
    }
    elseif ($diff -gt 0) {
        return "[green]+$diff[/]"
    }
    else {
        return "[red]$diff[/]"
    }
}
