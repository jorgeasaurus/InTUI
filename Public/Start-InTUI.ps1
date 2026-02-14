function Start-InTUI {
    <#
    .SYNOPSIS
        Launches the InTUI - Intune Terminal User Interface.
    .DESCRIPTION
        Starts the interactive terminal UI for managing Microsoft Intune
        resources including Devices, Apps, Users, and Groups. Supports
        multiple cloud environments including Commercial, GCC, GCC-High/DoD, and China.
    .PARAMETER TenantId
        Optional tenant ID to connect to a specific tenant.
    .PARAMETER Environment
        Cloud environment: Global, USGov, USGovDoD, or China. Defaults to Global.
    .PARAMETER SkipConnect
        Skip the connection step (useful if already connected).
    .EXAMPLE
        Start-InTUI
    .EXAMPLE
        Start-InTUI -TenantId "contoso.onmicrosoft.com"
    .EXAMPLE
        Start-InTUI -Environment USGov -TenantId "contoso.onmicrosoft.us"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global',

        [Parameter()]
        [switch]$SkipConnect
    )

    Initialize-InTUILog
    Initialize-InTUIConfig
    Initialize-InTUICache
    Write-InTUILog -Message "InTUI starting" -Context @{ Version = $script:InTUIVersion; Environment = $Environment }

    if (-not $SkipConnect) {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            $script:Connected = $true
            $script:TenantId = $context.TenantId
            $script:Account = $context.Account
            if ($context.Environment) {
                $script:CloudEnvironment = $context.Environment
                $envConfig = $script:CloudEnvironments[$context.Environment]
                if ($envConfig) {
                    $script:GraphBaseUrl = $envConfig.GraphBaseUrl
                    $script:GraphBetaUrl = $envConfig.GraphBetaUrl
                }
            }
            Write-InTUILog -Message "Reusing existing Graph connection" -Context @{
                TenantId = $context.TenantId
                Account = $context.Account
                Environment = $script:CloudEnvironment
            }
        }
        else {
            $params = @{ Environment = $Environment }
            if ($TenantId) { $params['TenantId'] = $TenantId }
            $connected = Connect-InTUI @params
            if (-not $connected) {
                Write-InTUILog -Level 'ERROR' -Message "Failed to connect, exiting"
                return
            }
        }
    }

    $exitApp = $false

    while (-not $exitApp) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home')
        Show-InTUIDashboard

        $mainChoices = @(
            "$([char]0x25A0) Devices",
            "$([char]0x25A6) Apps",
            "$([char]0x263A) Users",
            "$([char]0x2756) Groups",
            "$([char]0x2699) Configuration Profiles",
            "$([char]0x2713) Compliance Policies",
            "$([char]0x26A0) Conditional Access",
            "$([char]0x2B06) Enrollment",
            "$([char]0x2630) Scripts & Remediations",
            "$([char]0x26E8) Security",
            "$([char]0x25A3) Reports",
            "$([char]0x2550)$([char]0x2550)$([char]0x2550) Tools $([char]0x2550)$([char]0x2550)$([char]0x2550)",
            "$([char]0x2315) Global Search",
            "$([char]0x2605) Bookmarks",
            "$([char]0x21C4) Compare Tenants",
            "$([char]0x21BB) Live Dashboard",
            "$([char]0x25CF) Script Recording",
            "$([char]0x2699) Settings",
            "$([char]0x2550)$([char]0x2550)$([char]0x2550) Session $([char]0x2550)$([char]0x2550)$([char]0x2550)",
            "$([char]0x21BB) Refresh Dashboard",
            "$([char]0x21C6) Switch Tenant",
            "$([char]0x2601) Switch Cloud Environment",
            "$([char]0x003F) Help",
            "$([char]0x2717) Exit"
        )

        $selection = Show-InTUIMenu -Title "[blue]Navigate to[/]" -Choices $mainChoices

        # Strip icon prefix for switch matching
        $cleanSelection = $selection -replace "^[$([char]0x25A0)$([char]0x25A6)$([char]0x263A)$([char]0x2756)$([char]0x2699)$([char]0x2713)$([char]0x26A0)$([char]0x2B06)$([char]0x2630)$([char]0x26E8)$([char]0x25A3)$([char]0x2315)$([char]0x2605)$([char]0x21C4)$([char]0x21BB)$([char]0x25CF)$([char]0x21C6)$([char]0x2601)$([char]0x003F)$([char]0x2717)] ", ""

        switch ($cleanSelection) {
            'Devices' {
                Write-InTUILog -Message "Navigating to Devices view"
                Show-InTUIDevicesView
            }
            'Apps' {
                Write-InTUILog -Message "Navigating to Apps view"
                Show-InTUIAppsView
            }
            'Users' {
                Write-InTUILog -Message "Navigating to Users view"
                Show-InTUIUsersView
            }
            'Groups' {
                Write-InTUILog -Message "Navigating to Groups view"
                Show-InTUIGroupsView
            }
            'Configuration Profiles' {
                Write-InTUILog -Message "Navigating to Configuration Profiles view"
                Show-InTUIConfigProfilesView
            }
            'Compliance Policies' {
                Write-InTUILog -Message "Navigating to Compliance Policies view"
                Show-InTUICompliancePoliciesView
            }
            'Conditional Access' {
                Write-InTUILog -Message "Navigating to Conditional Access view"
                Show-InTUIConditionalAccessView
            }
            'Enrollment' {
                Write-InTUILog -Message "Navigating to Enrollment view"
                Show-InTUIEnrollmentView
            }
            'Scripts & Remediations' {
                Write-InTUILog -Message "Navigating to Scripts & Remediations view"
                Show-InTUIScriptsView
            }
            'Security' {
                Write-InTUILog -Message "Navigating to Security view"
                Show-InTUISecurityView
            }
            'Reports' {
                Write-InTUILog -Message "Navigating to Reports view"
                Show-InTUIReportsView
            }
            'Global Search' {
                Write-InTUILog -Message "Opening Global Search"
                Invoke-InTUIGlobalSearch
            }
            'Bookmarks' {
                Write-InTUILog -Message "Opening Bookmarks"
                Show-InTUIBookmarks
            }
            'Compare Tenants' {
                Write-InTUILog -Message "Opening Tenant Comparison"
                Show-InTUITenantComparison
            }
            'Live Dashboard' {
                Write-InTUILog -Message "Starting Live Dashboard"
                $interval = $script:InTUIConfig.RefreshInterval
                Start-InTUIAutoRefresh -IntervalSeconds $interval
            }
            'Script Recording' {
                Write-InTUILog -Message "Opening Script Recording menu"
                Show-InTUIRecordingMenu
            }
            'Settings' {
                Write-InTUILog -Message "Opening Settings"
                Show-InTUISettings
            }
            'Help' {
                Write-InTUILog -Message "Opening Help"
                Show-InTUIHelp
            }
            'Refresh Dashboard' {
                Write-InTUILog -Message "Refreshing dashboard"
                continue
            }
            'Switch Tenant' {
                $newTenant = Read-SpectreText -Message "[blue]Enter Tenant ID or domain[/]"
                if ($newTenant) {
                    Write-InTUILog -Message "Switching tenant" -Context @{ NewTenant = $newTenant }
                    Disconnect-MgGraph -ErrorAction SilentlyContinue
                    $script:Connected = $false
                    Connect-InTUI -TenantId $newTenant -Environment $script:CloudEnvironment
                }
            }
            'Switch Cloud Environment' {
                $envChoices = @()
                foreach ($envKey in @('Global', 'USGov', 'USGovDoD', 'China')) {
                    $envDef = $script:CloudEnvironments[$envKey]
                    $current = if ($envKey -eq $script:CloudEnvironment) { ' [green](current)[/]' } else { '' }
                    $envChoices += "$($envDef.Label)$current"
                }
                $envChoices += 'Cancel'

                $envSelection = Show-InTUIMenu -Title "[blue]Select Cloud Environment[/]" -Choices $envChoices
                if ($envSelection -ne 'Cancel') {
                    $selectedEnv = switch -Wildcard ($envSelection) {
                        '*DoD*'        { 'USGovDoD' }
                        '*GCC High*'   { 'USGov' }
                        '*Commercial*' { 'Global' }
                        '*China*'      { 'China' }
                        default        { $null }
                    }
                    if ($selectedEnv -and $selectedEnv -ne $script:CloudEnvironment) {
                        Write-InTUILog -Message "Switching cloud environment" -Context @{ From = $script:CloudEnvironment; To = $selectedEnv }
                        Disconnect-MgGraph -ErrorAction SilentlyContinue
                        $script:Connected = $false
                        Connect-InTUI -Environment $selectedEnv
                    }
                }
            }
            'Exit' {
                Write-InTUILog -Message "InTUI exiting"
                $exitApp = $true
            }
            default {
                continue
            }
        }
    }

    Clear-Host
    $goodbye = @"
[blue]  $([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)[/]
[blue]  $([char]0x25CF) Thanks for using InTUI! $([char]0x25CF)[/]
[blue]  $([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)$([char]0x2500)[/]
"@
    Write-SpectreHost $goodbye
}
