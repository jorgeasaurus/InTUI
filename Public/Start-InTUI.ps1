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
    .PARAMETER ClientId
        Application (client) ID for service principal auth.
    .PARAMETER ClientSecret
        Client secret for service principal auth.
    .PARAMETER SecretsFile
        Path to a dotenv-style file with TENANT_ID, CLIENT_ID, CLIENT_SECRET.
    .PARAMETER Environment
        Cloud environment: Global, USGov, USGovDoD, or China. Defaults to Global.
    .PARAMETER SkipConnect
        Skip the connection step (useful if already connected).
    .EXAMPLE
        Start-InTUI
    .EXAMPLE
        Start-InTUI -SecretsFile ./.secrets
    .EXAMPLE
        Start-InTUI -TenantId $tid -ClientId $cid -ClientSecret $sec
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$ClientSecret,

        [Parameter()]
        [string]$SecretsFile,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment = 'Global',

        [Parameter()]
        [switch]$SkipConnect
    )

    # Load secrets file if provided
    if ($SecretsFile -and (Test-Path $SecretsFile)) {
        foreach ($line in Get-Content $SecretsFile) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            $parts = $trimmed -split '=', 2
            if ($parts.Count -ne 2) { continue }
            $key = $parts[0].Trim()
            $val = $parts[1].Trim()
            switch ($key) {
                'TENANT_ID'     { if (-not $TenantId) { $TenantId = $val } }
                'CLIENT_ID'     { if (-not $ClientId) { $ClientId = $val } }
                'CLIENT_SECRET' { if (-not $ClientSecret) { $ClientSecret = $val } }
            }
        }
    }

    Initialize-InTUILog
    Initialize-InTUIConfig
    Initialize-InTUICache
    Initialize-InTUIHistory
    Write-InTUILog -Message "InTUI starting" -Context @{ Version = $script:InTUIVersion; Environment = $Environment }

    if (-not $SkipConnect) {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            $script:Connected = $true
            $script:TenantId = $context.TenantId
            $script:Account = $context.Account ?? $ClientId ?? 'ServicePrincipal'
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
            if ($ClientId) { $params['ClientId'] = $ClientId }
            if ($ClientSecret) { $params['ClientSecret'] = $ClientSecret }
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

        $sections = @(
            @{
                Title = 'Endpoint Management'
                Items = @('Devices', 'Apps', 'Users', 'Groups')
            }
            @{
                Title = 'Policy & Compliance'
                Items = @('Configuration Profiles', 'Compliance Policies', 'Conditional Access', 'Enrollment')
            }
            @{
                Title = 'Security & Scripts'
                Items = @('Scripts & Remediations', 'Security', 'Reports')
            }
            @{
                Title = 'Tools'
                Items = @('Global Search', 'Bookmarks', 'Recent History', "What's Applied?", 'Assignment Conflicts', 'Policy Diff', 'Command Palette', 'Live Dashboard', 'Script Recording', 'Settings')
            }
            @{
                Title = 'Session'
                Items = @('Refresh Dashboard', 'Switch Tenant', 'Switch Cloud Environment', 'Help', 'Exit')
            }
        )

        if ($script:HasArrowKeySupport) {
            $result = Show-InTUIMenuArrowAccordion -Title "[blue]Navigate to[/]" -Sections $sections
        }
        else {
            # Classic fallback - flatten sections into a single list
            $flatChoices = @()
            foreach ($sec in $sections) {
                foreach ($item in $sec.Items) { $flatChoices += $item }
            }
            $idx = Show-InTUIMenuClassic -Title "[blue]Navigate to[/]" -Choices $flatChoices
            if ($idx -eq 'Back') {
                $result = $null
            }
            elseif ($idx -is [int] -and $idx -ge 0 -and $idx -lt $flatChoices.Count) {
                $result = @{ ItemText = $flatChoices[$idx] }
            }
            else {
                $result = $null
            }
        }

        if (-not $result) { continue }
        $selection = $result.ItemText

        switch ($selection) {
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
            'Recent History' {
                Write-InTUILog -Message "Opening Recent History"
                Show-InTUIRecentHistory
            }
            "What's Applied?" {
                Write-InTUILog -Message "Opening What's Applied"
                Show-InTUIWhatsAppliedView
            }
            'Assignment Conflicts' {
                Write-InTUILog -Message "Opening Assignment Conflicts"
                Show-InTUIAssignmentConflictView
            }
            'Policy Diff' {
                Write-InTUILog -Message "Opening Policy Diff"
                Show-InTUIPolicyDiffView
            }
            'Command Palette' {
                Write-InTUILog -Message "Opening Command Palette"
                Show-InTUICommandPalette
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
                $newTenant = Read-InTUITextInput -Message "[blue]Enter Tenant ID or domain[/]"
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
    Write-InTUIText "[blue]Thanks for using InTUI![/]"
}
