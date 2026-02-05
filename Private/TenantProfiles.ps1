$script:TenantProfilePath = Join-Path $HOME '.intui_tenants.json'

function Get-InTUITenantProfiles {
    <#
    .SYNOPSIS
        Loads saved tenant profiles from disk.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:TenantProfilePath)) {
        return @()
    }

    try {
        $content = Get-Content $script:TenantProfilePath -Raw | ConvertFrom-Json
        return @($content)
    }
    catch {
        Write-InTUILog -Level 'WARN' -Message "Failed to load tenant profiles: $($_.Exception.Message)"
        return @()
    }
}

function Save-InTUITenantProfile {
    <#
    .SYNOPSIS
        Saves the current connection as a tenant profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Label
    )

    if (-not $script:Connected) {
        Show-InTUIWarning "Not connected. Connect first before saving a profile."
        return
    }

    $profiles = @(Get-InTUITenantProfiles)

    if (-not $Label) {
        $Label = Read-SpectreText -Prompt "[blue]Profile label[/]" -DefaultValue $script:TenantId
    }

    $existing = $profiles | Where-Object { $_.TenantId -eq $script:TenantId -and $_.Environment -eq $script:CloudEnvironment }
    if ($existing) {
        $existing.Label = $Label
        $existing.Account = $script:Account
        $existing.LastUsed = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
    else {
        $profiles += [PSCustomObject]@{
            Label       = $Label
            TenantId    = $script:TenantId
            Account     = $script:Account
            Environment = $script:CloudEnvironment
            LastUsed    = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        }
    }

    try {
        $profiles | ConvertTo-Json -Depth 5 | Set-Content $script:TenantProfilePath -Encoding UTF8
        Write-InTUILog -Message "Tenant profile saved" -Context @{ Label = $Label; TenantId = $script:TenantId }
        Show-InTUISuccess "Profile '$Label' saved."
    }
    catch {
        Show-InTUIError "Failed to save profile: $($_.Exception.Message)"
        Write-InTUILog -Level 'ERROR' -Message "Failed to save tenant profile: $($_.Exception.Message)"
    }
}

function Remove-InTUITenantProfile {
    <#
    .SYNOPSIS
        Removes a saved tenant profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$Environment
    )

    $profiles = @(Get-InTUITenantProfiles)
    $profiles = @($profiles | Where-Object { -not ($_.TenantId -eq $TenantId -and $_.Environment -eq $Environment) })

    try {
        $profiles | ConvertTo-Json -Depth 5 | Set-Content $script:TenantProfilePath -Encoding UTF8
        Write-InTUILog -Message "Tenant profile removed" -Context @{ TenantId = $TenantId }
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to remove tenant profile: $($_.Exception.Message)"
    }
}

function Show-InTUITenantSwitcher {
    <#
    .SYNOPSIS
        Shows saved tenant profiles for quick switching.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Tenant Profiles')

    $profiles = @(Get-InTUITenantProfiles)

    if ($profiles.Count -eq 0) {
        Show-InTUIWarning "No saved tenant profiles. Connect to a tenant and use 'Save Current Tenant' to create one."
        Read-InTUIKey
        return
    }

    $choices = @()
    foreach ($profile in $profiles) {
        $current = if ($profile.TenantId -eq $script:TenantId -and $profile.Environment -eq $script:CloudEnvironment) { ' [green](current)[/]' } else { '' }
        $envLabel = if ($script:CloudEnvironments[$profile.Environment]) { $script:CloudEnvironments[$profile.Environment].Label } else { $profile.Environment }
        $choices += "$($profile.Label) [grey]| $envLabel | $($profile.Account) | Last: $($profile.LastUsed)[/]$current"
    }

    $choices += '─────────────'
    $choices += 'Save Current Tenant'
    $choices += 'Back'

    $selection = Show-InTUIMenu -Title "[blue]Tenant Profiles[/]" -Choices $choices

    if ($selection -eq 'Back') { return }

    if ($selection -eq 'Save Current Tenant') {
        Save-InTUITenantProfile
        Read-InTUIKey
        return
    }

    $idx = $choices.IndexOf($selection)
    if ($idx -ge 0 -and $idx -lt $profiles.Count) {
        $selected = $profiles[$idx]

        if ($selected.TenantId -eq $script:TenantId -and $selected.Environment -eq $script:CloudEnvironment) {
            Show-InTUIWarning "Already connected to this tenant."
            Read-InTUIKey
            return
        }

        Write-InTUILog -Message "Switching tenant via profile" -Context @{ Label = $selected.Label; TenantId = $selected.TenantId; Environment = $selected.Environment }

        Disconnect-MgGraph -ErrorAction SilentlyContinue
        $script:Connected = $false
        $connected = Connect-InTUI -TenantId $selected.TenantId -Environment $selected.Environment

        if ($connected) {
            $selected.LastUsed = (Get-Date).ToString('yyyy-MM-dd HH:mm')
            $selected.Account = $script:Account
            $profiles | ConvertTo-Json -Depth 5 | Set-Content $script:TenantProfilePath -Encoding UTF8
        }
    }
}

function Show-InTUITenantHealthSummary {
    <#
    .SYNOPSIS
        Shows a quick health summary of the connected tenant on connect.
    #>
    [CmdletBinding()]
    param()

    $healthData = Show-InTUILoading -Title "[blue]Loading tenant health...[/]" -ScriptBlock {
        $org = Invoke-InTUIGraphRequest -Uri '/organization?$select=displayName,verifiedDomains,assignedPlans'
        $deviceOverview = Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDeviceOverview' -Beta
        $compliance = Invoke-InTUIGraphRequest -Uri '/deviceManagement/deviceCompliancePolicyDeviceStateSummary' -Beta

        @{
            OrgName       = if ($org.value) { $org.value[0].displayName } else { 'Unknown' }
            Domains       = if ($org.value) { ($org.value[0].verifiedDomains | Where-Object { $_.isDefault }).name } else { 'Unknown' }
            EnrolledCount = $deviceOverview.enrolledDeviceCount ?? 0
            Compliant     = $compliance.compliantDeviceCount ?? 0
            NonCompliant  = $compliance.nonCompliantDeviceCount ?? 0
            Error         = $compliance.errorDeviceCount ?? 0
        }
    }

    if ($null -eq $healthData) { return }

    $complianceRate = if ($healthData.EnrolledCount -gt 0) {
        [math]::Round(($healthData.Compliant / $healthData.EnrolledCount) * 100, 1)
    } else { 0 }

    $rateColor = if ($complianceRate -ge 90) { 'green' } elseif ($complianceRate -ge 70) { 'yellow' } else { 'red' }

    $content = @"
[grey]Organization:[/]    [white]$($healthData.OrgName)[/]
[grey]Default Domain:[/]  [white]$($healthData.Domains)[/]
[grey]Enrolled Devices:[/] [white]$($healthData.EnrolledCount)[/]
[grey]Compliance Rate:[/] [$rateColor]${complianceRate}%[/]
[grey]  Compliant:[/]     [green]$($healthData.Compliant)[/]
[grey]  Non-compliant:[/] [red]$($healthData.NonCompliant)[/]
[grey]  Error:[/]         [red]$($healthData.Error)[/]
"@

    Show-InTUIPanel -Title "[blue]Tenant Health[/]" -Content $content -BorderColor Blue
}
